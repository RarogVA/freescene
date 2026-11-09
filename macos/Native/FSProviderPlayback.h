#pragma once
#import "../../packages/freescene_provider_host/macos/freescene_provider_host/Sources/freescene_provider_host/include/FSProviderHost.h"
static inline BOOL FSProviderURLAllowed(NSURL *url, NSString *provider, NSString *kind) {
    if(!url || url.absoluteString.length>8192 || ![url.scheme isEqual:@"https"] || !url.host.length ||
       url.user || url.password || (url.port && url.port.integerValue!=443))return NO;
    return [FSProviderHost.adapter allowsURL:url provider:provider kind:kind];
}
