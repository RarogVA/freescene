// Included after FreeScene's native round button and typography definitions.
#import <WebKit/WebKit.h>
#import "FSProviderPlayback.h"
#import "FSWatched.h"
#import "FSPlayerKeyboard.h"
#import "FSWebFullscreen.h"
#import "FSPlayerPresentation.h"
NS_ASSUME_NONNULL_BEGIN

@interface FSProviderView : NSView <WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler>
@property(nullable) WKWebView *web;
@property(nullable) FSWatchedClock *watchedClock;
@property NSString *providerName;
@property FSRoundButton *playButton, *backButton, *forwardButton, *audioButton, *nativeButton, *fullButton;
@property FSProgressSlider *position;
@property NSTextField *timeLabel;
@property(nullable) NSTimer *playbackTimer;
@property NSDictionary *playbackState;
@property double lastPlaybackReport;
@property BOOL nativeControls;
@property NSURL *source;
@property NSTextField *message;
@property NSView *toolbar;
@property FSRoundButton *retryButton;
@property FSRoundButton *episodesButton;
@property FSRoundButton *scaleButton;
@property FSPlayerScaleMode scaleMode;
@property NSArray<NSDictionary *> *episodes;
@property NSInteger webPlayer;
@property BOOL selectsPlayer;
@property FSWebPlaybackContext *context;
@property BOOL contentRulesReady;
@property NSView *loadingCover;
@property(nullable) NSTimer *readiness;
@property BOOL inspectingPlayer;
@property NSUInteger loadGeneration;
@property NSTimeInterval loadStarted;
@property(nullable) FSWebFullscreen *fullscreen;
- (instancetype)initWithURL:(NSURL *)url frame:(NSRect)frame;
- (instancetype)initWithURL:(NSURL *)url frame:(NSRect)frame player:(NSInteger)player episodes:(NSArray<NSDictionary *> *)episodes;
- (instancetype)initWithURL:(NSURL *)url frame:(NSRect)frame player:(NSInteger)player episodes:(NSArray<NSDictionary *> *)episodes context:(nullable FSWebPlaybackContext *)context;
- (void)applyAppearance;
- (void)stop;
@end

