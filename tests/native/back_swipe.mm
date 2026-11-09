// Headless: calls the production recognizer directly; never posts desktop input.
#import "../../macos/Native/FSSwipeNavigation.h"

static NSUInteger checks=0;
static void check(BOOL value,const char *message) {
    ++checks; if (!value) { fprintf(stderr,"FAILED: %s\n",message);exit(1); }
}

@interface FSSwipeFixture : NSEvent
@property NSEventType type;
@property NSEventPhase phase,momentumPhase;
@property NSEventModifierFlags modifierFlags;
@property BOOL hasPreciseScrollingDeltas;
@property(getter=isDirectionInvertedFromDevice) BOOL inverted;
@property CGFloat scrollingDeltaX,scrollingDeltaY,deltaX,deltaY;
@property NSTimeInterval timestamp;
@property NSWindow *window;
@property NSPoint locationInWindow;
@end
@implementation FSSwipeFixture
@synthesize type=_type,phase=_phase,momentumPhase=_momentumPhase,modifierFlags=_modifierFlags;
@synthesize hasPreciseScrollingDeltas=_hasPreciseScrollingDeltas,inverted=_inverted;
@synthesize scrollingDeltaX=_scrollingDeltaX,scrollingDeltaY=_scrollingDeltaY,deltaX=_deltaX,deltaY=_deltaY,timestamp=_timestamp;
@synthesize window=_window,locationInWindow=_locationInWindow;
@end

@interface FSSwipeWindowFixture : NSObject
@property(getter=isVisible) BOOL visible;
@property(getter=isKeyWindow) BOOL keyWindow;
@property(getter=isMiniaturized) BOOL miniaturized;
@property NSWindow *attachedSheet;
@property NSResponder *firstResponder;
@end
@implementation FSSwipeWindowFixture
@end

@interface FSSwipeViewFixture : NSView
@property BOOL fixtureFlipped;
@property NSView *fixtureHit;
@end
@implementation FSSwipeViewFixture
- (BOOL)isFlipped { return self.fixtureFlipped; }
- (NSPoint)convertPoint:(NSPoint)point fromView:(NSView *)view { return NSMakePoint(point.x-10,point.y-20); }
- (NSView *)hitTest:(NSPoint)point { return self.fixtureHit ?: self; }
@end

static FSSwipeFixture *fixture(void) {
    FSSwipeFixture *event=[FSSwipeFixture new];
    event.type=NSEventTypeScrollWheel;event.hasPreciseScrollingDeltas=YES;
    return event;
}
static BOOL send(FSSwipeBackRecognizer *recognizer,FSSwipeFixture *event,NSEventPhase phase,CGFloat x,CGFloat y) {
    event.phase=phase;event.scrollingDeltaX=x;event.scrollingDeltaY=y;event.timestamp+=0.05;
    return [recognizer observe:event];
}
static BOOL gesture(FSSwipeBackRecognizer *recognizer,FSSwipeFixture *event,CGFloat x,CGFloat y) {
    event.timestamp+=1;
    check(!send(recognizer,event,NSEventPhaseBegan,x,y),"never navigate at gesture start");
    return send(recognizer,event,NSEventPhaseEnded,0,0);
}

