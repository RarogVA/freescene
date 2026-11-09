#import <Cocoa/Cocoa.h>
#import "FSReleaseUpdater.h"

// Native About window with anonymous updates and open-source notices.
@interface FSAboutWindow : NSObject <NSWindowDelegate>
@property NSWindow *window;
@property NSTextField *status;
@property NSButton *checkButton;
@property NSButton *licensesButton;
@property NSWindow *licensesWindow;
@property NSTextView *licenseText;
@property (copy) void (^licensesRequested)(void);
@property FSReleaseUpdater *updater;
@property NSAlert *startupAlert;
@property NSUInteger startupOfferGeneration;
- (void)show;
- (void)cancel;
- (void)offerStartupUpdateForWindow:(NSWindow *)window allowed:(BOOL (^)(void))allowed;
- (void)dismissStartupOffer;
- (void)applyAppearance;
- (void)showLicensesText:(NSString *)text;
@end
@implementation FSAboutWindow
- (instancetype)init {
    if((self=[super init])) {
        self.updater=[FSReleaseUpdater new];__weak FSAboutWindow *weak=self;
        self.updater.changed=^{[weak updateControls];};
    }
    return self;
}
- (void)show {
    [self.updater cancelStartupCheck];[self dismissStartupOffer];
    if (!self.window) {
        self.window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,540,388) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
        self.window.releasedWhenClosed=NO; self.window.delegate=self;
        NSImageView *icon=[NSImageView imageViewWithImage:NSApp.applicationIconImage]; icon.frame=NSMakeRect(230,282,80,80); [self.window.contentView addSubview:icon];
        NSString *version=[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"";
        NSArray *labels=@[@"FreeScene",[NSString stringWithFormat:@"%@ %@",fsEnglish ? @"Version" : @"Версия",version],@"FreeScene - портал для Вашего удобства!"];
        CGFloat y=246;
        for(NSUInteger i=0;i<labels.count;++i) { NSTextField *label=[NSTextField labelWithString:labels[i]]; label.font=FSFont(i==0?26:14); label.alignment=NSTextAlignmentCenter; label.frame=NSMakeRect(20,y,500,30); label.tag=10+i; [self.window.contentView addSubview:label]; y-=32; }
        self.checkButton=[NSButton buttonWithTitle:@"" target:self action:@selector(check:)]; self.checkButton.bezelStyle=NSBezelStyleRounded; self.checkButton.font=FSFont(13); self.checkButton.frame=NSMakeRect(120,90,300,30); [self.window.contentView addSubview:self.checkButton];
        self.licensesButton=[NSButton buttonWithTitle:@"" target:self action:@selector(licenses:)]; self.licensesButton.bezelStyle=NSBezelStyleRounded; self.licensesButton.font=FSFont(13); self.licensesButton.frame=NSMakeRect(120,52,300,30); [self.window.contentView addSubview:self.licensesButton];
        self.status=[NSTextField wrappingLabelWithString:@""]; self.status.font=FSFont(11); self.status.alignment=NSTextAlignmentCenter; self.status.frame=NSMakeRect(20,6,500,40); [self.window.contentView addSubview:self.status];
        [self.window center];
    }
    [self applyAppearance]; [self.window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
}
- (void)applyAppearance {
    self.window.title=fsEnglish ? @"About FreeScene" : @"О приложении FreeScene";
    self.window.appearance=[NSAppearance appearanceNamed:fsDark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
    self.window.backgroundColor=FSThemeBackground(fsDark);
    for(NSView *view in self.window.contentView.subviews) if([view isKindOfClass:NSTextField.class]) ((NSTextField *)view).textColor=FSThemeText(fsDark);
    NSTextField *version=[self.window.contentView viewWithTag:11]; version.stringValue=[NSString stringWithFormat:@"%@ %@",fsEnglish ? @"Version" : @"Версия",[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @""];
    [self updateControls];
    NSString *licensesTitle=fsEnglish ? @"Open-source licences" : @"Лицензии открытого ПО";
    self.licensesButton.title=licensesTitle;
    self.licensesWindow.title=licensesTitle;
    self.licensesWindow.appearance=[NSAppearance appearanceNamed:fsDark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
    self.licensesWindow.backgroundColor=FSThemeBackground(fsDark);
    self.licenseText.backgroundColor=FSThemeBackground(fsDark);
    self.licenseText.textColor=FSThemeText(fsDark);
}
- (void)licenses:(id)sender { if(self.licensesRequested) self.licensesRequested(); }
- (void)showLicensesText:(NSString *)text {
    [self.updater cancelStartupCheck];[self dismissStartupOffer];
    if(!self.licensesWindow) {
        self.licensesWindow=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,720,560) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
        self.licensesWindow.releasedWhenClosed=NO;
        self.licensesWindow.contentMinSize=NSMakeSize(440,320);
        NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:self.licensesWindow.contentView.bounds];
        scroll.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
        scroll.hasVerticalScroller=YES; scroll.autohidesScrollers=YES;
        self.licenseText=[[NSTextView alloc] initWithFrame:scroll.contentView.bounds];
        self.licenseText.editable=NO; self.licenseText.selectable=YES; self.licenseText.richText=NO;
        self.licenseText.font=FSFont(12); self.licenseText.textContainerInset=NSMakeSize(16,16);
        self.licenseText.minSize=NSMakeSize(0,scroll.contentSize.height);
        self.licenseText.maxSize=NSMakeSize(CGFLOAT_MAX,CGFLOAT_MAX);
        self.licenseText.verticallyResizable=YES; self.licenseText.horizontallyResizable=NO;
        self.licenseText.autoresizingMask=NSViewWidthSizable;
        self.licenseText.textContainer.containerSize=NSMakeSize(scroll.contentSize.width,CGFLOAT_MAX);
        self.licenseText.textContainer.widthTracksTextView=YES;
        self.licenseText.usesFindBar=YES;
        scroll.documentView=self.licenseText; [self.licensesWindow.contentView addSubview:scroll];
        [self.licensesWindow center];
    }
    self.licenseText.string=text;
    [self.licenseText scrollRangeToVisible:NSMakeRange(0,0)];
    [self applyAppearance]; [self.licensesWindow makeKeyAndOrderFront:nil];
}
- (void)updateControls {
    NSString *phase=self.updater.phase;
    if(![phase isEqual:@"available"])[self dismissStartupOffer];
    self.checkButton.enabled=!phase || [@[@"idle",@"available",@"ready"] containsObject:phase];
    NSDictionary *labels=fsEnglish ?
        @{@"checking":@"Checking…",@"downloading":@"Downloading…",@"installing":@"Installing…",@"available":@"Install updates",@"ready":@"Install updates"} :
        @{@"checking":@"Проверка…",@"downloading":@"Загрузка…",@"installing":@"Установка…",@"available":@"Установить обновления",@"ready":@"Установить обновления"};
    self.checkButton.title=labels[phase ?: @"idle"] ?: (fsEnglish ? @"Check for updates" : @"Проверить обновления");
    self.status.stringValue=self.updater.message ?: @"";
}
- (void)offerStartupUpdateForWindow:(NSWindow *)window allowed:(BOOL (^)(void))allowed {
    if(self.startupAlert || !window || ![self.updater.phase isEqual:@"available"] || !self.updater.asset || !allowed || !allowed())return;
    NSUInteger generation=++self.startupOfferGeneration,updaterGeneration=self.updater.generation;
    NSAlert *alert=[NSAlert new];self.startupAlert=alert;
    alert.alertStyle=NSAlertStyleInformational;
    alert.messageText=[NSString stringWithFormat:fsEnglish ? @"FreeScene %@ is available" : @"Доступна FreeScene %@",self.updater.asset[@"version"]];
    alert.informativeText=fsEnglish ? @"Open About to download and verify the update. You can install it when you are ready." : @"Откройте «О приложении», чтобы загрузить и проверить обновление. Установить его можно в удобный момент.";
    [alert addButtonWithTitle:fsEnglish ? @"Update…" : @"Обновить…"];
    [alert addButtonWithTitle:fsEnglish ? @"Later" : @"Позже"];
    __weak FSAboutWindow *weak=self;
    [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
        FSAboutWindow *s=weak;if(!s || generation!=s.startupOfferGeneration)return;
        s.startupAlert=nil;
        if(response==NSAlertFirstButtonReturn && updaterGeneration==s.updater.generation &&
           [s.updater.phase isEqual:@"available"])[s show];
    }];
}
- (void)dismissStartupOffer {
    ++self.startupOfferGeneration;
    NSAlert *alert=self.startupAlert;self.startupAlert=nil;
    if(alert.window.sheetParent)[alert.window.sheetParent endSheet:alert.window returnCode:NSModalResponseCancel];
    [alert.window orderOut:nil];
}
- (void)check:(id)sender {
    [self dismissStartupOffer];
    [self.updater activate];
}
- (void)cancel {
    [self dismissStartupOffer];[self.updater cancel];
}
- (void)windowWillClose:(NSNotification *)notification {[self cancel];}
@end
