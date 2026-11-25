#import "../../macos/Native/FSNativeBridge.mm"
#include <cassert>

static BOOL waitFor(BOOL (^condition)()) {
    for(int i=0;i<100;i++) { if(condition())return YES;[NSThread sleepForTimeInterval:.05]; }
    return NO;
}
int main(int argc,const char **argv) { @autoreleasepool {
    assert(argc==3);
    setenv("VLC_PLUGIN_PATH","build/native/vlc/plugins",1);
    const char *args[]={"--no-video","--aout=adummy","--no-plugins-cache","--no-metadata-network-access"};
    FSPlayer *player=[FSPlayer alloc];player.vlc=libvlc_new(4,args);assert(player.vlc);
    player.player=libvlc_media_player_new(player.vlc);assert(player.player);
    assert(FSAudioPreferenceScore(@"en-US",@"")==200);
    assert(FSAudioPreferenceScore(@"eng",@"Commentary")==190);
    assert(FSAudioPreferenceScore(@"ru",@"English")==0);
    assert(FSAudioPreferenceScore(@"",@"Стерео")==0);
    for(int file=1;file<=2;file++) {
        auto media=libvlc_media_new_path(player.vlc,argv[file]);
        libvlc_media_player_set_media(player.player,media);libvlc_media_release(media);
        player.preferEnglishAudio=YES;player.manualAudio=NO;player.audioPreferenceSnapshot=nil;
        [player choosePreferredAudio]; // Metadata may not exist yet.
        assert(libvlc_media_player_play(player.player)==0);
        assert(waitFor(^BOOL{return libvlc_audio_get_track_count(player.player)>2;}));
        [player choosePreferredAudio];
        libvlc_media_track_t **tracks=nullptr;
        unsigned count=libvlc_media_tracks_get(libvlc_media_player_get_media(player.player),&tracks);
        int expected=-1,russian=-1;
        for(unsigned i=0;i<count;i++)if(tracks[i]->i_type==libvlc_track_audio) {
            NSString *language=tracks[i]->psz_language ? [NSString stringWithUTF8String:tracks[i]->psz_language] : @"";
            NSString *label=tracks[i]->psz_description ? [NSString stringWithUTF8String:tracks[i]->psz_description] : @"";
            if([language isEqual:@"rus"])russian=tracks[i]->i_id;
            if(FSAudioPreferenceScore(language,label)==(file==1 ? 200 : 100))expected=tracks[i]->i_id;
        }
        libvlc_media_tracks_release(tracks,count);
        assert(expected>=0 && russian>=0);
        assert(waitFor(^BOOL{return libvlc_audio_get_track(player.player)==expected;}));
        NSMenuItem *manual=[NSMenuItem new];manual.tag=russian;[player audioChanged:manual];
        [player choosePreferredAudio];assert(libvlc_audio_get_track(player.player)==russian);
        player.manualAudio=NO;player.preferEnglishAudio=NO;player.audioPreferenceSnapshot=nil;
        [player choosePreferredAudio];assert(libvlc_audio_get_track(player.player)==russian);
        libvlc_media_player_stop(player.player);
    }
    libvlc_media_player_release(player.player);libvlc_release(player.vlc);
    player.player=nullptr;player.vlc=nullptr;
    puts("Native audio: real multi-track media, English/original, late metadata and manual choice passed.");
} return 0; }
