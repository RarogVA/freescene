// Isolated signing-Keychain administration. All paths/passwords arrive on stdin;
// never change the default Keychain, search list, partition list, or trust store.
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <CommonCrypto/CommonDigest.h>

static NSArray *FSSearchPaths(void) {
    CFArrayRef list = NULL;
    if (SecKeychainCopySearchList(&list) != errSecSuccess) return nil;
    NSMutableArray *paths = [NSMutableArray new];
    for (id object in (__bridge NSArray *)list) {
        char path[4096]; UInt32 length = sizeof(path);
        if (SecKeychainGetPath((__bridge SecKeychainRef)object, &length, path) != errSecSuccess) {
            CFRelease(list); return nil;
        }
        [paths addObject:[NSString stringWithUTF8String:path]];
    }
    CFRelease(list);
    return paths;
}

static NSString *FSDefaultPath(void) {
    SecKeychainRef keychain = NULL;
    OSStatus status = SecKeychainCopyDefault(&keychain);
    if (status == errSecNoDefaultKeychain) return @"<none>";
    if (status != errSecSuccess) return nil;
    char path[4096]; UInt32 length = sizeof(path);
    status = SecKeychainGetPath(keychain, &length, path);
    CFRelease(keychain);
    return status == errSecSuccess ? [NSString stringWithUTF8String:path] : nil;
}

int main(void) {
    @autoreleasepool {
        SecKeychainSetUserInteractionAllowed(false); // This utility process only.
        NSData *input = [NSFileHandle.fileHandleWithStandardInput readDataToEndOfFile];
        id request = input.length < 65536 ? [NSJSONSerialization JSONObjectWithData:input options:0 error:nil] : nil;
        if (![request isKindOfClass:NSDictionary.class]) return 2;
        NSString *operation = request[@"operation"];
        NSString *path = request[@"keychain"];
        NSString *password = request[@"password"];
        NSArray *searchBefore = FSSearchPaths();
        NSString *defaultBefore = FSDefaultPath();
        if (!searchBefore || !defaultBefore) return 3;
        SecKeychainRef keychain = NULL;
        OSStatus status = errSecSuccess;
        if ([operation isEqualToString:@"create"] && path.isAbsolutePath && password.length) {
            NSData *pass = [password dataUsingEncoding:NSUTF8StringEncoding];
            status = SecKeychainCreate(path.fileSystemRepresentation, (UInt32)pass.length, pass.bytes, false, NULL, &keychain);
            if (status == errSecSuccess) status = SecKeychainUnlock(keychain, (UInt32)pass.length, pass.bytes, true);
            SecTrustedApplicationRef signer = NULL;
            SecAccessRef access = NULL;
            if (status == errSecSuccess) status = SecTrustedApplicationCreateFromPath("/usr/bin/codesign", &signer);
            if (status == errSecSuccess) {
                NSArray *trusted = @[(__bridge id)signer];
                status = SecAccessCreate(CFSTR("FreeScene local release signing key"), (__bridge CFArrayRef)trusted, &access);
            }
            if (status == errSecSuccess) {
                NSString *archive = request[@"pkcs12"];
                NSData *data = archive.isAbsolutePath ? [NSData dataWithContentsOfFile:archive] : nil;
                SecExternalFormat format = kSecFormatPKCS12;
                SecExternalItemType type = kSecItemTypeAggregate;
                SecItemImportExportKeyParameters parameters = {0};
                parameters.version = SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION;
                parameters.passphrase = (__bridge CFStringRef)request[@"archivePassword"];
                parameters.accessRef = access;
                status = data ? SecItemImport((__bridge CFDataRef)data, NULL, &format, &type, 0, &parameters, keychain, NULL) : errSecParam;
            }
            if (access) CFRelease(access);
            if (signer) CFRelease(signer);
        } else if (([operation isEqualToString:@"unlock"] || [operation isEqualToString:@"check"]) && path.isAbsolutePath && password.length) {
            status = SecKeychainOpen(path.fileSystemRepresentation, &keychain);
            NSData *pass = [password dataUsingEncoding:NSUTF8StringEncoding];
            if (status == errSecSuccess) status = SecKeychainUnlock(keychain, (UInt32)pass.length, pass.bytes, true);
            if (status == errSecSuccess && [operation isEqualToString:@"check"]) {
                SecIdentitySearchRef search = NULL;
                status = SecIdentitySearchCreate(keychain, CSSM_KEYUSE_SIGN, &search);
                BOOL found = NO;
                while (status == errSecSuccess && !found) {
                    SecIdentityRef identity = NULL;
                    status = SecIdentitySearchCopyNext(search, &identity);
                    if (status != errSecSuccess) break;
                    SecCertificateRef certificate = NULL;
                    if (SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess) {
                        CFDataRef data = SecCertificateCopyData(certificate);
                        unsigned char digest[CC_SHA256_DIGEST_LENGTH];
                        CC_SHA256(CFDataGetBytePtr(data), (CC_LONG)CFDataGetLength(data), digest);
                        NSMutableString *hex = [NSMutableString new];
                        for (NSUInteger i=0; i<sizeof(digest); i++) [hex appendFormat:@"%02x", digest[i]];
                        found = [hex isEqualToString:request[@"certificateSHA256"]];
                        CFRelease(data); CFRelease(certificate);
                    }
                    CFRelease(identity);
                }
                if (search) CFRelease(search);
                status = found ? errSecSuccess : errSecItemNotFound;
            }
        } else if (![operation isEqualToString:@"state"]) {
            status = errSecParam;
        }
        NSString *actualPath = nil;
        if (keychain) {
            char value[4096]; UInt32 length = sizeof(value);
            if (SecKeychainGetPath(keychain, &length, value) == errSecSuccess) actualPath = [NSString stringWithUTF8String:value];
            CFRelease(keychain);
        }
        NSArray *searchAfter = FSSearchPaths();
        NSString *defaultAfter = FSDefaultPath();
        BOOL searchUnchanged = searchAfter && [searchBefore isEqual:searchAfter];
        BOOL defaultUnchanged = defaultAfter && [defaultBefore isEqualToString:defaultAfter];
        NSMutableDictionary *result = [@{@"status": @(status), @"searchListUnchanged": @(searchUnchanged), @"defaultUnchanged": @(defaultUnchanged)} mutableCopy];
        if (actualPath) result[@"keychain"] = actualPath;
        // Only state returns public Keychain path metadata; never secret values.
        if ([operation isEqualToString:@"state"]) { result[@"searchList"] = searchAfter ?: @[]; result[@"default"] = defaultAfter ?: @"<error>"; }
        NSData *output = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
        fwrite(output.bytes, 1, output.length, stdout); fputc('\n', stdout);
        return status == errSecSuccess && searchUnchanged && defaultUnchanged ? 0 : 1;
    }
}
