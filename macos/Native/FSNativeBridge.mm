#import "FSNativeBridge.h"
#import "FSPlayerGeometry.h"
#import "FSPlayerKeyboard.h"
#import "FSPlayerPresentation.h"
#import "FSVideoView.h"
#import "FSStatusIcon.h"
#import "FSTheme.h"
#import "FSPlaybackStatus.h"
#import "FSProgressSlider.h"
#import "FSSwipeNavigation.h"
#import "../../native/engine.h"
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdocumentation"
#pragma clang diagnostic ignored "-Wdocumentation-deprecated-sync"
#include <vlc/vlc.h>
#pragma clang diagnostic pop
#import <UserNotifications/UserNotifications.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <CoreText/CoreText.h>

static BOOL fsEnglish=NO;
static BOOL fsDark=YES;
static BOOL FSIsWindowButtonEvent(NSWindow *window, NSEvent *event) {
    // Fullscreen can overlay window buttons inside the content coordinates.
    for (NSNumber *kind in @[@(NSWindowCloseButton),@(NSWindowMiniaturizeButton),@(NSWindowZoomButton)]) {
        NSButton *button=[window standardWindowButton:(NSWindowButton)kind.integerValue];
        if (button && !button.hiddenOrHasHiddenAncestor && NSPointInRect([button convertPoint:event.locationInWindow fromView:nil],button.bounds)) return YES;
    }
    return NO;
}
static void FSPopUpAboveLeft(NSMenu *menu,NSView *anchor) {
    if (!anchor.window) return;
    [menu update]; NSSize size=menu.size;
    NSRect screen=[anchor.window convertRectToScreen:[anchor convertRect:anchor.bounds toView:nil]];
    // Using the button's own coordinates reverses the vertical offset when
    // NSButton is flipped. Convert the whole rect before positioning the menu.
    [menu popUpMenuPositioningItem:nil atLocation:FSMenuPopupScreenPoint(screen,size) inView:nil];
}
static NSFont *FSFont(CGFloat size) {
    static CTFontDescriptorRef descriptor;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *frameworks=NSBundle.mainBundle.privateFrameworksPath;
        if (!frameworks) return;
        NSString *path=[frameworks stringByAppendingPathComponent:@"App.framework/Resources/flutter_assets/assets/fonts/Play-Regular.ttf"];
        if (![NSFileManager.defaultManager fileExistsAtPath:path]) return;
        NSURL *url=[NSURL fileURLWithPath:path];
        CTFontManagerRegisterFontsForURL((__bridge CFURLRef)url,kCTFontManagerScopeProcess,nullptr);
        CFArrayRef fonts=CTFontManagerCreateFontDescriptorsFromURL((__bridge CFURLRef)url);
        if (fonts && CFArrayGetCount(fonts)) descriptor=(CTFontDescriptorRef)CFRetain(CFArrayGetValueAtIndex(fonts,0));
        if (fonts) CFRelease(fonts);
    });
    return descriptor ? (__bridge_transfer NSFont *)CTFontCreateWithFontDescriptor(descriptor,size,nullptr) : [NSFont systemFontOfSize:size];
}
static NSString *FSL(NSString *ru) {
    if(!fsEnglish) return ru;
    static NSDictionary *words;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ words=@{
      @"Плеер":@"Player", @"Ожидание источника…":@"Waiting for source…", @"Пауза":@"Pause",
      @"Повторить":@"Retry", @"На весь экран":@"Full screen", @"Аудио":@"Audio", @"Субтитры":@"Subtitles",
      @"Не удалось начать воспроизведение. Повторите попытку.":@"Could not start playback. Retry.",
      @"Ожидание метаданных торрента…":@"Waiting for torrent metadata…", @"Продолжить":@"Resume",
      @"Ошибка воспроизведения или ожидания данных. Повторите попытку.":@"Playback or buffering error. Retry.",
      @"Воспроизведение завершено":@"Playback ended", @"Буферизация…":@"Buffering…", @"Нет дорожек":@"No tracks",
      @"Файл":@"File", @"Открыть видео…":@"Open video…", @"Закрыть окно":@"Close window"
      , @"Открыть FreeScene":@"Open FreeScene", @"Выход":@"Quit"
    }; });
    return words[ru] ?: ru;
}

@interface FSRoundButton : NSButton
@property BOOL primary;
@property NSString *symbolName;
- (void)symbol:(NSString *)name label:(NSString *)label;
- (void)applyAppearance;
@end
@implementation FSRoundButton
- (NSEdgeInsets)alignmentRectInsets { return NSEdgeInsetsMake(0,0,0,0); }
- (instancetype)init {
    if (!(self=[super initWithFrame:NSMakeRect(0,0,44,44)])) return nil;
    self.bordered=NO; self.imagePosition=NSImageOnly; self.focusRingType=NSFocusRingTypeNone;
    [self setButtonType:NSButtonTypeMomentaryChange];
    self.translatesAutoresizingMaskIntoConstraints=NO;
    [NSLayoutConstraint activateConstraints:@[[self.widthAnchor constraintEqualToConstant:44],[self.heightAnchor constraintEqualToConstant:44]]];
    return self;
}
- (void)symbol:(NSString *)name label:(NSString *)label {
    if (![self.symbolName isEqualToString:name]) {
        self.symbolName=name;
        self.image=[[NSImage imageWithSystemSymbolName:name accessibilityDescription:label] imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:19 weight:NSFontWeightSemibold]];
    }
    self.toolTip=label; [self setAccessibilityLabel:label];
}
- (void)applyAppearance {
    self.contentTintColor=self.primary ? FSThemeOnAccent(fsDark) : FSThemeText(fsDark);
    self.needsDisplay=YES;
}
- (void)drawRect:(NSRect)dirty {
    NSColor *fill=self.primary ? FSThemeAccent(fsDark) : FSThemeRaised(fsDark);
    [([self isHighlighted] ? [fill blendedColorWithFraction:0.18 ofColor:self.contentTintColor ?: NSColor.labelColor] : fill) setFill];
    NSRect circle=FSControlCircleBounds(self.bounds);
    [[NSBezierPath bezierPathWithOvalInRect:circle] fill];
    [super drawRect:dirty];
    if (self.window.firstResponder==self) {
        [[FSThemeAccent(fsDark) colorWithAlphaComponent:0.9] setStroke];
        NSBezierPath *ring=[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(circle,-0.25,-0.25)]; ring.lineWidth=1.5; [ring stroke];
    }
}
@end

#import "FSWatched.h"
#import "FSProviderView.h"
#import "FSVideoSelection.h"
#import "FSAboutWindow.h"
#import "FSPermissions.h"

