// Included after FreeScene's native round button and typography definitions.
#import <WebKit/WebKit.h>
#import "FSProviderPlayback.h"
#import "FSPlayerKeyboard.h"
#import "FSWebFullscreen.h"
#import "FSPlayerPresentation.h"
NS_ASSUME_NONNULL_BEGIN

@interface FSProviderView : NSView <WKNavigationDelegate, WKUIDelegate>
@property(nullable) WKWebView *web;
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
    [config.userContentController addUserScript:[[WKUserScript alloc] initWithSource:FSPlayerKeyboardScript() injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO]];
    [config.userContentController addUserScript:[[WKUserScript alloc] initWithSource:FSPlayerPresentationScript(self.scaleMode) injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO]];
    config.websiteDataStore=context.store ? (WKWebsiteDataStore * _Nonnull)context.store : WKWebsiteDataStore.nonPersistentDataStore;
    if(self.selectsPlayer) [config.userContentController addUserScript:[[WKUserScript alloc] initWithSource:context.selectionScript injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES inContentWorld:[WKContentWorld worldWithName:@"FreeScene.Provider.player"]]];
    config.mediaTypesRequiringUserActionForPlayback=WKAudiovisualMediaTypeAll;
    config.preferences.javaScriptCanOpenWindowsAutomatically=NO;
    config.preferences.elementFullscreenEnabled=YES;
    WKWebView *web=[[WKWebView alloc] initWithFrame:NSMakeRect(0,60,frame.size.width,MAX(0,frame.size.height-60)) configuration:config];
    self.web=web;
    self.fullscreen=[[FSWebFullscreen alloc] initWithWebView:web container:self];
    web.underPageBackgroundColor=NSColor.blackColor;
    self.web.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
    self.web.navigationDelegate=self; self.web.UIDelegate=self;
    [self addSubview:web];
    self.loadingCover=[[NSView alloc] initWithFrame:web.frame];self.loadingCover.wantsLayer=YES;self.loadingCover.layer.backgroundColor=NSColor.blackColor.CGColor;
    self.loadingCover.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;self.loadingCover.hidden=!self.selectsPlayer;[self addSubview:self.loadingCover];
    self.toolbar=[[NSView alloc] initWithFrame:NSMakeRect(0,0,frame.size.width,60)];
    self.toolbar.wantsLayer=YES; self.toolbar.autoresizingMask=NSViewWidthSizable;
    [self addSubview:self.toolbar];
    self.message=[NSTextField labelWithString:@""]; self.message.font=FSFont(12); self.message.maximumNumberOfLines=2;
    self.message.lineBreakMode=NSLineBreakByTruncatingTail;
    self.retryButton=[FSRoundButton new]; self.retryButton.target=self; self.retryButton.action=@selector(retry:);
    self.episodesButton=[FSRoundButton new];self.episodesButton.target=self;self.episodesButton.action=@selector(chooseEpisode:);self.episodesButton.hidden=!self.selectsPlayer || episodes.count<2;
    self.scaleButton=[FSRoundButton new];self.scaleButton.target=self;self.scaleButton.action=@selector(chooseScale:);
    NSArray<NSView *> *controls=@[self.message,self.episodesButton,self.scaleButton,self.retryButton];
    NSStackView *stack=[NSStackView stackViewWithViews:controls];
    stack.distribution=NSStackViewDistributionFill;stack.spacing=12; stack.translatesAutoresizingMaskIntoConstraints=NO; [self.toolbar addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:self.toolbar.leadingAnchor constant:16],
      [stack.trailingAnchor constraintEqualToAnchor:self.toolbar.trailingAnchor constant:-16],
      [stack.centerYAnchor constraintEqualToAnchor:self.toolbar.centerYAnchor]]];
    [self.message setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
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
    self.message.textColor=FSThemeText(fsDark);
    [self.retryButton symbol:@"arrow.clockwise" label:fsEnglish ? @"Retry" : @"Повторить"];
    [self.episodesButton symbol:@"list.bullet" label:fsEnglish ? @"Seasons and episodes" : @"Сезоны и серии"];
    [self.scaleButton symbol:@"aspectratio" label:fsEnglish ? @"Video scale" : @"Масштаб видео"];
    [self.scaleButton applyAppearance];
    [self.episodesButton applyAppearance];
    [self.retryButton applyAppearance];
}
- (void)retry:(nullable id)sender {
    if(self.selectsPlayer && !self.contentRulesReady) return;
    self.message.stringValue=(fsEnglish ? @"Loading video…" : @"Загрузка видео…");
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
            self.message.stringValue=@"";
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
    self.message.stringValue=@"";
}
- (void)failure:(NSError *)error {
    if (error.code==NSURLErrorCancelled) return;
    [self.readiness invalidate];self.readiness=nil;
    self.message.stringValue=(fsEnglish ? @"Player unavailable. Retry or choose another source." : @"Плеер недоступен. Повторите или выберите другой источник.");
}
- (void)webView:(WKWebView *)web didFailNavigation:(WKNavigation * _Null_unspecified)navigation withError:(NSError *)error { [self failure:error]; }
- (void)webView:(WKWebView *)web didFailProvisionalNavigation:(WKNavigation * _Null_unspecified)navigation withError:(NSError *)error { [self failure:error]; }
- (void)webViewWebContentProcessDidTerminate:(WKWebView *)web { [self failure:[NSError errorWithDomain:@"FreeScene" code:1 userInfo:nil]]; }
- (void)stop {
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
