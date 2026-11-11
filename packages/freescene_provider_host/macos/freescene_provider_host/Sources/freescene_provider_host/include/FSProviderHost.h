#pragma once
#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
NS_ASSUME_NONNULL_BEGIN
@interface FSWebPlaybackContext : NSObject
@property(nullable) WKWebsiteDataStore *store;
@property(nullable,copy) NSString *selectionScript;
@property(nullable,copy) NSString *contentRules;
@property(nullable,copy) NSString *progressRootSelector;
// Optional trusted JS function (frameWindow), installed before page scripts.
@property(nullable,copy) NSString *mediaPreparationScript;
@property(copy) BOOL (^sameTitle)(NSURL *target, NSURL *source);
@property(copy) BOOL (^navigation)(NSURL *target, NSURL *source, BOOL mainFrame);
@end
@protocol FSProviderAdapter <NSObject>
- (BOOL)allowsURL:(NSURL *)url provider:(NSString *)provider kind:(NSString *)kind;
- (nullable FSWebPlaybackContext *)contextForURL:(NSURL *)url provider:(nullable NSString *)provider player:(NSInteger)player episodes:(NSArray *)episodes;
- (BOOL)allowsTrailer:(NSDictionary *)reference;
- (void)resolveTrailer:(NSDictionary *)reference userAgent:(NSString *)agent completion:(void (^)(NSURL * _Nullable media, NSURL * _Nullable referrer, NSString * _Nullable webProvider, NSString * _Nullable error))completion;
- (void)cancelTrailers;
- (void)stop;
@optional
// Provider-owned HTTP headers for native playback, never account credentials.
- (nullable NSDictionary<NSString *, NSString *> *)playbackHeadersForURL:(NSURL *)url provider:(NSString *)provider;
@end
@interface FSProviderHost : NSObject
+ (nullable id<FSProviderAdapter>)adapter;
+ (void)setAdapter:(nullable id<FSProviderAdapter>)adapter;
@end
NS_ASSUME_NONNULL_END
