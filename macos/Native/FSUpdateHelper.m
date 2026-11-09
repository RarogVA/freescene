// Standalone updater. The application validates the downloaded bundle before
// invoking this process; this helper owns only the final same-volume swap.
#import <Cocoa/Cocoa.h>
#import <dirent.h>
#import <errno.h>
#import <fcntl.h>
#import <limits.h>
#import <signal.h>
#import <stdio.h>
#import <stdlib.h>
#import <sys/stat.h>
#import <unistd.h>

static NSString *const FSFixturePrefix = @"freescene-update-helper-test-";

@interface FSUpdatePaths : NSObject {
@public
    int directoryFD;
    struct stat appIdentity;
    struct stat stagedIdentity;
    struct stat parentIdentity;
}
@property(nonatomic, copy) NSString *parent;
@property(nonatomic, copy) NSString *appName;
@property(nonatomic, copy) NSString *stagedName;
@property(nonatomic, copy) NSString *backupName;
@end

@implementation FSUpdatePaths
- (instancetype)init {
    self = [super init];
    if (self) directoryFD = -1;
    return self;
}
- (void)dealloc {
    if (directoryFD >= 0) close(directoryFD);
}
@end

static BOOL FSProductionReady = NO;
static FSUpdatePaths *FSActivePaths = nil;
static void FSHandleInstallFailure(NSDictionary *result, FSUpdatePaths *paths);

static NSDictionary *FSResult(BOOL ok, NSString *code, NSString *message,
                              BOOL installed, BOOL rolledBack,
                              BOOL launched, BOOL backupRemoved) {
    return @{@"ok": @(ok), @"code": code, @"message": message,
             @"installed": @(installed), @"rolledBack": @(rolledBack),
             @"launched": @(launched), @"backupRemoved": @(backupRemoved)};
}

