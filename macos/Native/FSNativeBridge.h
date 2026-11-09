#import <Cocoa/Cocoa.h>
#import <FlutterMacOS/FlutterMacOS.h>
@interface FSNativeBridge : NSObject
+ (void)registerWithController:(FlutterViewController *)controller window:(NSWindow *)window;
+ (void)showMainWindow;
+ (void)shutdownWithCompletion:(void (^)(void))completion;
+ (void)openLocalVideo;
@end
