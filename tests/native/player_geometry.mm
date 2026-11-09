#import "../../macos/Native/FSPlayerGeometry.h"
#include <cassert>
#include <cstdio>

int main() {
    @autoreleasepool {
        int checks=0;
        for (NSValue *size in @[[NSValue valueWithSize:NSMakeSize(1100,700)],
                               [NSValue valueWithSize:NSMakeSize(640,400)],
                               [NSValue valueWithSize:NSMakeSize(1920,1080)]]) {
            NSSize dimensions=size.sizeValue;
            NSRect content=NSMakeRect(0,0,dimensions.width,dimensions.height);
            NSRect controls=NSMakeRect(0,0,dimensions.width,124);
            // Video click works; title bar/traffic lights and every panel edge don't.
            assert(FSPlaybackGestureContainsPoint(NSMakePoint(300,200),content,content,controls)); ++checks;
            for (NSValue *value in @[[NSValue valueWithPoint:NSMakePoint(15,dimensions.height+16)],
                                    [NSValue valueWithPoint:NSMakePoint(39,dimensions.height+16)],
                                    [NSValue valueWithPoint:NSMakePoint(62,dimensions.height+16)],
                                    [NSValue valueWithPoint:NSMakePoint(24,24)],
                                    [NSValue valueWithPoint:NSMakePoint(300,110)],
                                    [NSValue valueWithPoint:NSMakePoint(dimensions.width-24,60)],
                                    [NSValue valueWithPoint:NSMakePoint(0,0)]]) {
                assert(!FSPlaybackGestureContainsPoint(value.pointValue,content,content,controls)); ++checks;
            }
            // Above the reserved panel is video, below the content is not.
            assert(FSPlaybackGestureContainsPoint(NSMakePoint(300,124),content,content,controls)); ++checks;
            assert(!FSPlaybackGestureContainsPoint(NSMakePoint(300,-1),content,content,controls)); ++checks;
        }
        for (NSValue *value in @[[NSValue valueWithRect:NSMakeRect(0,0,44,44)],
                                [NSValue valueWithRect:NSMakeRect(0,0,44,52)],
                                [NSValue valueWithRect:NSMakeRect(4,6,52,44)]]) {
            NSRect bounds=value.rectValue, circle=FSControlCircleBounds(bounds);
            assert(NSWidth(circle)==42 && NSHeight(circle)==42); ++checks;
            assert(NSMidX(circle)==NSMidX(bounds) && NSMidY(circle)==NSMidY(bounds)); ++checks;
        }
        std::printf("{\"passed\":true,\"checks\":%d,\"suite\":\"native player gesture regions and circular controls\"}\n",checks);
    }
}