@interface FSPlayer : NSObject <NSWindowDelegate>
@property NSWindow *window;
@property FSVideoView *video;
@property NSView *bar;
@property NSTextField *status;
@property NSTextField *time;
@property FSRoundButton *play;
@property FSRoundButton *retryButton;
@property FSRoundButton *full;
@property FSRoundButton *scale;
@property FSPlayerScaleMode scaleMode;
@property NSString *appliedScaleRatio;
@property FSProgressSlider *position;
@property FSRoundButton *audio;
@property FSRoundButton *subtitles;
@property FSRoundButton *episodes;
@property NSArray<NSDictionary *> *torrentFiles;
@property FSVideoSelection *videoSelection;
@property NSInteger currentFile;
@property NSTimer *timer;
@property NSDate *lastActivity;
@property NSString *location;
@property NSString *taskID;
@property NSString *mediaTitle;
@property NSString *mediaUserAgent;
@property NSString *mediaReferrer;
@property BOOL loadingTrailer;
@property(copy) void (^sourceWillChange)(void);
@property(copy) void (^retryMedia)(void);
@property NSString *externalStatus;
@property NSString *playbackError;
@property NSDictionary *torrentStats;
@property BOOL userPaused;
@property libvlc_instance_t *vlc;
@property libvlc_media_player_t *player;
@property NSActivityOptions activityOptions;
@property id activityToken;
@property id eventMonitor;
@property BOOL seeking;
@property double seekAnchor,seekPreview;
@property int64_t seekDuration;
@property BOOL started;
@property NSInteger trackCount;
@property NSUInteger requestGeneration;
@property FSProviderView *providerView;
@property FSWatchedClock *watchedClock;
@property(copy) void (^playbackPauseChanged)(NSString *, BOOL);
@property(copy) void (^playbackClosed)(NSString *);
@property(copy) void (^retryRequested)(NSString *);
@property(copy) void (^fileRequested)(NSString *,NSInteger,NSString *);
- (void)applyAppearance;
- (void)open:(NSString *)location title:(NSString *)title task:(NSString *)task userAgent:(NSString *)userAgent;
@end
@implementation FSPlayer
- (instancetype)init {
    if (!(self=[super init])) return nil;
    self.trackCount=-1;
    NSString *plugins=[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"VLC/plugins"];
    setenv("VLC_PLUGIN_PATH",plugins.UTF8String,1);
    const char *args[]={"--no-video-title-show","--no-osd","--no-plugins-cache","--no-stats","--network-caching=1200","--no-metadata-network-access"};
    self.vlc=libvlc_new(6,args);
    if (!self.vlc) return nil;
    self.player=libvlc_media_player_new(self.vlc);
    self.window=[[NSWindow alloc] initWithContentRect:NSMakeRect(100,100,1100,700) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    self.window.title=FSL(@"FreeScene — Плеер"); self.window.delegate=self; self.window.releasedWhenClosed=NO;
    self.window.minSize=NSMakeSize(640,400); self.window.acceptsMouseMovedEvents=YES;
    self.window.backgroundColor=NSColor.blackColor;
    NSView *root=self.window.contentView; root.wantsLayer=YES; root.layer.backgroundColor=NSColor.blackColor.CGColor;
    self.video=[[FSVideoView alloc] initWithFrame:root.bounds]; self.video.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
    [root addSubview:self.video];
    libvlc_media_player_set_nsobject(self.player,(__bridge void *)self.video);
    self.bar=[[NSView alloc] initWithFrame:NSMakeRect(0,0,1100,112)]; self.bar.wantsLayer=YES;
    self.bar.autoresizingMask=NSViewWidthSizable; [root addSubview:self.bar];
    self.status=[NSTextField labelWithString:FSL(@"Ожидание источника…")];
    self.status.font=FSFont(13);
    self.time=[NSTextField labelWithString:@"0:00 / 0:00"]; self.time.font=FSFont(12);
    self.play=[FSRoundButton new]; self.play.primary=YES; self.play.target=self; self.play.action=@selector(toggle:);
    self.retryButton=[FSRoundButton new]; self.retryButton.target=self; self.retryButton.action=@selector(retry:);
    self.full=[FSRoundButton new]; self.full.target=self; self.full.action=@selector(fullscreen:);
    self.scale=[FSRoundButton new]; self.scale.target=self; self.scale.action=@selector(showScale:);
    self.position=[FSProgressSlider sliderWithValue:0 minValue:0 maxValue:1 target:self action:@selector(seek:)];
    self.audio=[FSRoundButton new]; self.audio.target=self; self.audio.action=@selector(showAudio:); self.audio.enabled=NO;
    self.subtitles=[FSRoundButton new]; self.subtitles.target=self; self.subtitles.action=@selector(showSubtitles:); self.subtitles.enabled=NO;
    self.episodes=[FSRoundButton new]; self.episodes.target=self; self.episodes.action=@selector(showEpisodes:); self.episodes.hidden=YES;
    NSStackView *upper=[NSStackView stackViewWithViews:@[self.position,self.time]]; upper.orientation=NSUserInterfaceLayoutOrientationHorizontal; upper.alignment=NSLayoutAttributeCenterY; upper.spacing=12;
    [self.time setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSView *spacer=[NSView new]; [spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [spacer setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    self.status.translatesAutoresizingMaskIntoConstraints=NO; [spacer addSubview:self.status];
    NSStackView *lower=[NSStackView stackViewWithViews:@[self.play,self.retryButton,spacer,self.episodes,self.audio,self.subtitles,self.scale,self.full]];
    lower.orientation=NSUserInterfaceLayoutOrientationHorizontal; lower.alignment=NSLayoutAttributeCenterY; lower.distribution=NSStackViewDistributionFill; lower.spacing=12;
    NSStackView *stack=[NSStackView stackViewWithViews:@[upper,lower]]; stack.orientation=NSUserInterfaceLayoutOrientationVertical; stack.alignment=NSLayoutAttributeLeading; stack.spacing=10; stack.translatesAutoresizingMaskIntoConstraints=NO;
    [self.bar addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:self.bar.leadingAnchor constant:24],[stack.trailingAnchor constraintEqualToAnchor:self.bar.trailingAnchor constant:-24],[stack.centerYAnchor constraintEqualToAnchor:self.bar.centerYAnchor],[spacer.heightAnchor constraintEqualToConstant:44],[self.status.widthAnchor constraintEqualToAnchor:spacer.widthAnchor],[self.status.centerXAnchor constraintEqualToAnchor:spacer.centerXAnchor],[self.status.centerYAnchor constraintEqualToAnchor:spacer.centerYAnchor constant:6],[self.status.heightAnchor constraintGreaterThanOrEqualToConstant:32],[upper.widthAnchor constraintEqualToAnchor:stack.widthAnchor],[lower.widthAnchor constraintEqualToAnchor:stack.widthAnchor],[self.position.widthAnchor constraintGreaterThanOrEqualToConstant:200]]];
    self.status.maximumNumberOfLines=3; self.status.lineBreakMode=NSLineBreakByWordWrapping; self.status.alignment=NSTextAlignmentCenter;
    [self applyAppearance];
    __weak FSPlayer *weakSelf=self;
    self.video.singleClick=^{ [weakSelf toggle:nil]; };
    self.video.doubleClick=^{ [weakSelf fullscreen:nil]; };
    self.video.activity=^{ [weakSelf showControls]; };
    self.video.acceptsPlaybackEvent=^BOOL(NSEvent *event) {
        FSPlayer *s=weakSelf;
        if (!s || FSIsWindowButtonEvent(s.window,event)) return NO;
        NSPoint point=[s.window.contentView convertPoint:event.locationInWindow fromView:nil];
        return FSPlaybackGestureContainsPoint(point,s.window.contentView.bounds,s.video.frame,s.bar.frame);
    };
    self.video.seekBegan=^BOOL {
        FSPlayer *s=weakSelf;
        if(!s || !s.player || !s.window.visible || !libvlc_media_player_is_seekable(s.player) || libvlc_media_player_get_length(s.player)<=0) return NO;
        s.seeking=YES; s.seekDuration=libvlc_media_player_get_length(s.player);
        s.seekAnchor=FSSeekPreviewPosition(libvlc_media_player_get_position(s.player),0);
        s.seekPreview=s.seekAnchor; return YES;
    };
    self.video.seekChanged=^(double movement) {
        FSPlayer *s=weakSelf; if(!s.seeking) return;
        s.seekPreview=FSSeekPreviewPosition(s.seekAnchor,movement); [s updateTimeline]; [s showControls];
    };
    self.video.seekEnded=^(BOOL cancelled) {
        FSPlayer *s=weakSelf; if(!s.seeking) return;
        s.seeking=NO;
        if(!cancelled && s.player && s.window.visible) libvlc_media_player_set_position(s.player,(float)s.seekPreview);
        if(cancelled) [s updateTimeline];
        [s showControls];
    };
    self.eventMonitor=[NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown|NSEventMaskMouseMoved|NSEventMaskScrollWheel|NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        FSPlayer *s=weakSelf;
        if(!s)return event;
        if(s.providerView && event.type==NSEventTypeKeyDown && event.keyCode==53 &&
           !(event.modifierFlags & (NSEventModifierFlagCommand|NSEventModifierFlagControl|NSEventModifierFlagOption|NSEventModifierFlagShift)) &&
           !s.window.attachedSheet && !NSApp.modalWindow &&
           [s.providerView.fullscreen exitFromWindow:event.window])return nil;
        if(event.window!=s.window)return event;
        if(!s.providerView && event.type==NSEventTypeKeyDown && (event.keyCode==123 || event.keyCode==124) &&
           !(event.modifierFlags & (NSEventModifierFlagCommand|NSEventModifierFlagControl|NSEventModifierFlagOption|NSEventModifierFlagShift)) &&
           s.window.isKeyWindow && !s.window.attachedSheet && !NSApp.modalWindow &&
           ![s.window.firstResponder isKindOfClass:NSTextView.class] && s.player && libvlc_media_player_is_seekable(s.player)) {
            int64_t duration=libvlc_media_player_get_length(s.player);
            if(duration>0) {
                [s.video cancelInput]; s.seeking=NO;
                int64_t target=FSKeyboardSeekTarget(libvlc_media_player_get_time(s.player),duration,event.keyCode==124);
                libvlc_media_player_set_time(s.player,target);
                [s updateTimeline]; [s showControls]; return nil;
            }
        }
        if(s.providerView || event.type==NSEventTypeKeyDown) return event;
        if(FSIsWindowButtonEvent(s.window,event)) { [s.video cancelInput]; return event; }
        // A gesture which started over video owns its end/cancel event even if
        // the pointer crosses the controls. A new gesture cannot start there.
        if(event.type==NSEventTypeScrollWheel && s.video.scrolling) { [s.video scrollWheel:event]; return nil; }
        NSView *content=s.window.contentView;
        NSPoint point=[content convertPoint:event.locationInWindow fromView:nil];
        // Title-bar events belong to AppKit, including the three traffic lights.
        // Only intercept clicks/gestures over video, never window chrome or controls.
        if(!NSPointInRect(point,content.bounds) || !NSPointInRect(point,s.video.frame)) return event;
        if(event.type==NSEventTypeMouseMoved) { [s showControls]; return event; }
        // Reserve the controls area even while it is hidden. Showing it must
        // never toggle playback, seek by gesture or trigger double-click fullscreen.
        if(!FSPlaybackGestureContainsPoint(point,content.bounds,s.video.frame,s.bar.frame)) {
            [s.video cancelInput];
            [s showControls]; return event;
        }
        if(event.type==NSEventTypeLeftMouseDown) { [s.video mouseDown:event]; return nil; }
        if(event.type==NSEventTypeScrollWheel) { [s.video scrollWheel:event]; return nil; }
        return event;
    }];
    self.timer=[NSTimer scheduledTimerWithTimeInterval:0.25 target:self selector:@selector(tick:) userInfo:nil repeats:YES];
    return self;
}
- (void)applyAppearance {
    self.window.appearance=[NSAppearance appearanceNamed:fsDark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
    self.bar.layer.backgroundColor=FSThemePanel(fsDark).CGColor;
    self.status.textColor=FSThemeText(fsDark);
    self.time.textColor=FSThemeText(fsDark);
    self.position.trackFillColor=FSThemeAccent(fsDark);
    [self.position updateBusyAppearance];
    [self.play symbol:@"pause.fill" label:FSL(@"Пауза")];
    [self.retryButton symbol:@"arrow.clockwise" label:FSL(@"Повторить")];
    [self.full symbol:@"arrow.up.left.and.arrow.down.right" label:FSL(@"На весь экран")];
    [self.scale symbol:@"aspectratio" label:fsEnglish ? @"Video scale" : @"Масштаб видео"];
    [self.audio symbol:@"speaker.wave.2" label:FSL(@"Аудио")];
    [self.subtitles symbol:@"captions.bubble" label:FSL(@"Субтитры")];
    [self.episodes symbol:@"list.bullet" label:fsEnglish ? @"Seasons and episodes" : @"Сезоны и серии"];
    for(FSRoundButton *button in @[self.play,self.retryButton,self.full,self.audio,self.subtitles,self.episodes,self.scale]) [button applyAppearance];
    [self.providerView applyAppearance];
    [self showControls];
}
- (void)showControls { self.lastActivity=NSDate.date; self.bar.hidden=self.providerView!=nil; }
- (void)endProvider {
    [self.providerView stop]; [self.providerView removeFromSuperview]; self.providerView=nil;
    self.video.hidden=NO;
}
- (void)openEmbed:(NSURL *)url title:(NSString *)title player:(NSInteger)index episodes:(NSArray *)episodes context:(FSWebPlaybackContext *)context {
    [self open:@"" title:title task:nil];
    self.torrentStats=nil; self.position.busy=NO; self.bar.hidden=YES; self.video.hidden=YES;
    self.providerView=[[FSProviderView alloc] initWithURL:url frame:self.window.contentView.bounds player:index episodes:episodes context:context];
    [self.window.contentView addSubview:self.providerView]; [self.window makeFirstResponder:self.providerView.web];
}
- (void)open:(NSString *)location title:(NSString *)title task:(NSString *)task {
    [self open:location title:title task:task userAgent:nil];
}
- (void)open:(NSString *)location title:(NSString *)title task:(NSString *)task userAgent:(NSString *)userAgent {
    [self open:location title:title task:task userAgent:userAgent referrer:nil];
}
- (void)open:(NSString *)location title:(NSString *)title task:(NSString *)task userAgent:(NSString *)userAgent referrer:(NSString *)referrer {
    [self.watchedClock sample:NO at:NSProcessInfo.processInfo.systemUptime];
    if(!(task && [task isEqual:self.taskID]) && !(location.length && [location isEqual:self.location]))self.watchedClock=nil;
    if(self.sourceWillChange)self.sourceWillChange();
    self.loadingTrailer=NO;self.retryMedia=nil;self.mediaUserAgent=userAgent;self.mediaReferrer=referrer;
    self.play.enabled=YES;self.retryButton.enabled=YES;
    [self.video cancelInput];
    if(self.taskID && ![self.taskID isEqualToString:task] && self.playbackClosed) self.playbackClosed(self.taskID);
    if(!task || ![self.taskID isEqualToString:task]) { self.torrentFiles=nil;self.currentFile=-1;self.episodes.hidden=YES; }
    [self endProvider];
    BOOL keepPaused=task && [self.taskID isEqual:task] && self.userPaused && !self.location.length && location.length;
    ++self.requestGeneration;
    [self.videoSelection cancel]; self.videoSelection=nil;
    self.location=location; self.taskID=task; self.mediaTitle=title; self.externalStatus=@""; self.playbackError=@""; self.started=NO; self.trackCount=-1;
    self.userPaused=keepPaused; self.torrentStats=task && !location.length ? @{@"metadata":@NO,@"dht":@"unknown",@"seeds":NSNull.null,@"peers":NSNull.null,@"rate":@0,@"error":@""} : nil;
    self.window.title=[@"FreeScene — " stringByAppendingString:title];
    [self.window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES]; [self.window makeFirstResponder:self.video];
    [self showControls];
    libvlc_media_player_stop(self.player);
    self.appliedScaleRatio=nil;
    [self applyScale];
    // A pending trailer or torrent must not retain a playable previous source.
    if(!location.length)libvlc_media_player_set_media(self.player,nullptr);
    if(task && self.playbackPauseChanged) self.playbackPauseChanged(task,keepPaused);
    if (location.length) {
        libvlc_media_t *media=[location hasPrefix:@"http://"] || [location hasPrefix:@"https://"] ? libvlc_media_new_location(self.vlc,location.UTF8String) : libvlc_media_new_path(self.vlc,location.UTF8String);
        if(userAgent.length)libvlc_media_add_option(media,[[NSString stringWithFormat:@":http-user-agent=%@",userAgent] UTF8String]);
        if(referrer.length)libvlc_media_add_option(media,[[NSString stringWithFormat:@":http-referrer=%@",referrer] UTF8String]);
        libvlc_media_player_set_media(self.player,media); libvlc_media_release(media);
        if (libvlc_media_player_play(self.player)<0) self.status.stringValue=FSL(@"Не удалось начать воспроизведение. Повторите попытку.");
        if (keepPaused) libvlc_media_player_set_pause(self.player,1);
    } else self.status.stringValue=FSL(@"Ожидание метаданных торрента…");
    if (!self.activityToken) self.activityToken=[[NSProcessInfo processInfo] beginActivityWithOptions:NSActivityUserInitiated|NSActivityIdleDisplaySleepDisabled reason:@"FreeScene playback"];
}
- (void)toggle:(id)sender {
    if(!self.player || !self.window.visible || self.loadingTrailer || (!self.location.length && !self.taskID)) return;
    BOOL pause=!self.userPaused;
    self.userPaused=pause;
    libvlc_media_player_set_pause(self.player,pause ? 1 : 0);
    if(self.taskID && self.playbackPauseChanged) self.playbackPauseChanged(self.taskID,pause);
    [self showControls];
}
- (void)retry:(id)sender {
    if(self.taskID && self.retryRequested)self.retryRequested(self.taskID);
    else if(self.retryMedia)self.retryMedia();
    else [self open:self.location title:self.mediaTitle task:self.taskID userAgent:self.mediaUserAgent referrer:self.mediaReferrer];
}
- (void)fullscreen:(id)sender { [self.window toggleFullScreen:nil]; [self showControls]; }
- (void)applyScale {
    if(!self.player) return;
    NSString *ratio=FSPlayerViewportRatio(self.video.bounds.size);
    NSString *key=[NSString stringWithFormat:@"%ld/%@",(long)self.scaleMode,ratio];
    if([key isEqualToString:self.appliedScaleRatio]) return;
    self.appliedScaleRatio=key;
    libvlc_video_set_scale(self.player,0);
    libvlc_video_set_aspect_ratio(self.player,self.scaleMode==FSPlayerScaleStretch ? ratio.UTF8String : nullptr);
    libvlc_video_set_crop_geometry(self.player,self.scaleMode==FSPlayerScaleFill ? ratio.UTF8String : nullptr);
}
- (void)showScale:(NSButton *)sender {
    NSMenu *menu=[NSMenu new];menu.font=FSFont(13);
    NSArray<NSString *> *labels=FSPlayerScaleLabels(fsEnglish);
    for(NSInteger i=0;i<labels.count;i++) {
        NSMenuItem *item=[menu addItemWithTitle:labels[i] action:@selector(scaleChanged:) keyEquivalent:@""];
        item.target=self;item.tag=i;item.state=i==self.scaleMode ? NSControlStateValueOn : NSControlStateValueOff;
    }
    [self showControls];FSPopUpAboveLeft(menu,sender);
}
- (void)scaleChanged:(NSMenuItem *)sender {
    if(sender.tag<FSPlayerScaleFit || sender.tag>FSPlayerScaleStretch) return;
    self.scaleMode=(FSPlayerScaleMode)sender.tag;[self applyScale];[self showControls];
}
- (void)windowDidResize:(NSNotification *)note { [self applyScale]; }
- (void)seek:(NSSlider *)sender { [self.video cancelInput]; libvlc_media_player_set_position(self.player,(float)sender.doubleValue); [self showControls]; }
- (void)audioChanged:(NSMenuItem *)sender { libvlc_audio_set_track(self.player,(int)sender.tag); }
- (void)subtitlesChanged:(NSMenuItem *)sender { libvlc_video_set_spu(self.player,(int)sender.tag); }
- (void)tracks:(NSButton *)button description:(libvlc_track_description_t *)first selected:(int)selected action:(SEL)action {
    NSMenu *menu=[NSMenu new];
    menu.font=FSFont(13);
    if(!first) return;
    for(auto* t=first;t;t=t->p_next) {
        NSString *title=t->psz_name ? [NSString stringWithUTF8String:t->psz_name] : nil;
        NSMenuItem *item=[menu addItemWithTitle:title ?: [NSString stringWithFormat:@"%d",t->i_id] action:action keyEquivalent:@""];
        item.target=self; item.tag=t->i_id; item.state=t->i_id==selected ? NSControlStateValueOn : NSControlStateValueOff;
    }
    libvlc_track_description_list_release(first);
    [self showControls];
    FSPopUpAboveLeft(menu,button);
}
- (void)showAudio:(NSButton *)sender { [self tracks:sender description:libvlc_audio_get_track_description(self.player) selected:libvlc_audio_get_track(self.player) action:@selector(audioChanged:)]; }
- (void)showSubtitles:(NSButton *)sender { [self tracks:sender description:libvlc_video_get_spu_description(self.player) selected:libvlc_video_get_spu(self.player) action:@selector(subtitlesChanged:)]; }
- (void)showEpisodes:(NSButton *)sender {
    NSMenu *menu=[NSMenu new];menu.font=FSFont(13);
    for(NSDictionary *file in self.torrentFiles) {
        if(![file[@"video"] boolValue]) continue;
        NSString *name=file[@"name"] ?: @"";
        NSMenuItem *item=[menu addItemWithTitle:name action:@selector(episodeChanged:) keyEquivalent:@""];
        item.target=self;item.tag=[file[@"index"] integerValue];item.representedObject=name;
        item.state=item.tag==self.currentFile ? NSControlStateValueOn : NSControlStateValueOff;
    }
    [self showControls];FSPopUpAboveLeft(menu,sender);
}
- (void)episodeChanged:(NSMenuItem *)sender {
    if(self.taskID && sender.tag!=self.currentFile && self.fileRequested) self.fileRequested(self.taskID,sender.tag,sender.representedObject);
}
- (NSString *)clock:(int64_t)milliseconds { int64_t s=MAX(0,milliseconds)/1000; return [NSString stringWithFormat:@"%lld:%02lld",s/60,s%60]; }
- (void)updateTimeline {
    int64_t duration=self.seeking ? self.seekDuration : libvlc_media_player_get_length(self.player);
    double position=self.seeking ? self.seekPreview : FSSeekPreviewPosition(libvlc_media_player_get_position(self.player),0);
    int64_t time=self.seeking ? (int64_t)(duration*position) : libvlc_media_player_get_time(self.player);
    self.time.stringValue=[NSString stringWithFormat:@"%@ / %@",[self clock:time],[self clock:duration]];
    self.position.doubleValue=position;
}
- (void)tick:(id)sender {
    if (!self.window.visible || self.providerView) return;
    self.episodes.hidden=[[self.torrentFiles filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *file,NSDictionary *bindings){return [file[@"video"] boolValue];}]] count]<2;
    auto state=libvlc_media_player_get_state(self.player);
    [self applyScale];
    BOOL playing=state==libvlc_Playing;
    [self.watchedClock sample:playing && !self.userPaused && !self.seeking at:NSProcessInfo.processInfo.systemUptime];
    [self.play symbol:self.userPaused ? @"play.fill" : @"pause.fill" label:self.userPaused ? FSL(@"Продолжить") : FSL(@"Пауза")];
    if (playing) self.started=YES;
    if (self.location.length) self.status.stringValue=state==libvlc_Error ? FSL(@"Ошибка воспроизведения или ожидания данных. Повторите попытку.") : state==libvlc_Ended ? FSL(@"Воспроизведение завершено") : state==libvlc_Buffering || state==libvlc_Opening ? FSL(@"Буферизация…") : playing ? @"" : FSL(@"Пауза");
    [self updateTimeline];
    NSInteger count=libvlc_audio_get_track_count(self.player)*1000+libvlc_video_get_spu_count(self.player);
    if (self.started && count!=self.trackCount) {
        self.trackCount=count;
        self.audio.enabled=libvlc_audio_get_track_count(self.player)>0;
        self.subtitles.enabled=libvlc_video_get_spu_count(self.player)>0;
    }
    if (self.externalStatus.length) self.status.stringValue=self.externalStatus;
    NSString *mediaState=state==libvlc_Error ? @"error" : state==libvlc_Ended ? @"ended" : state==libvlc_Opening || (!self.started && self.location.length) ? @"opening" : state==libvlc_Buffering ? @"buffering" : @"playing";
    NSDictionary *presentation=FSPlaybackPresentation(self.torrentStats,mediaState,self.userPaused,fsEnglish);
    self.position.busy=[presentation[@"busy"] boolValue] && !self.playbackError.length;
    self.position.enabled=libvlc_media_player_get_length(self.player)>0;
    if (self.torrentStats) self.status.stringValue=presentation[@"text"] ?: @"";
    if (self.externalStatus.length) self.status.stringValue=[self.externalStatus stringByAppendingFormat:@"\n%@",self.status.stringValue];
    if (self.playbackError.length) self.status.stringValue=self.playbackError;
    if(self.loadingTrailer) {
        self.status.stringValue=fsEnglish ? @"Loading trailer…" : @"Загрузка трейлера…";
        self.position.busy=YES;self.position.enabled=NO;
    }
    self.bar.hidden=!self.seeking && !self.position.busy && !self.playbackError.length && !self.externalStatus.length && self.started && playing && -[self.lastActivity timeIntervalSinceNow]>2.5;
}
- (void)windowDidResignKey:(NSNotification *)note { [self.video cancelInput]; }
- (void)windowDidFailToExitFullScreen:(NSWindow *)window { [self.providerView.fullscreen finishEscape]; }
- (void)windowWillClose:(NSNotification *)note {
    self.watchedClock=nil;
    if(self.sourceWillChange)self.sourceWillChange();
    self.loadingTrailer=NO;self.retryMedia=nil;
    [self endProvider];
    ++self.requestGeneration;
    [self.video cancelInput];
    NSString *closedTask=self.taskID; self.taskID=nil;
    [self.videoSelection cancel]; self.videoSelection=nil;
    if(closedTask && self.playbackClosed) self.playbackClosed(closedTask);
    if(self.player) libvlc_media_player_stop(self.player);
    self.position.busy=NO; self.torrentStats=nil;
    self.torrentFiles=nil;self.currentFile=-1;self.episodes.hidden=YES;
    if (self.activityToken) { [[NSProcessInfo processInfo] endActivity:self.activityToken]; self.activityToken=nil; }
}
- (void)stop {
    [self.video cancelInput];
    if(self.eventMonitor) { [NSEvent removeMonitor:self.eventMonitor]; self.eventMonitor=nil; }
    [self.timer invalidate]; self.timer=nil;
    [self.window close];
    if (self.player) { libvlc_media_player_release(self.player); self.player=nullptr; }
    if (self.vlc) { libvlc_release(self.vlc); self.vlc=nullptr; }
}
@end

