#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

@interface FSProgressSlider : NSSlider
@property(nonatomic) BOOL busy;
@property CALayer *busyTrack;
@property CAGradientLayer *sweep;
- (void)updateBusyAppearance;
@end
@implementation FSProgressSlider
- (void)updateBusyAppearance {
    if (!self.busyTrack) {
        self.wantsLayer=YES; self.busyTrack=[CALayer layer]; self.busyTrack.masksToBounds=YES; self.busyTrack.cornerRadius=2;
        self.sweep=[CAGradientLayer layer]; self.sweep.startPoint=CGPointMake(0,0.5); self.sweep.endPoint=CGPointMake(1,0.5);
        self.sweep.locations=@[@0,@0.5,@1]; [self.busyTrack addSublayer:self.sweep]; [self.layer addSublayer:self.busyTrack];
    }
    NSColor *color=self.trackFillColor ?: NSColor.controlAccentColor;
    self.busyTrack.backgroundColor=[color colorWithAlphaComponent:0.18].CGColor;
    self.sweep.colors=@[(__bridge id)[color colorWithAlphaComponent:0].CGColor,(__bridge id)color.CGColor,(__bridge id)[color colorWithAlphaComponent:0].CGColor];
    self.busyTrack.hidden=!self.busy;
    [self setNeedsLayout:YES];
}
- (void)setBusy:(BOOL)busy {
    if (_busy==busy && self.busyTrack) return;
    _busy=busy; [self updateBusyAppearance];
    [self.sweep removeAllAnimations];
    if (busy && !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
        CABasicAnimation *motion=[CABasicAnimation animationWithKeyPath:@"position.x"];
        motion.fromValue=@(-self.bounds.size.width/2); motion.toValue=@(self.bounds.size.width*1.5);
        motion.duration=1.35; motion.repeatCount=HUGE_VALF;
        [self.sweep addAnimation:motion forKey:@"FreeScene.buffering"];
    }
}
- (void)layout {
    [super layout];
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    self.busyTrack.frame=CGRectMake(6,CGRectGetMidY(self.bounds)-2,MAX(0,self.bounds.size.width-12),4);
    self.sweep.frame=CGRectMake(0,0,self.busyTrack.bounds.size.width,4);
    [CATransaction commit];
}
@end
