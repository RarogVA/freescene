// Exercise the production rollback after the staged bundle already occupies the
// application path, without starting an application or waiting for a PID.
#define main FSUpdateHelperEntryPoint
#import "../../macos/Native/FSUpdateHelper.m"
#undef main

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 4) return 2;
        NSString *error = nil;
        FSUpdatePaths *paths = FSValidate([NSString stringWithUTF8String:argv[1]],
                                         [NSString stringWithUTF8String:argv[2]],
                                         [NSString stringWithUTF8String:argv[3]],
                                         YES, &error);
        if (!paths) return FSPrint(FSResult(NO, @"invalid_paths", error, NO, NO, NO, NO));
        if (!FSRenameExclusive(paths, paths.appName, paths.backupName) ||
            !FSRenameExclusive(paths, paths.stagedName, paths.appName)) return 3;
        BOOL rollback = FSRollback(paths, YES, &error);
        return FSPrint(FSResult(rollback, @"post_swap_rollback", error ?: @"Restored original app and returned update to staging.",
                               NO, rollback, NO, NO));
    }
}
