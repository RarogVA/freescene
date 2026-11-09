#import <Cocoa/Cocoa.h>
static BOOL fsEnglish=NO;
#import "../../macos/Native/FSReleaseUpdater.h"

static int checks=0;
static void check(BOOL value,const char *label){if(!value){fprintf(stderr,"FAILED: %s\n",label);exit(1);}++checks;}
int main(int argc,const char **argv){@autoreleasepool {
    if(argc==5 && !strcmp(argv[1],"--validate")) {
        NSString *reason=nil;BOOL archive=FSUpdateArchiveSafe(@(argv[2]));BOOL bundle=FSUpdateBundleValid(@(argv[3]),@(argv[4]),&reason);
        NSData *json=[NSJSONSerialization dataWithJSONObject:@{@"archiveSafe":@(archive),@"bundleValid":@(bundle),@"error":reason ?: @""} options:0 error:nil];
        puts([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String);return archive && bundle ? 0 : 1;
    }
    if(argc!=2)return 2;NSString *root=@(argv[1]);
    for(NSString *v in @[@"0.0.0",@"1.2.1",@"v10.12.13"])check(FSUpdateVersion(v)!=nil,"strict stable version accepted");
    for(NSString *v in @[@"01.2.1",@"1.2",@"1.2.1-beta.1",@"1.2.1+19",@"1.2.1\n",@"v1.2.9999999999",@"1.2.-1"])check(!FSUpdateVersion(v),"nonstable or malformed version refused");
    check(FSUpdateCompareVersions(@"1.10.0",@"1.2.9")==NSOrderedDescending,"version comparison is numeric");
    NSMutableDictionary *asset=[@{@"name":[NSString stringWithFormat:@"FreeScene-1.2.1-macos-%@.dmg",FSUpdateArchitectureName()],@"id":@123,@"url":@"https://api.github.com/repos/RarogVA/freescene/releases/assets/123",@"digest":[@"sha256:" stringByAppendingString:[@"a" stringByPaddingToLength:64 withString:@"a" startingAtIndex:0]],@"size":@1024,@"state":@"uploaded"} mutableCopy];
    NSMutableDictionary *release=[@{@"tag_name":@"v1.2.1",@"draft":@NO,@"prerelease":@NO,@"assets":@[asset]} mutableCopy];
    NSString *reason=nil;check(FSUpdateReleaseAsset(release,@"1.2.0",&reason)!=nil,"stable release asset selected");
    NSString *correctName=asset[@"name"];
    asset[@"name"]=[NSString stringWithFormat:@"FreeScene-1.2.1-macos-%@.dmg",[FSUpdateArchitectureName() isEqual:@"arm64"] ? @"x86_64" : @"arm64"];
    check(!FSUpdateReleaseAsset(release,@"1.2.0",nil),"release for the other architecture refused");asset[@"name"]=correctName;
    asset[@"name"]=[correctName.stringByDeletingPathExtension stringByAppendingPathExtension:@"zip"];
    check(!FSUpdateReleaseAsset(release,@"1.2.0",nil),"legacy ZIP is not selected as a DMG update");asset[@"name"]=correctName;
    check(!FSUpdateReleaseAsset(release,@"1.2.1",&reason) && [reason isEqual:@"up_to_date"],"equal version does not update");
    release[@"prerelease"]=@YES;check(!FSUpdateReleaseAsset(release,@"1.2.0",nil),"prerelease refused");release[@"prerelease"]=@NO;
    release[@"draft"]=@YES;check(!FSUpdateReleaseAsset(release,@"1.2.0",nil),"draft refused");release[@"draft"]=@NO;
    NSString *digest=asset[@"digest"];[asset removeObjectForKey:@"digest"];check(!FSUpdateReleaseAsset(release,@"1.2.0",nil),"missing API digest refused");asset[@"digest"]=digest;
    asset[@"url"]=@"https://evil.example/update.zip";check(!FSUpdateReleaseAsset(release,@"1.2.0",nil),"asset URL must match hardcoded repository and ID");asset[@"url"]=@"https://api.github.com/repos/RarogVA/freescene/releases/assets/123";
    release[@"assets"]=@[asset,asset];check(!FSUpdateReleaseAsset(release,@"1.2.0",nil),"duplicate update asset refused");
    check(FSUpdateHashMatches([root stringByAppendingPathComponent:@"hash.bin"],@"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),"matching SHA256 accepted");
    check(!FSUpdateHashMatches([root stringByAppendingPathComponent:@"hash.bin"],[@"0" stringByPaddingToLength:64 withString:@"0" startingAtIndex:0]),"damaged download digest refused");
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://release-assets.githubusercontent.com/asset?sig=fixture"]];[request setValue:@"Bearer fixture" forHTTPHeaderField:@"Authorization"];[request setValue:@"private=fixture" forHTTPHeaderField:@"Cookie"];
    NSURLRequest *safe=FSUpdateRedirectRequest(request,YES);check(safe && ![safe valueForHTTPHeaderField:@"Authorization"] && ![safe valueForHTTPHeaderField:@"Cookie"],"CDN redirect strips credentials");
    check(!FSUpdateRedirectRequest(request,NO),"metadata cannot redirect to asset CDN");
    for(NSString *url in @[@"https://api.github.com/user",@"http://release-assets.githubusercontent.com/x",@"https://evil.example/x",@"https://api.github.com.evil.example/user",@"https://api.github.com/repos/other/repo",@"https://user:secret@api.github.com/user",@"https://api.github.com:444/user"]){request.URL=[NSURL URLWithString:url];check(!FSUpdateRedirectRequest(request,YES),"unsafe redirect refused");}
    for(NSString *name in @[@"safe.zip",@"framework-links.zip"])check(FSUpdateArchiveSafe([root stringByAppendingPathComponent:name]),"safe ZIP and internal framework symlinks accepted");
    for(NSString *name in @[@"traversal.zip",@"absolute.zip",@"backslash.zip",@"symlink-escape.zip",@"symlink-ancestor.zip",@"duplicate-case.zip",@"special-file.zip",@"local-mismatch.zip",@"unicode-override.zip",@"damaged.zip"]){BOOL safe=FSUpdateArchiveSafe([root stringByAppendingPathComponent:name]);if(safe)fprintf(stderr,"Unsafe fixture accepted: %s\n",name.UTF8String);check(!safe,"unsafe or damaged ZIP refused before extraction");}
    check(FSUpdateBundleValid([root stringByAppendingPathComponent:@"valid.app"],@"1.2.1",&reason),"signed fixture bundle for this architecture accepted");
    check(!FSUpdateBundleValid([root stringByAppendingPathComponent:@"valid.app"],@"1.2.2",&reason),"wrong bundle version refused");
    for(NSString *name in @[@"wrong-id.app",@"bad-signature.app",@"wrong-arch.app",@"future-os.app"]){BOOL valid=FSUpdateBundleValid([root stringByAppendingPathComponent:name],@"1.2.1",&reason);if(valid)fprintf(stderr,"Invalid bundle accepted: %s\n",name.UTF8String);check(!valid,"bundle identity signature architecture or minimum OS refused");}
    check(!FSUpdateInstallLocationWritable([root stringByAppendingPathComponent:@"app-link.app"]),"symlink install root refused");
    check(FSUpdateBundlePathsSafe([root stringByAppendingPathComponent:@"valid.app"]),"real app tree accepted");
    check(!FSUpdateBundlePathsSafe([root stringByAppendingPathComponent:@"app-link.app"]),"symlink bundle root refused");
    check(FSUpdateBundlePathsSafe([root stringByAppendingPathComponent:@"internal-links.app"]),"internal framework symlink chain accepted");
    check(!FSUpdateBundlePathsSafe([root stringByAppendingPathComponent:@"escape-links.app"]),"escaping symlink refused before copying");
    check(!FSUpdateBundlePathsSafe([root stringByAppendingPathComponent:@"special-files.app"]),"special files refused before copying");
    NSString *unpacked=[root stringByAppendingPathComponent:@"dmg-extracted"];
    reason=nil;
    check(FSUpdateExtractDiskImage([root stringByAppendingPathComponent:@"valid.dmg"],unpacked,@"1.2.1",&reason),"read-only DMG validates and copies signed app");
    check(FSUpdateBundleValid([unpacked stringByAppendingPathComponent:@"FreeScene.app"],@"1.2.1",nil),"copied app retains valid signature and metadata");
    check(![NSFileManager.defaultManager fileExistsAtPath:[unpacked stringByAppendingPathComponent:@"mount"]],"successful DMG mount is detached and removed");
    check(!FSUpdateExtractDiskImage([root stringByAppendingPathComponent:@"valid.dmg"],unpacked,@"1.2.1",nil),"existing extraction directory is never overwritten");
    for(NSString *name in @[@"linked-app.dmg",@"damaged.dmg"]) {
        NSString *destination=[root stringByAppendingPathComponent:[name stringByAppendingString:@"-extracted"]];
        check(!FSUpdateExtractDiskImage([root stringByAppendingPathComponent:name],destination,@"1.2.1",nil),"unsafe or damaged DMG refused");
        check(![NSFileManager.defaultManager fileExistsAtPath:[destination stringByAppendingPathComponent:@"FreeScene.app"]],"invalid DMG never leaves staged application");
        check(![NSFileManager.defaultManager fileExistsAtPath:[destination stringByAppendingPathComponent:@"mount"]],"failed DMG mount is cleaned up");
    }
    NSString *wrongVersion=[root stringByAppendingPathComponent:@"wrong-version-extracted"];
    check(!FSUpdateExtractDiskImage([root stringByAppendingPathComponent:@"valid.dmg"],wrongVersion,@"1.2.2",nil),"DMG app version must match release metadata");
    check(![NSFileManager.defaultManager fileExistsAtPath:[wrongVersion stringByAppendingPathComponent:@"mount"]],"version rejection detaches image");
    NSString *stage=[root stringByAppendingPathComponent:@"owned-stage.app"];[NSFileManager.defaultManager createDirectoryAtPath:stage withIntermediateDirectories:NO attributes:nil error:nil];
    FSReleaseUpdater *updater=[FSReleaseUpdater new];updater.stage=stage;updater.handedOff=YES;[updater cancel];check([NSFileManager.defaultManager fileExistsAtPath:stage],"shutdown cancellation preserves staged app after helper handoff");updater.handedOff=NO;[updater cancel];check(![NSFileManager.defaultManager fileExistsAtPath:stage],"ordinary cancellation removes owned staging");
    NSUInteger stale=updater.generation;updater.phase=@"installing";[updater fail:@"helper"];[updater handleReady:@{@"ready":@YES} task:[NSTask new] generation:stale];check(!updater.handedOff && [updater.phase isEqual:@"idle"] && updater.generation!=stale,"late helper handshake after timeout cannot hand off");
    stale=updater.generation;updater.phase=@"installing";[updater cancel];[updater handleReady:@{@"ready":@YES} task:[NSTask new] generation:stale];check(!updater.handedOff && [updater.phase isEqual:@"idle"] && updater.generation!=stale,"late helper handshake after cancel cannot hand off");
    printf("{\"passed\":true,\"checks\":%d,\"realCredentialsRead\":false,\"installedApplicationChanged\":false}\n",checks);return 0;
}}