int main(void) { @autoreleasepool {
    FSSwipeBackRecognizer *recognizer=[FSSwipeBackRecognizer new];
    FSSwipeFixture *event=fixture();
    check(!send(recognizer,event,NSEventPhaseBegan,-30,1),"finger start does not navigate");
    check(!send(recognizer,event,NSEventPhaseChanged,-90,1),"crossing threshold does not navigate before release");
    check(send(recognizer,event,NSEventPhaseEnded,0,0),"rightward horizontal gesture navigates at release");
    check(!send(recognizer,event,NSEventPhaseEnded,0,0),"one navigation per gesture");
    event.momentumPhase=NSEventPhaseChanged;
    check(!send(recognizer,event,NSEventPhaseNone,-500,0),"momentum cannot navigate");
    event.momentumPhase=NSEventPhaseNone;
    check(!gesture(recognizer,event,-50,0),"short horizontal scroll ignored");
    check(!gesture(recognizer,event,120,0),"opposite horizontal direction ignored");
    check(!gesture(recognizer,event,-100,80),"diagonal scroll ignored");
    event.timestamp+=1;
    send(recognizer,event,NSEventPhaseBegan,0,20);send(recognizer,event,NSEventPhaseChanged,-180,0);
    check(!send(recognizer,event,NSEventPhaseEnded,0,0),"vertical initial intent cannot later become Back");
    event.timestamp+=1;
    send(recognizer,event,NSEventPhaseBegan,-100,0);send(recognizer,event,NSEventPhaseChanged,55,0);
    check(!send(recognizer,event,NSEventPhaseEnded,-40,0),"substantial reversal cancels Back");
    event.timestamp+=1;
    send(recognizer,event,NSEventPhaseBegan,-150,0);
    check(!send(recognizer,event,NSEventPhaseCancelled,0,0),"cancelled gesture ignored");
    check(!send(recognizer,event,NSEventPhaseEnded,0,0),"cancel cannot leak to subsequent release");
    check(!send(recognizer,event,NSEventPhaseChanged,-150,0),"missing start ignored");
    check(!send(recognizer,event,NSEventPhaseEnded,0,0),"missing start cannot commit");
    event.hasPreciseScrollingDeltas=NO;
    check(!gesture(recognizer,event,-150,0),"mouse wheel cannot navigate");
    event.hasPreciseScrollingDeltas=YES;
    check(!send(recognizer,event,NSEventPhaseNone,-150,0),"unphased smooth scrolling cannot navigate");
    event.inverted=YES;
    check(gesture(recognizer,event,120,0),"Natural Scrolling preserves physical rightward direction");
    check(!gesture(recognizer,event,-120,0),"Natural Scrolling opposite direction ignored");
    event.inverted=NO;event.modifierFlags=NSEventModifierFlagShift;
    check(!gesture(recognizer,event,-150,0),"modified wheel input ignored");
    event.modifierFlags=0;
    event.timestamp+=1;send(recognizer,event,NSEventPhaseBegan,-150,0);event.timestamp+=3;
    check(!send(recognizer,event,NSEventPhaseEnded,0,0),"stale gesture ignored");
    event.timestamp+=1;send(recognizer,event,NSEventPhaseBegan,-100,0);[recognizer cancel];
    check(!send(recognizer,event,NSEventPhaseEnded,0,0),"window or modal cancellation prevents navigation");
    event.type=NSEventTypeSwipe;event.timestamp+=1;event.deltaX=-1;event.deltaY=0;
    check([recognizer observe:event],"AppKit discrete physical swipe right supported");
    event.timestamp+=0.1;
    check(![recognizer observe:event],"duplicate scroll/swipe completion debounced");
    event.timestamp+=1;event.deltaX=1;
    check(![recognizer observe:event],"discrete swipe left ignored");
    event.timestamp+=1;event.inverted=YES;
    check([recognizer observe:event],"discrete swipe honors inversion metadata");
    event.timestamp+=1;event.deltaY=1;
    check(![recognizer observe:event],"discrete diagonal ignored");

    // Real Cocoa events exercise the public AppKit phase/delta mapping rather
    // than relying exclusively on test doubles. No CGEvent is posted.
    recognizer=[FSSwipeBackRecognizer new];
    CGEventRef raw=CGEventCreateScrollWheelEvent(NULL,kCGScrollEventUnitPixel,2,0,-120);
    CGEventSetIntegerValueField(raw,kCGScrollWheelEventIsContinuous,1);
    CGEventSetIntegerValueField(raw,kCGScrollWheelEventScrollPhase,NSEventPhaseBegan);
    NSEvent *native=[NSEvent eventWithCGEvent:raw];
    check(native.type==NSEventTypeScrollWheel && native.hasPreciseScrollingDeltas && (native.phase & NSEventPhaseBegan),"synthetic Cocoa event is a precise phased scroll");
    check(![recognizer observe:native],"real phased event waits for release");
    CGEventSetIntegerValueField(raw,kCGScrollWheelEventScrollPhase,NSEventPhaseCancelled);
    check(![recognizer observe:[NSEvent eventWithCGEvent:raw]],"real Cocoa cancellation cannot navigate");
    CFRelease(raw);
    // The coordinator is called directly against inert window fixtures. It
    // registers no event monitor and does not create/show an NSApplication.
    FSSwipeWindowFixture *window=[FSSwipeWindowFixture new];window.visible=window.keyWindow=YES;
    FSSwipeViewFixture *view=[[FSSwipeViewFixture alloc] initWithFrame:NSMakeRect(0,0,500,300)];
    FSSwipeNavigation *navigation=[FSSwipeNavigation new];
    navigation.recognizer=[FSSwipeBackRecognizer new];navigation.window=(NSWindow *)window;navigation.view=view;
    __block NSUInteger navigations=0;__block NSDictionary *point=nil;
    navigation.navigateBack=^(NSDictionary *origin) { ++navigations;point=origin; };
    event=fixture();event.window=(NSWindow *)window;event.locationInWindow=NSMakePoint(60,120);
    void (^navigate)(void)=^{
        event.timestamp+=1;event.phase=NSEventPhaseBegan;event.scrollingDeltaX=-120;event.scrollingDeltaY=0;
        [navigation observe:event];event.timestamp+=0.1;event.phase=NSEventPhaseEnded;event.scrollingDeltaX=0;[navigation observe:event];
    };
    navigate();check(navigations==1,"main window forwards one native back event");
    check([point[@"x"] doubleValue]==50 && [point[@"y"] doubleValue]==200,"unflipped Cocoa point converts to top-left Flutter coordinates");
    view.fixtureFlipped=YES;navigate();
    check([point[@"x"] doubleValue]==50 && [point[@"y"] doubleValue]==100,"flipped Flutter view point is not inverted twice");
    NSUInteger before=navigations;
    window.keyWindow=NO;navigate();check(navigations==before,"background main window ignored");window.keyWindow=YES;
    window.miniaturized=YES;navigate();check(navigations==before,"minimized main window ignored");window.miniaturized=NO;
    window.visible=NO;navigate();check(navigations==before,"hidden main window ignored");window.visible=YES;
    FSSwipeWindowFixture *other=[FSSwipeWindowFixture new];event.window=(NSWindow *)other;
    navigate();check(navigations==before,"player and About window events ignored");event.window=(NSWindow *)window;
    window.attachedSheet=(NSWindow *)other;navigate();check(navigations==before,"attached modal sheet ignored");window.attachedSheet=nil;
    window.firstResponder=[NSTextView alloc];navigate();check(navigations==before,"native text editing ignored");window.firstResponder=nil;
    event.locationInWindow=NSMakePoint(900,100);navigate();check(navigations==before,"outside Flutter content ignored");event.locationInWindow=NSMakePoint(60,120);
    NSScrollView *horizontal=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,100,100)];
    horizontal.documentView=[[NSView alloc] initWithFrame:NSMakeRect(0,0,400,100)];
    view.fixtureHit=horizontal.documentView;navigate();check(navigations==before,"native horizontal scrolling keeps its gesture");
    view.fixtureHit=nil;navigate();check(navigations==before+1,"navigation recovers after rejected contexts");
    [navigation invalidate];navigate();check(navigations==before+1,"shutdown invalidation prevents late callbacks");
    printf("{\"passed\":true,\"checks\":%lu,\"commitOnRelease\":true,\"naturalScrolling\":true,\"verticalAndMomentumIgnored\":true,\"mouseWheelIgnored\":true,\"cocoaEventsNotPosted\":true}\n",(unsigned long)checks);
} }
