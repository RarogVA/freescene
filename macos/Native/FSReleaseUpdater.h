#pragma once
#import "FSGitHub.h"
#import <Cocoa/Cocoa.h>
#include <unistd.h>

@interface FSReleaseUpdater : NSObject
@property FSGitHubHTTP *client;
@property NSString *phase;
@property NSString *message;
@property NSString *failure;
@property NSDictionary *asset;
@property NSURL *work;
@property NSString *stage;
@property NSString *backup;
@property NSTask *helper;
@property NSUInteger generation;
@property BOOL handedOff;
@property BOOL installAfterDownload;
@property BOOL startupAttempted, startupChecking;
@property BOOL startupOfferStarted, startupOfferPending;
@property NSUInteger startupOfferAttempts;
@property (copy) FSGitHubHTTP *(^makeHTTP)(void);
@property (copy) NSString *(^installedVersion)(void);
@property (copy) void (^scheduleStartupOffer)(NSTimeInterval delay,dispatch_block_t work);
@property (copy) void (^changed)(void);
- (void)activate;
- (void)cancel;
- (void)checkAtStartup:(void (^)(NSDictionary *asset))offer;
- (void)cancelStartupCheck;
- (void)offerAtStartupWhenEligible:(void (^)(void (^reply)(BOOL)))eligibility offer:(void (^)(void))offer;
- (void)handleReady:(id)reply task:(NSTask *)task generation:(NSUInteger)generation;
@end
@implementation FSReleaseUpdater
- (instancetype)init {if((self=[super init])) {
    self.phase=@"idle";
    self.makeHTTP=^{return [FSGitHubHTTP new];};
    self.installedVersion=^{return [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];};
    self.scheduleStartupOffer=^(NSTimeInterval delay,dispatch_block_t work){dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay*NSEC_PER_SEC)),dispatch_get_main_queue(),work);};
}return self;}
- (NSString *)label:(NSString *)ru english:(NSString *)en{return fsEnglish ? en : ru;}
- (void)publish:(NSString *)phase message:(NSString *)message {self.phase=phase;self.message=message;if(self.changed)self.changed();}
- (void)fail:(NSString *)error {
    if(self.handedOff)return;
    self.failure=error;self.installAfterDownload=NO;
    self.startupChecking=self.startupOfferPending=NO;
    ++self.generation;FSGitHubHTTP *client=self.client;self.client=nil;[client cancel];
    if(self.helper.running)[self.helper terminate];self.helper=nil;self.asset=nil;
    NSDictionary *ru=@{@"auth":@"Выпуски FreeScene сейчас недоступны. Повторите позже.",@"repo_access":@"Выпуски FreeScene сейчас недоступны. Повторите позже.",@"hash":@"Контрольная сумма обновления не совпала. Файлы приложения не изменены.",@"archive":@"Образ обновления повреждён или содержит небезопасные файлы.",@"signature":@"Подпись обновления не прошла проверку.",@"architecture":@"Обновление не подходит для архитектуры этого Mac.",@"minimum_os":@"Обновление требует более новой версии macOS.",@"location":@"Переместите FreeScene в «Программы» или другую папку с правом записи и повторите.",@"helper":@"Не удалось запустить установщик. Текущее приложение не изменено.",@"up_to_date":@"Более новая версия не опубликована."};
    NSDictionary *en=@{@"auth":@"FreeScene releases are currently unavailable. Please try again later.",@"repo_access":@"FreeScene releases are currently unavailable. Please try again later.",@"hash":@"Update checksum mismatch. The application was not changed.",@"archive":@"The update disk image is damaged or contains unsafe files.",@"signature":@"Update signature verification failed.",@"architecture":@"This update does not match this Mac’s architecture.",@"minimum_os":@"This update requires a newer macOS version.",@"location":@"Move FreeScene to Applications or another writable folder and try again.",@"helper":@"Could not start the installer. The current application was not changed.",@"up_to_date":@"No newer version is published."};
    [self cleanup];[self publish:@"idle" message:(fsEnglish ? en : ru)[error] ?: [self label:@"Не удалось получить или проверить обновление. Повторите попытку." english:@"Could not download or verify the update. Please try again."]];
}
- (void)cleanup {
    if(self.handedOff)return;
    if(self.stage)[NSFileManager.defaultManager removeItemAtPath:self.stage error:nil];self.stage=nil;
    if(self.work)[NSFileManager.defaultManager removeItemAtURL:self.work error:nil];self.work=nil;
}
- (void)cancel {
    self.failure=nil;self.installAfterDownload=NO;
    self.startupAttempted=YES;self.startupChecking=self.startupOfferPending=NO;
    if(self.handedOff)return;
    ++self.generation;FSGitHubHTTP *client=self.client;self.client=nil;[client cancel];
    if(self.helper.running)[self.helper terminate];self.helper=nil;
    [self cleanup];self.asset=nil;[self publish:@"idle" message:@""];
}
- (void)cancelStartupCheck {
    // A manual operation also suppresses a startup check that was scheduled but
    // has not started yet. Startup is attempted at most once in this process.
    self.startupAttempted=YES;
    if(!self.startupChecking && !self.startupOfferPending)return;
    self.startupChecking=self.startupOfferPending=NO;++self.generation;
    FSGitHubHTTP *client=self.client;self.client=nil;[client cancel];
}
- (void)checkAtStartup:(void (^)(NSDictionary *))offer {
    if(self.startupAttempted)return;self.startupAttempted=YES;
    if(self.handedOff || ![self.phase isEqual:@"idle"])return;
    self.startupChecking=YES;NSUInteger generation=++self.generation;
        self.client=self.makeHTTP();
        [self.client get:[NSURL URLWithString:[FSGitHubRepositoryAPI stringByAppendingString:@"/releases/latest"]] downloadTo:nil size:0 completion:^(NSData *data,NSString *failure){
            if(!self.startupChecking || generation!=self.generation)return;
            self.startupChecking=NO;self.client=nil;
            if(failure)return;
            id release=data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            NSDictionary *asset=FSUpdateReleaseAsset(release,self.installedVersion(),nil);
            if(!asset)return;
            self.asset=asset;
            [self publish:@"available" message:[NSString stringWithFormat:[self label:@"Доступна версия %@. Нажмите «Установить обновления»." english:@"Version %@ is available. Choose Install updates."],asset[@"version"]]];
            // The presenter rechecks window/modal state and generation before
            // showing an offer. This never downloads or installs the asset.
            if(generation==self.generation && [self.phase isEqual:@"available"] && offer)offer(asset);
        }];
}
- (void)tryStartupOffer:(NSUInteger)generation eligibility:(void (^)(void (^reply)(BOOL)))eligibility offer:(void (^)(void))offer {
    if(generation!=self.generation || !self.startupOfferPending || ![self.phase isEqual:@"available"])return;
    ++self.startupOfferAttempts;__block BOOL replied=NO;
    eligibility(^(BOOL allowed) {
        if(replied)return;replied=YES;
        if(generation!=self.generation || !self.startupOfferPending || ![self.phase isEqual:@"available"])return;
        if(allowed){self.startupOfferPending=NO;if(offer)offer();return;}
        if(self.startupOfferAttempts>=31){self.startupOfferPending=NO;return;}
        self.scheduleStartupOffer(2,^{[self tryStartupOffer:generation eligibility:eligibility offer:offer];});
    });
}
- (void)offerAtStartupWhenEligible:(void (^)(void (^reply)(BOOL)))eligibility offer:(void (^)(void))offer {
    if(self.startupOfferStarted || !eligibility || ![self.phase isEqual:@"available"] || !self.asset)return;
    self.startupOfferStarted=self.startupOfferPending=YES;self.startupOfferAttempts=0;
    NSUInteger generation=self.generation;
    // Expire even if Flutter never replies. Neither retries nor delayed replies
    // can offer a different/manual operation's asset or repeat a network lookup.
    self.scheduleStartupOffer(60,^{if(generation==self.generation)self.startupOfferPending=NO;});
    [self tryStartupOffer:generation eligibility:eligibility offer:offer];
}
- (void)activate {
    self.failure=nil;
    [self cancelStartupCheck];
    if([self.phase isEqual:@"available"]){self.installAfterDownload=YES;[self download];return;}
    if([self.phase isEqual:@"ready"]){[self install];return;}
    if(![self.phase isEqual:@"idle"])return;
    NSUInteger generation=++self.generation;
    [self publish:@"checking" message:[self label:@"Проверяю выпуски…" english:@"Checking releases…"]];
        self.client=self.makeHTTP();
        [self.client get:[NSURL URLWithString:[FSGitHubRepositoryAPI stringByAppendingString:@"/releases/latest"]] downloadTo:nil size:0 completion:^(NSData *data,NSString *error){
            if(generation!=self.generation)return;self.client=nil;
            if(error){[self fail:error];return;}
            id release=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];NSString *reason=nil;
            self.asset=FSUpdateReleaseAsset(release,self.installedVersion(),&reason);
            if(!self.asset){[self fail:reason];return;}
            [self publish:@"available" message:[NSString stringWithFormat:[self label:@"Доступна версия %@. Нажмите «Установить обновления»." english:@"Version %@ is available. Choose Install updates."],self.asset[@"version"]]];
        }];
}
- (void)download {
    if(!FSUpdateInstallLocationWritable(NSBundle.mainBundle.bundlePath)){[self fail:@"location"];return;}
    NSUInteger generation=++self.generation;
    self.work=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[@"freescene-update-" stringByAppendingString:NSUUID.UUID.UUIDString]] isDirectory:YES];
    if(![NSFileManager.defaultManager createDirectoryAtURL:self.work withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:nil]){[self fail:@"disk"];return;}
    NSURL *image=[self.work URLByAppendingPathComponent:@"update.dmg"];
    [self publish:@"downloading" message:[self label:@"Загружаю обновление…" english:@"Downloading update…"]];
        self.client=self.makeHTTP();__weak FSReleaseUpdater *weak=self;
        self.client.progress=^(double fraction){FSReleaseUpdater *s=weak;if(s && generation==s.generation)[s publish:@"downloading" message:[NSString stringWithFormat:[s label:@"Загрузка обновления: %.0f %%" english:@"Downloading update: %.0f %%"],fraction*100]];};
        [self.client get:[NSURL URLWithString:self.asset[@"url"]] downloadTo:image size:[self.asset[@"size"] longLongValue] completion:^(NSData *data,NSString *error){
            if(generation!=self.generation)return;self.client=nil;if(error){[self fail:error];return;}
            [self prepare:image generation:generation];
        }];
}
- (void)prepare:(NSURL *)image generation:(NSUInteger)generation {
    [self publish:@"checking" message:[self label:@"Проверяю образ, подпись и совместимость…" english:@"Verifying disk image, signature and compatibility…"]];
    NSDictionary *asset=self.asset;NSURL *work=self.work;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSString *error=nil;NSString *unpacked=[[work URLByAppendingPathComponent:@"unpacked"] path];
        if(!FSUpdateHashMatches(image.path,asset[@"digest"]))error=@"hash";
        else if(!FSUpdateExtractDiskImage(image.path,unpacked,asset[@"version"],&error) && !error)error=@"archive";
        NSString *app=[unpacked stringByAppendingPathComponent:@"FreeScene.app"];
        if(!error)FSUpdateBundleValid(app,asset[@"version"],&error);
        dispatch_async(dispatch_get_main_queue(),^{
            if(generation!=self.generation){[NSFileManager.defaultManager removeItemAtURL:work error:nil];return;}
            if(error){[self fail:error];return;}
            NSString *target=NSBundle.mainBundle.bundlePath;
            if(!FSUpdateInstallLocationWritable(target)){[self fail:@"location"];return;}
            NSString *uuid=NSUUID.UUID.UUIDString;NSString *parent=target.stringByDeletingLastPathComponent;
            self.stage=[parent stringByAppendingPathComponent:[NSString stringWithFormat:@".FreeScene-update-%@.app",uuid]];
            self.backup=[parent stringByAppendingPathComponent:[NSString stringWithFormat:@".FreeScene-backup-%@.app",uuid]];
            if(![NSFileManager.defaultManager copyItemAtPath:app toPath:self.stage error:nil]){[self fail:@"location"];return;}
            NSString *reason=nil;if(!FSUpdateBundleValid(self.stage,asset[@"version"],&reason)){[self fail:reason];return;}
            [NSFileManager.defaultManager removeItemAtURL:self.work error:nil];self.work=nil;
            [self publish:@"ready" message:[self label:@"Обновление проверено. Установить и перезапустить FreeScene?" english:@"Update verified. Install and restart FreeScene?"]];
            if(self.installAfterDownload)[self install];
        });
    });
}
- (void)install {
    if(!FSUpdateInstallLocationWritable(NSBundle.mainBundle.bundlePath)){[self fail:@"location"];return;}
    NSString *reason=nil;if(!FSUpdateBundleValid(self.stage,self.asset[@"version"],&reason)){[self fail:reason];return;}
    NSString *path=[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Contents/Helpers/FreeSceneUpdateHelper"];
    if(![NSFileManager.defaultManager isExecutableFileAtPath:path]){[self fail:@"helper"];return;}
    NSUInteger generation=++self.generation;[self publish:@"installing" message:[self label:@"Запускаю установщик…" english:@"Starting installer…"]];
    NSTask *task=[NSTask new];task.executableURL=[NSURL fileURLWithPath:path];task.arguments=@[@"--install",[@(getpid()) stringValue],NSBundle.mainBundle.bundlePath,self.stage,self.backup];
    NSPipe *pipe=[NSPipe pipe];task.standardOutput=pipe;task.standardError=NSFileHandle.fileHandleWithNullDevice;
    if(![task launchAndReturnError:nil]){[self fail:@"helper"];return;}self.helper=task;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSData *data=[pipe.fileHandleForReading availableData];NSString *line=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        id reply=line.length<4096 ? [NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] ?: NSData.data options:0 error:nil] : nil;
        dispatch_async(dispatch_get_main_queue(),^{
            [self handleReady:reply task:task generation:generation];
        });
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        if(generation==self.generation && !self.handedOff){if(task.running)[task terminate];self.helper=nil;[self fail:@"helper"];}
    });
}
- (void)handleReady:(id)reply task:(NSTask *)task generation:(NSUInteger)generation {
    if(generation!=self.generation || ![self.phase isEqual:@"installing"] || self.handedOff)return;
    if(![reply isKindOfClass:NSDictionary.class] || ![reply[@"ready"] isEqual:@YES] || !task.running){[self fail:@"helper"];return;}
    self.handedOff=YES;[self publish:@"installing" message:[self label:@"Сохраняю задачи и перезапускаю приложение…" english:@"Saving tasks and restarting the application…"]];
    // AppKit may enter its terminateLater run loop before terminate: returns.
    // A readiness callback runs on the serial main dispatch queue; calling
    // terminate: directly there prevents the queued shutdown completion from
    // replying. Return from that dispatch block before starting termination.
    [NSApp performSelector:@selector(terminate:) withObject:nil afterDelay:0
                   inModes:@[NSRunLoopCommonModes]];
}
- (void)dealloc {if(!self.handedOff)[self cleanup];}
@end
