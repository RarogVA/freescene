#import "../../macos/Native/FSWebFullscreen.h"
#include <assert.h>

// No windows, media, network or Spaces are changed by these lifecycle checks.
@interface FSFullscreenWindowSpy : NSObject
@property(getter=isVisible) BOOL visible;
@property NSUInteger hides, shows;
@property NSWindowStyleMask styleMask;
@property NSUInteger nativeExits;
- (void)orderOut:(id)sender;
- (void)orderFront:(id)sender;
- (void)toggleFullScreen:(id)sender;
@end
@implementation FSFullscreenWindowSpy
- (void)orderOut:(id)sender { self.visible=NO;++self.hides; }
- (void)orderFront:(id)sender { self.visible=YES;++self.shows; }
- (void)toggleFullScreen:(id)sender { ++self.nativeExits; }
@end
@interface FSFullscreenWebSpy : NSObject
@property WKFullscreenState fullscreenState;
@property NSWindow *window;
@property NSUInteger closes;
@property(copy) void (^closed)(void);
@end
@implementation FSFullscreenWebSpy
- (void)closeAllMediaPresentationsWithCompletionHandler:(void (^)(void))completion { ++self.closes;self.closed=completion; }
@end
@interface FSFullscreenContainerSpy : NSObject
@property NSWindow *window;
@end
@implementation FSFullscreenContainerSpy
@end

