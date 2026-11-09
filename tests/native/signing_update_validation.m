// Exercise the production updater's signer-continuity check, with explicit
// fixture reference paths rather than the currently installed application.
#import "../../macos/Native/FSUpdateSecurity.h"
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 3) return 2;
        BOOL valid = FSUpdateSignatureMatches([NSString stringWithUTF8String:argv[1]],
                                              [NSString stringWithUTF8String:argv[2]]);
        printf("{\"valid\":%s}\n", valid ? "true" : "false");
        return 0;
    }
}
