#import "../../macos/Native/FSNativeBridge.mm"
#include <cassert>
static BOOL until(BOOL (^condition)(void),double seconds=10) {
    NSDate *end=[NSDate dateWithTimeIntervalSinceNow:seconds];
    while(!condition() && end.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    return condition();
}
int main(int argc,char **argv) { @autoreleasepool {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    NSString *address=[NSString stringWithUTF8String:argv[1]];
    FSWebPlaybackContext *context=[FSWebPlaybackContext new];
    context.navigation=^BOOL(NSURL *target,NSURL *source,BOOL main){return [target.host isEqual:@"127.0.0.1"] || [target.host isEqual:@"localhost"];};
    context.sameTitle=^BOOL(NSURL *target,NSURL *source){return [target.host isEqual:source.host];};
    NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(100,100,1100,700) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    window.title=@"FreeScene — Web player verification";
    FSProviderView *view=[[FSProviderView alloc] initWithURL:[NSURL URLWithString:address] frame:window.contentView.bounds player:0 episodes:@[] context:context];
    view.watchedClock=[FSWatchedClock new];view.watchedClock.source=address;view.watchedClock.title=@"fixture-film";
    view.providerName=@"Fixture provider";[window.contentView addSubview:view];[window makeKeyAndOrderFront:nil];
    assert(until(^BOOL{return view.lastPlaybackReport>0 && [view.playbackState[@"duration"] doubleValue]>170;}));
    assert(view.playButton.enabled && view.position.enabled);
    [view togglePlayback:nil];assert(until(^BOOL{return [view.playbackState[@"playing"] boolValue];}));
    view.position.doubleValue=0.5;[view seek:nil];assert(until(^BOOL{return [view.playbackState[@"position"] doubleValue]>=90;}));
    [view togglePlayback:nil];assert(until(^BOOL{return [view.playbackState[@"paused"] boolValue];}));
    [view skipBack:nil];assert(until(^BOOL{return [view.playbackState[@"position"] doubleValue]<82;}));
    assert(view.watchedClock.elapsed<10 && !FSWatchedSnapshot()[address]);
    double elapsed=view.watchedClock.elapsed;
    NSDate *pauseUntil=[NSDate dateWithTimeIntervalSinceNow:2];
    while(pauseUntil.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];
    assert(fabs(view.watchedClock.elapsed-elapsed)<.1);
    view.watchedClock.elapsed=59;
    [view togglePlayback:nil];
    assert(until(^BOOL{return [FSWatchedSnapshot()[address] isEqual:@"fixture-film"];},5));
    [view togglePlayback:nil];assert(until(^BOOL{return [view.playbackState[@"paused"] boolValue];}));
    [view sendAction:@"volume" value:@0.25];assert(until(^BOOL{return [view.playbackState[@"volume"] doubleValue]==0.25;}));
    [view toggleNative:nil];assert(!view.nativeControls);[view toggleNative:nil];assert(view.nativeControls);
    assert([view.message.stringValue isEqual:@"Официальный плеер «Fixture provider»"]);
    [window.contentView layoutSubtreeIfNeeded];
    NSBitmapImageRep *shot=[view bitmapImageRepForCachingDisplayInRect:view.bounds];[view cacheDisplayInRect:view.bounds toBitmapImageRep:shot];
    [[shot representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[NSString stringWithUTF8String:argv[2]] atomically:YES];
    for(NSNumber *width in @[@640,@1100]) {
        [window setContentSize:NSMakeSize(width.doubleValue,700)];[window.contentView layoutSubtreeIfNeeded];
        for(NSView *button in @[view.playButton,view.retryButton,view.fullButton,view.nativeButton]) {
            NSRect frame=[button convertRect:button.bounds toView:view];assert(NSMinX(frame)>=0 && NSMaxX(frame)<=view.bounds.size.width+1);
        }
    }
    [view stop];assert(!view.web && !view.playbackTimer);[window orderOut:nil];
    puts("WebKit controls: playback, seek, pause, volume, provider fallback, label, responsive native layout and teardown passed");
}return 0;}
