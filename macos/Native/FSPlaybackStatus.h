#import <Foundation/Foundation.h>

// This presentation never substitutes catalogue counts for engine connections.
static inline NSString *FSRate(NSNumber *bytes, BOOL english) {
    double rate=MAX(0,bytes.doubleValue);
    if (rate<1024) return [NSString stringWithFormat:english ? @"%.0f B/s" : @"%.0f Б/с",rate];
    return rate>=1048576 ? [NSString stringWithFormat:english ? @"%.1f MiB/s" : @"%.1f МиБ/с",rate/1048576] :
        [NSString stringWithFormat:english ? @"%.0f KiB/s" : @"%.0f КиБ/с",rate/1024];
}
static inline NSDictionary *FSPlaybackPresentation(NSDictionary *task, NSString *mediaState, BOOL paused, BOOL english) {
    NSString *problem=[task[@"error"] isKindOfClass:NSString.class] ? task[@"error"] : @"";
    BOOL failed=[mediaState isEqual:@"error"] || problem.length>0;
    BOOL inactive=paused || [task[@"phase"] isEqual:@"paused"] || [task[@"phase"] isEqual:@"queued"] || [mediaState isEqual:@"ended"];
    BOOL metadata=[task[@"metadata"] boolValue];
    BOOL busy=!failed && !inactive && ((task && !metadata) || [task[@"buffering"] boolValue] || [@[@"opening",@"buffering"] containsObject:mediaState]);
    NSString *phase=failed ? (english ? @"Playback error" : @"Ошибка воспроизведения") : inactive ?
        (english ? @"Waiting / paused" : @"Ожидание / пауза") : task && !metadata ?
        (english ? @"Receiving torrent metadata…" : @"Получение метаданных торрента…") : busy ?
        (english ? @"Buffering…" : @"Буферизация…") : (english ? @"Playing" : @"Воспроизведение");
    if (!task) return @{@"busy":@(busy),@"text":phase};
    NSDictionary *dhtNames=english ? @{@"ready":@"ready",@"searching":@"finding nodes",@"starting":@"starting",@"disabled":@"off",@"private":@"private torrent",@"error":@"unavailable"} :
        @{@"ready":@"готова",@"searching":@"поиск узлов",@"starting":@"запуск",@"disabled":@"выключена",@"private":@"приватный торрент",@"error":@"недоступна"};
    id seeds=task[@"seeds"], peers=task[@"peers"];
    NSString *counts=[NSString stringWithFormat:english ? @"Seeds: %@ · Peers: %@" : @"Сиды: %@ · Пиры: %@",
        [seeds isKindOfClass:NSNumber.class] ? seeds : @"—", [peers isKindOfClass:NSNumber.class] ? peers : @"—"];
    NSString *text=[NSString stringWithFormat:@"%@ · info: %@ · DHT: %@\n%@ · ↓ %@",phase,
        metadata ? (english ? @"received" : @"получена") : (english ? @"waiting" : @"ожидание"),
        dhtNames[task[@"dht"] ?: @""] ?: @"—", counts, FSRate(task[@"rate"],english)];
    return @{@"busy":@(busy),@"text":text};
}