@interface FSNativeBridge () <UNUserNotificationCenterDelegate>
@property void *engine;
@property dispatch_queue_t queue;
@property FlutterMethodChannel *channel;
@property FSPlayer *player;
@property NSWindow *mainWindow;
@property NSStatusItem *statusItem;
@property FSAboutWindow *about;
@property FSPermissions *permissions;
@property FSSwipeNavigation *swipeNavigation;
@property BOOL closing;
@property BOOL shutdownComplete;
@property NSMutableArray<void (^)(void)> *shutdownCompletions;
@end
static FSNativeBridge *bridge;
@implementation FSNativeBridge
+ (void)registerWithController:(FlutterViewController *)controller window:(NSWindow *)window {
    bridge=[FSNativeBridge new]; [UNUserNotificationCenter currentNotificationCenter].delegate=bridge; bridge.queue=dispatch_queue_create("FreeScene.engine",DISPATCH_QUEUE_SERIAL);
    bridge.mainWindow=window;
    bridge.statusItem=[NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    bridge.statusItem.button.target=bridge;
    bridge.statusItem.button.action=@selector(statusItemClicked:);
    [bridge.statusItem.button sendActionOn:NSEventMaskLeftMouseUp|NSEventMaskRightMouseUp];
    [bridge updateStatusIcon];
    bridge.channel=[FlutterMethodChannel methodChannelWithName:@"freescene/native" binaryMessenger:controller.engine.binaryMessenger];
    [bridge.channel setMethodCallHandler:^(FlutterMethodCall *call, FlutterResult result) { [bridge handle:call result:result]; }];
    __weak FSNativeBridge *weakBridge=bridge;
    bridge.swipeNavigation=[[FSSwipeNavigation alloc] initWithWindow:window view:controller.view navigateBack:^(NSDictionary *point) {
        FSNativeBridge *s=weakBridge;
        if (s && !s.closing) [s.channel invokeMethod:@"navigateBack" arguments:point];
    }];
}
- (void)updateStatusIcon {
    NSImage *image=[NSImage imageWithSize:NSMakeSize(18,18) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        FSDrawStatusTemplate(NSGraphicsContext.currentContext.CGContext,rect); return YES;
    }];
    [image setTemplate:YES];
    self.statusItem.button.image=image;
    self.statusItem.button.imageScaling=NSImageScaleProportionallyDown;
    self.statusItem.button.toolTip=FSL(@"Открыть FreeScene");
    [self.statusItem.button setAccessibilityLabel:@"FreeScene"];
}
+ (void)showMainWindow {
    if (!bridge.mainWindow || bridge.closing) return;
    if (bridge.mainWindow.miniaturized) [bridge.mainWindow deminiaturize:nil];
    [bridge.mainWindow makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
}
- (void)showMainFromMenu:(id)sender { [FSNativeBridge showMainWindow]; }
- (void)openVideoFromMenu:(id)sender { [FSNativeBridge openLocalVideo]; }
- (void)statusItemClicked:(id)sender {
    if (NSApp.currentEvent.type==NSEventTypeRightMouseUp) {
        NSMenu *menu=[NSMenu new];
        NSMenuItem *open=[menu addItemWithTitle:FSL(@"Открыть FreeScene") action:@selector(showMainFromMenu:) keyEquivalent:@""]; open.target=self;
        NSMenuItem *video=[menu addItemWithTitle:FSL(@"Открыть видео…") action:@selector(openVideoFromMenu:) keyEquivalent:@""]; video.target=self;
        [menu addItem:NSMenuItem.separatorItem];
        NSMenuItem *quit=[menu addItemWithTitle:FSL(@"Выход") action:@selector(terminate:) keyEquivalent:@"q"]; quit.target=NSApp;
        [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0,NSHeight(self.statusItem.button.bounds)+4) inView:self.statusItem.button];
    } else [FSNativeBridge showMainWindow];
}
- (NSDictionary *)request:(NSDictionary *)request {
    if (!self.engine) {
        NSString *profile=NSProcessInfo.processInfo.environment[@"FREESCENE_DATA"] ?: [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/FreeScene"];
        NSString *downloads=FSDownloadsPath();
        NSDictionary *config=@{@"profile":[profile stringByAppendingPathComponent:@"torrents"],@"downloads":downloads,@"isolated":@([NSProcessInfo.processInfo.environment[@"FREESCENE_TEST_MODE"] isEqualToString:@"1"])};
        NSData *data=[NSJSONSerialization dataWithJSONObject:config options:0 error:nil]; self.engine=fs_engine_create([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding].UTF8String);
    }
    NSData *data=[NSJSONSerialization dataWithJSONObject:request options:0 error:nil];
    char *raw=fs_engine_command(self.engine,[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding].UTF8String);
    NSData *response=[NSData dataWithBytes:raw length:strlen(raw)]; fs_engine_free(raw);
    return [NSJSONSerialization JSONObjectWithData:response options:0 error:nil];
}
- (FSPlayer *)ensurePlayer {
    if (!self.player) {
        self.player=[FSPlayer new];
        __weak FSNativeBridge *weakSelf=self;
        self.player.sourceWillChange=^{[FSProviderHost.adapter cancelTrailers];};
        self.player.retryRequested=^(NSString *task) {
            FSNativeBridge *s=weakSelf; if(!s || s.closing) return;
            dispatch_async(s.queue,^{
                [s request:@{@"method":@"resume",@"id":task}];
                dispatch_async(dispatch_get_main_queue(),^{
                    if (s.player.window.visible && [s.player.taskID isEqualToString:task]) [s.player open:s.player.location title:s.player.mediaTitle task:task];
                });
            });
        };
        self.player.playbackPauseChanged=^(NSString *task,BOOL paused) {
            FSNativeBridge *s=weakSelf; if(!s || s.closing) return;
            dispatch_async(s.queue,^{ [s request:@{@"method":@"streamPaused",@"id":task,@"paused":@(paused)}]; });
        };
        self.player.playbackClosed=^(NSString *task) {
            FSNativeBridge *s=weakSelf; if(!s || s.closing) return;
            dispatch_async(s.queue,^{ [s request:@{@"method":@"pause",@"id":task}]; });
        };
        self.player.fileRequested=^(NSString *task,NSInteger index,NSString *name) {
            FSNativeBridge *s=weakSelf;if(!s || s.closing || !s.player.window.visible || ![s.player.taskID isEqualToString:task])return;
            [s.player open:@"" title:name task:task];
            NSUInteger generation=s.player.requestGeneration;
            dispatch_async(s.queue,^{
                NSDictionary *reply=[s request:@{@"method":@"stream",@"id":task,@"file":@(index)}];
                dispatch_async(dispatch_get_main_queue(),^{
                    if(!s.player.window.visible || s.player.requestGeneration!=generation)return;
                    if(reply[@"error"])s.player.playbackError=reply[@"error"];
                    else { [s.player open:reply[@"result"][@"url"] title:name task:task];s.player.currentFile=index; }
                });
            });
        };
    }
    return self.player;
}
- (void)showTrailer:(NSDictionary *)arguments completion:(FlutterResult)completion {
    FlutterResult reply=completion ?: ^(id value){};
    NSString *title=arguments[@"title"];
    if(![FSProviderHost.adapter allowsTrailer:arguments] || ![title isKindOfClass:NSString.class] || !title.length || title.length>512) {
        reply([FlutterError errorWithCode:@"trailer" message:@"Invalid trailer reference" details:nil]);return;
    }
    if(self.closing){reply(nil);return;}
    FSPlayer *player=[self ensurePlayer];
    if(!player){reply([FlutterError errorWithCode:@"player" message:@"libVLC could not start" details:nil]);return;}
    NSString *caption=[NSString stringWithFormat:fsEnglish ? @"Trailer · %@" : @"Трейлер · %@",title];
    NSString *version=[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"1.2.6";
    NSString *userAgent=[NSString stringWithFormat:@"FreeScene/%@ macOS",version];
    [player open:@"" title:caption task:nil];
    NSUInteger generation=player.requestGeneration;
    player.loadingTrailer=YES;player.play.enabled=NO;player.retryButton.enabled=NO;
    [player tick:nil];
    __weak FSNativeBridge *weak=self;
    NSDictionary *request=[arguments copy];
    void (^retry)(void)=^{FSNativeBridge *s=weak;if(s && !s.closing)[s showTrailer:request completion:nil];};
    player.retryMedia=retry;
    void (^resolved)(NSURL *,NSURL *,NSString *,NSString *)=^(NSURL *media,NSURL *referrer,NSString *webProvider,NSString *error){
        FSNativeBridge *s=weak;
        if(!s || s.closing || [error isEqual:@"cancelled"] || !player.window.visible || player.requestGeneration!=generation) {reply(nil);return;}
        player.loadingTrailer=NO;player.play.enabled=YES;player.retryButton.enabled=YES;
        if(error || !media) {
            player.playbackError=fsEnglish ? @"Could not load the trailer. Retry." : @"Не удалось загрузить трейлер. Повторите попытку.";
            player.position.busy=NO;[player tick:nil];
            reply([FlutterError errorWithCode:@"trailer" message:@"Could not resolve trailer" details:nil]);return;
        }
        if(webProvider) {
            FSWebPlaybackContext *context=[FSProviderHost.adapter contextForURL:media provider:webProvider player:0 episodes:@[]];
            if(!context){reply([FlutterError errorWithCode:@"trailer" message:@"Invalid player" details:nil]);return;}
            [player openEmbed:media title:caption player:0 episodes:@[] context:context];
        } else [player open:media.absoluteString title:caption task:nil userAgent:userAgent referrer:referrer.absoluteString];
        player.retryMedia=retry;
        reply(nil);
    };
    [FSProviderHost.adapter resolveTrailer:arguments userAgent:userAgent completion:resolved];
}
+ (void)openLocalVideo {
    NSOpenPanel *panel=[NSOpenPanel openPanel]; panel.allowsMultipleSelection=NO; panel.canChooseDirectories=NO;
    NSMutableArray<UTType *> *types=[NSMutableArray arrayWithObjects:UTTypeMovie,UTTypeVideo,nil];
    for(NSString *extension in @[@"mkv",@"mp4",@"avi",@"mov",@"webm",@"m4v",@"ts",@"m2ts",@"mpg",@"mpeg",@"wmv"]) {
        UTType *type=[UTType typeWithFilenameExtension:extension]; if(type) [types addObject:type];
    }
    panel.allowedContentTypes=types;
    [panel beginWithCompletionHandler:^(NSModalResponse answer) { if(answer==NSModalResponseOK) [[bridge ensurePlayer] open:panel.URL.path title:panel.URL.lastPathComponent task:nil]; }];
}
- (FSAboutWindow *)ensureAbout {
    if(!self.about) {
        self.about=[FSAboutWindow new];
        __weak FSNativeBridge *weakSelf=self;
        self.about.licensesRequested=^{
            FSNativeBridge *s=weakSelf; if(!s || s.closing || !s.about.licensesButton.enabled) return;
            s.about.licensesButton.enabled=NO;
            [s.channel invokeMethod:@"openLicenses" arguments:nil result:^(id reply) {
                FSNativeBridge *s=weakSelf; if(!s || s.closing) return;
                s.about.licensesButton.enabled=YES;
                if([reply isKindOfClass:FlutterError.class] || reply==FlutterMethodNotImplemented)
                    s.about.status.stringValue=fsEnglish ? @"Could not load licences. Please try again." : @"Не удалось загрузить лицензии. Повторите попытку.";
            }];
        };
    }
    return self.about;
}
- (BOOL)canOfferStartupUpdate {
    return !self.closing && self.mainWindow.visible && self.mainWindow.keyWindow &&
        !self.mainWindow.miniaturized && NSApp.active && !NSApp.modalWindow &&
        !self.mainWindow.attachedSheet && !self.player.window.visible &&
        !self.about.window.visible && !self.about.licensesWindow.visible;
}
- (void)scheduleStartupUpdateCheck {
    static BOOL scheduled=NO;
    if(scheduled || !self.mainWindow)return;scheduled=YES;
    FSAboutWindow *about=[self ensureAbout];
    __weak FSNativeBridge *weak=self;
    // Let the Flutter navigator and initial permission flow become ready.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{
        FSNativeBridge *s=weak;if(!s || s.closing)return;
        [about.updater checkAtStartup:^(NSDictionary *asset) {
            [about.updater offerAtStartupWhenEligible:^(void (^reply)(BOOL)) {
                FSNativeBridge *s=weak;if(!s || ![s canOfferStartupUpdate]){reply(NO);return;}
                [s.channel invokeMethod:@"canOfferStartupUpdate" arguments:nil result:^(id allowed) {
                    FSNativeBridge *current=weak;
                    reply([allowed isEqual:@YES] && current && [current canOfferStartupUpdate]);
                }];
            } offer:^{
                FSNativeBridge *s=weak;if(!s)return;
                [about offerStartupUpdateForWindow:s.mainWindow allowed:^BOOL {
                    FSNativeBridge *current=weak;return current && [current canOfferStartupUpdate];
                }];
            }];
        }];
    });
}
- (void)trackPlayer:(FSPlayer *)player arguments:(NSDictionary *)args {
    player.watchedClock=nil;
    if([args[@"watchedSource"] isKindOfClass:NSString.class] && [args[@"watchedTitle"] isKindOfClass:NSString.class]) {
        FSWatchedClock *clock=[FSWatchedClock new];clock.source=args[@"watchedSource"];clock.title=args[@"watchedTitle"];player.watchedClock=clock;
    }
}
- (void)handle:(FlutterMethodCall *)call result:(FlutterResult)result {
    if (self.closing) {
        result([call.method isEqual:@"status"] ? @{@"shuttingDown":@YES} : [FlutterError errorWithCode:@"app_closing" message:nil details:nil]);
        return;
    }
    if([call.method isEqual:@"requestAppPermissionsIfNeeded"] || [call.method isEqual:@"requestAppPermissions"]) {
        if(!self.permissions)self.permissions=[FSPermissions new];
        [self.permissions requestAgain:[call.method isEqual:@"requestAppPermissions"] completion:^(NSDictionary *value){result(value);}];return;
    }
    if ([call.method isEqual:@"watchedSnapshot"]) { result(FSWatchedSnapshot());return; }
    if ([call.method isEqual:@"setWatched"]) {
        if(FSSetWatched(call.arguments[@"watchedSource"],call.arguments[@"watchedTitle"],[call.arguments[@"watched"] boolValue]))result(nil);
        else result([FlutterError errorWithCode:@"watched_save" message:@"Could not save watched status" details:nil]);return;
    }
    if ([call.method isEqual:@"showAbout"]) { [[self ensureAbout] show]; result(nil); return; }
    if([call.method isEqual:@"showTrailer"]) {
        [self showTrailer:[call.arguments isKindOfClass:NSDictionary.class] ? call.arguments : @{} completion:result];return;
    }
    if ([call.method isEqual:@"showLicenses"]) {
        NSString *text=[call.arguments[@"text"] isKindOfClass:NSString.class] ? call.arguments[@"text"] : nil;
        if(!text.length) { result([FlutterError errorWithCode:@"licenses_empty" message:@"License notices are unavailable" details:nil]);return; }
        [[self ensureAbout] showLicensesText:text]; result(nil);return;
    }
    if ([call.method isEqualToString:@"configureUI"]) {
        fsEnglish=[call.arguments[@"english"] boolValue];
        fsDark=[call.arguments[@"dark"] boolValue];
        self.mainWindow.appearance=[NSAppearance appearanceNamed:fsDark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
        self.mainWindow.backgroundColor=FSThemeBackground(fsDark);
        [self updateStatusIcon];
        [self.player applyAppearance]; [self.about applyAppearance];
        [self scheduleStartupUpdateCheck];
        for(NSMenuItem *top in NSApp.mainMenu.itemArray) for(NSMenuItem *item in top.submenu.itemArray) {
            if(item.action==NSSelectorFromString(@"openVideo:")) { top.title=FSL(@"Файл"); item.title=FSL(@"Открыть видео…"); }
            if([item.identifier isEqualToString:@"fsCloseWindow"]) item.title=FSL(@"Закрыть окно");
        }
        result(nil); return;
    }
    if (self.closing) { result([FlutterError errorWithCode:@"closing" message:@"FreeScene is closing" details:nil]); return; }
    if ([call.method isEqual:@"openDownload"]) {
        NSDictionary *args=[call.arguments isKindOfClass:NSDictionary.class] ? call.arguments : @{};
        NSString *value=[args[@"url"] isKindOfClass:NSString.class] ? args[@"url"] : @"";
        NSString *provider=[args[@"provider"] isKindOfClass:NSString.class] ? args[@"provider"] : @"";
        NSURL *url=[NSURL URLWithString:value];
        if(!FSProviderURLAllowed(url,provider,@"download")) {
            result([FlutterError errorWithCode:@"providerURL" message:@"Unsupported provider download URL" details:nil]);return;
        }
        if(![NSWorkspace.sharedWorkspace openURL:url]) {
            result([FlutterError errorWithCode:@"download_open" message:@"Could not open download in browser" details:nil]);return;
        }
        result(nil);return;
    }
    if ([call.method isEqual:@"openProvider"]) {
        NSURL *url=[NSURL URLWithString:call.arguments[@"url"] ?: @""];
        NSString *provider=call.arguments[@"provider"] ?: @"", *kind=call.arguments[@"kind"] ?: @"";
        if (!FSProviderURLAllowed(url,provider,kind)) { result([FlutterError errorWithCode:@"providerURL" message:@"Unsupported provider playback URL" details:nil]); return; }
        id selection=call.arguments[@"webPlayer"];
        NSInteger index=[selection isKindOfClass:NSNumber.class] ? [selection integerValue] : 0;
        NSArray *episodes=call.arguments[@"webEpisodes"] ?: @[];
        FSWebPlaybackContext *context=nil;
        if([kind isEqual:@"embed"]) {
            context=[FSProviderHost.adapter contextForURL:url provider:provider player:index episodes:episodes];
            if(!context) {result([FlutterError errorWithCode:@"providerURL" message:@"Invalid player context" details:nil]);return;}
        }
        FSPlayer *player=[self ensurePlayer];
        if (!player) { result([FlutterError errorWithCode:@"player" message:@"libVLC could not start" details:nil]); return; }
        if ([kind isEqual:@"embed"]) {
            [player openEmbed:url title:call.arguments[@"title"] ?: @"Video" player:index episodes:episodes context:context];
        }
        else {
            id<FSProviderAdapter> adapter=FSProviderHost.adapter;
            NSDictionary *headers=[adapter respondsToSelector:@selector(playbackHeadersForURL:provider:)] ? [adapter playbackHeadersForURL:url provider:provider] : nil;
            [player open:url.absoluteString title:call.arguments[@"title"] ?: @"Video" task:nil
                userAgent:headers[@"User-Agent"] referrer:headers[@"Referer"]];
        }
        [self trackPlayer:player arguments:call.arguments];
        player.providerView.watchedClock=player.watchedClock;
        player.providerView.providerName=call.arguments[@"providerName"] ?: provider;
        result(nil); return;
    }
    if ([call.method isEqualToString:@"showMainWindow"]) { [FSNativeBridge showMainWindow]; result(nil); return; }
    if ([call.method isEqualToString:@"requestNotifications"] || [call.method isEqualToString:@"requestNotificationsIfNeeded"]) {
        UNUserNotificationCenter *center=UNUserNotificationCenter.currentNotificationCenter;
        [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
            if (settings.authorizationStatus==UNAuthorizationStatusNotDetermined) {
                [center requestAuthorizationWithOptions:UNAuthorizationOptionAlert|UNAuthorizationOptionSound completionHandler:^(BOOL granted, NSError *error) {
                    dispatch_async(dispatch_get_main_queue(), ^{ result(@(granted)); });
                }];
            } else {
                BOOL allowed=settings.authorizationStatus==UNAuthorizationStatusAuthorized || settings.authorizationStatus==UNAuthorizationStatusProvisional;
                dispatch_async(dispatch_get_main_queue(), ^{ result(@(allowed)); });
            }
        }]; return;
    }
    if ([call.method isEqualToString:@"notify"]) {
        UNMutableNotificationContent *content=[UNMutableNotificationContent new];
        content.title=call.arguments[@"title"] ?: @"FreeScene"; content.body=call.arguments[@"body"] ?: @""; content.sound=UNNotificationSound.defaultSound;
        UNNotificationRequest *request=[UNNotificationRequest requestWithIdentifier:call.arguments[@"id"] ?: NSUUID.UUID.UUIDString content:content trigger:nil];
        [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request withCompletionHandler:nil]; result(nil); return;
    }
    if ([call.method isEqualToString:@"preparePlayer"]) {
        FSPlayer *p=[self ensurePlayer]; if(!p) { result([FlutterError errorWithCode:@"player" message:@"libVLC could not start" details:nil]); return; }
        [p open:@"" title:call.arguments[@"title"] task:call.arguments[@"id"]]; [self trackPlayer:p arguments:call.arguments]; result(nil); return;
    }
    if ([call.method isEqualToString:@"choosePlayerVideo"]) {
        FSPlayer *p=self.player;NSString *task=call.arguments[@"id"] ?: @"";
        if(!p.window.visible || ![p.taskID isEqualToString:task]) { result(nil);return; }
        NSArray *files=[p.torrentFiles filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *file,NSDictionary *bindings){return [file[@"video"] boolValue];}]];
        if(files.count<2) { result(files.firstObject[@"index"]);return; }
        [p.videoSelection cancel];p.videoSelection=[FSVideoSelection new];
        NSUInteger generation=p.requestGeneration;
        [p.videoSelection showForPlayer:p.window files:files title:p.mediaTitle completion:^(NSNumber *index){
            result(p.window.visible && p.requestGeneration==generation && [p.taskID isEqualToString:task] ? index : nil);
        }];return;
    }
    if ([call.method isEqualToString:@"cancelPreparedPlayer"] || [call.method isEqualToString:@"playerMessage"]) {
        if ([self.player.taskID isEqualToString:call.arguments[@"id"] ?: @""]) {
            if ([call.method isEqualToString:@"cancelPreparedPlayer"]) [self.player.window close];
            else self.player.playbackError=call.arguments[@"message"];
        }
        result(nil); return;
    }
    if ([@[@"videoDownloadLocations",@"openDownloadedVideo"] containsObject:call.method]) {
        NSString *directory=call.arguments[@"directory"];
        if(![directory isKindOfClass:NSString.class] || ![[NSPredicate predicateWithFormat:@"SELF MATCHES %@",@"^[A-Za-z0-9_-]{1,64}$"] evaluateWithObject:directory]) {
            result([FlutterError errorWithCode:@"download_path" message:@"Invalid download namespace" details:nil]);return;
        }
    }
    if ([call.method isEqual:@"videoDownloadLocations"]) {
        NSString *profile=NSProcessInfo.processInfo.environment[@"FREESCENE_DATA"] ?: [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/FreeScene"];
        result(@{@"profile":profile,@"downloads":[FSDownloadsPath() stringByAppendingPathComponent:call.arguments[@"directory"]]}); return;
    }
    if ([call.method isEqual:@"openDownloadedVideo"]) {
        NSString *filename=call.arguments[@"filename"];
        if(![filename isKindOfClass:NSString.class]) {
            result([FlutterError errorWithCode:@"download_missing" message:FSL(@"Скачанный файл не найден") details:nil]); return;
        }
        NSString *root=[[FSDownloadsPath() stringByAppendingPathComponent:call.arguments[@"directory"]] stringByResolvingSymlinksInPath];
        NSString *path=[root stringByAppendingPathComponent:filename ?: @""];
        BOOL directory=NO;
        if(![filename isKindOfClass:NSString.class] || ![filename isEqual:filename.lastPathComponent] ||
           ![filename.pathExtension isEqual:@"ts"] || ![[path stringByResolvingSymlinksInPath] isEqual:path] ||
           ![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&directory] || directory) {
            result([FlutterError errorWithCode:@"download_missing" message:FSL(@"Скачанный файл не найден") details:nil]); return;
        }
        [[self ensurePlayer] open:path title:call.arguments[@"title"] ?: filename task:nil]; result(nil); return;
    }
    if ([call.method isEqualToString:@"openVideo"]) { [FSNativeBridge openLocalVideo]; result(nil); return; }
    if ([call.method isEqualToString:@"chooseTorrent"]) {
        NSOpenPanel *panel=[NSOpenPanel openPanel]; panel.allowedContentTypes=@[[UTType typeWithFilenameExtension:@"torrent"] ?: UTTypeData]; panel.canChooseDirectories=NO; panel.allowsMultipleSelection=NO;
        [panel beginWithCompletionHandler:^(NSModalResponse answer) { result(answer==NSModalResponseOK ? panel.URL.path : nil); }]; return;
    }
    if ([call.method isEqualToString:@"reveal"]) {
        NSString *path=call.arguments[@"path"];
        if (!path.length) { result([FlutterError errorWithCode:@"path" message:@"Missing file path" details:nil]); return; }
        [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:path]]]; result(nil); return;
    }
    NSDictionary *args=[call.arguments isKindOfClass:NSDictionary.class] ? call.arguments : @{};
    NSMutableDictionary *request=[args mutableCopy]; request[@"method"]=call.method;
    NSUInteger streamGeneration=0;
    if([call.method isEqualToString:@"prepareStream"] && (!self.player.window.visible || ![self.player.taskID isEqualToString:args[@"id"] ?: @""])) { result(nil); return; }
    if ([call.method isEqualToString:@"stream"]) {
        if ([args[@"prepared"] boolValue] && (!self.player.window.visible || ![self.player.taskID isEqualToString:args[@"id"] ?: @""])) { result(nil); return; }
        FSPlayer *player=[self ensurePlayer];
        if (!player) { result([FlutterError errorWithCode:@"player" message:@"libVLC could not start" details:nil]); return; }
        if (![args[@"prepared"] boolValue]) [player open:@"" title:args[@"title"] ?: FSL(@"Плеер") task:args[@"id"]];
        streamGeneration=player.requestGeneration;
    }
    dispatch_async(self.queue,^{
        if (self.closing) { dispatch_async(dispatch_get_main_queue(),^{ result([call.method isEqual:@"status"] ? @{@"shuttingDown":@YES} : [FlutterError errorWithCode:@"app_closing" message:nil details:nil]); });return; }
        NSDictionary *reply=[self request:request];
        dispatch_async(dispatch_get_main_queue(),^{
            if (self.closing) { result([call.method isEqual:@"status"] ? @{@"shuttingDown":@YES} : [FlutterError errorWithCode:@"app_closing" message:nil details:nil]);return; }
            if (reply[@"error"]) { result([FlutterError errorWithCode:@"engine" message:reply[@"error"] details:nil]); }
            else {
                if ([call.method isEqualToString:@"status"] && self.player.taskID) {
                    for(NSDictionary *task in reply[@"result"][@"tasks"]) if([task[@"id"] isEqualToString:self.player.taskID]) { self.player.externalStatus=task[@"error"]; self.player.torrentStats=task;self.player.torrentFiles=task[@"files"]; }
                }
                if ([call.method isEqualToString:@"stream"] && self.player.window.visible && self.player.requestGeneration==streamGeneration) {
                    [self.player open:reply[@"result"][@"url"] title:args[@"title"] ?: FSL(@"Плеер") task:args[@"id"]];
                    self.player.currentFile=[args[@"file"] integerValue];
                }
                if ([call.method isEqualToString:@"status"]) {
                    NSMutableDictionary *snapshot=[reply[@"result"] mutableCopy];
                    snapshot[@"playerTaskId"]=self.player.taskID ?: NSNull.null;
                    result(snapshot);
                } else result(reply[@"result"]);
            }
        });
    });
}
- (void)userNotificationCenter:(UNUserNotificationCenter *)center willPresentNotification:(UNNotification *)notification withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
    completionHandler(UNNotificationPresentationOptionBanner|UNNotificationPresentationOptionSound);
}
+ (void)shutdownWithCompletion:(void (^)(void))completion {
    FSNativeBridge *s=bridge;
    if (!s || s.shutdownComplete) { dispatch_async(dispatch_get_main_queue(),completion);return; }
    if (!s.shutdownCompletions) s.shutdownCompletions=[NSMutableArray new];
    [s.shutdownCompletions addObject:[completion copy]];
    if (s.closing) return;
    s.closing=YES;
    [FSProviderHost.adapter cancelTrailers];
    [s.swipeNavigation invalidate]; s.swipeNavigation=nil;
    [s.channel invokeMethod:@"applicationWillTerminate" arguments:nil];
    NSString *task=s.player.taskID;
    [s.player stop]; [FSProviderHost.adapter stop]; [s.about cancel]; [s.about.window orderOut:nil]; [s.about.licensesWindow orderOut:nil];
    [s.mainWindow orderOut:nil];
    if (s.statusItem) { [NSStatusBar.systemStatusBar removeStatusItem:s.statusItem]; s.statusItem=nil; }
    // Keep the channel alive until process exit. Late polling receives an
    // explicit shutdown state, never MissingPluginException or a new engine.
    dispatch_async(s.queue,^{
        if (task && s.engine) [s request:@{@"method":@"pause",@"id":task}];
        fs_engine_destroy(s.engine);s.engine=nullptr;
        dispatch_async(dispatch_get_main_queue(),^{
            s.shutdownComplete=YES;
            NSArray *callbacks=[s.shutdownCompletions copy];[s.shutdownCompletions removeAllObjects];
            for (void (^callback)(void) in callbacks) callback();
        });
    });
}
@end
