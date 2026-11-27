// Production updater and About presenter with inert HTTP, Keychain and alert
// replacements. No network request, desktop UI or user Keychain is reachable.
#import <Cocoa/Cocoa.h>
#import <Security/Security.h>
static BOOL fsEnglish=NO,fsDark=YES;
#import "../../macos/Native/FSTheme.h"
static NSFont *FSFont(CGFloat size){return nil;}
static NSUInteger checks=0,forbiddenSecurityCalls=0;
static void check(BOOL value,const char *label){++checks;if(!value){fprintf(stderr,"FAILED: %s\n",label);exit(1);}}
static OSStatus FSForbiddenInteraction(Boolean *value){++forbiddenSecurityCalls;return errSecInteractionNotAllowed;}
static OSStatus FSForbiddenSetInteraction(Boolean value){++forbiddenSecurityCalls;return errSecInteractionNotAllowed;}
static OSStatus FSForbiddenCopy(CFDictionaryRef query,CFTypeRef *value){++forbiddenSecurityCalls;return errSecInteractionNotAllowed;}
static OSStatus FSForbiddenUpdate(CFDictionaryRef query,CFDictionaryRef value){++forbiddenSecurityCalls;return errSecInteractionNotAllowed;}
static OSStatus FSForbiddenAdd(CFDictionaryRef value,CFTypeRef *result){++forbiddenSecurityCalls;return errSecInteractionNotAllowed;}
static OSStatus FSForbiddenDelete(CFDictionaryRef value){++forbiddenSecurityCalls;return errSecInteractionNotAllowed;}
#define SecKeychainGetUserInteractionAllowed FSForbiddenInteraction
#define SecKeychainSetUserInteractionAllowed FSForbiddenSetInteraction
#define SecItemCopyMatching FSForbiddenCopy
#define SecItemUpdate FSForbiddenUpdate
#define SecItemAdd FSForbiddenAdd
#define SecItemDelete FSForbiddenDelete
#import "../../macos/Native/FSReleaseUpdater.h"
#undef SecKeychainGetUserInteractionAllowed
#undef SecKeychainSetUserInteractionAllowed
#undef SecItemCopyMatching
#undef SecItemUpdate
#undef SecItemAdd
#undef SecItemDelete

@interface FSStartupWindow : NSObject
@property NSWindow *sheetParent;
@property NSUInteger hidden;
- (void)orderOut:(id)sender;
@end
@implementation FSStartupWindow
- (void)orderOut:(id)sender{++self.hidden;}
@end
@interface FSStartupAlert : NSObject
@property NSAlertStyle alertStyle;
@property NSString *messageText,*informativeText;
@property NSView *accessoryView;
@property NSWindow *window;
@property NSMutableArray<NSString *> *buttons;
@property(copy) void (^completion)(NSModalResponse);
- (void)addButtonWithTitle:(NSString *)title;
- (void)beginSheetModalForWindow:(NSWindow *)window completionHandler:(void (^)(NSModalResponse))completion;
@end
@implementation FSStartupAlert
- (instancetype)init{if((self=[super init])){self.buttons=[NSMutableArray new];self.window=(NSWindow *)[FSStartupWindow new];}return self;}
- (void)addButtonWithTitle:(NSString *)title{[self.buttons addObject:title];}
- (void)beginSheetModalForWindow:(NSWindow *)window completionHandler:(void (^)(NSModalResponse))completion{self.completion=completion;}
@end
#define NSAlert FSStartupAlert
#import "../../macos/Native/FSAboutWindow.h"
#undef NSAlert

@interface FSAboutFixture : FSAboutWindow
@property NSUInteger shown;
@end
@implementation FSAboutFixture
- (void)show {++self.shown;[self.updater cancelStartupCheck];[self dismissStartupOffer];}
@end

@interface FSAboutControl : NSObject
@property(getter=isEnabled) BOOL enabled;
@property NSString *title,*stringValue;
@end
@implementation FSAboutControl
@end

@interface FSStartupHTTP : FSGitHubHTTP
@property id fixture;
@property NSString *failure;
@property BOOL held,cancelled;
@property NSUInteger gets;
@property(copy) FSGitHubHTTPReply pending,late;
@end
@implementation FSStartupHTTP
- (void)get:(NSURL *)url downloadTo:(NSURL *)destination size:(long long)size completion:(FSGitHubHTTPReply)completion {
    ++self.gets;
    check([url.absoluteString isEqual:[FSGitHubRepositoryAPI stringByAppendingString:@"/releases/latest"]],"startup/manual check uses only the fixed latest-release API");
    check(!destination && size==0,"startup lookup cannot download a release asset");
    if(self.held){self.pending=completion;self.late=completion;return;}
    NSData *data=[self.fixture isKindOfClass:NSData.class] ? self.fixture : self.fixture ? [NSJSONSerialization dataWithJSONObject:self.fixture options:0 error:nil] : nil;
    completion(data,self.failure);
}
- (void)cancel {self.cancelled=YES;FSGitHubHTTPReply reply=self.pending;self.pending=nil;if(reply)reply(nil,@"cancelled");}
@end