static int FSPrint(NSDictionary *result) {
    if (FSProductionReady) {
        // The application may have quit and closed its copy of this pipe.
        // Only the readiness handshake is written in production.
        if (![result[@"ok"] boolValue]) FSHandleInstallFailure(result, FSActivePaths);
        return [result[@"ok"] boolValue] ? 0 : 1;
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
    if (data) fwrite(data.bytes, 1, data.length, stdout);
    fputc('\n', stdout);
    return [result[@"ok"] boolValue] ? 0 : 1;
}

static NSString *FSErrnoMessage(NSString *action, int value) {
    return [NSString stringWithFormat:@"%@: %s", action, strerror(value)];
}

static BOOL FSSameIdentity(struct stat a, struct stat b) {
    return a.st_dev == b.st_dev && a.st_ino == b.st_ino;
}

static NSString *FSRealDirectory(NSString *path) {
    char resolved[PATH_MAX];
    if (!realpath(path.fileSystemRepresentation, resolved)) return nil;
    struct stat value;
    if (stat(resolved, &value) != 0 || !S_ISDIR(value.st_mode)) return nil;
    return [[NSFileManager defaultManager] stringWithFileSystemRepresentation:resolved
                                                                    length:strlen(resolved)];
}

static BOOL FSAppPathShape(NSString *path) {
    if (!path.isAbsolutePath ||
        [path.pathExtension caseInsensitiveCompare:@"app"] != NSOrderedSame) return NO;
    for (NSString *component in path.pathComponents) {
        if ([component isEqualToString:@"."] || [component isEqualToString:@".."]) return NO;
    }
    return YES;
}

static BOOL FSFixtureParent(NSString *parent) {
    if (![parent.lastPathComponent hasPrefix:FSFixturePrefix]) return NO;
    // Use the OS user-temp location rather than trusting a supplied TMPDIR.
    char temporary[PATH_MAX];
    size_t count = confstr(_CS_DARWIN_USER_TEMP_DIR, temporary, sizeof(temporary));
    NSString *userTemp = nil;
    if (count > 0 && count <= sizeof(temporary)) {
        userTemp = FSRealDirectory([NSString stringWithUTF8String:temporary]);
    }
    NSString *parentParent = parent.stringByDeletingLastPathComponent;
    return (userTemp && [parentParent isEqualToString:userTemp]) ||
           [parentParent isEqualToString:FSRealDirectory(@"/tmp")];
}

static BOOL FSStatRoot(FSUpdatePaths *paths, NSString *name, struct stat *value) {
    return fstatat(paths->directoryFD, name.fileSystemRepresentation, value,
                   AT_SYMLINK_NOFOLLOW) == 0 && S_ISDIR(value->st_mode) &&
           !S_ISLNK(value->st_mode);
}

static BOOL FSAbsentRoot(FSUpdatePaths *paths, NSString *name) {
    struct stat value;
    if (fstatat(paths->directoryFD, name.fileSystemRepresentation, &value,
                AT_SYMLINK_NOFOLLOW) == 0) return NO;
    return errno == ENOENT;
}

static FSUpdatePaths *FSValidate(NSString *app, NSString *staged, NSString *backup,
                                BOOL testMode, NSString **error) {
    if (!FSAppPathShape(app) || !FSAppPathShape(staged) || !FSAppPathShape(backup)) {
        *error = @"All three paths must be absolute .app roots without traversal components.";
        return nil;
    }
    NSString *parent = FSRealDirectory(app.stringByDeletingLastPathComponent);
    if (!parent || ![parent isEqualToString:FSRealDirectory(staged.stringByDeletingLastPathComponent)] ||
        ![parent isEqualToString:FSRealDirectory(backup.stringByDeletingLastPathComponent)]) {
        *error = @"Application, staged bundle, and backup must have the same existing parent directory.";
        return nil;
    }
    if (testMode && !FSFixtureParent(parent)) {
        *error = @"Test mode is restricted to dedicated updater fixtures in system temporary storage.";
        return nil;
    }
    FSUpdatePaths *paths = [FSUpdatePaths new];
    paths.parent = parent;
    paths.appName = app.lastPathComponent;
    paths.stagedName = staged.lastPathComponent;
    paths.backupName = backup.lastPathComponent;
    if ([paths.appName isEqualToString:paths.stagedName] ||
        [paths.appName isEqualToString:paths.backupName] ||
        [paths.stagedName isEqualToString:paths.backupName]) {
        *error = @"Application, staged bundle, and backup must be distinct roots.";
        return nil;
    }
    paths->directoryFD = open(parent.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    if (paths->directoryFD < 0 || fstat(paths->directoryFD, &paths->parentIdentity) != 0) {
        *error = FSErrnoMessage(@"Cannot open installation directory", errno);
        return nil;
    }
    if (!FSStatRoot(paths, paths.appName, &paths->appIdentity) ||
        !FSStatRoot(paths, paths.stagedName, &paths->stagedIdentity) ||
        FSSameIdentity(paths->appIdentity, paths->stagedIdentity)) {
        *error = @"Application and staged bundle must be distinct existing directories, not symlink roots.";
        return nil;
    }
    if (!FSAbsentRoot(paths, paths.backupName)) {
        *error = @"Backup root already exists or cannot be safely inspected.";
        return nil;
    }
    if (faccessat(paths->directoryFD, ".", W_OK | X_OK, 0) != 0 ||
        (paths->appIdentity.st_flags & (UF_IMMUTABLE | SF_IMMUTABLE)) != 0 ||
        (paths->stagedIdentity.st_flags & (UF_IMMUTABLE | SF_IMMUTABLE)) != 0) {
        *error = @"Installation directory or application roots do not permit the update swap.";
        return nil;
    }
    return paths;
}

static BOOL FSWaitForExit(pid_t pid, NSString **error) {
    NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime + 120;
    while (YES) {
        if (kill(pid, 0) != 0) {
            int value = errno;
            if (value == ESRCH) return YES;
            if (value != EPERM) {
                *error = FSErrnoMessage(@"Cannot inspect application process", value);
                return NO;
            }
        }
        if (NSProcessInfo.processInfo.systemUptime >= deadline) {
            *error = @"Application did not exit within 120 seconds; no bundle was changed.";
            return NO;
        }
        usleep(100000);
    }
}

static BOOL FSExpectedRoot(FSUpdatePaths *paths, NSString *name, struct stat expected) {
    struct stat current;
    return FSStatRoot(paths, name, &current) && FSSameIdentity(current, expected);
}

static BOOL FSRenameExclusive(FSUpdatePaths *paths, NSString *from, NSString *to) {
    // An exclusive same-directory rename cannot overwrite a concurrent foreign
    // entry and cannot silently fall back to a cross-volume copy.
    return renameatx_np(paths->directoryFD, from.fileSystemRepresentation,
                       paths->directoryFD, to.fileSystemRepresentation,
                       RENAME_EXCL) == 0;
}

static BOOL FSRollback(FSUpdatePaths *paths, BOOL stagedInstalled, NSString **error) {
    if (!FSExpectedRoot(paths, paths.backupName, paths->appIdentity)) {
        *error = @"Original backup identity changed; backup was preserved for recovery.";
        return NO;
    }
    if (stagedInstalled) {
        if (!FSExpectedRoot(paths, paths.appName, paths->stagedIdentity) ||
            !FSAbsentRoot(paths, paths.stagedName)) {
            *error = @"Installed or staging root changed; all remaining bundles were preserved.";
            return NO;
        }
        if (!FSRenameExclusive(paths, paths.appName, paths.stagedName)) {
            *error = FSErrnoMessage(@"Cannot return failed installation to staging", errno);
            return NO;
        }
    }
    if (!FSAbsentRoot(paths, paths.appName) ||
        !FSRenameExclusive(paths, paths.backupName, paths.appName)) {
        *error = FSErrnoMessage(@"Cannot restore original application; backup was preserved", errno);
        return NO;
    }
    return YES;
}

typedef NS_ENUM(NSInteger, FSLaunchState) {
    FSLaunchSucceeded,
    FSLaunchFailed,
    FSLaunchPending,
};
typedef void (^FSLaunchCompletion)(BOOL applicationOpened, NSError *error);
typedef void (^FSLaunchRequest)(FSLaunchCompletion completion);

static FSLaunchState FSWaitForLaunchRequest(FSLaunchRequest request,
                                            NSTimeInterval timeout,
                                            NSString **error) {
    __block BOOL complete = NO;
    __block BOOL success = NO;
    __block NSError *completionError = nil;
    request(^(BOOL applicationOpened, NSError *launchError) {
        dispatch_async(dispatch_get_main_queue(), ^{
            success = applicationOpened;
            completionError = launchError;
            complete = YES;
        });
    });
    NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime + timeout;
    while (!complete && NSProcessInfo.processInfo.systemUptime < deadline) {
        NSTimeInterval remaining = deadline - NSProcessInfo.processInfo.systemUptime;
        if (remaining > 0) {
            [NSRunLoop.currentRunLoop runUntilDate:
             [NSDate dateWithTimeIntervalSinceNow:MIN(0.05, remaining)]];
        }
    }
    if (!complete) {
        // NSWorkspace does not cancel its request when our wait expires. A late
        // success may still start this exact installed bundle. Preserve both
        // new app and backup; never restore/start the old version concurrently.
        *error = @"macOS has not yet confirmed the application launch.";
        return FSLaunchPending;
    }
    if (completionError) {
        *error = completionError.localizedDescription;
        return FSLaunchFailed;
    }
    if (!success) {
        *error = @"macOS returned no application and no definite launch error.";
        return FSLaunchPending;
    }
    return FSLaunchSucceeded;
}

static FSLaunchState FSLaunch(FSUpdatePaths *paths, NSString **error) {
    struct stat currentParent;
    if (stat(paths.parent.fileSystemRepresentation, &currentParent) != 0 ||
        !FSSameIdentity(currentParent, paths->parentIdentity)) {
        *error = @"Installation directory identity changed before launch.";
        return FSLaunchFailed;
    }
    if (!FSExpectedRoot(paths, paths.appName, paths->appIdentity) &&
        !FSExpectedRoot(paths, paths.appName, paths->stagedIdentity)) {
        *error = @"Application root identity changed before launch.";
        return FSLaunchFailed;
    }
    NSURL *url = [NSURL fileURLWithPath:[paths.parent stringByAppendingPathComponent:paths.appName]
                          isDirectory:YES];
    NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
    configuration.activates = YES;
    configuration.createsNewApplicationInstance = YES;
    return FSWaitForLaunchRequest(^(FSLaunchCompletion completion) {
        [NSWorkspace.sharedWorkspace openApplicationAtURL:url configuration:configuration
                                       completionHandler:^(NSRunningApplication *application, NSError *launchError) {
            completion(application != nil, launchError);
        }];
    }, 120, error);
}

static void FSRelaunchOriginalAfterRollback(NSDictionary *result, FSUpdatePaths *paths,
                                           void (^launchOriginal)(FSUpdatePaths *)) {
    if ([result[@"rolledBack"] boolValue] && paths &&
        FSExpectedRoot(paths, paths.appName, paths->appIdentity)) {
        launchOriginal(paths);
    }
}

static void FSHandleInstallFailure(NSDictionary *result, FSUpdatePaths *paths) {
    FSRelaunchOriginalAfterRollback(result, paths, ^(FSUpdatePaths *original) {
        NSString *ignored = nil;
        FSLaunch(original, &ignored);
    });
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    NSAlert *alert = [NSAlert new];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = @"Не удалось обновить FreeScene";
    if ([result[@"code"] isEqualToString:@"launch_pending"]) {
        alert.messageText = @"Запуск FreeScene ещё не подтверждён";
        alert.informativeText = @"macOS ещё обрабатывает запуск новой версии. Обновлённое приложение и резервная копия сохранены. Дождитесь открытия FreeScene.";
    } else if ([result[@"rolledBack"] boolValue]) {
        alert.informativeText = @"Прежняя версия восстановлена. Повторите обновление позже.";
    } else if ([result[@"code"] isEqualToString:@"rollback_failed"]) {
        alert.informativeText = @"Файлы сохранены. Резервная копия приложения находится рядом с FreeScene.app. Восстановите её перед повторной попыткой.";
    } else {
        alert.informativeText = @"Текущая версия сохранена. Закройте приложение и повторите обновление позже.";
    }
    [alert addButtonWithTitle:@"OK"];
    [NSApp activateIgnoringOtherApps:YES];
    [alert runModal];
}

static BOOL FSRemoveTreeAt(int parentFD, const char *name, struct stat expected) {
    int treeFD = openat(parentFD, name, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    if (treeFD < 0) return NO;
    struct stat opened;
    if (fstat(treeFD, &opened) != 0 || !FSSameIdentity(opened, expected)) {
        close(treeFD);
        errno = ESTALE;
        return NO;
    }
    DIR *directory = fdopendir(dup(treeFD));
    if (!directory) {
        int saved = errno;
        close(treeFD);
        errno = saved;
        return NO;
    }
    BOOL ok = YES;
    int saved = 0;
    struct dirent *entry;
    while (YES) {
        errno = 0;
        entry = readdir(directory);
        if (!entry) {
            if (errno != 0) { ok = NO; saved = errno; }
            break;
        }
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) continue;
        struct stat child;
        if (fstatat(treeFD, entry->d_name, &child, AT_SYMLINK_NOFOLLOW) != 0) {
            ok = NO; saved = errno; break;
        }
        if (S_ISDIR(child.st_mode)) {
            // Never cross into a mounted foreign volume during cleanup.
            if (child.st_dev != expected.st_dev || !FSRemoveTreeAt(treeFD, entry->d_name, child)) {
                ok = NO; saved = child.st_dev != expected.st_dev ? EXDEV : errno; break;
            }
        } else if (unlinkat(treeFD, entry->d_name, 0) != 0) {
            // Symlinks are unlinked themselves; their targets are never visited.
            ok = NO; saved = errno; break;
        }
    }
    closedir(directory);
    close(treeFD);
    if (ok) {
        struct stat current;
        if (fstatat(parentFD, name, &current, AT_SYMLINK_NOFOLLOW) != 0 ||
            !FSSameIdentity(current, expected)) {
            ok = NO; saved = ESTALE;
        } else if (unlinkat(parentFD, name, AT_REMOVEDIR) != 0) {
            ok = NO; saved = errno;
        }
    }
    if (!ok) errno = saved;
    return ok;
}

static BOOL FSRemoveBackup(FSUpdatePaths *paths, NSString **error) {
    if (!FSExpectedRoot(paths, paths.backupName, paths->appIdentity)) {
        *error = @"Backup identity changed; no cleanup was performed.";
        return NO;
    }
    BOOL removed = FSRemoveTreeAt(paths->directoryFD,
                                 paths.backupName.fileSystemRepresentation,
                                 paths->appIdentity);
    if (!removed) *error = FSErrnoMessage(@"Backup cleanup failed", errno);
    return removed;
}

static NSDictionary *FSFinalizeInstalledLaunch(FSUpdatePaths *paths,
                                               FSLaunchState state,
                                               NSString *launchError,
                                               BOOL launchRequested) {
    if (state == FSLaunchPending) {
        NSMutableDictionary *result = [FSResult(NO, @"launch_pending",
            launchError ?: @"macOS has not yet confirmed the application launch.",
            YES, NO, NO, NO) mutableCopy];
        result[@"launchState"] = @"pending";
        return result;
    }
    if (state == FSLaunchFailed) {
        NSString *reason = launchError ?: @"The updated application could not be launched.";
        NSString *rollbackError = nil;
        BOOL rollback = FSRollback(paths, YES, &rollbackError);
        return FSResult(NO, rollback ? @"launch_failed_rolled_back" : @"rollback_failed",
                        rollback ? reason : [reason stringByAppendingFormat:@" %@", rollbackError],
                        NO, rollback, NO, NO);
    }
    NSString *cleanupError = nil;
    BOOL removed = FSRemoveBackup(paths, &cleanupError);
    return FSResult(YES, removed ? @"installed" : @"installed_backup_retained",
                    removed ? @"Application installed successfully." : cleanupError,
                    YES, NO, launchRequested, removed);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        signal(SIGPIPE, SIG_IGN);
        BOOL testMode = argc > 1 && strcmp(argv[1], "--test-install") == 0;
        BOOL installMode = argc > 1 && strcmp(argv[1], "--install") == 0;
        if ((!testMode && !installMode) || (testMode ? argc != 5 : argc != 6)) {
            return FSPrint(FSResult(NO, @"usage", @"Use --install PID APP STAGED BACKUP or --test-install APP STAGED BACKUP.", NO, NO, NO, NO));
        }
        pid_t pid = 0;
        if (!testMode) {
            char *end = NULL;
            errno = 0;
            long parsed = strtol(argv[2], &end, 10);
            if (errno || argv[2][0] < '0' || argv[2][0] > '9' || end == argv[2] || *end || parsed <= 1 || parsed > INT_MAX || parsed == getpid()) {
                return FSPrint(FSResult(NO, @"invalid_pid", @"A valid application process ID is required.", NO, NO, NO, NO));
            }
            pid = (pid_t)parsed;
        }
        int start = testMode ? 2 : 3;
        NSString *error = nil;
        FSUpdatePaths *paths = FSValidate([NSString stringWithUTF8String:argv[start]],
                                         [NSString stringWithUTF8String:argv[start + 1]],
                                         [NSString stringWithUTF8String:argv[start + 2]],
                                         testMode, &error);
        if (!paths) return FSPrint(FSResult(NO, @"invalid_paths", error, NO, NO, NO, NO));
        if (!testMode) {
            // Do not let the application quit until this helper is fully
            // validated and ready to wait for its PID to disappear.
            if (fputs("{\"ready\":true}\n", stdout) < 0 || fflush(stdout) != 0) return 1;
            FSActivePaths = paths;
            FSProductionReady = YES;
        }
        if (!testMode && !FSWaitForExit(pid, &error)) {
            return FSPrint(FSResult(NO, @"wait_failed", error, NO, NO, NO, NO));
        }
        if (!FSExpectedRoot(paths, paths.appName, paths->appIdentity) ||
            !FSExpectedRoot(paths, paths.stagedName, paths->stagedIdentity) ||
            !FSAbsentRoot(paths, paths.backupName)) {
            return FSPrint(FSResult(NO, @"roots_changed", @"Installation roots changed while waiting; no bundle was changed.", NO, NO, NO, NO));
        }
        if (!FSRenameExclusive(paths, paths.appName, paths.backupName)) {
            return FSPrint(FSResult(NO, @"backup_failed", FSErrnoMessage(@"Cannot create backup", errno), NO, NO, NO, NO));
        }
        BOOL injected = testMode && getenv("FS_UPDATE_TEST_FAIL_RENAME") &&
                        strcmp(getenv("FS_UPDATE_TEST_FAIL_RENAME"), "1") == 0;
        BOOL installed = !injected && FSExpectedRoot(paths, paths.stagedName, paths->stagedIdentity) &&
                         FSRenameExclusive(paths, paths.stagedName, paths.appName);
        if (!installed) {
            NSString *reason = injected ? @"Injected staged rename failure." : FSErrnoMessage(@"Cannot install staged application", errno);
            NSString *rollbackError = nil;
            BOOL rollback = FSRollback(paths, NO, &rollbackError);
            return FSPrint(FSResult(NO, rollback ? @"install_failed_rolled_back" : @"rollback_failed",
                                    rollback ? reason : [reason stringByAppendingFormat:@" %@", rollbackError], NO, rollback, NO, NO));
        }
        FSLaunchState launch = testMode ? FSLaunchSucceeded : FSLaunch(paths, &error);
        return FSPrint(FSFinalizeInstalledLaunch(paths, launch, error, !testMode));
    }
}
