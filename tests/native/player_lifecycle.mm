// Exercise the real player close delegate without displaying a window.
#import "../../macos/Native/FSNativeBridge.mm"
#include <cassert>

// Capture menu placement without tracking a real menu or showing any window.
@interface FSCaptureMenu : NSMenu
@property NSPoint captured;
@property NSView *capturedView;
@end
@implementation FSCaptureMenu
- (void)update {}
- (NSSize)size { return NSMakeSize(240,120); }
- (BOOL)popUpMenuPositioningItem:(NSMenuItem *)item atLocation:(NSPoint)point inView:(NSView *)view {
    self.captured=point;self.capturedView=view;return NO;
}
@end
@interface FSFakeScreenWindow : NSObject
@end
@implementation FSFakeScreenWindow
- (NSRect)convertRectToScreen:(NSRect)rect { return NSOffsetRect(rect,100,200); }
@end
@interface FSMenuAnchor : NSView
@property BOOL testFlipped;
@property FSFakeScreenWindow *screenWindow;
@end
@implementation FSMenuAnchor
- (BOOL)isFlipped { return self.testFlipped; }
- (NSWindow *)window { return (NSWindow *)self.screenWindow; }
- (NSRect)convertRect:(NSRect)rect toView:(NSView *)view { return NSMakeRect(400,50,44,44); }
@end

@interface FSLicenseWindowSpy : FSAboutWindow
@property NSString *capturedNotices;
@end
@implementation FSLicenseWindowSpy
- (void)showLicensesText:(NSString *)text { self.capturedNotices=text; }
@end

@interface FSReadinessWebSpy : NSObject
@property(copy) void (^inspection)(id,NSError *);
@end
@implementation FSReadinessWebSpy
- (void)evaluateJavaScript:(NSString *)script inFrame:(WKFrameInfo *)frame inContentWorld:(WKContentWorld *)world completionHandler:(void (^)(id,NSError *))completion {
    self.inspection=completion;
}
@end

@interface FSClosingWebSpy : NSObject
@property WKFullscreenState fullscreenState;
@property id navigationDelegate,UIDelegate;
@property NSMutableArray<NSString *> *events;
@property(copy) void (^closed)(void);
@end
@implementation FSClosingWebSpy
- (WKWebViewConfiguration *)configuration { return [WKWebViewConfiguration new]; }
- (void)stopLoading { [self.events addObject:@"stop"]; }
- (void)pauseAllMediaPlaybackWithCompletionHandler:(void (^)(void))completion { [self.events addObject:@"pause"]; }
- (void)closeAllMediaPresentationsWithCompletionHandler:(void (^)(void))completion { [self.events addObject:@"exit"];self.closed=completion; }
- (id)loadHTMLString:(NSString *)html baseURL:(NSURL *)url { assert(!html.length);[self.events addObject:@"clear"];return nil; }
- (void)removeFromSuperview { [self.events addObject:@"detach"]; }
@end

