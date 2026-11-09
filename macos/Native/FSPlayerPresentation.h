#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSInteger, FSPlayerScaleMode) {
    FSPlayerScaleFit,
    FSPlayerScaleFill,
    FSPlayerScaleStretch
};

static inline NSArray<NSString *> *FSPlayerScaleLabels(BOOL english) {
    return english ? @[@"Fit",@"Fill",@"Stretch"] : @[@"Вписать",@"Заполнить",@"Растянуть"];
}

static inline NSString *FSPlayerPresentationScript(FSPlayerScaleMode mode) {
    NSString *path=[NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@"App.framework/Resources/flutter_assets/assets/player/presentation.js"];
    NSString *source=path ? [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] : nil;
    return source.length ? [NSString stringWithFormat:@"(%@)(%ld);",source,(long)mode] : @"";
}

static inline NSString *FSPlayerViewportRatio(NSSize size) {
    return [NSString stringWithFormat:@"%ld:%ld",(long)MAX(1,lround(size.width)),(long)MAX(1,lround(size.height))];
}
