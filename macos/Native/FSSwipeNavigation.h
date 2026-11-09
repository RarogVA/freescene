#import <Cocoa/Cocoa.h>
#include <float.h>
#include <math.h>

// Observe fluid two-finger scrolling without consuming Flutter's scroll events.
// A page change is committed on finger release, never during momentum scrolling.
@interface FSSwipeBackRecognizer : NSObject
@property BOOL tracking, rejected;
@property CGFloat movementX, movementY, verticalDistance, oppositeDistance;
@property NSTimeInterval startedAt, lastNavigationAt;
- (BOOL)observe:(NSEvent *)event;
- (void)cancel;
@end

@implementation FSSwipeBackRecognizer
- (instancetype)init {
    if ((self=[super init])) self.lastNavigationAt=-DBL_MAX;
    return self;
}
- (void)cancel {
    self.tracking=self.rejected=NO;
    self.movementX=self.movementY=self.verticalDistance=self.oppositeDistance=0;
}
- (BOOL)observe:(NSEvent *)event {
    if (event.modifierFlags & (NSEventModifierFlagShift|NSEventModifierFlagControl|NSEventModifierFlagOption|NSEventModifierFlagCommand)) {
        [self cancel]; return NO;
    }
    CGFloat direction=event.isDirectionInvertedFromDevice ? -1 : 1;
    if (event.type==NSEventTypeSwipe) {
        [self cancel];
        // AppKit's discrete swipe events use -1 for a physical swipe right.
        BOOL back=event.deltaX*direction < -0.5 && fabs(event.deltaY)<0.25;
        if (back && event.timestamp-self.lastNavigationAt>=0.45) {
            self.lastNavigationAt=event.timestamp; return YES;
        }
        return NO;
    }
    if (event.type!=NSEventTypeScrollWheel || !event.hasPreciseScrollingDeltas ||
        event.momentumPhase!=NSEventPhaseNone || event.phase==NSEventPhaseNone) {
        [self cancel]; return NO;
    }
    if (event.phase & NSEventPhaseCancelled) { [self cancel]; return NO; }
    if (event.phase & NSEventPhaseBegan) {
        [self cancel]; self.tracking=YES; self.startedAt=event.timestamp;
    }
    if (!self.tracking) return NO;
    CGFloat x=event.scrollingDeltaX*direction,y=event.scrollingDeltaY*direction;
    if (!isfinite(x) || !isfinite(y)) { [self cancel]; return NO; }
    self.movementX+=x; self.movementY+=y;
    self.verticalDistance+=fabs(y); self.oppositeDistance+=MAX(0,x);
    // Lock the initial intent. A vertical scroll must not become Back after
    // incidental sideways drift; a reversed gesture must not navigate either.
    if (MAX(fabs(self.movementX),fabs(self.movementY))>=12 &&
        (self.movementX>=0 || fabs(self.movementX)<fabs(self.movementY)*1.8)) self.rejected=YES;
    if (!(event.phase & NSEventPhaseEnded)) return NO;
    BOOL back=!self.rejected && self.movementX<=-80 &&
        fabs(self.movementX)>=self.verticalDistance*2 &&
        self.oppositeDistance<=fabs(self.movementX)*0.2 &&
        event.timestamp-self.startedAt<=2.0 &&
        event.timestamp-self.lastNavigationAt>=0.45;
    [self cancel];
    if (back) self.lastNavigationAt=event.timestamp;
    return back;
}
@end

static BOOL FSBackSwipeHasHorizontalScroller(NSView *view) {
    for (NSView *candidate=view;candidate;candidate=candidate.superview) {
        if (![candidate isKindOfClass:NSScrollView.class]) continue;
        NSScrollView *scroll=(NSScrollView *)candidate;
        if (NSWidth(scroll.documentView.frame)>NSWidth(scroll.contentView.bounds)+1) return YES;
    }
    return NO;
}

@interface FSSwipeNavigation : NSObject
@property(weak) NSWindow *window;
@property(weak) NSView *view;
@property FSSwipeBackRecognizer *recognizer;
@property id monitor;
@property NSPoint origin;
@property(copy) void (^navigateBack)(NSDictionary *point);
- (instancetype)initWithWindow:(NSWindow *)window view:(NSView *)view navigateBack:(void (^)(NSDictionary *point))navigateBack;
- (void)observe:(NSEvent *)event;
- (void)invalidate;
@end

@implementation FSSwipeNavigation
- (instancetype)initWithWindow:(NSWindow *)window view:(NSView *)view navigateBack:(void (^)(NSDictionary *))navigateBack {
    if (!(self=[super init])) return nil;
    self.window=window;self.view=view;self.navigateBack=navigateBack;
    self.recognizer=[FSSwipeBackRecognizer new];
    __weak FSSwipeNavigation *weakSelf=self;
    self.monitor=[NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskScrollWheel|NSEventMaskSwipe handler:^NSEvent *(NSEvent *event) {
        [weakSelf observe:event]; return event;
    }];
    return self;
}
- (void)observe:(NSEvent *)event {
    NSWindow *window=self.window; NSView *view=self.view;
    // The player has its own progressive seek gesture. Sheets, native About,
    // background windows and native text editing never cause page navigation.
    if (!window || !view || event.window!=window || !window.visible ||
        !window.keyWindow || window.miniaturized || NSApp.modalWindow ||
        window.attachedSheet || [window.firstResponder isKindOfClass:NSTextView.class] ||
        [window.firstResponder isKindOfClass:NSTextField.class]) {
        [self.recognizer cancel]; return;
    }
    NSPoint point=[view convertPoint:event.locationInWindow fromView:nil];
    if (!NSPointInRect(point,view.bounds)) { [self.recognizer cancel]; return; }
    if (event.type==NSEventTypeSwipe || (event.phase & NSEventPhaseBegan)) {
        NSPoint hitPoint=view.superview ? [view.superview convertPoint:event.locationInWindow fromView:nil] : event.locationInWindow;
        if (FSBackSwipeHasHorizontalScroller([view hitTest:hitPoint])) { [self.recognizer cancel]; return; }
        self.origin=NSMakePoint(point.x-NSMinX(view.bounds),view.flipped ? point.y-NSMinY(view.bounds) : NSMaxY(view.bounds)-point.y);
    }
    if ([self.recognizer observe:event] && self.navigateBack) {
        // Flutter performs the route/modal and horizontal-table checks. Points
        // are in Flutter view logical coordinates, before application scaling.
        self.navigateBack(@{@"x":@(self.origin.x),@"y":@(self.origin.y)});
    }
}
- (void)invalidate {
    if (self.monitor) { [NSEvent removeMonitor:self.monitor]; self.monitor=nil; }
    [self.recognizer cancel]; self.navigateBack=nil;
}
- (void)dealloc { [self invalidate]; }
@end
