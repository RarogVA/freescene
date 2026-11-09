// Calls the recognizer directly. Never posts input events to the desktop.
#import "../../macos/Native/FSVideoView.h"
#include <cassert>

@interface FSTestScroll : NSObject
@property NSEventPhase phase,momentumPhase;
@property BOOL hasPreciseScrollingDeltas;
@property(getter=isDirectionInvertedFromDevice) BOOL inverted;
@property CGFloat scrollingDeltaX,scrollingDeltaY;
@end
@implementation FSTestScroll
@end

int main() { @autoreleasepool {
    FSVideoView *view=[[FSVideoView alloc] initWithFrame:NSMakeRect(0,0,1000,600)];
    NSMutableArray *preview=[NSMutableArray new], *end=[NSMutableArray new];
    __block int begins=0;
    view.seekBegan=^BOOL { ++begins; return YES; };
    view.seekChanged=^(double movement) { [preview addObject:@(movement)]; };
    view.seekEnded=^(BOOL cancelled) { [end addObject:@(cancelled)]; };
    FSTestScroll *event=[FSTestScroll new]; event.hasPreciseScrollingDeltas=YES;
    void (^send)(NSEventPhase,CGFloat,CGFloat)=^(NSEventPhase phase,CGFloat x,CGFloat y) {
        event.phase=phase; event.scrollingDeltaX=x; event.scrollingDeltaY=y;
        [view consumeScroll:(NSEvent *)event];
    };
    send(NSEventPhaseBegan,-20,0); send(NSEventPhaseChanged,-80,0);
    assert(begins==1 && preview.count==2 && end.count==0);
    assert(fabs([preview.lastObject doubleValue]-0.1)<0.0001);
    // A pause while fingers remain down must not commit a phased gesture.
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.22]];
    assert(end.count==0);
    send(NSEventPhaseEnded,0,0); assert([end isEqual:@[@NO]]);
    event.momentumPhase=NSEventPhaseChanged; send(NSEventPhaseNone,-300,0);
    assert(begins==1 && end.count==1); event.momentumPhase=NSEventPhaseNone;
    event.inverted=YES; send(NSEventPhaseBegan,-100,0);
    assert(fabs([preview.lastObject doubleValue]+0.1)<0.0001);
    send(NSEventPhaseCancelled,0,0); assert([end.lastObject boolValue]); event.inverted=NO;
    int before=begins; send(NSEventPhaseBegan,2,100); send(NSEventPhaseEnded,0,0);
    assert(begins==before);
    event.hasPreciseScrollingDeltas=NO; send(NSEventPhaseNone,-100,0); assert(begins==before);
    event.hasPreciseScrollingDeltas=YES;
    send(NSEventPhaseNone,-40,0); send(NSEventPhaseNone,-60,0);
    NSUInteger ends=end.count;
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
    assert(end.count==ends+1 && ![end.lastObject boolValue]);
    send(NSEventPhaseNone,-50,0); ends=end.count;
    [view cancelInput]; assert(end.count==ends+1 && [end.lastObject boolValue]);
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
    assert(end.count==ends+1);
    view.seekBegan=^BOOL { return NO; }; ends=end.count;
    send(NSEventPhaseBegan,-100,0); send(NSEventPhaseEnded,0,0); assert(end.count==ends);
    assert(FSSeekPreviewPosition(0.9,0.3)==1 && FSSeekPreviewPosition(0.1,-0.3)==0);
    puts("{\"passed\":true,\"progressivePreview\":true,\"commitOnRelease\":true,\"naturalScrolling\":true,\"momentumAndVerticalIgnored\":true,\"cancelledInputCannotSeek\":true,\"phaselessDevices\":true}");
} }
