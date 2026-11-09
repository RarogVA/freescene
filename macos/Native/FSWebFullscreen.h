#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN
static char FSWebFullscreenObservation;

// WebKit moves its view into a separate fullscreen window and leaves a
// placeholder in our player. Keep that empty host out of the other Spaces.
@interface FSWebFullscreen : NSObject
@property(weak, nullable) WKWebView *web;
@property(weak, nullable) NSView *container;
@property(weak, nullable) NSWindow *hiddenHost;
@property BOOL observing;
@property BOOL escaping;
@property NSUInteger escapeGeneration;
@property(nullable) id nativeExitObserver;
@property(nullable) NSTimer *escapeTimer;
@property BOOL nativeExitPending;
@property NSUInteger escapeChecks;
- (instancetype)initWithWebView:(WKWebView *)web container:(NSView *)container;
- (BOOL)exitFromWindow:(nullable NSWindow *)window;
- (void)finishEscape;
- (void)completeEscapeIfReady;
- (void)stop;
@end

@implementation FSWebFullscreen
- (instancetype)initWithWebView:(WKWebView *)web container:(NSView *)container {
    if (!(self=[super init])) return nil;
    self.web=web;self.container=container;
    [web addObserver:self forKeyPath:@"fullscreenState" options:0 context:&FSWebFullscreenObservation];
    self.observing=YES;
    __weak FSWebFullscreen *weak=self;
    self.nativeExitObserver=[NSNotificationCenter.defaultCenter addObserverForName:NSWindowDidExitFullScreenNotification object:nil queue:nil usingBlock:^(NSNotification *note){
        FSWebFullscreen *owner=weak;
        if(note.object==owner.container.window)[owner finishEscape];
    }];
    return self;
}
- (void)finishEscape {
    self.escaping=NO;self.nativeExitPending=NO;
    [self.escapeTimer invalidate];self.escapeTimer=nil;
}
- (void)completeEscapeIfReady {
    if(!self.observing || !self.escaping || !self.nativeExitPending)return;
    NSWindow *host=self.container.window;WKWebView *web=self.web;
    // Wait for WebKit to restore the view before starting AppKit's exit.
    if(web.fullscreenState!=WKFullscreenStateNotInFullscreen || web.window!=host)return;
    self.nativeExitPending=NO;[self.escapeTimer invalidate];self.escapeTimer=nil;
    if(host.styleMask&NSWindowStyleMaskFullScreen)[host toggleFullScreen:nil];
    else [self finishEscape];
}
- (BOOL)exitFromWindow:(nullable NSWindow *)window {
    WKWebView *web=self.web;NSWindow *host=self.container.window;
    if(!self.observing || !window || !host || (window!=host && window!=web.window))return NO;
    if(self.escaping)return YES;
    BOOL webFullscreen=web.fullscreenState!=WKFullscreenStateNotInFullscreen;
    if(!webFullscreen && !(host.styleMask&NSWindowStyleMaskFullScreen))return NO;
    self.escaping=YES;self.escapeChecks=0;
    self.nativeExitPending=YES;NSUInteger generation=++self.escapeGeneration;
    __weak FSWebFullscreen *weak=self;
    // WebKit first restores its view. Then leave the enclosing native Space.
    // Consume repeated Esc presses until AppKit finishes that transition.
    if(webFullscreen) {
        self.escapeTimer=[NSTimer timerWithTimeInterval:0.05 repeats:YES block:^(NSTimer *timer){
            FSWebFullscreen *owner=weak;
            if(!owner.observing || generation!=owner.escapeGeneration){[timer invalidate];return;}
            if(++owner.escapeChecks>100){[owner finishEscape];return;}
            [owner completeEscapeIfReady];
        }];
        [NSRunLoop.mainRunLoop addTimer:self.escapeTimer forMode:NSRunLoopCommonModes];
        // Let WebKit handle the original key event. Forcing media dismissal
        // here can strand its view while the enclosing AppKit Space is active.
        if(window==web.window)return NO;
        [web evaluateJavaScript:@"document.exitFullscreen ? document.exitFullscreen() : document.webkitExitFullscreen?.()" completionHandler:nil];
    } else [self completeEscapeIfReady];
    return YES;
}
- (void)observeValueForKeyPath:(nullable NSString *)keyPath ofObject:(nullable id)object change:(nullable NSDictionary *)change context:(nullable void *)context {
    if(context!=&FSWebFullscreenObservation) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];return;
    }
    WKWebView *web=self.web;
    if(!self.observing || object!=web) return;
    NSWindow *host=self.container.window;
    if(web.fullscreenState==WKFullscreenStateInFullscreen) {
        // Native macOS fullscreen keeps the web view in the same window.
        // Only hide the host after WebKit has moved it into another window.
        if(host.visible && web.window && web.window!=host) {
            self.hiddenHost=host;
            [host orderOut:nil];
        }
    } else if(web.fullscreenState==WKFullscreenStateExitingFullscreen || web.fullscreenState==WKFullscreenStateNotInFullscreen) {
        NSWindow *hidden=self.hiddenHost;self.hiddenHost=nil;
        if(hidden && host==hidden) [hidden orderFront:nil];
    }
}
- (void)stop {
    ++self.escapeGeneration;[self finishEscape];
    if(self.nativeExitObserver)[NSNotificationCenter.defaultCenter removeObserver:self.nativeExitObserver];
    self.nativeExitObserver=nil;
    if(self.observing) {
        [self.web removeObserver:self forKeyPath:@"fullscreenState" context:&FSWebFullscreenObservation];
        self.observing=NO;
    }
    // A closing/replaced player must not reappear when WebKit finishes exiting.
    self.hiddenHost=nil;self.container=nil;self.web=nil;
}
- (void)dealloc { [self stop]; }
@end
NS_ASSUME_NONNULL_END
