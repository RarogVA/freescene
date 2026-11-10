#pragma once
#import <Foundation/Foundation.h>

static inline NSString *FSWatchedPath(void) {
    NSString *root=NSProcessInfo.processInfo.environment[@"FREESCENE_DATA"] ?: [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/FreeScene"];
    return [root stringByAppendingPathComponent:@"watched.json"];
}
static inline NSDictionary *FSWatchedSnapshot(void) {
    NSData *data=[NSData dataWithContentsOfFile:FSWatchedPath()];
    id value=data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if(![value isKindOfClass:NSDictionary.class])return @{};
    NSMutableDictionary *valid=[NSMutableDictionary new];
    for(id key in value)if([key isKindOfClass:NSString.class] && [value[key] isKindOfClass:NSString.class])valid[key]=value[key];
    return valid;
}
static inline BOOL FSSetWatched(NSString *source,NSString *title,BOOL watched) {
    if(![source isKindOfClass:NSString.class] || ![title isKindOfClass:NSString.class] || !source.length || !title.length || source.length>4096 || title.length>4096)return NO;
    NSMutableDictionary *entries=[FSWatchedSnapshot() mutableCopy];
    if(watched)entries[source]=title;else [entries removeObjectForKey:source];
    NSString *path=FSWatchedPath();
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    NSData *data=[NSJSONSerialization dataWithJSONObject:entries options:0 error:nil];
    return [data writeToFile:path options:NSDataWritingAtomic error:nil];
}
@interface FSWatchedClock : NSObject
@property(copy) NSString *source;
@property(copy) NSString *title;
@property double elapsed;
@property double last;
@property BOOL active;
- (void)sample:(BOOL)playing at:(double)now;
@end
@implementation FSWatchedClock
- (void)sample:(BOOL)playing at:(double)now {
    double delta=now-self.last;
    if(self.active && playing && delta>=0 && delta<=6 && self.elapsed<120) {
        self.elapsed+=delta;
        if(self.elapsed>=120 && !FSSetWatched(self.source,self.title,YES))self.elapsed=119;
    }
    self.last=now;self.active=playing;
}
@end