static int checks;
static void check(BOOL condition) { assert(condition);++checks; }
int main(void) { @autoreleasepool {
    FSFullscreenWindowSpy *host=[FSFullscreenWindowSpy new],*video=[FSFullscreenWindowSpy new];
    FSFullscreenWebSpy *web=[FSFullscreenWebSpy new];
    FSFullscreenContainerSpy *container=[FSFullscreenContainerSpy new];
    container.window=(NSWindow *)host;host.visible=YES;web.window=(NSWindow *)host;
    FSWebFullscreen *fullscreen=[[FSWebFullscreen alloc] initWithWebView:(WKWebView *)web container:(NSView *)container];
    // Native green-button fullscreen never hides the window showing the video.
    web.fullscreenState=WKFullscreenStateEnteringFullscreen;
    web.fullscreenState=WKFullscreenStateInFullscreen;
    check(host.visible && host.hides==0);
    web.fullscreenState=WKFullscreenStateNotInFullscreen;
    check(host.shows==0);
    // Only WebKit's separate video window hides the placeholder host.
    web.fullscreenState=WKFullscreenStateEnteringFullscreen;
    web.window=(NSWindow *)video;
    check(host.visible);
    web.fullscreenState=WKFullscreenStateInFullscreen;
    check(!host.visible && host.hides==1);
    web.fullscreenState=WKFullscreenStateInFullscreen;
    check(host.hides==1);
    web.fullscreenState=WKFullscreenStateExitingFullscreen;
    check(host.visible && host.shows==1);
    web.window=(NSWindow *)host;
    web.fullscreenState=WKFullscreenStateNotInFullscreen;
    check(host.shows==1);
    // Web process failure can skip the intermediate exiting state.
    web.window=(NSWindow *)video;web.fullscreenState=WKFullscreenStateInFullscreen;
    web.fullscreenState=WKFullscreenStateNotInFullscreen;
    check(host.visible && host.shows==2);
    // A host that was hidden beforehand must stay hidden on fullscreen exit.
    host.visible=NO;web.fullscreenState=WKFullscreenStateInFullscreen;
    web.fullscreenState=WKFullscreenStateNotInFullscreen;
    check(!host.visible && host.shows==2);
    // Replacing/closing a provider removes observation before WebKit's late exit.
    host.visible=YES;web.fullscreenState=WKFullscreenStateInFullscreen;
    check(!host.visible);
    [fullscreen stop];[fullscreen stop];
    web.fullscreenState=WKFullscreenStateExitingFullscreen;
    web.fullscreenState=WKFullscreenStateNotInFullscreen;
    check(!host.visible && host.shows==2);
    fullscreen=nil;
    // Removing the container cannot resurrect an old player window.
    host.visible=YES;
    fullscreen=[[FSWebFullscreen alloc] initWithWebView:(WKWebView *)web container:(NSView *)container];
    web.fullscreenState=WKFullscreenStateInFullscreen;
    check(!host.visible);
    container.window=nil;web.fullscreenState=WKFullscreenStateNotInFullscreen;
    check(!host.visible && host.shows==2);
    __weak FSWebFullscreen *weakFullscreen=fullscreen;fullscreen=nil;
    check(!weakFullscreen);
    web.fullscreenState=WKFullscreenStateInFullscreen;
    check(host.shows==2);
    // Esc affects only our host or the window WebKit moved this view into.
    container.window=(NSWindow *)host;web.window=(NSWindow *)host;host.visible=YES;
    web.fullscreenState=WKFullscreenStateNotInFullscreen;
    fullscreen=[[FSWebFullscreen alloc] initWithWebView:(WKWebView *)web container:(NSView *)container];
    check(![fullscreen exitFromWindow:(NSWindow *)host]);
    host.styleMask=NSWindowStyleMaskFullScreen;
    check(![fullscreen exitFromWindow:(NSWindow *)video]);
    check([fullscreen exitFromWindow:(NSWindow *)host] && host.nativeExits==1);
    check([fullscreen exitFromWindow:(NSWindow *)host] && host.nativeExits==1);
    host.styleMask=0;
    [NSNotificationCenter.defaultCenter postNotificationName:NSWindowDidExitFullScreenNotification object:host];
    check(!fullscreen.escaping && ![fullscreen exitFromWindow:(NSWindow *)host]);
    host.styleMask=NSWindowStyleMaskFullScreen;web.window=(NSWindow *)video;
    web.fullscreenState=WKFullscreenStateInFullscreen;
    check(![fullscreen exitFromWindow:(NSWindow *)video] && web.closes==0 && host.nativeExits==1);
    check([fullscreen exitFromWindow:(NSWindow *)video] && web.closes==0);
    check(host.nativeExits==1 && fullscreen.escaping);
    web.fullscreenState=WKFullscreenStateExitingFullscreen;
    web.fullscreenState=WKFullscreenStateNotInFullscreen;
    [fullscreen completeEscapeIfReady];check(host.nativeExits==1);
    web.window=(NSWindow *)host;[fullscreen completeEscapeIfReady];
    check(host.nativeExits==2 && fullscreen.escaping);
    check([fullscreen exitFromWindow:(NSWindow *)host] && host.nativeExits==2);
    host.styleMask=0;
    [NSNotificationCenter.defaultCenter postNotificationName:NSWindowDidExitFullScreenNotification object:host];
    check(!fullscreen.escaping);
    // Web-only fullscreen exits without toggling a normal native window.
    web.window=(NSWindow *)video;web.fullscreenState=WKFullscreenStateInFullscreen;
    check(![fullscreen exitFromWindow:(NSWindow *)video] && web.closes==0);
    web.fullscreenState=WKFullscreenStateExitingFullscreen;
    web.window=(NSWindow *)host;web.fullscreenState=WKFullscreenStateNotInFullscreen;
    [fullscreen completeEscapeIfReady];
    check(host.nativeExits==2 && !fullscreen.escaping);
    // Switching source during Esc cannot toggle the next source's window.
    host.styleMask=NSWindowStyleMaskFullScreen;web.window=(NSWindow *)video;web.fullscreenState=WKFullscreenStateInFullscreen;
    check(![fullscreen exitFromWindow:(NSWindow *)video]);
    [fullscreen stop];[fullscreen completeEscapeIfReady];
    check(host.nativeExits==2 && !fullscreen.escaping);
    printf("{\"passed\":true,\"checks\":%d,\"nativeFullscreenPreserved\":true,\"placeholderHostHidden\":true,\"hostRestoredOnExit\":true,\"lateExitCannotResurrectClosedPlayer\":true,\"oneEscapeExitsNestedFullscreen\":true,\"repeatedEscapeDoesNotToggleTwice\":true,\"staleEscapeIgnored\":true}\n",checks);
} return 0; }
