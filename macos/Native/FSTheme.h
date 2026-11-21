#import <Cocoa/Cocoa.h>

// Keep the native player and About window aligned with FreeSceneTheme's roles.
static NSColor *FSThemeColor(BOOL dark, unsigned graphite, unsigned porcelain) {
    unsigned rgb=dark ? graphite : porcelain;
    return [NSColor colorWithSRGBRed:((rgb>>16)&255)/255.0 green:((rgb>>8)&255)/255.0 blue:(rgb&255)/255.0 alpha:1];
}
static NSColor *FSThemeBackground(BOOL dark) { return FSThemeColor(dark,0x1b1b1d,0xf4f4f6); }
static NSColor *FSThemePanel(BOOL dark) { return FSThemeColor(dark,0x232325,0xededf0); }
static NSColor *FSThemeRaised(BOOL dark) { return FSThemeColor(dark,0x303033,0xffffff); }
static NSColor *FSThemeText(BOOL dark) { return FSThemeColor(dark,0xeeeef0,0x252731); }
static NSColor *FSThemeAccent(BOOL dark) { return FSThemeColor(dark,0xbdb3ff,0x6755b6); }
static NSColor *FSThemeOnAccent(BOOL dark) { return FSThemeColor(dark,0x241d46,0xffffff); }
static NSColor *FSThemeSelected(BOOL dark) { return FSThemeColor(dark,0x403951,0xe8e1fa); }
