#import "../../macos/Native/FSWebFullscreen.h"
@interface FSFullscreenFixture : NSObject <NSApplicationDelegate>
@property NSWindow *catalog,*player;
@property NSView *root;
@property WKWebView *web;
@property FSWebFullscreen *fullscreen;
@property NSTextField *status;
@property NSTimer *timer;
@property id eventMonitor;
@end
@implementation FSFullscreenFixture
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSWindow.allowsAutomaticWindowTabbing=NO;
    NSMenu *menu=[NSMenu new];NSMenuItem *app=[NSMenuItem new];[menu addItem:app];app.submenu=[NSMenu new];[app.submenu addItemWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"];NSApp.mainMenu=menu;
    NSUInteger style=NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable;
    self.catalog=[[NSWindow alloc] initWithContentRect:NSMakeRect(60,100,650,350) styleMask:style backing:NSBackingStoreBuffered defer:NO];self.catalog.title=@"FreeScene Fullscreen — Каталог";self.catalog.releasedWhenClosed=NO;
    NSTextField *label=[NSTextField labelWithString:@"Локальная проверка окон FreeScene\nБез сети, аккаунтов и настоящего видео."];
    label.frame=NSMakeRect(24,220,580,80);[self.catalog.contentView addSubview:label];
    self.status=[NSTextField labelWithString:@""];self.status.frame=NSMakeRect(24,60,600,130);self.status.maximumNumberOfLines=8;[self.catalog.contentView addSubview:self.status];
    [self.catalog makeKeyAndOrderFront:nil];
    self.player=[[NSWindow alloc] initWithContentRect:NSMakeRect(140,200,860,540) styleMask:style backing:NSBackingStoreBuffered defer:NO];self.player.title=@"FreeScene Fullscreen — Плеер";self.player.releasedWhenClosed=NO;self.player.collectionBehavior=NSWindowCollectionBehaviorFullScreenPrimary;
    self.root=self.player.contentView;
    WKWebViewConfiguration *config=[WKWebViewConfiguration new];config.preferences.elementFullscreenEnabled=YES;config.websiteDataStore=WKWebsiteDataStore.nonPersistentDataStore;
    self.web=[[WKWebView alloc] initWithFrame:NSMakeRect(0,60,860,480) configuration:config];self.web.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;[self.root addSubview:self.web];
    self.fullscreen=[[FSWebFullscreen alloc] initWithWebView:self.web container:self.root];
    __weak FSFullscreenFixture *weak=self;
    self.eventMonitor=[NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event){
        if(event.keyCode==53 && [weak.fullscreen exitFromWindow:event.window])return nil;
        return event;
    }];
    NSTextField *footer=[NSTextField labelWithString:@"Нативная панель плеера FreeScene"];footer.frame=NSMakeRect(20,16,750,28);footer.autoresizingMask=NSViewWidthSizable;[self.root addSubview:footer];
    NSString *html=@"<!doctype html><meta charset=utf-8><style>html,body{margin:0;height:100%;background:#111;color:#eee;font:24px system-ui}#film{display:grid;place-content:center;text-align:center;height:100%;background:linear-gradient(35deg,#17212b,#73513b)}button{font:20px system-ui;padding:18px;margin:20px}#film:fullscreen{width:100vw;height:100vh}</style><div id=film><h1>Проверка полноэкранного плеера</h1><p>Настоящий WKWebView, без загрузки видео</p><button onclick=\"document.getElementById('film').requestFullscreen()\">Полный экран WebKit</button><p>Esc — вернуться в окно</p></div>";
    [self.web loadHTMLString:html baseURL:nil];[self.player makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES];
    self.timer=[NSTimer scheduledTimerWithTimeInterval:0.2 target:self selector:@selector(update:) userInfo:nil repeats:YES];
}
- (void)update:(id)sender {
    NSDictionary *state=@{@"hostVisible":@(self.player.visible),@"nativeFullscreen":@((self.player.styleMask&NSWindowStyleMaskFullScreen)!=0),@"webFullscreen":@(self.web.fullscreenState),@"webMoved":@(self.web.window!=self.player),@"fullscreenWindowVisible":@(self.web.window.visible)};
    self.status.stringValue=state.description;
    NSData *json=[NSJSONSerialization dataWithJSONObject:state options:NSJSONWritingPrettyPrinted error:nil];NSURL *stateURL=[NSBundle.mainBundle.bundleURL.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"web-fullscreen-ui-state.json"];[json writeToURL:stateURL atomically:YES];
}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender { if(self.eventMonitor)[NSEvent removeMonitor:self.eventMonitor];[self.fullscreen stop];return NSTerminateNow; }
@end
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];FSFullscreenFixture *delegate=[FSFullscreenFixture new];NSApp.delegate=delegate;[NSApp run];
} return 0; }
