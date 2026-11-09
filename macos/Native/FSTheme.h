#import <Cocoa/Cocoa.h>

// Keep the native player and About window aligned with FreeSceneTheme's roles.
static NSColor *FSThemeColor(BOOL dark, unsigned graphite, unsigned porcelain) {
    unsigned rgb=dark ? graphite : porcelain;
    return [NSColor colorWithSRGBRed:((rgb>>16)&255)/255.0 green:((rgb>>8)&255)/255.0 blue:(rgb&255)/255.0 alpha:1];
}
static NSColor *FSThemeBackground(BOOL dark) { return FSThemeColor(dark,0x17181b,0xf4f3f0); }
static NSColor *FSThemePanel(BOOL dark) { return FSThemeColor(dark,0x222429,0xeae9e5); }
static NSColor *FSThemeRaised(BOOL dark) { return FSThemeColor(dark,0x2c2e34,0xffffff); }
static NSColor *FSThemeText(BOOL dark) { return FSThemeColor(dark,0xeeeef0,0x252731); }
static NSColor *FSThemeAccent(BOOL dark) { return FSThemeColor(dark,0xdda66c,0x5263c7); }
static NSColor *FSThemeOnAccent(BOOL dark) { return FSThemeColor(dark,0x241a10,0xffffff); }
static NSColor *FSThemeSelected(BOOL dark) { return FSThemeColor(dark,0x393127,0xdce0f4); }
