#import <Cocoa/Cocoa.h>

static inline double FSSeekPreviewPosition(double anchor,double movement) {
    return MIN(1.0,MAX(0.0,anchor+movement));
}

@interface FSVideoView : NSView
@property(copy) void (^singleClick)(void);
@property(copy) void (^doubleClick)(void);
@property(copy) BOOL (^seekBegan)(void);
@property(copy) void (^seekChanged)(double);
@property(copy) void (^seekEnded)(BOOL);
@property(copy) void (^activity)(void);
@property(copy) BOOL (^acceptsPlaybackEvent)(NSEvent *);
@property BOOL scrolling,seeking;
@property CGFloat scrollX,scrollY,gestureWidth;
@property NSUInteger scrollGeneration;
- (BOOL)consumeScroll:(NSEvent *)event;
- (void)cancelInput;
@end

@implementation FSVideoView
- (BOOL)isOpaque { return YES; }
- (void)drawRect:(NSRect)dirty {
    [NSColor.blackColor setFill]; NSRectFill(dirty);
}
- (BOOL)acceptsFirstResponder { return YES; }
- (void)mouseDown:(NSEvent *)event {
    [self cancelInput];
    if (self.activity) self.activity();
    if (self.acceptsPlaybackEvent && !self.acceptsPlaybackEvent(event)) return;
    if (event.clickCount==2) { if(self.doubleClick) self.doubleClick(); }
    else [self performSelector:@selector(delayedClick) withObject:nil afterDelay:NSEvent.doubleClickInterval];
}
- (void)delayedClick { if(self.singleClick) self.singleClick(); }
- (void)mouseMoved:(NSEvent *)event { if(self.activity) self.activity(); }
- (void)finishGesture:(BOOL)cancelled {
    BOOL seeking=self.seeking;
    self.scrolling=self.seeking=NO; self.scrollX=self.scrollY=0; ++self.scrollGeneration;
    if(seeking && self.seekEnded) self.seekEnded(cancelled);
}
- (void)cancelInput {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [self finishGesture:YES];
}
- (BOOL)consumeScroll:(NSEvent *)event {
    if(event.momentumPhase!=NSEventPhaseNone) return NO;
    if(event.phase & NSEventPhaseCancelled) {
        BOOL handled=self.seeking; [self finishGesture:YES]; return handled;
    }
    if(!event.hasPreciseScrollingDeltas) return NO;
    if(!self.scrolling && (event.phase & NSEventPhaseEnded)) return NO;
    if((event.phase & NSEventPhaseBegan) || !self.scrolling) {
        [self cancelInput]; self.scrolling=YES;
        self.gestureWidth=MAX(1,NSWidth(self.bounds));
    }
    if(self.activity) self.activity();
    // Match physical finger direction regardless of Natural Scrolling.
    CGFloat direction=event.isDirectionInvertedFromDevice ? -1 : 1;
    self.scrollX+=event.scrollingDeltaX*direction;
    self.scrollY+=event.scrollingDeltaY*direction;
    if(!self.seeking && fabs(self.scrollX)>=6 && fabs(self.scrollX)>fabs(self.scrollY)*1.5)
        self.seeking=self.seekBegan && self.seekBegan();
    BOOL handled=self.seeking;
    if(self.seeking && self.seekChanged) self.seekChanged(-self.scrollX/self.gestureWidth);
    if(event.phase & NSEventPhaseEnded) [self finishGesture:NO];
    else if(event.phase==NSEventPhaseNone) {
        // Some precise devices omit phases. Commit once after their input ends.
        NSUInteger generation=++self.scrollGeneration; __weak FSVideoView *weak=self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.18*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
            FSVideoView *view=weak;
            if(view && view.scrollGeneration==generation) [view finishGesture:NO];
        });
    }
    return handled;
}
- (void)scrollWheel:(NSEvent *)event {
    if(!self.scrolling && self.acceptsPlaybackEvent && !self.acceptsPlaybackEvent(event)) return;
    [self consumeScroll:event];
}
- (void)keyDown:(NSEvent *)event {
    if(event.keyCode==53 && (self.window.styleMask & NSWindowStyleMaskFullScreen)) [self.window toggleFullScreen:nil];
    else if([event.characters isEqualToString:@" "]) { if(self.singleClick) self.singleClick(); }
    else [super keyDown:event];
}
@end
