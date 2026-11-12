// Real AppKit layout and state checks; no HTTP, credentials or installed app.
#import <Cocoa/Cocoa.h>
static BOOL fsEnglish=NO,fsDark=YES;
#import "../../macos/Native/FSTheme.h"
static NSFont *FSFont(CGFloat size){return [NSFont systemFontOfSize:size];}
#import "../../macos/Native/FSAboutWindow.h"

int main(void){@autoreleasepool {
    [NSApplication sharedApplication];
    NSApp.applicationIconImage=[[NSImage alloc] initWithSize:NSMakeSize(64,64)];
    FSAboutWindow *about=[FSAboutWindow new];
    __block NSUInteger requests=0;
    about.updater.makeHTTP=^{++requests;return [FSGitHubHTTP new];};
    [about show];
    NSUInteger actions=0;
    for(NSView *view in about.window.contentView.subviews) {
        if([view isKindOfClass:NSButton.class]) ++actions;
        NSCAssert(![view isKindOfClass:NSSecureTextField.class],@"Token input must be absent");
    }
    NSCAssert(actions==2,@"Only update and licenses actions belong in About");
    NSRect windowFrame=about.window.frame,checkFrame=about.checkButton.frame,licensesFrame=about.licensesButton.frame;
    NSRect statusFrame=about.statusScroll.frame,progressFrame=about.progress.frame;
    for(NSNumber *english in @[@NO,@YES]) {
        fsEnglish=english.boolValue;[about applyAppearance];
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
    NSBitmapImageRep *bitmap=[view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
    [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@"build/public-updates-about.png" atomically:YES];
    [about.window close];
    printf("{\"passed\":true,\"actions\":2,\"equalWidths\":true,\"states\":12,\"networkUsed\":false}\n");
}return 0;}