static void waitFor(BOOL (^done)(void)) {
    NSDate *end=[NSDate dateWithTimeIntervalSinceNow:3];
    while(!done() && end.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    check(done(),"asynchronous fixture finished");
}
static NSData *data(id value){return [NSJSONSerialization dataWithJSONObject:value options:0 error:nil];}
static NSMutableDictionary *release(NSString *version) {
    NSDictionary *asset=@{@"name":[NSString stringWithFormat:@"FreeScene-%@-macos-%@.dmg",version,FSUpdateArchitectureName()],@"id":@123,
        @"url":@"https://api.github.com/repos/RarogVA/freescene/releases/assets/123",@"digest":[@"sha256:" stringByAppendingString:[@"a" stringByPaddingToLength:64 withString:@"a" startingAtIndex:0]],@"size":@1024,@"state":@"uploaded"};
    return [@{@"tag_name":[@"v" stringByAppendingString:version],@"draft":@NO,@"prerelease":@NO,@"assets":@[asset]} mutableCopy];
}
static FSReleaseUpdater *updater(FSStartupHTTP *http,NSMutableArray<NSNumber *> *reads) {
    FSReleaseUpdater *value=[FSReleaseUpdater new];
    value.installedVersion=^{return @"1.2.6";};
    value.makeHTTP=^{return http;};
    return value;
}
static void quietResult(FSReleaseUpdater *value,FSStartupHTTP *http) {
    __block NSUInteger offered=0,changes=0;
    value.changed=^{++changes;};
    [value checkAtStartup:^(NSDictionary *asset){++offered;}];
    waitFor(^BOOL{return !value.startupChecking;});
    check(!offered && !changes && [value.phase isEqual:@"idle"] && !value.message && !value.asset,"startup failure/up-to-date result is entirely silent");
    check(!value.work && !value.stage && !value.helper && !value.handedOff,"quiet result creates no download, stage or installer");
}
static NSMutableArray *scheduler(FSReleaseUpdater *value) {
    NSMutableArray *scheduled=[NSMutableArray new];
    value.scheduleStartupOffer=^(NSTimeInterval delay,dispatch_block_t work){[scheduled addObject:@{@"delay":@(delay),@"work":[work copy]}];};
    value.phase=@"available";value.asset=@{@"version":@"1.2.7"};
    return scheduled;
}
static BOOL runScheduled(NSMutableArray *scheduled,NSTimeInterval delay) {
    NSUInteger index=[scheduled indexOfObjectPassingTest:^BOOL(NSDictionary *entry,NSUInteger index,BOOL *stop){return [entry[@"delay"] doubleValue]==delay;}];
    if(index==NSNotFound)return NO;
    dispatch_block_t work=scheduled[index][@"work"];[scheduled removeObjectAtIndex:index];work();return YES;
}

int main(void){@autoreleasepool {
    NSMutableArray *reads=nil;FSStartupHTTP *http=nil;FSReleaseUpdater *value=nil;
    for(NSString *failure in @[@"network",@"auth",@"repo_access",@"cancelled",@"redirect"]) {
        reads=[NSMutableArray new];http=[FSStartupHTTP new];http.failure=failure;value=updater(http,reads);quietResult(value,http);
        check(reads.count==0 && http.gets==1,"offline/rejected account produces no UI or interactive read");
    }
    NSMutableArray *releases=[NSMutableArray new];
    [releases addObject:release(@"1.2.6")];[releases addObject:release(@"1.2.5")];
    NSMutableDictionary *draft=release(@"1.2.7");draft[@"draft"]=@YES;[releases addObject:draft];
    NSMutableDictionary *pre=release(@"1.2.7");pre[@"prerelease"]=@YES;[releases addObject:pre];
    NSMutableDictionary *invalid=release(@"1.2.7");invalid[@"tag_name"]=@"v1.2.7-beta";[releases addObject:invalid];
    NSMutableDictionary *missingDigest=release(@"1.2.7"),*missingAsset=[missingDigest[@"assets"][0] mutableCopy];[missingAsset removeObjectForKey:@"digest"];missingDigest[@"assets"]=@[missingAsset];[releases addObject:missingDigest];
    NSMutableDictionary *unsafe=release(@"1.2.7"),*unsafeAsset=[unsafe[@"assets"][0] mutableCopy];unsafeAsset[@"url"]=@"https://other.example/update.zip";unsafe[@"assets"]=@[unsafeAsset];[releases addObject:unsafe];
    [releases addObject:[@"not json" dataUsingEncoding:NSUTF8StringEncoding]];
    for(id fixture in releases) {reads=[NSMutableArray new];http=[FSStartupHTTP new];http.fixture=fixture;value=updater(http,reads);quietResult(value,http);}

    reads=[NSMutableArray new];http=[FSStartupHTTP new];http.fixture=release(@"1.2.7");value=updater(http,reads);
    __block NSUInteger offers=0,changes=0;__block NSDictionary *offered=nil;value.changed=^{++changes;};
    [value checkAtStartup:^(NSDictionary *asset){++offers;offered=asset;}];
    waitFor(^BOOL{return !value.startupChecking;});
    check(offers==1 && changes==1 && [value.phase isEqual:@"available"] && [offered isEqual:value.asset] && [value.asset[@"version"] isEqual:@"1.2.7"],"only newer validated stable release becomes available and is offered");
    check(reads.count==0 && http.gets==1 && !value.stage && !value.work && !value.helper,"newer release does not download/install or use interactive Keychain");
    [value checkAtStartup:^(NSDictionary *asset){++offers;}];
    check(offers==1 && http.gets==1 && http.gets==1,"startup check runs once on the shared updater");

    reads=[NSMutableArray new];http=[FSStartupHTTP new];http.held=YES;value=updater(http,reads);
    offers=0;[value checkAtStartup:^(NSDictionary *asset){++offers;}];waitFor(^BOOL{return http.pending!=nil;});
    FSGitHubHTTPReply stale=http.late;
    FSStartupHTTP *manual=[FSStartupHTTP new];manual.fixture=release(@"1.2.8");value.makeHTTP=^{return manual;};
    [value activate];waitFor(^BOOL{return [value.phase isEqual:@"available"];});
    check(http.cancelled && reads.count==0 && manual.gets==1,"manual check cancels startup and uses the existing interactive manual path");
    stale(data(release(@"9.0.0")),nil);
    check(!offers && [value.asset[@"version"] isEqual:@"1.2.8"],"late startup callback cannot overwrite manual state or offer a stale update");

    reads=[NSMutableArray new];http=[FSStartupHTTP new];http.held=YES;value=updater(http,reads);
    offers=0;[value checkAtStartup:^(NSDictionary *asset){++offers;}];waitFor(^BOOL{return http.pending!=nil;});stale=http.late;
    [value cancel];stale(data(release(@"9.0.0")),nil);
    check(!offers && http.cancelled && !value.startupChecking && !value.asset && [value.phase isEqual:@"idle"],"logout/shutdown cancellation invalidates held startup responses");
    [value checkAtStartup:^(NSDictionary *asset){++offers;}];check(http.gets==1,"cancellation cannot restart startup checking in the same session");

    reads=[NSMutableArray new];http=[FSStartupHTTP new];value=updater(http,reads);[value cancelStartupCheck];
    [value checkAtStartup:^(NSDictionary *asset){++offers;}];check(!reads.count && !http.gets,"opening manual About before scheduled startup suppresses its pending attempt");

    reads=[NSMutableArray new];http=[FSStartupHTTP new];value=updater(http,reads);
    NSMutableArray *scheduled=scheduler(value);offers=0;__block NSUInteger eligibilityChecks=0;
    [value offerAtStartupWhenEligible:^(void (^reply)(BOOL)){reply(++eligibilityChecks>=3);} offer:^{++offers;}];
    check(!offers && value.startupOfferPending && scheduled.count==2,"busy UI defers only eligibility with a bounded deadline");
    check(runScheduled(scheduled,2) && !offers,"first retry waits while another modal is active");
    check(runScheduled(scheduled,2) && offers==1 && !value.startupOfferPending,"offer appears when the main screen becomes eligible");
    check(!http.gets && !reads.count && !value.work,"UI eligibility retries never repeat HTTP, Keychain or download work");
    [value offerAtStartupWhenEligible:^(void (^reply)(BOOL)){reply(YES);} offer:^{++offers;}];
    runScheduled(scheduled,60);check(offers==1,"completed offer cannot be repeated by another gate or its deadline");

    reads=[NSMutableArray new];http=[FSStartupHTTP new];value=updater(http,reads);scheduled=scheduler(value);offers=0;
    __block void (^eligibilityReply)(BOOL)=nil;
    [value offerAtStartupWhenEligible:^(void (^reply)(BOOL)){eligibilityReply=reply;} offer:^{++offers;}];
    check(value.startupOfferPending && runScheduled(scheduled,60) && !value.startupOfferPending,"deadline expires even when Flutter never replies");
    eligibilityReply(YES);check(!offers,"late eligibility reply after the deadline cannot show an offer");

    for(NSNumber *manual in @[@YES,@NO]) {
        reads=[NSMutableArray new];http=[FSStartupHTTP new];value=updater(http,reads);scheduled=scheduler(value);offers=0;eligibilityReply=nil;
        [value offerAtStartupWhenEligible:^(void (^reply)(BOOL)){eligibilityReply=reply;} offer:^{++offers;}];
        NSUInteger generation=value.generation;
        if(manual.boolValue)[value cancelStartupCheck];else [value cancel];
        eligibilityReply(YES);runScheduled(scheduled,60);
        check(!offers && value.generation!=generation && !value.startupOfferPending,"manual About/logout/shutdown invalidates pending eligibility callbacks");
        check(manual.boolValue ? [value.phase isEqual:@"available"] && value.asset!=nil : [value.phase isEqual:@"idle"] && value.asset==nil,"manual About keeps the validated asset while logout/shutdown clears it");
    }
    reads=[NSMutableArray new];http=[FSStartupHTTP new];value=updater(http,reads);scheduled=scheduler(value);offers=0;
    [value offerAtStartupWhenEligible:^(void (^reply)(BOOL)){reply(NO);reply(YES);} offer:^{++offers;}];
    while(runScheduled(scheduled,2)){}
    check(!offers && value.startupOfferAttempts==31 && !value.startupOfferPending,"duplicate eligibility replies are ignored and retries stop after 31 attempts");
    check(!http.gets && !reads.count,"exhausted UI retries do not access credentials or the network");

    FSAboutFixture *about=[FSAboutFixture new];
    check(about.updater && !about.window,"startup updater exists without opening About");
    about.updater.phase=@"available";about.updater.asset=@{@"version":@"1.2.7"};about.updater.generation=7;
    NSWindow *parent=(NSWindow *)[FSStartupWindow new];
    [about offerStartupUpdateForWindow:parent allowed:^BOOL{return NO;}];check(!about.startupAlert,"ineligible modal/window state suppresses the offer");
    [about offerStartupUpdateForWindow:parent allowed:^BOOL{return YES;}];FSStartupAlert *alert=about.startupAlert;
    check(alert && [alert.buttons isEqual:@[@"Обновить…",@"Позже"]] && about.shown==0,"offer presents two explicit choices without opening About or downloading");
    alert.completion(NSAlertSecondButtonReturn);check(!about.startupAlert && !about.shown && [about.updater.phase isEqual:@"available"],"Later keeps the validated asset for a future manual update");
    [about offerStartupUpdateForWindow:parent allowed:^BOOL{return YES;}];alert=about.startupAlert;alert.completion(NSAlertFirstButtonReturn);
    check(about.shown==1 && [about.updater.phase isEqual:@"available"] && !about.updater.work,"Update opens the existing About flow while download remains explicit");
    [about offerStartupUpdateForWindow:parent allowed:^BOOL{return YES;}];alert=about.startupAlert;
    [about dismissStartupOffer];alert.completion(NSAlertFirstButtonReturn);
    check(about.shown==1 && !about.startupAlert,"manual presentation cancels an older alert response");
    [about offerStartupUpdateForWindow:parent allowed:^BOOL{return YES;}];alert=about.startupAlert;
    [about.updater cancel];alert.completion(NSAlertFirstButtonReturn);
    check(about.shown==1 && !about.startupAlert,"logout/shutdown dismisses an existing offer and ignores its late button response");
    fsEnglish=YES;
    FSAboutFixture *pane=[FSAboutFixture new];pane.checkButton=(NSButton *)[FSAboutControl new];pane.status=(NSTextField *)[FSAboutControl new];
    for(NSString *phase in @[@"idle",@"checking",@"available",@"downloading",@"ready",@"installing"]) {
        [pane.updater publish:phase message:@"fixture"];
        check(pane.checkButton.enabled==[@[@"idle",@"available",@"ready"] containsObject:phase],"update button disables while work is in progress");
        check(![pane.checkButton.title.lowercaseString containsString:@"token"],"update action never asks for credentials");
    }
    [pane.updater publish:@"idle" message:nil];
    check([pane.checkButton.title isEqual:@"Check for updates"],"idle action checks public releases");
    [pane.updater publish:@"available" message:nil];
    check([pane.checkButton.title isEqual:@"Install updates"],"available action offers installation");
    [pane.updater fail:@"repo_access"];
    check(pane.checkButton.enabled && [pane.checkButton.title isEqual:@"Check for updates"],"HTTP failure offers a retry");
    check(![pane.status.stringValue.lowercaseString containsString:@"token"],"HTTP failure has no credential instructions");
    check(forbiddenSecurityCalls==0,"all tests use injected credential storage and never reach any Security function");
    printf("{\"passed\":true,\"checks\":%lu,\"realCredentialsRead\":false,\"networkUsed\":false,\"desktopUIShown\":false,\"installedApplicationChanged\":false}\n",(unsigned long)checks);
}return 0;}