@implementation FSProviderView
- (instancetype)initWithURL:(NSURL *)url frame:(NSRect)frame {
    return [self initWithURL:url frame:frame player:0 episodes:@[]];
}
- (instancetype)initWithURL:(NSURL *)url frame:(NSRect)frame player:(NSInteger)player episodes:(NSArray<NSDictionary *> *)episodes {
    return [self initWithURL:url frame:frame player:player episodes:episodes context:[FSProviderHost.adapter contextForURL:url provider:nil player:player episodes:episodes]];
}
- (instancetype)initWithURL:(NSURL *)url frame:(NSRect)frame player:(NSInteger)player episodes:(NSArray<NSDictionary *> *)episodes context:(nullable FSWebPlaybackContext *)context {
    if (!(self=[super initWithFrame:frame])) return nil;
    self.source=url; self.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
    if(!context)return nil;self.context=context;
    self.selectsPlayer=context.selectionScript.length>0;self.webPlayer=player;self.episodes=episodes;
    self.wantsLayer=YES;self.layer.backgroundColor=NSColor.blackColor.CGColor;
    WKWebViewConfiguration *config=[WKWebViewConfiguration new];
    self.nativeControls=YES;
    [config.userContentController addScriptMessageHandler:self name:@"FreeSceneControls"];
    NSString *controlsPath=[NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@"App.framework/Resources/flutter_assets/assets/player/web_controls.js"];
    NSString *controls=[NSString stringWithContentsOfFile:controlsPath encoding:NSUTF8StringEncoding error:nil];
    NSData *settings=[NSJSONSerialization dataWithJSONObject:@{@"rootSelector":context.progressRootSelector ?: NSNull.null} options:0 error:nil];
    NSString *json=[[NSString alloc] initWithData:settings encoding:NSUTF8StringEncoding];
    NSString *controlConfig=[NSString stringWithFormat:@"Object.assign(%@,{prepare:%@})",json,context.mediaPreparationScript ?: @"null"];
    if(controls.length)[config.userContentController addUserScript:[[WKUserScript alloc] initWithSource:[NSString stringWithFormat:@"(%@)(%@);",controls,controlConfig] injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO]];
    [config.userContentController addUserScript:[[WKUserScript alloc] initWithSource:FSPlayerKeyboardScript() injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO]];
    [config.userContentController addUserScript:[[WKUserScript alloc] initWithSource:FSPlayerPresentationScript(self.scaleMode) injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO]];
    config.websiteDataStore=context.store ? (WKWebsiteDataStore * _Nonnull)context.store : WKWebsiteDataStore.nonPersistentDataStore;
    if(self.selectsPlayer) [config.userContentController addUserScript:[[WKUserScript alloc] initWithSource:context.selectionScript injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES inContentWorld:[WKContentWorld worldWithName:@"FreeScene.Provider.player"]]];
    config.mediaTypesRequiringUserActionForPlayback=WKAudiovisualMediaTypeNone;
    config.preferences.javaScriptCanOpenWindowsAutomatically=NO;
    config.preferences.elementFullscreenEnabled=YES;
    WKWebView *web=[[WKWebView alloc] initWithFrame:NSMakeRect(0,112,frame.size.width,MAX(0,frame.size.height-112)) configuration:config];
    self.web=web;
    self.fullscreen=[[FSWebFullscreen alloc] initWithWebView:web container:self];
    web.underPageBackgroundColor=NSColor.blackColor;
    self.web.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
    self.web.navigationDelegate=self; self.web.UIDelegate=self;
    [self addSubview:web];
    self.loadingCover=[[NSView alloc] initWithFrame:web.frame];self.loadingCover.wantsLayer=YES;self.loadingCover.layer.backgroundColor=NSColor.blackColor.CGColor;
    self.loadingCover.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;self.loadingCover.hidden=!self.selectsPlayer;[self addSubview:self.loadingCover];
    self.toolbar=[[NSView alloc] initWithFrame:NSMakeRect(0,0,frame.size.width,112)];
    self.toolbar.wantsLayer=YES; self.toolbar.autoresizingMask=NSViewWidthSizable;
    [self addSubview:self.toolbar];
    self.message=[NSTextField labelWithString:@""]; self.message.font=FSFont(12); self.message.maximumNumberOfLines=2;
    self.message.lineBreakMode=NSLineBreakByTruncatingTail;
    self.retryButton=[FSRoundButton new]; self.retryButton.target=self; self.retryButton.action=@selector(retry:);
    self.episodesButton=[FSRoundButton new];self.episodesButton.target=self;self.episodesButton.action=@selector(chooseEpisode:);self.episodesButton.hidden=!self.selectsPlayer || episodes.count<2;
    self.scaleButton=[FSRoundButton new];self.scaleButton.target=self;self.scaleButton.action=@selector(chooseScale:);
    self.playButton=[FSRoundButton new];self.playButton.primary=YES;self.playButton.target=self;self.playButton.action=@selector(togglePlayback:);
    self.backButton=[FSRoundButton new];self.backButton.target=self;self.backButton.action=@selector(skipBack:);
    self.forwardButton=[FSRoundButton new];self.forwardButton.target=self;self.forwardButton.action=@selector(skipForward:);
    self.audioButton=[FSRoundButton new];self.audioButton.target=self;self.audioButton.action=@selector(showAudio:);
    self.nativeButton=[FSRoundButton new];self.nativeButton.target=self;self.nativeButton.action=@selector(toggleNative:);
    self.fullButton=[FSRoundButton new];self.fullButton.target=self;self.fullButton.action=@selector(toggleFullscreen:);
    self.position=[FSProgressSlider sliderWithValue:0 minValue:0 maxValue:1 target:self action:@selector(seek:)];self.position.enabled=NO;
    self.timeLabel=[NSTextField labelWithString:@"0:00 / 0:00"];self.timeLabel.font=FSFont(12);
    [self.timeLabel setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *upper=[NSStackView stackViewWithViews:@[self.position,self.timeLabel]];upper.spacing=12;
    self.message.alignment=NSTextAlignmentCenter;
    [self.message setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self.message setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *lower=[NSStackView stackViewWithViews:@[self.playButton,self.backButton,self.forwardButton,self.message,self.episodesButton,self.audioButton,self.nativeButton,self.scaleButton,self.fullButton,self.retryButton]];
    lower.spacing=8;lower.alignment=NSLayoutAttributeCenterY;
    NSStackView *stack=[NSStackView stackViewWithViews:@[upper,lower]];stack.orientation=NSUserInterfaceLayoutOrientationVertical;stack.spacing=10;stack.translatesAutoresizingMaskIntoConstraints=NO;
    [self.toolbar addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:self.toolbar.leadingAnchor constant:24],
      [stack.trailingAnchor constraintEqualToAnchor:self.toolbar.trailingAnchor constant:-24],
      [stack.centerYAnchor constraintEqualToAnchor:self.toolbar.centerYAnchor],
      [upper.widthAnchor constraintEqualToAnchor:stack.widthAnchor],[lower.widthAnchor constraintEqualToAnchor:stack.widthAnchor]]];
    __weak FSProviderView *playbackOwner=self;
    self.playbackTimer=[NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer){[playbackOwner updatePlaybackControls];}];
    [self applyAppearance];
    if(context.contentRules.length) {
        self.message.stringValue=fsEnglish ? @"Loading video…" : @"Загрузка видео…";
        __weak FSProviderView *weakSelf=self;
        [WKContentRuleListStore.defaultStore compileContentRuleListForIdentifier:@"FreeScene.Provider.contentRules" encodedContentRuleList:context.contentRules completionHandler:^(WKContentRuleList *rules,NSError *error){
            FSProviderView *owner=weakSelf;
            if(!owner || !owner.web) return;
            if(rules) [owner.web.configuration.userContentController addContentRuleList:rules];
            // A filter compilation failure must not prevent video playback.
            owner.contentRulesReady=YES;[owner retry:nil];
        }];
    } else {self.contentRulesReady=YES;[self retry:nil];}
    return self;
}
- (void)applyAppearance {
    self.toolbar.layer.backgroundColor=FSThemePanel(fsDark).CGColor;
    self.message.textColor=FSThemeText(fsDark);self.timeLabel.textColor=FSThemeText(fsDark);
    self.position.trackFillColor=FSThemeAccent(fsDark);[self.position updateBusyAppearance];
    [self.playButton symbol:@"play.fill" label:fsEnglish ? @"Play / pause" : @"Смотреть / пауза"];
    [self.backButton symbol:@"gobackward.10" label:fsEnglish ? @"Rewind 10 seconds" : @"Назад на 10 секунд"];
    [self.forwardButton symbol:@"goforward.10" label:fsEnglish ? @"Forward 10 seconds" : @"Вперёд на 10 секунд"];
    [self.audioButton symbol:@"speaker.wave.2" label:FSL(@"Аудио")];
    [self.nativeButton symbol:@"slider.horizontal.3" label:fsEnglish ? @"Provider controls / FreeScene controls" : @"Управление провайдера / FreeScene"];
    [self.fullButton symbol:@"arrow.up.left.and.arrow.down.right" label:FSL(@"На весь экран")];
    for(FSRoundButton *button in @[self.playButton,self.backButton,self.forwardButton,self.audioButton,self.nativeButton,self.fullButton])[button applyAppearance];
    [self.retryButton symbol:@"arrow.clockwise" label:fsEnglish ? @"Retry" : @"Повторить"];
    [self.episodesButton symbol:@"list.bullet" label:fsEnglish ? @"Seasons and episodes" : @"Сезоны и серии"];
    [self.scaleButton symbol:@"aspectratio" label:fsEnglish ? @"Video scale" : @"Масштаб видео"];
    [self.scaleButton applyAppearance];
    [self.episodesButton applyAppearance];
    [self.retryButton applyAppearance];
}
- (void)retry:(nullable id)sender {
    [self.watchedClock sample:NO at:NSProcessInfo.processInfo.systemUptime];
    if(self.selectsPlayer && !self.contentRulesReady) return;
    self.message.stringValue=(fsEnglish ? @"Loading video…" : @"Загрузка видео…");
    self.lastPlaybackReport=0;self.playbackState=nil;self.position.busy=YES;self.nativeControls=YES;self.loadStarted=NSDate.timeIntervalSinceReferenceDate;
    [self.readiness invalidate];self.readiness=nil;++self.loadGeneration;self.inspectingPlayer=NO;
    if(self.selectsPlayer) {
        self.loadingCover.hidden=NO;self.loadStarted=NSDate.timeIntervalSinceReferenceDate;
        __weak FSProviderView *weakSelf=self;
        self.readiness=[NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer){[weakSelf inspectPlayer];}];
    }
    [self.web loadRequest:[NSURLRequest requestWithURL:self.source cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:25]];
}
- (void)inspectPlayer {
    if(!self.selectsPlayer || !self.web || self.inspectingPlayer) return;
    self.inspectingPlayer=YES;NSUInteger generation=self.loadGeneration;WKWebView *web=self.web;
    [web evaluateJavaScript:self.context.selectionScript inFrame:nil inContentWorld:[WKContentWorld worldWithName:@"FreeScene.Provider.player"] completionHandler:^(id value,NSError *error){
        if(self.web!=web || generation!=self.loadGeneration) return;
        self.inspectingPlayer=NO;
        if([value isEqual:@YES]) {
            self.loadingCover.hidden=YES;[self.readiness invalidate];self.readiness=nil;
            self.message.stringValue=[self officialLabel];
        } else if(NSDate.timeIntervalSinceReferenceDate-self.loadStarted>30) {
            // A fullscreen/Space transition can delay the timer. Inspect the
            // current document before declaring a player that is ready timed out.
            [self.readiness invalidate];self.readiness=nil;
            self.message.stringValue=fsEnglish ? @"The player did not respond. Retry or select another source." : @"Плеер не ответил. Повторите или выберите другой источник.";
        }
    }];
}
- (void)chooseEpisode:(id)sender {
    NSMenu *menu=[NSMenu new];
    for(NSUInteger i=0;i<self.episodes.count;i++) {
        NSDictionary *episode=self.episodes[i];NSMenuItem *item=[menu addItemWithTitle:episode[@"title"] ?: @"" action:@selector(episodeChanged:) keyEquivalent:@""];
        item.target=self;item.tag=i;item.state=[episode[@"url"] isEqual:self.source.absoluteString] ? NSControlStateValueOn : NSControlStateValueOff;
    }
    FSPopUpAboveLeft(menu,self.episodesButton);
}
- (void)chooseScale:(NSButton *)sender {
    NSMenu *menu=[NSMenu new];menu.font=FSFont(13);
    NSArray<NSString *> *labels=FSPlayerScaleLabels(fsEnglish);
    for(NSInteger i=0;i<labels.count;i++) {
        NSMenuItem *item=[menu addItemWithTitle:labels[i] action:@selector(scaleChanged:) keyEquivalent:@""];
        item.target=self;item.tag=i;item.state=i==self.scaleMode ? NSControlStateValueOn : NSControlStateValueOff;
    }
    FSPopUpAboveLeft(menu,sender);
}
- (void)scaleChanged:(NSMenuItem *)item {
    if(item.tag<FSPlayerScaleFit || item.tag>FSPlayerScaleStretch) return;
    self.scaleMode=(FSPlayerScaleMode)item.tag;
    [self.web evaluateJavaScript:FSPlayerPresentationScript(self.scaleMode) completionHandler:nil];
}
- (void)episodeChanged:(NSMenuItem *)item {
    if(item.tag<0 || item.tag>=self.episodes.count) return;
    NSDictionary *episode=self.episodes[item.tag];NSURL *url=[NSURL URLWithString:episode[@"url"] ?: @""];
    if(!url || !self.context.sameTitle(url,self.source)) return;
    self.source=url;self.window.title=episode[@"title"] ?: @"Video";[self retry:nil];
}
- (void)webView:(WKWebView *)web decidePolicyForNavigationAction:(WKNavigationAction *)action decisionHandler:(void (^)(WKNavigationActionPolicy))handler {
    NSURL *url=action.request.URL;
    BOOL main=action.targetFrame.isMainFrame;
    BOOL allowed=self.context.navigation(url,self.source,main);
    if (!action.targetFrame) allowed=NO;
    handler(allowed ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel);
}
- (nullable WKWebView *)webView:(WKWebView *)web createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)action windowFeatures:(WKWindowFeatures *)features { return nil; }
- (void)webView:(WKWebView *)web didFinishNavigation:(WKNavigation * _Null_unspecified)navigation {
    [web evaluateJavaScript:FSPlayerPresentationScript(self.scaleMode) completionHandler:nil];
    if(self.selectsPlayer) {
        [self inspectPlayer];return;
    }
    self.message.stringValue=[self officialLabel];
}
- (void)failure:(NSError *)error {
    if (error.code==NSURLErrorCancelled) return;
    [self.readiness invalidate];self.readiness=nil;
    self.message.stringValue=(fsEnglish ? @"Player unavailable. Retry or choose another source." : @"Плеер недоступен. Повторите или выберите другой источник.");
}
- (void)webView:(WKWebView *)web didFailNavigation:(WKNavigation * _Null_unspecified)navigation withError:(NSError *)error { [self failure:error]; }
- (void)webView:(WKWebView *)web didFailProvisionalNavigation:(WKNavigation * _Null_unspecified)navigation withError:(NSError *)error { [self failure:error]; }
- (void)webViewWebContentProcessDidTerminate:(WKWebView *)web { [self failure:[NSError errorWithDomain:@"FreeScene" code:1 userInfo:nil]]; }
- (NSString *)officialLabel {
    NSString *name=self.providerName.length ? self.providerName : self.source.host;
    return [NSString stringWithFormat:fsEnglish ? @"Official player “%@”" : @"Официальный плеер «%@»",name ?: @""];
}
- (void)sendAction:(NSString *)action value:(id)value {
    NSMutableDictionary *command=[@{@"action":action} mutableCopy];if(value)command[@"value"]=value;
    NSData *data=[NSJSONSerialization dataWithJSONObject:command options:0 error:nil];
    NSString *json=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    [self.web evaluateJavaScript:[NSString stringWithFormat:@"window.__freesceneControls?.command(%@);",json] completionHandler:nil];
}
- (void)togglePlayback:(id)sender { [self sendAction:@"toggle" value:nil]; }
- (void)skipBack:(id)sender { [self sendAction:@"skip" value:@(-10)]; }
- (void)skipForward:(id)sender { [self sendAction:@"skip" value:@10]; }
- (void)seek:(id)sender { [self sendAction:@"seek" value:@(self.position.doubleValue*[self.playbackState[@"duration"] doubleValue])]; }
- (void)toggleFullscreen:(id)sender { [self.window toggleFullScreen:nil]; }
- (void)toggleNative:(id)sender {
    self.nativeControls=!self.nativeControls;[self sendAction:@"native" value:@(self.nativeControls)];
    [self.nativeButton symbol:self.nativeControls ? @"slider.horizontal.3" : @"rectangle.bottomthird.inset.filled" label:fsEnglish ? @"Provider controls / FreeScene controls" : @"Управление провайдера / FreeScene"];
}
- (void)mute:(id)sender { [self sendAction:@"mute" value:nil]; }
- (void)volume:(NSSlider *)slider { [self sendAction:@"volume" value:@(slider.doubleValue)]; }
- (void)showAudio:(id)sender {
    NSMenu *menu=[NSMenu new];menu.font=FSFont(13);
    NSMenuItem *mute=[menu addItemWithTitle:fsEnglish ? @"Mute / unmute" : @"Выключить / включить звук" action:@selector(mute:) keyEquivalent:@""];mute.target=self;
    NSMenuItem *volume=[NSMenuItem new];NSSlider *slider=[NSSlider sliderWithValue:[self.playbackState[@"volume"] doubleValue] minValue:0 maxValue:1 target:self action:@selector(volume:)];slider.frame=NSMakeRect(12,0,150,30);slider.continuous=YES;slider.trackFillColor=FSThemeAccent(fsDark);[slider setAccessibilityLabel:fsEnglish ? @"Volume" : @"Громкость"];
    NSView *view=[[NSView alloc] initWithFrame:NSMakeRect(0,0,174,30)];[view addSubview:slider];volume.view=view;[menu addItem:volume];FSPopUpAboveLeft(menu,self.audioButton);
}
- (void)updatePlaybackControls {
    BOOL ready=self.lastPlaybackReport>0 && NSProcessInfo.processInfo.systemUptime-self.lastPlaybackReport<3;
    BOOL buffering=ready && [self.playbackState[@"buffering"] boolValue];
    self.playButton.enabled=ready;self.audioButton.enabled=ready;
    self.position.enabled=ready && [self.playbackState[@"seekable"] boolValue] && [self.playbackState[@"duration"] doubleValue]>0;
    self.backButton.enabled=self.forwardButton.enabled=self.position.enabled;
    if(ready) {
        self.loadingCover.hidden=YES;self.position.busy=buffering;
        BOOL paused=[self.playbackState[@"paused"] boolValue];
        [self.playButton symbol:paused ? @"play.fill" : @"pause.fill" label:paused ? FSL(@"Продолжить") : FSL(@"Пауза")];
        self.message.stringValue=buffering ? FSL(@"Буферизация…") : [self officialLabel];
    } else if(self.lastPlaybackReport>0 || NSDate.timeIntervalSinceReferenceDate-self.loadStarted>10) {
        [self.watchedClock sample:NO at:NSProcessInfo.processInfo.systemUptime];self.position.busy=NO;
        self.message.stringValue=fsEnglish ? @"Open provider controls to continue" : @"Откройте управление провайдера для продолжения";
    }
}
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
    if(!self.web || ![message.body isKindOfClass:NSDictionary.class])return;
    NSDictionary *value=message.body;
    for(NSString *key in @[@"position",@"duration",@"volume",@"paused",@"ended",@"buffering",@"playing",@"muted",@"seekable"])if(![value[key] isKindOfClass:NSNumber.class] || !isfinite([value[key] doubleValue]))return;
    double p=[value[@"position"] doubleValue],d=[value[@"duration"] doubleValue],v=[value[@"volume"] doubleValue];
    if(p<0 || d<0 || d>604800 || p>604800 || v<0 || v>1)return;
    self.playbackState=value;self.lastPlaybackReport=NSProcessInfo.processInfo.systemUptime;
    if(d>0)self.position.doubleValue=MIN(1,p/d);
    NSInteger position=(NSInteger)p,duration=(NSInteger)d;
    self.timeLabel.stringValue=[NSString stringWithFormat:@"%ld:%02ld / %ld:%02ld",position/60,position%60,duration/60,duration%60];
    [self.watchedClock sample:[value[@"playing"] isEqual:@YES] at:self.lastPlaybackReport];
    [self updatePlaybackControls];
}
- (void)stop {
    [self.watchedClock sample:NO at:NSProcessInfo.processInfo.systemUptime];
    [self.playbackTimer invalidate];self.playbackTimer=nil;
    [self.web.configuration.userContentController removeScriptMessageHandlerForName:@"FreeSceneControls"];
    ++self.loadGeneration;[self.readiness invalidate];self.readiness=nil;
    [self.fullscreen stop];self.fullscreen=nil;
    WKWebView *web=self.web;self.web=nil;
    web.navigationDelegate=nil;web.UIDelegate=nil;[web stopLoading];
    void (^detach)(void)=^{[web loadHTMLString:@"" baseURL:nil];[web removeFromSuperview];};
    if(web.fullscreenState!=WKFullscreenStateNotInFullscreen) {
        [web pauseAllMediaPlaybackWithCompletionHandler:nil];
        [web closeAllMediaPresentationsWithCompletionHandler:detach];
    } else detach();
}
@end
NS_ASSUME_NONNULL_END
