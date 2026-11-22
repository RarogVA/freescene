// Real AppKit layout and state checks; no HTTP, credentials or installed app.
#import <Cocoa/Cocoa.h>
#import <CoreText/CoreText.h>
static BOOL fsEnglish=NO,fsDark=YES;
#import "../../macos/Native/FSTheme.h"
static NSFont *FSFont(CGFloat size){return [NSFont fontWithName:@"Play" size:size] ?: [NSFont systemFontOfSize:size];}
#import "../../macos/Native/FSAboutWindow.h"

int main(void){@autoreleasepool {
    [NSApplication sharedApplication];
    CTFontManagerRegisterFontsForURL((__bridge CFURLRef)[NSURL fileURLWithPath:@"assets/fonts/Play-Regular.ttf"],kCTFontManagerScopeProcess,NULL);
    NSApp.applicationIconImage=[[NSImage alloc] initWithContentsOfFile:@"macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png"];
    FSAboutWindow *about=[FSAboutWindow new];
    __block NSUInteger requests=0;
    about.updater.makeHTTP=^{++requests;return [FSGitHubHTTP new];};
    [about show];
    NSUInteger actions=0;
    for(NSView *view in about.window.contentView.subviews) {
        if([view isKindOfClass:NSButton.class]) ++actions;
        NSCAssert(![view isKindOfClass:NSSecureTextField.class],@"Token input must be absent");
    }
    NSCAssert(actions==3,@"About includes updates, licenses and developer support");
    NSRect windowFrame=about.window.frame,checkFrame=about.checkButton.frame,licensesFrame=about.licensesButton.frame;
    NSRect statusFrame=about.statusScroll.frame,progressFrame=about.progress.frame;
    for(NSNumber *english in @[@NO,@YES]) {
        fsEnglish=english.boolValue;[about applyAppearance];
        NSCAssert([about.supportButton.title isEqualToString:fsEnglish ? @"Support the developer" : @"Поддержать разработчика"],@"Support action follows the interface language");
        NSCAssert(NSWidth(about.supportButton.frame)==NSWidth(about.checkButton.frame) && NSMinX(about.supportButton.frame)==NSMinX(about.checkButton.frame),@"Support aligns with existing actions");
        NSCAssert(NSMaxY(about.supportButton.frame)<NSMinY(about.licensesButton.frame),@"Support does not overlap licenses");
        NSCAssert([about.supportButton.title sizeWithAttributes:@{NSFontAttributeName:about.supportButton.font}].width+28<NSWidth(about.supportButton.frame),@"Localized support title fits with its icon");
        for(NSString *phase in @[@"idle",@"checking",@"available",@"downloading",@"ready",@"installing"]) {
            [about.updater publish:phase message:@""];
            NSCAssert(NSWidth(about.checkButton.frame)==NSWidth(about.licensesButton.frame),@"Actions must have equal widths");
            NSCAssert(NSMinX(about.checkButton.frame)==NSMinX(about.licensesButton.frame),@"Actions must align horizontally");
            NSCAssert((about.checkButton.enabled==[@[@"idle",@"available",@"ready"] containsObject:phase]),@"Busy operations disable update action");
            NSCAssert(![about.checkButton.title.lowercaseString containsString:@"token"],@"No account state in update action");
            NSCAssert(NSEqualRects(windowFrame,about.window.frame) && NSEqualRects(checkFrame,about.checkButton.frame) && NSEqualRects(licensesFrame,about.licensesButton.frame),@"Status transitions preserve window and actions");
            NSCAssert(NSEqualRects(statusFrame,about.statusScroll.frame) && NSEqualRects(progressFrame,about.progress.frame),@"Status and progress regions stay allocated");
            NSCAssert((about.progress.hidden==![@[@"checking",@"downloading",@"installing"] containsObject:phase]),@"Progress is visible only during work");
        }
    }
    [about.updater publish:@"downloading" message:@"Downloading 42 %"];
    about.updater.downloadProgress=.42;[about updateControls];
    NSCAssert(!about.progress.indeterminate && about.progress.doubleValue==.42,@"Download progress reflects the actual transfer");
    [about.updater publish:@"idle" message:[@"Подробное сообщение об ошибке подключения. " stringByPaddingToLength:1800 withString:@"Повторите попытку позже. " startingAtIndex:0]];
    NSCAssert(about.status.frame.size.height>about.statusScroll.contentSize.height,@"Long messages can scroll inside the reserved area");
    NSCAssert(NSEqualRects(windowFrame,about.window.frame) && NSEqualRects(checkFrame,about.checkButton.frame),@"Long errors do not resize the window");
    NSCAssert(!NSIntersectsRect(about.statusScroll.frame,about.checkButton.frame),@"Messages never overlap actions");
    NSCAssert(requests==0,@"Opening and rendering About must not access HTTP");
    fsEnglish=NO;[about.updater publish:@"idle" message:@""];[about applyAppearance];
    [about.window.contentView layoutSubtreeIfNeeded];
    [about.window displayIfNeeded];
    NSView *view=about.window.contentView;
    view.wantsLayer=YES;view.layer.backgroundColor=about.window.backgroundColor.CGColor;
    NSBitmapImageRep *bitmap=[view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
    [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@"build/public-updates-about.png" atomically:YES];
    NSBitmapImageRep *button=[about.supportButton bitmapImageRepForCachingDisplayInRect:about.supportButton.bounds];
    [about.supportButton cacheDisplayInRect:about.supportButton.bounds toBitmapImageRep:button];
    [NSFileManager.defaultManager createDirectoryAtPath:@"build/developer-support" withIntermediateDirectories:YES attributes:nil error:nil];
    [[button representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@"build/developer-support/button-macos.png" atomically:YES];
    [about.window close];
    printf("{\"passed\":true,\"actions\":3,\"equalWidths\":true,\"states\":12,\"networkUsed\":false}\n");
}return 0;}
