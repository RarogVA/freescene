#import <CoreGraphics/CoreGraphics.h>

// Folded F and rounded frame of the app icon, with a transparent interior.
// Only alpha is significant: AppKit tints the template for the menu bar.
static inline void FSDrawStatusTemplate(CGContextRef c, CGRect bounds) {
    CGContextSaveGState(c);
    CGFloat scale=(bounds.size.width<bounds.size.height ? bounds.size.width : bounds.size.height)/18.0;
    CGContextTranslateCTM(c,CGRectGetMidX(bounds)-9*scale,CGRectGetMidY(bounds)-9*scale);
    CGContextScaleCTM(c,scale,scale);
    CGContextSetRGBFillColor(c,0,0,0,1); CGContextSetRGBStrokeColor(c,0,0,0,1);
    CGPathRef frame=CGPathCreateWithRoundedRect(CGRectMake(0.75,0.75,16.5,16.5),4.3,4.3,NULL);
    CGContextSetLineWidth(c,0.65); CGContextAddPath(c,frame); CGContextStrokePath(c); CGPathRelease(frame);

    CGContextMoveToPoint(c,6.25,2.4);
    CGContextAddCurveToPoint(c,4.95,2.4,4.8,3.2,4.8,4.1);
    CGContextAddLineToPoint(c,4.8,11.5);
    CGContextAddCurveToPoint(c,4.8,13.9,5.8,15.1,8.1,15.1);
    CGContextAddLineToPoint(c,13.8,15.1);
    CGContextAddCurveToPoint(c,14.15,15.1,14.15,14.8,14.05,14.4);
    CGContextAddLineToPoint(c,13.85,13.5);
    CGContextAddCurveToPoint(c,13.7,12.9,13.2,12.6,12.4,12.6);
    CGContextAddLineToPoint(c,7.5,12.6); CGContextAddLineToPoint(c,7.5,10.6);
    CGContextAddLineToPoint(c,12.7,10.6);
    CGContextAddCurveToPoint(c,13.05,10.6,13.05,10.25,12.9,9.7);
    CGContextAddLineToPoint(c,12.5,8.5);
    CGContextAddCurveToPoint(c,12.3,8.0,11.9,7.95,11.4,7.95);
    CGContextAddLineToPoint(c,8.65,7.95);
    CGContextAddCurveToPoint(c,7.8,7.95,7.5,7.5,7.5,6.4);
    CGContextAddLineToPoint(c,7.5,3.8);
    CGContextAddCurveToPoint(c,7.5,2.7,7.0,2.4,6.25,2.4);
    CGContextClosePath(c); CGContextFillPath(c);

    // Transparent folds preserve the ribbon construction at menu-bar sizes.
    CGContextSetBlendMode(c,kCGBlendModeClear); CGContextSetLineWidth(c,0.38);
    CGContextMoveToPoint(c,4.95,10.55);
    CGContextAddCurveToPoint(c,5.35,11.7,6.2,12.45,7.5,12.6);
    CGContextMoveToPoint(c,4.95,6.2);
    CGContextAddCurveToPoint(c,5.35,7.35,6.55,7.9,8.65,7.95);
    CGContextStrokePath(c);
    CGContextRestoreGState(c);
}
