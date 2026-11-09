// Drive the real launch wait/outcome/recovery code with a controlled asynchronous
// completion. Real bundle renames occur only inside dedicated temp fixtures;
// neither NSWorkspace nor a real application is started by this harness.
#define main FSUpdateHelperEntryPoint
#import "../../macos/Native/FSUpdateHelper.m"
#undef main

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 5) return 2;
        NSString *mode = [NSString stringWithUTF8String:argv[1]];
        NSString *error = nil;
        FSUpdatePaths *paths = FSValidate([NSString stringWithUTF8String:argv[2]],
                                         [NSString stringWithUTF8String:argv[3]],
                                         [NSString stringWithUTF8String:argv[4]],
                                         YES, &error);
        if (!paths) return FSPrint(FSResult(NO, @"invalid_paths", error, NO, NO, NO, NO));
        if (!FSRenameExclusive(paths, paths.appName, paths.backupName) ||
            !FSRenameExclusive(paths, paths.stagedName, paths.appName)) return 3;
        __block NSInteger launchRequests = 0;
        __block NSInteger oldRelaunchRequests = 0;
        __block BOOL lateCompletionObserved = NO;
        FSLaunchState launch = FSWaitForLaunchRequest(^(FSLaunchCompletion completion) {
            launchRequests++;
            if ([mode isEqualToString:@"pending"]) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC),
                               dispatch_get_main_queue(), ^{
                    lateCompletionObserved = YES;
                    completion(YES, nil);
                });
            } else if ([mode isEqualToString:@"failed"]) {
                completion(NO, [NSError errorWithDomain:@"FreeSceneUpdaterFixture" code:1
                                               userInfo:@{NSLocalizedDescriptionKey: @"Definite fixture launch failure."}]);
            } else if ([mode isEqualToString:@"unknown-completion"]) {
                completion(NO, nil);
            } else {
                completion(YES, nil);
            }
        }, 0.02, &error);
        NSMutableDictionary *result = [FSFinalizeInstalledLaunch(paths, launch, error, YES) mutableCopy];
        FSRelaunchOriginalAfterRollback(result, paths, ^(FSUpdatePaths *original) {
            (void)original;
            oldRelaunchRequests++;
        });
        // Let the timed-out request complete, exactly as NSWorkspace may do.
        // Its late callback must not trigger rollback, cleanup or another open.
        NSTimeInterval until = NSProcessInfo.processInfo.systemUptime + 0.2;
        while (NSProcessInfo.processInfo.systemUptime < until) {
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        }
        result[@"launchRequests"] = @(launchRequests);
        result[@"oldRelaunchRequests"] = @(oldRelaunchRequests);
        result[@"lateCompletionObserved"] = @(lateCompletionObserved);
        return FSPrint(result);
    }
}
