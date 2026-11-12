#import "../../macos/Native/FSWatched.h"
int main(void) { @autoreleasepool {
    NSCAssert(NSProcessInfo.processInfo.environment[@"FREESCENE_DATA"], @"Use an isolated profile");
    FSWatchedClock *clock=[FSWatchedClock new];clock.source=@"source-a";clock.title=@"film";
    [clock sample:YES at:0];for(int i=1;i<60;i++)[clock sample:YES at:i];
    NSCAssert(FSWatchedSnapshot().count==0,@"59 seconds is not watched");
    [clock sample:NO at:59];[clock sample:NO at:1000];[clock sample:YES at:1001];
    NSCAssert(FSWatchedSnapshot().count==0,@"Pause must not count");
    [clock sample:YES at:1002];NSCAssert([FSWatchedSnapshot()[@"source-a"] isEqual:@"film"],@"60 seconds persisted");
    FSSetWatched(@"source-b",@"film",YES);FSSetWatched(@"source-a",@"film",NO);
    [clock sample:YES at:1003];NSCAssert(!FSWatchedSnapshot()[@"source-a"],@"One automatic mark per session");
    NSCAssert([FSWatchedSnapshot()[@"source-b"] isEqual:@"film"],@"Other variant remains watched");
    puts("watched threshold, pause and persistence: passed");
} return 0; }