static NSDictionary *command(void *engine,NSDictionary *request) {
    NSData *data=[NSJSONSerialization dataWithJSONObject:request options:0 error:nil];
    char *raw=fs_engine_command(engine,[[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] UTF8String]);
    NSDictionary *reply=[NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:raw length:strlen(raw)] options:0 error:nil];
    fs_engine_free(raw);assert(!reply[@"error"]);return reply[@"result"];
}
int main() { @autoreleasepool {
    // Returning from another Space must inspect the current page before timeout.
    FSProviderView *provider=[[FSProviderView alloc] initWithFrame:NSZeroRect];
    FSReadinessWebSpy *web=[FSReadinessWebSpy new];provider.web=(WKWebView *)web;provider.selectsPlayer=YES;
    provider.loadingCover=[NSView new];provider.message=[NSTextField labelWithString:@"Loading"];
    provider.loadStarted=NSDate.timeIntervalSinceReferenceDate-60;
    [provider inspectPlayer];assert(web.inspection && provider.inspectingPlayer);
    web.inspection(@YES,nil);
    assert(provider.loadingCover.hidden && [provider.message.stringValue hasPrefix:@"Официальный плеер"] && !provider.inspectingPlayer);
    provider.loadingCover.hidden=NO;
    [provider inspectPlayer];web.inspection(@NO,nil);
    assert(!provider.loadingCover.hidden && provider.message.stringValue.length && !provider.inspectingPlayer);
    provider.message.stringValue=@"New source";
    [provider inspectPlayer];++provider.loadGeneration;
    web.inspection(@YES,nil);
    assert(!provider.loadingCover.hidden && [provider.message.stringValue isEqual:@"New source"]);
    web.inspection=nil;provider.web=nil;
    // WebKit must return from its presentation before its view is detached.
    for(NSNumber *state in @[@(WKFullscreenStateNotInFullscreen),@(WKFullscreenStateEnteringFullscreen),@(WKFullscreenStateInFullscreen),@(WKFullscreenStateExitingFullscreen)]) {
        FSClosingWebSpy *closing=[FSClosingWebSpy new];closing.events=[NSMutableArray new];closing.fullscreenState=(WKFullscreenState)state.integerValue;
        provider.web=(WKWebView *)closing;NSUInteger before=provider.loadGeneration;
        [provider stop];assert(!provider.web && provider.loadGeneration==before+1);
        if(state.integerValue==WKFullscreenStateNotInFullscreen) {
            assert(([closing.events isEqual:@[@"stop",@"clear",@"detach"]]));
        } else {
            assert(([closing.events isEqual:@[@"stop",@"pause",@"exit"]]));
            closing.closed();closing.closed=nil;
            assert(([closing.events isEqual:@[@"stop",@"pause",@"exit",@"clear",@"detach"]]));
        }
        [provider stop];
    }
    FSCaptureMenu *menu=[FSCaptureMenu new];FSMenuAnchor *anchor=[FSMenuAnchor new];anchor.screenWindow=[FSFakeScreenWindow new];
    for(NSNumber *flipped in @[@NO,@YES]) {
        anchor.testFlipped=flipped.boolValue;FSPopUpAboveLeft(menu,anchor);
        assert(!menu.capturedView && menu.captured.x==260 && menu.captured.y==414);
        // The menu bottom-right is exactly the button's top-left in screen space.
        assert(menu.captured.x+menu.size.width==500 && menu.captured.y-menu.size.height==294);
    }
    anchor.screenWindow=nil;
    NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"freescene-lifecycle-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    NSDictionary *config=@{@"profile":[root stringByAppendingPathComponent:@"profile"],@"downloads":[root stringByAppendingPathComponent:@"downloads"],@"isolated":@YES};
    NSData *data=[NSJSONSerialization dataWithJSONObject:config options:0 error:nil];
    void *engine=fs_engine_create([[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] UTF8String]);assert(engine);
    NSString *first=@"1111111111111111111111111111111111111111",*second=@"2222222222222222222222222222222222222222";
    for(NSString *hash in @[first,second])command(engine,@{@"method":@"add",@"source":[@"magnet:?xt=urn:btih:" stringByAppendingString:hash]});
    FSPlayer *player=[FSPlayer alloc];player.video=[FSVideoView new];player.taskID=first;player.currentFile=0;
    __block int changes=0,closes=0;
    player.fileRequested=^(NSString *task,NSInteger index,NSString *name){assert([task isEqual:first] && index==1);++changes;};
    NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:@"Episode 2" action:nil keyEquivalent:@""];item.tag=1;item.representedObject=@"Episode 2";
    [player episodeChanged:item];assert(changes==1);
    item.tag=0;[player episodeChanged:item];assert(changes==1);
    player.playbackClosed=^(NSString *task){assert([task isEqual:first]);++closes;command(engine,@{@"method":@"pause",@"id":task});};
    __block int pickerReplies=0;
    FSVideoSelection *pending=[FSVideoSelection new];
    pending.completion=^(NSNumber *index){ assert(!index);++pickerReplies; };
    player.videoSelection=pending;
    NSUInteger generation=player.requestGeneration;
    [player windowWillClose:[NSNotification notificationWithName:NSWindowWillCloseNotification object:nil]];
    assert(!player.taskID && player.requestGeneration==generation+1 && closes==1);
    assert(!player.videoSelection && pickerReplies==1);[pending finish:@1];assert(pickerReplies==1);
    [player windowWillClose:[NSNotification notificationWithName:NSWindowWillCloseNotification object:nil]];assert(closes==1);
    NSArray *tasks=command(engine,@{@"method":@"status"})[@"tasks"];
    for(NSDictionary *task in tasks) { BOOL selected=[task[@"id"] isEqual:first];assert([task[@"phase"] isEqual:@"paused"]==selected); }
    FSNativeBridge *native=[FSNativeBridge new];native.player=player;native.engine=engine;
    FSLicenseWindowSpy *about=[FSLicenseWindowSpy new];native.about=about;
    NSString *notices=[@"Full licence · Полная лицензия\n" stringByPaddingToLength:100000 withString:@"Complete copyright text.\n" startingAtIndex:0];
    __block BOOL licenseReply=NO;
    [native handle:[FlutterMethodCall methodCallWithMethodName:@"showLicenses" arguments:@{@"text":notices}] result:^(id result){assert(!result);licenseReply=YES;}];
    assert(licenseReply && [about.capturedNotices isEqualToString:notices]);
    licenseReply=NO;
    [native handle:[FlutterMethodCall methodCallWithMethodName:@"showLicenses" arguments:@{@"text":@""}] result:^(id result){assert([result isKindOfClass:FlutterError.class] && [((FlutterError *)result).code isEqual:@"licenses_empty"]);licenseReply=YES;}];
    assert(licenseReply && [about.capturedNotices isEqualToString:notices]);
    __block BOOL replied=NO;
    [native handle:[FlutterMethodCall methodCallWithMethodName:@"prepareStream" arguments:@{@"id":first}] result:^(id result){replied=YES;}];
    assert(replied);
    replied=NO;
    [native handle:[FlutterMethodCall methodCallWithMethodName:@"choosePlayerVideo" arguments:@{@"id":first}] result:^(id result){assert(!result);replied=YES;}];
    assert(replied);
    for(NSDictionary *task in command(engine,@{@"method":@"status"})[@"tasks"])if([task[@"id"] isEqual:first])assert([task[@"phase"] isEqual:@"paused"]);
    // Quit keeps the native handler responsive while the engine saves state.
    native.queue=dispatch_queue_create("FreeScene.shutdown.test",DISPATCH_QUEUE_SERIAL);bridge=native;
    __block int quitReplies=0;
    [FSNativeBridge shutdownWithCompletion:^{++quitReplies;}];
    [FSNativeBridge shutdownWithCompletion:^{++quitReplies;}];
    assert(native.closing);
    replied=NO;
    [native handle:[FlutterMethodCall methodCallWithMethodName:@"status" arguments:nil] result:^(id result){assert([result[@"shuttingDown"] boolValue]);replied=YES;}];
    assert(replied);
    [native handle:[FlutterMethodCall methodCallWithMethodName:@"preparePlayer" arguments:nil] result:^(id result){assert([result isKindOfClass:FlutterError.class] && [((FlutterError *)result).code isEqual:@"app_closing"]);}];
    NSDate *until=[NSDate dateWithTimeIntervalSinceNow:15];
    while(!native.shutdownComplete && until.timeIntervalSinceNow>0) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    assert(native.shutdownComplete && !native.engine && quitReplies==2);
    NSDictionary *manifest=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:@"profile/tasks.json"]] options:0 error:nil];
    for(NSDictionary *task in manifest[@"tasks"])assert([task[@"paused"] boolValue]==[task[@"id"] isEqual:first]);
    [NSFileManager.defaultManager removeItemAtPath:root error:nil];
    puts("{\"passed\":true,\"closePausesSelectedTorrent\":true,\"otherTorrentUnaffected\":true,\"pausePersists\":true,\"episodeSwitchCallback\":true,\"repeatedCloseIsSafe\":true,\"latePrepareCannotResume\":true,\"menusAboveLeftInScreenCoordinates\":true,\"closingPlayerCancelsPickerExactlyOnce\":true,\"closedPlayerCannotShowPicker\":true,\"shutdownKeepsChannelAlive\":true,\"repeatedQuitCompletesExactlyOnce\":true,\"completeLicenseNoticesDelivered\":true,\"emptyLicenseNoticesRejected\":true,\"readyPlayerCheckedBeforeTimeout\":true,\"staleReadinessIgnored\":true,\"fullscreenClosedBeforeWebViewDetach\":true}");
} }
