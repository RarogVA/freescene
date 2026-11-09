#import <Foundation/Foundation.h>

// AppKit content coordinates: title bar lies outside contentBounds. The bottom
// controls region remains reserved when hidden, so revealing it is not play/pause.
static inline BOOL FSPlaybackGestureContainsPoint(NSPoint point, NSRect contentBounds, NSRect videoFrame, NSRect controlsFrame) {
    return NSPointInRect(point,contentBounds) && NSPointInRect(point,videoFrame) && !NSPointInRect(point,controlsFrame);
}

// NSButton may add alignment insets to its frame. Always draw a true circle.
static inline NSRect FSControlCircleBounds(NSRect bounds) {
    CGFloat diameter=MAX(0,MIN(NSWidth(bounds),NSHeight(bounds))-2);
    return NSMakeRect(NSMidX(bounds)-diameter/2,NSMidY(bounds)-diameter/2,diameter,diameter);
}

// Screen coordinates always grow upwards, even when the button is flipped.
// NSMenu's nil positioning item uses the menu content's top-left corner.
static inline NSPoint FSMenuPopupScreenPoint(NSRect button, NSSize menu) {
    return NSMakePoint(NSMinX(button)-menu.width,NSMaxY(button)+menu.height);
}
