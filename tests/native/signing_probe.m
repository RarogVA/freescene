// A disposable CLI executable inside a fixture .app, never a user application.
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#ifndef PROBE_VERSION
#define PROBE_VERSION 0
#endif
int main(void) {
    @autoreleasepool {
        SecKeychainSetUserInteractionAllowed(false);
        NSData *input = [NSFileHandle.fileHandleWithStandardInput readDataToEndOfFile];
        NSDictionary *request = [NSJSONSerialization JSONObjectWithData:input options:0 error:nil];
        NSString *path = request[@"keychain"], *password = request[@"password"];
        SecKeychainRef keychain = NULL;
        OSStatus status = SecKeychainOpen(path.fileSystemRepresentation, &keychain);
        NSData *pass = [password dataUsingEncoding:NSUTF8StringEncoding];
        if (status == errSecSuccess) status = SecKeychainUnlock(keychain, (UInt32)pass.length, pass.bytes, true);
        BOOL matched = NO;
        if (status == errSecSuccess) {
            NSMutableDictionary *query = [@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
                (__bridge id)kSecAttrService:@"FreeScene.isolated-signing-regression",
                (__bridge id)kSecAttrAccount:@"fixture",
                (__bridge id)kSecUseAuthenticationUI:(__bridge id)kSecUseAuthenticationUIFail} mutableCopy];
            NSData *dummy = [@"Disposable signing regression value" dataUsingEncoding:NSUTF8StringEncoding];
            if ([request[@"operation"] isEqual:@"write"]) {
                query[(__bridge id)kSecUseKeychain] = (__bridge id)keychain;
                query[(__bridge id)kSecValueData] = dummy;
                status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
            } else {
                query[(__bridge id)kSecMatchSearchList] = @[(__bridge id)keychain];
                query[(__bridge id)kSecReturnData] = @YES;
                CFTypeRef value = NULL;
                status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &value);
                matched = status == errSecSuccess && [(__bridge NSData *)value isEqual:dummy];
                if (value) CFRelease(value);
            }
        }
        if (keychain) CFRelease(keychain);
        NSDictionary *result = @{@"status":@(status), @"matched":@(matched), @"version":@(PROBE_VERSION)};
        NSData *output = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
        fwrite(output.bytes, 1, output.length, stdout); fputc('\n', stdout);
        return 0;
    }
}
