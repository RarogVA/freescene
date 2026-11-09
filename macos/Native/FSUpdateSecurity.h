#pragma once
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <CommonCrypto/CommonDigest.h>
#include <sys/stat.h>
#include <sys/mount.h>
#include <mach/machine.h>

static NSString *const FSGitHubRepositoryAPI=@"https://api.github.com/repos/RarogVA/freescene";
static NSString *FSUpdateArchitectureName(void) {
#if defined(__x86_64__)
    return @"x86_64";
#else
    return @"arm64";
#endif
}
static cpu_type_t FSUpdateCPUType(void) {
#if defined(__x86_64__)
    return CPU_TYPE_X86_64;
#else
    return CPU_TYPE_ARM64;
#endif
}

static BOOL FSUpdateMatch(NSString *value,NSString *pattern) {
    if(![value isKindOfClass:NSString.class])return NO;
    NSTextCheckingResult *match=[[NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil] firstMatchInString:value options:0 range:NSMakeRange(0,value.length)];
    return match && NSEqualRanges(match.range,NSMakeRange(0,value.length));
}
static NSArray<NSNumber *> *FSUpdateVersion(NSString *value) {
    if(!FSUpdateMatch(value,@"^v?(0|[1-9][0-9]{0,8})\\.(0|[1-9][0-9]{0,8})\\.(0|[1-9][0-9]{0,8})$"))return nil;
    if([value hasPrefix:@"v"])value=[value substringFromIndex:1];
    NSArray *parts=[value componentsSeparatedByString:@"."];
    return @[@([parts[0] integerValue]),@([parts[1] integerValue]),@([parts[2] integerValue])];
}
static NSComparisonResult FSUpdateCompareVersions(NSString *left,NSString *right) {
    NSArray *a=FSUpdateVersion(left),*b=FSUpdateVersion(right);
    for(NSUInteger i=0;i<3;++i) { NSComparisonResult c=[a[i] compare:b[i]];if(c!=NSOrderedSame)return c; }
    return NSOrderedSame;
}
static BOOL FSUpdateURLBaseAllowed(NSURL *url) {
    return url && [url.scheme.lowercaseString isEqual:@"https"] && !url.user.length && !url.password.length && (!url.port || url.port.integerValue==443) && !url.fragment.length;
}
static BOOL FSUpdateAPIURLAllowed(NSURL *url) {
    if(!FSUpdateURLBaseAllowed(url) || ![url.host.lowercaseString isEqual:@"api.github.com"] || url.query.length)return NO;
    if([url.path isEqual:@"/repos/RarogVA/freescene"] || [url.path isEqual:@"/repos/RarogVA/freescene/releases/latest"])return YES;
    return FSUpdateMatch(url.path,@"^/repos/RarogVA/freescene/releases/assets/[1-9][0-9]{0,18}$");
}
static BOOL FSUpdateCDNURLAllowed(NSURL *url) {
    return FSUpdateURLBaseAllowed(url) && [@[@"release-assets.githubusercontent.com",@"objects.githubusercontent.com",@"github-releases.githubusercontent.com"] containsObject:url.host.lowercaseString];
}
static NSURLRequest *FSUpdateRedirectRequest(NSURLRequest *request,BOOL downloading) {
    BOOL api=FSUpdateAPIURLAllowed(request.URL);
    if(!api && !(downloading && FSUpdateCDNURLAllowed(request.URL)))return nil;
    NSMutableURLRequest *safe=[request mutableCopy];
    if(!api)[safe setValue:nil forHTTPHeaderField:@"Authorization"];
    [safe setValue:nil forHTTPHeaderField:@"Cookie"];
    [safe setValue:nil forHTTPHeaderField:@"Referer"];
    return safe;
}
static NSDictionary *FSUpdateReleaseAsset(id raw,NSString *installed,NSString **error) {
    if(!FSUpdateVersion(installed)){if(error)*error=@"installed_version";return nil;}
    if(![raw isKindOfClass:NSDictionary.class] || ![raw[@"draft"] isKindOfClass:NSNumber.class] || ![raw[@"prerelease"] isKindOfClass:NSNumber.class] || [raw[@"draft"] boolValue] || [raw[@"prerelease"] boolValue]){if(error)*error=@"release";return nil;}
    NSString *tag=raw[@"tag_name"];
    if(!FSUpdateVersion(tag)){if(error)*error=@"release_version";return nil;}
    if(FSUpdateCompareVersions(tag,installed)!=NSOrderedDescending){if(error)*error=@"up_to_date";return nil;}
    NSString *version=[tag hasPrefix:@"v"] ? [tag substringFromIndex:1] : tag;
    NSString *name=[NSString stringWithFormat:@"FreeScene-%@-macos-%@.dmg",version,FSUpdateArchitectureName()];
    if(![raw[@"assets"] isKindOfClass:NSArray.class]){if(error)*error=@"asset";return nil;}
    NSDictionary *found=nil;
    for(id item in raw[@"assets"])if([item isKindOfClass:NSDictionary.class] && [item[@"name"] isEqual:name]) {
        if(found){if(error)*error=@"asset";return nil;}
        found=item;
    }
    NSString *digest=found[@"digest"];
    NSNumber *assetID=found[@"id"],*size=found[@"size"];
    NSString *identifier=[assetID isKindOfClass:NSNumber.class] ? assetID.stringValue : @"";
    NSString *url=[NSString stringWithFormat:@"%@/releases/assets/%@",FSGitHubRepositoryAPI,identifier];
    if(!found || !FSUpdateMatch(identifier,@"^[1-9][0-9]{0,18}$") || ![size isKindOfClass:NSNumber.class] || size.longLongValue<=0 || size.longLongValue>512LL*1024*1024 || ![found[@"state"] isEqual:@"uploaded"] || !FSUpdateMatch(digest,@"^sha256:[0-9a-f]{64}$") || ![found[@"url"] isEqual:url]){if(error)*error=@"asset";return nil;}
    return @{@"version":version,@"url":url,@"digest":[digest substringFromIndex:7],@"size":size};
}
static BOOL FSUpdateHashMatches(NSString *file,NSString *expected) {
    if(!FSUpdateMatch(expected,@"^[0-9a-f]{64}$"))return NO;
    NSInputStream *stream=[NSInputStream inputStreamWithFileAtPath:file];[stream open];
    CC_SHA256_CTX hash;CC_SHA256_Init(&hash);uint8_t bytes[65536];NSInteger count;
    while((count=[stream read:bytes maxLength:sizeof(bytes)])>0)CC_SHA256_Update(&hash,bytes,(CC_LONG)count);
    BOOL valid=count==0;[stream close];if(!valid)return NO;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256_Final(digest,&hash);
    NSMutableString *actual=[NSMutableString new];for(NSUInteger i=0;i<sizeof(digest);++i)[actual appendFormat:@"%02x",digest[i]];
    return [actual isEqual:expected];
}
static uint16_t FSZip16(const uint8_t *p){return p[0]|((uint16_t)p[1]<<8);}
static uint32_t FSZip32(const uint8_t *p){return FSZip16(p)|((uint32_t)FSZip16(p+2)<<16);}
static BOOL FSUpdateZipExtrasSafe(const uint8_t *data,NSUInteger length) {
    NSUInteger offset=0;
    while(offset<length) {
        if(offset+4>length)return NO;
        uint16_t tag=FSZip16(data+offset),size=FSZip16(data+offset+2);
        // Only timestamp/owner records emitted by ordinary ZIP tools. Alternate
        // Unicode paths, ASi Unix links, ZIP64 and unknown extraction overrides
        // must not disagree with the filenames and types checked below.
        if(tag!=0x5455 && tag!=0x5855 && tag!=0x7875 && tag!=0x000a)return NO;
        offset+=4;if(offset+size>length)return NO;offset+=size;
    }
    return offset==length;
}
static NSString *FSUpdateArchivePath(NSString *path) {
    if(![path isKindOfClass:NSString.class] || !path.length || path.length>2048 || [path hasPrefix:@"/"] || [path rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location!=NSNotFound || [path rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"\\:*?[]"]].location!=NSNotFound)return nil;
    NSString *trimmed=[path hasSuffix:@"/"] ? [path substringToIndex:path.length-1] : path;
    NSArray *parts=[trimmed componentsSeparatedByString:@"/"];
    if(![@[@"FreeScene.app",@"__MACOSX"] containsObject:parts.firstObject])return nil;
    for(NSString *part in parts)if(!part.length || [@[@".",@".."] containsObject:part])return nil;
    return trimmed;
}
static BOOL FSUpdateArchiveLinkAllowed(NSString *path,NSString *target) {
    if(!target.length || target.length>4096 || [target hasPrefix:@"/"] || [target containsString:@"\\"] || [target rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound)return NO;
    NSMutableArray *parts=[[[path stringByDeletingLastPathComponent] componentsSeparatedByString:@"/"] mutableCopy];
    for(NSString *part in [target componentsSeparatedByString:@"/"]) {
        if(!part.length || [part isEqual:@"."])continue;
        if([part isEqual:@".."]) {if(parts.count<=1)return NO;[parts removeLastObject];}
        else [parts addObject:part];
    }
    return [parts.firstObject isEqual:@"FreeScene.app"];
}
// Validate both ZIP directory records and local headers before ditto writes any
// file. Framework symlinks are allowed only inside the app; no archive entry may
// have a symlink ancestor. ZIP64, encrypted entries and special files are refused.
static BOOL FSUpdateArchiveSafe(NSString *file) {
    NSData *data=[NSData dataWithContentsOfFile:file options:NSDataReadingMappedIfSafe error:nil];
    if(data.length<22 || data.length>512ULL*1024*1024)return NO;
    const uint8_t *p=(const uint8_t *)data.bytes;NSUInteger end=NSNotFound;
    NSUInteger begin=data.length>65557 ? data.length-65557 : 0;
    for(NSUInteger i=data.length-22;;--i) {
        if(FSZip32(p+i)==0x06054b50 && i+22+FSZip16(p+i+20)==data.length){end=i;break;}
        if(i==begin)break;
    }
    if(end==NSNotFound || FSZip16(p+end+4) || FSZip16(p+end+6))return NO;
    NSUInteger count=FSZip16(p+end+10),offset=FSZip32(p+end+16),length=FSZip32(p+end+12);
    if(!count || count>10000 || count!=FSZip16(p+end+8) || offset>data.length || length>end || offset+length!=end)return NO;
    NSMutableSet *names=[NSMutableSet new],*links=[NSMutableSet new];NSMutableArray *paths=[NSMutableArray new];
    unsigned long long expanded=0;
    for(NSUInteger i=0;i<count;++i) {
        if(offset+46>end || FSZip32(p+offset)!=0x02014b50)return NO;
        const uint8_t *h=p+offset;NSUInteger n=FSZip16(h+28),extra=FSZip16(h+30),comment=FSZip16(h+32);
        NSUInteger compressed=FSZip32(h+20),size=FSZip32(h+24),local=FSZip32(h+42);
        if(offset+46+n+extra+comment>end || !n || (FSZip16(h+8)&0x41) || (FSZip16(h+10)!=0 && FSZip16(h+10)!=8) || FSZip16(h+34) || compressed==UINT32_MAX || size==UINT32_MAX || local==UINT32_MAX || size>512ULL*1024*1024 || !FSUpdateZipExtrasSafe(h+46+n,extra))return NO;
        NSData *nameData=[NSData dataWithBytes:h+46 length:n];NSString *name=[[NSString alloc] initWithData:nameData encoding:NSUTF8StringEncoding];NSString *path=FSUpdateArchivePath(name);
        NSString *key=[[path precomposedStringWithCanonicalMapping] lowercaseString];
        if(!path || [names containsObject:key])return NO;[names addObject:key];[paths addObject:path];
        if(local+30>FSZip32(p+end+16) || FSZip32(p+local)!=0x04034b50 || FSZip16(p+local+6)!=FSZip16(h+8) || FSZip16(p+local+8)!=FSZip16(h+10) || FSZip16(p+local+26)!=n)return NO;
        NSUInteger start=local+30+n+FSZip16(p+local+28);
        if(start>FSZip32(p+end+16) || compressed>FSZip32(p+end+16)-start || memcmp(p+local+30,h+46,n))return NO;
        if(!FSUpdateZipExtrasSafe(p+local+30+n,FSZip16(p+local+28)))return NO;
        expanded+=size;if(expanded>2ULL*1024*1024*1024)return NO;
        mode_t mode=(FSZip32(h+38)>>16)&S_IFMT;
        if(mode && mode!=S_IFREG && mode!=S_IFDIR && mode!=S_IFLNK)return NO;
        if(mode==S_IFLNK) {
            if(![path hasPrefix:@"FreeScene.app/"] || size>4096)return NO;
            NSTask *task=[NSTask new];task.executableURL=[NSURL fileURLWithPath:@"/usr/bin/unzip"];task.arguments=@[@"-p",file,name];
            NSPipe *pipe=[NSPipe pipe];task.standardOutput=pipe;task.standardError=NSFileHandle.fileHandleWithNullDevice;
            if(![task launchAndReturnError:nil])return NO;
            NSData *value=[pipe.fileHandleForReading readDataOfLength:4097];
            if(value.length>4096){[task terminate];[task waitUntilExit];return NO;}[task waitUntilExit];
            NSString *target=[[NSString alloc] initWithData:value encoding:NSUTF8StringEncoding];
            if(task.terminationStatus || !FSUpdateArchiveLinkAllowed(path,target))return NO;
            [links addObject:[[path precomposedStringWithCanonicalMapping] lowercaseString]];
        }
        offset+=46+n+extra+comment;
    }
    if(offset!=end)return NO;
    for(NSString *path in paths) {
        NSString *parent=path;
        while((parent=[parent stringByDeletingLastPathComponent]).length)
            if([links containsObject:[[parent precomposedStringWithCanonicalMapping] lowercaseString]])return NO;
    }
    return YES;
}
static BOOL FSUpdateRun(NSString *command,NSArray<NSString *> *arguments,NSString **output) {
    NSTask *task=[NSTask new];task.executableURL=[NSURL fileURLWithPath:command];task.arguments=arguments;
    NSPipe *pipe=[NSPipe pipe];task.standardOutput=output ? pipe : NSFileHandle.fileHandleWithNullDevice;task.standardError=NSFileHandle.fileHandleWithNullDevice;
    if(![task launchAndReturnError:nil])return NO;
    NSData *data=output ? [pipe.fileHandleForReading readDataToEndOfFile] : nil;[task waitUntilExit];
    if(output)*output=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    return task.terminationStatus==0;
}
// A certificate-signed release must keep the installed app's designated
// identity. Legacy ad-hoc releases have only a per-build cdhash, so allow the
// one-way migration from those releases to the first stable identity.
static BOOL FSUpdateSignatureMatches(NSString *bundle,NSString *referencePath) {
    SecStaticCodeRef candidate=NULL,referenceStatic=NULL;
    SecCodeRef reference=NULL;
    SecRequirementRef ownRequirement=NULL,installedRequirement=NULL;
    CFDictionaryRef signing=NULL;
    BOOL valid=NO;
    @try {
        if(SecStaticCodeCreateWithPath((__bridge CFURLRef)[NSURL fileURLWithPath:bundle],kSecCSDefaultFlags,&candidate)!=errSecSuccess)return NO;
        if(SecCodeCopyDesignatedRequirement((SecCodeRef)candidate,kSecCSDefaultFlags,&ownRequirement)!=errSecSuccess ||
           SecStaticCodeCheckValidity(candidate,kSecCSStrictValidate|kSecCSCheckAllArchitectures,ownRequirement)!=errSecSuccess)return NO;
        if(referencePath) {
            if(SecStaticCodeCreateWithPath((__bridge CFURLRef)[NSURL fileURLWithPath:referencePath],kSecCSDefaultFlags,&referenceStatic)!=errSecSuccess)return NO;
            reference=(SecCodeRef)referenceStatic;
        } else if(SecCodeCopySelf(kSecCSDefaultFlags,&reference)!=errSecSuccess)return NO;
        if(SecCodeCopySigningInformation(reference,kSecCSSigningInformation,&signing)!=errSecSuccess)return NO;
        NSDictionary *info=(__bridge NSDictionary *)signing;
        NSArray *certificates=info[(__bridge id)kSecCodeInfoCertificates];
        if(!certificates.count) {
            valid=([info[(__bridge id)kSecCodeInfoFlags] unsignedIntValue]&kSecCodeSignatureAdhoc)!=0;
        } else if(SecCodeCopyDesignatedRequirement(reference,kSecCSDefaultFlags,&installedRequirement)==errSecSuccess) {
            valid=SecStaticCodeCheckValidity(candidate,kSecCSStrictValidate|kSecCSCheckAllArchitectures,installedRequirement)==errSecSuccess;
        }
    } @finally {
        if(signing)CFRelease(signing);
        if(ownRequirement)CFRelease(ownRequirement);
        if(installedRequirement)CFRelease(installedRequirement);
        if(referenceStatic)CFRelease(referenceStatic);
        else if(reference)CFRelease(reference);
        if(candidate)CFRelease(candidate);
    }
    return valid;
}
static BOOL FSUpdateBundleValid(NSString *bundle,NSString *version,NSString **error) {
    NSDictionary *info=[NSDictionary dictionaryWithContentsOfFile:[bundle stringByAppendingPathComponent:@"Contents/Info.plist"]];
    if(![info[@"CFBundleIdentifier"] isEqual:@"local.freescene.freescene"] || !FSUpdateVersion(version) || ![info[@"CFBundleShortVersionString"] isEqual:version] || !FSUpdateMatch(info[@"CFBundleExecutable"],@"^[A-Za-z0-9_-]{1,128}$")){if(error)*error=@"bundle";return NO;}
    NSArray *arches=[NSBundle bundleWithPath:bundle].executableArchitectures;
    if(arches.count!=1 || [arches.firstObject integerValue]!=FSUpdateCPUType()){if(error)*error=@"architecture";return NO;}
    NSString *minimum=info[@"LSMinimumSystemVersion"];
    if(!FSUpdateMatch(minimum,@"^(0|[1-9][0-9]{0,3})\\.(0|[1-9][0-9]{0,3})(\\.(0|[1-9][0-9]{0,3}))?$")){if(error)*error=@"minimum_os";return NO;}
    NSArray *components=[minimum componentsSeparatedByString:@"."];
    NSOperatingSystemVersion needed={[components[0] integerValue],[components[1] integerValue],components.count==3 ? [components[2] integerValue] : 0};
    if(![NSProcessInfo.processInfo isOperatingSystemAtLeastVersion:needed]){if(error)*error=@"minimum_os";return NO;}
    if(!FSUpdateRun(@"/usr/bin/codesign",@[@"--verify",@"--deep",@"--strict",bundle],nil) || !FSUpdateSignatureMatches(bundle,nil)){if(error)*error=@"signature";return NO;}
    return YES;
}
static BOOL FSUpdateBundlePathsSafe(NSString *bundle) {
    struct stat st;
    if(lstat(bundle.fileSystemRepresentation,&st) || !S_ISDIR(st.st_mode))return NO;
    NSString *root=bundle.stringByResolvingSymlinksInPath;
    NSString *prefix=[root stringByAppendingString:@"/"];
    __block BOOL valid=YES;
    NSDirectoryEnumerator *files=[NSFileManager.defaultManager enumeratorAtURL:[NSURL fileURLWithPath:bundle]
        includingPropertiesForKeys:nil options:0 errorHandler:^BOOL(NSURL *url,NSError *error){valid=NO;return NO;}];
    if(!files)return NO;
    NSUInteger count=0;unsigned long long bytes=0;
    for(NSURL *url in files) {
        if(++count>100000 || lstat(url.fileSystemRepresentation,&st))return NO;
        if(S_ISLNK(st.st_mode)) {
            NSString *target=[NSFileManager.defaultManager destinationOfSymbolicLinkAtPath:url.path error:nil];
            NSString *resolved=url.path.stringByResolvingSymlinksInPath;
            if(!target.length || target.isAbsolutePath ||
                !([resolved isEqual:root] || [resolved hasPrefix:prefix]) ||
                stat(url.fileSystemRepresentation,&st))return NO;
        } else if(S_ISREG(st.st_mode)) {
            if(st.st_size<0 || (bytes+=(unsigned long long)st.st_size)>2ULL*1024*1024*1024)return NO;
        } else if(!S_ISDIR(st.st_mode))return NO;
    }
    return valid;
}

// Called only after the GitHub asset's SHA-256 has been verified. Mount in an
// isolated directory, copy just the signed app, then detach before installation.
static BOOL FSUpdateExtractDiskImage(NSString *image,NSString *destination,NSString *version,NSString **error) {
    NSFileManager *fm=NSFileManager.defaultManager;
    if(!FSUpdateRun(@"/usr/bin/hdiutil",@[@"verify",image],nil))return NO;
    if(![fm createDirectoryAtPath:destination withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:nil])return NO;
    NSString *mount=[destination.stringByResolvingSymlinksInPath stringByAppendingPathComponent:@"mount"];
    if(![fm createDirectoryAtPath:mount withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:nil])return NO;
    BOOL attached=NO,valid=NO;
    @try {
        do {
            NSString *output=nil;
            attached=FSUpdateRun(@"/usr/bin/hdiutil",@[@"attach",@"-readonly",@"-nobrowse",@"-noautoopen",@"-plist",@"-mountpoint",mount,image],&output);
            if(!attached)break;
            id info=[NSPropertyListSerialization propertyListWithData:[output dataUsingEncoding:NSUTF8StringEncoding]
                options:NSPropertyListImmutable format:nil error:nil];
            if(![info isKindOfClass:NSDictionary.class] || ![info[@"system-entities"] isKindOfClass:NSArray.class])break;
            NSUInteger mounts=0;
            for(id entity in info[@"system-entities"]) {
                if(![entity isKindOfClass:NSDictionary.class])continue;
                if(entity[@"mount-point"]) {
                    NSString *reported=entity[@"mount-point"];
                    if(![reported isKindOfClass:NSString.class] ||
                       ![reported.stringByResolvingSymlinksInPath isEqual:mount.stringByResolvingSymlinksInPath]){mounts=NSUIntegerMax;break;}
                    ++mounts;
                }
            }
            struct statfs volume;
            if(mounts!=1 || statfs(mount.fileSystemRepresentation,&volume) || !(volume.f_flags&MNT_RDONLY))break;
            NSString *source=[mount stringByAppendingPathComponent:@"FreeScene.app"];
            if(!FSUpdateBundlePathsSafe(source))break;
            if(!FSUpdateBundleValid(source,version,error))break;
            NSString *app=[destination stringByAppendingPathComponent:@"FreeScene.app"];
            if(![fm copyItemAtPath:source toPath:app error:nil])break;
            valid=FSUpdateBundlePathsSafe(app) && FSUpdateBundleValid(app,version,error);
        } while(NO);
    } @finally {
        struct stat mountStat,parentStat;
        BOOL mounted=!lstat(mount.fileSystemRepresentation,&mountStat) &&
            !lstat(destination.fileSystemRepresentation,&parentStat) && mountStat.st_dev!=parentStat.st_dev;
        if(attached || mounted) {
            if(!FSUpdateRun(@"/usr/bin/hdiutil",@[@"detach",mount],nil)) {
                valid=NO;
                FSUpdateRun(@"/usr/bin/hdiutil",@[@"detach",@"-force",mount],nil);
            }
        }
        [fm removeItemAtPath:mount error:nil];
        if(!valid)[fm removeItemAtPath:[destination stringByAppendingPathComponent:@"FreeScene.app"] error:nil];
    }
    return valid;
}

static BOOL FSUpdateInstallLocationWritable(NSString *app) {
    struct stat current,parent;
    NSString *directory=app.stringByDeletingLastPathComponent;
    if(![app isAbsolutePath] || ![app.pathExtension isEqual:@"app"] || lstat(app.fileSystemRepresentation,&current) || !S_ISDIR(current.st_mode) || lstat(directory.fileSystemRepresentation,&parent) || !S_ISDIR(parent.st_mode))return NO;
    NSNumber *readOnly=nil;[[NSURL fileURLWithPath:app] getResourceValue:&readOnly forKey:NSURLVolumeIsReadOnlyKey error:nil];
    return !readOnly.boolValue && [NSFileManager.defaultManager isWritableFileAtPath:app] && [NSFileManager.defaultManager isWritableFileAtPath:directory];
}
