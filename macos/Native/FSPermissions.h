#import <Cocoa/Cocoa.h>
#import <UserNotifications/UserNotifications.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>

static inline NSString *FSDownloadsPath(void) {
    return NSProcessInfo.processInfo.environment[@"FREESCENE_DOWNLOADS"] ?: [NSHomeDirectory() stringByAppendingPathComponent:@"Downloads/FreeScene"];
}
// Apple TN3179: connecting a UDP socket to a local address can invoke Local
// Network consent without sending any traffic. No peers or files are disclosed.
// macOS owns the decision; there is no API to query or reset this permission.
static void FSRequestLocalNetwork(void) {
    if(@available(macOS 15.0,*)) {
        struct ifaddrs *interfaces=nullptr;
        if(getifaddrs(&interfaces)!=0) return;
        BOOL attempted=NO;
        for(auto *i=interfaces;i;i=i->ifa_next) {
            if(!i->ifa_addr || !(i->ifa_flags & IFF_UP) || !(i->ifa_flags & IFF_BROADCAST) || i->ifa_addr->sa_family!=AF_INET6) continue;
            auto address=*reinterpret_cast<sockaddr_in6 *>(i->ifa_addr);
            if(!IN6_IS_ADDR_LINKLOCAL(&address.sin6_addr)) continue;
            address.sin6_port=htons(9);
            arc4random_buf(&address.sin6_addr.s6_addr[8],8);
            int descriptor=socket(AF_INET6,SOCK_DGRAM,0);
            if(descriptor<0) continue;
            connect(descriptor,reinterpret_cast<sockaddr *>(&address),sizeof(address));
            close(descriptor); attempted=YES;
        }
        if(!attempted) for(auto *i=interfaces;i;i=i->ifa_next) {
            if(!i->ifa_addr || !i->ifa_broadaddr || !(i->ifa_flags & IFF_UP) || !(i->ifa_flags & IFF_BROADCAST) || i->ifa_addr->sa_family!=AF_INET) continue;
            auto address=*reinterpret_cast<sockaddr_in *>(i->ifa_broadaddr); address.sin_port=htons(9);
            int descriptor=socket(AF_INET,SOCK_DGRAM,0); if(descriptor<0) continue;
            int yes=1; setsockopt(descriptor,SOL_SOCKET,SO_BROADCAST,&yes,sizeof(yes));
            connect(descriptor,reinterpret_cast<sockaddr *>(&address),sizeof(address)); close(descriptor);
        }
        freeifaddrs(interfaces);
    }
}
@interface FSPermissions : NSObject
@property BOOL busy;
- (void)requestAgain:(BOOL)again completion:(void (^)(NSDictionary *))completion;
@end
@implementation FSPermissions
- (void)requestAgain:(BOOL)again completion:(void (^)(NSDictionary *))completion {
    if(self.busy) { completion(@{@"busy":@YES}); return; }
    if(!again && [NSUserDefaults.standardUserDefaults boolForKey:@"FreeScene.permissions.v1"]) { completion(@{@"requested":@YES}); return; }
    self.busy=YES;
    UNUserNotificationCenter *center=UNUserNotificationCenter.currentNotificationCenter;
    void (^finish)(BOOL)=^(BOOL notifications) {
        dispatch_async(dispatch_get_main_queue(),^{
            // Accessing our actual download directory invokes macOS Files and
            // Folders consent when required. Never ask for Full Disk Access.
            NSError *error=nil; NSString *directory=FSDownloadsPath();
            BOOL files=[NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error];
            // macOS may allow creating a new file without asking. Reading our
            // own directory is necessary to resume downloads and requests the
            // actual Files and Folders permission, without inspecting Downloads.
            if(files) files=[NSFileManager.defaultManager contentsOfDirectoryAtPath:directory error:&error]!=nil;
            NSString *probe=[directory stringByAppendingPathComponent:[@".freescene-access-" stringByAppendingString:NSUUID.UUID.UUIDString]];
            if(files) { files=[NSData.data writeToFile:probe options:NSDataWritingAtomic error:&error]; if(files) [NSFileManager.defaultManager removeItemAtPath:probe error:nil]; }
            FSRequestLocalNetwork();
            [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"FreeScene.permissions.v1"];
            self.busy=NO;
            if(again) {
                NSAlert *alert=[NSAlert new];alert.messageText=fsEnglish?@"FreeScene permissions":@"Разрешения FreeScene";
                alert.informativeText=[NSString stringWithFormat:fsEnglish?@"Notifications: %@\nDownloads: %@\nLocal network is managed by macOS when peer discovery starts.\nIf access was denied, change it in System Settings.":@"Уведомления: %@\nКаталог загрузок: %@\nДоступ к локальной сети запрашивает macOS при поиске пиров.\nЕсли доступ был запрещён, измените выбор в системных настройках.",notifications?(fsEnglish?@"allowed":@"разрешены"):(fsEnglish?@"not allowed":@"не разрешены"),files?(fsEnglish?@"available":@"доступен"):(fsEnglish?@"not available":@"недоступен")];
                for(NSString *title in fsEnglish?@[@"Notifications",@"Files and Folders",@"Local network",@"Close"]:@[@"Уведомления",@"Файлы и папки",@"Локальная сеть",@"Закрыть"]) [alert addButtonWithTitle:title];
                NSInteger answer=[alert runModal]-NSAlertFirstButtonReturn;
                NSArray *urls=@[@"x-apple.systempreferences:com.apple.Notifications-Settings.extension",@"x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders",@"x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork"];
                if(answer>=0 && answer<3) { NSURL *url=[NSURL URLWithString:urls[answer]];if(url)[NSWorkspace.sharedWorkspace openURL:url]; }
            }
            completion(@{@"notifications":@(notifications),@"downloads":@(files)});
        });
    };
    [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
        if(settings.authorizationStatus==UNAuthorizationStatusNotDetermined) [center requestAuthorizationWithOptions:UNAuthorizationOptionAlert|UNAuthorizationOptionSound completionHandler:^(BOOL granted,NSError *error){finish(granted);}];
        else finish(settings.authorizationStatus==UNAuthorizationStatusAuthorized || settings.authorizationStatus==UNAuthorizationStatusProvisional);
    }];
}
@end
