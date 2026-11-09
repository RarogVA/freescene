// Run a real Cocoa application and the production updater readiness handler.
// Bundle roots, helper and all markers are supplied only by the disposable
// Python fixture. No FreeScene account, user profile or installed app is used.
#import <Cocoa/Cocoa.h>
#include <unistd.h>
static BOOL fsEnglish=NO;
#import "../../macos/Native/FSReleaseUpdater.h"

static void FSFixtureMarker(NSString *root,NSString *name,NSDictionary *value) {
    NSData *json=[NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
    [json writeToFile:[root stringByAppendingPathComponent:[name stringByAppendingString:@".json"]] atomically:YES];
}
@interface FSQuitFixture : NSObject <NSApplicationDelegate>
@property NSString *root;
@property NSString *mode;
@property NSString *helperPath;
@property NSString *stage;
@property NSString *backup;
@property BOOL requested;
@property BOOL relaunched;
@property FSReleaseUpdater *updater;
@end
@implementation FSQuitFixture
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    self.relaunched=[[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"] isEqual:@"new"];
    self.root=NSBundle.mainBundle.bundlePath.stringByDeletingLastPathComponent;
    if(self.relaunched) {
        FSFixtureMarker(self.root,@"relaunched",@{@"pid":@(getpid()),@"version":@"new"});
        [NSApp performSelector:@selector(terminate:) withObject:nil afterDelay:1 inModes:@[NSRunLoopCommonModes]];
        return;
    }
    FSFixtureMarker(self.root,@"started",@{@"pid":@(getpid())});
    if([self.mode isEqual:@"direct-control"]) {
        // The old production pattern: terminateLater nests inside the serial
        // main-queue block, so the queued shutdown reply cannot be delivered.
        dispatch_async(dispatch_get_main_queue(),^{[NSApp terminate:nil];});
        return;
    }
    self.updater=[FSReleaseUpdater new];self.updater.phase=@"installing";self.updater.generation=1;
    self.updater.stage=self.stage;self.updater.backup=self.backup;
    NSTask *helper=[NSTask new];helper.executableURL=[NSURL fileURLWithPath:self.helperPath];
    helper.arguments=@[@"--install",[@(getpid()) stringValue],NSBundle.mainBundle.bundlePath,self.stage,self.backup];
    NSPipe *pipe=[NSPipe pipe];helper.standardOutput=pipe;helper.standardError=NSFileHandle.fileHandleWithNullDevice;
    if(![helper launchAndReturnError:nil])exit(3);self.updater.helper=helper;
    FSFixtureMarker(self.root,@"helper",@{@"pid":@(helper.processIdentifier)});
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSData *data=[pipe.fileHandleForReading availableData];
        id ready=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        dispatch_async(dispatch_get_main_queue(),^{
            FSFixtureMarker(self.root,@"ready",@{@"ready":[ready[@"ready"] isEqual:@YES] ? @YES : @NO});
            [self.updater handleReady:ready task:helper generation:1];
        });
    });
}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    if(self.relaunched)return NSTerminateNow;
    // This is the asynchronous contract used by Runner/AppDelegate.swift and
    // FSNativeBridge.shutdown: completion comes back on the serial main queue.
    if(self.requested)return NSTerminateLater;self.requested=YES;
    FSFixtureMarker(self.root,@"shutdown-started",@{@"requested":@YES});
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        usleep(100000);
        FSFixtureMarker(self.root,@"shutdown-worker-finished",@{@"saved":@YES});
        dispatch_async(dispatch_get_main_queue(),^{
            FSFixtureMarker(self.root,@"shutdown-completed",@{@"saved":@YES});
            [sender replyToApplicationShouldTerminate:YES];
        });
    });
    return NSTerminateLater;
}
- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    FSFixtureMarker(self.root,self.relaunched ? @"relaunched-exited" : @"old-exited",@{@"pid":@(getpid())});
}
@end
int main(int argc,const char **argv) {@autoreleasepool {
    [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    FSQuitFixture *delegate=[FSQuitFixture new];
    if(argc==5) {delegate.mode=@(argv[1]);delegate.helperPath=@(argv[2]);delegate.stage=@(argv[3]);delegate.backup=@(argv[4]);}
    NSApp.delegate=delegate;[NSApp run];return 0;
}}
