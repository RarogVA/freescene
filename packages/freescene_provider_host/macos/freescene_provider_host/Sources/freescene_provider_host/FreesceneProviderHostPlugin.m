#import "include/FreesceneProviderHostPlugin.h"
#import "include/FSProviderHost.h"
@implementation FSWebPlaybackContext
@end
static id<FSProviderAdapter> activeAdapter;
@implementation FSProviderHost
+ (id<FSProviderAdapter>)adapter {return activeAdapter;}
+ (void)setAdapter:(id<FSProviderAdapter>)adapter {activeAdapter=adapter;}
@end
@implementation FreesceneProviderHostPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {}
@end
