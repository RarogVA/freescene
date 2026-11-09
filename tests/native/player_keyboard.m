#import <Foundation/Foundation.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import "../../macos/Native/FSPlayerKeyboard.h"
#include <assert.h>
int main(void) { @autoreleasepool {
    assert(FSKeyboardSeekTarget(25000,60000,YES)==35000);
    assert(FSKeyboardSeekTarget(25000,60000,NO)==15000);
    assert(FSKeyboardSeekTarget(3000,60000,NO)==0);
    assert(FSKeyboardSeekTarget(55000,60000,YES)==60000);
    JSContext *js=[JSContext new];
    [js evaluateScript:@"let handler,stopped=0;const window={addEventListener:(type,fn,capture)=>{if(type!=='keydown'||!capture)throw Error('capture');handler=fn;}};"
      "const video={currentTime:25,readyState:1,seekable:{length:1,start:()=>0,end:()=>60},getBoundingClientRect:()=>({width:600})};"
      "const document={querySelectorAll:()=>[video]};"
      "const press=(key,extra={})=>handler({key,target:{closest:()=>false},preventDefault:()=>stopped++,stopImmediatePropagation:()=>stopped++,...extra});"];
    [js evaluateScript:FSPlayerKeyboardScript()];
    [js evaluateScript:@"press('ArrowRight');if(video.currentTime!==35||stopped!==2)throw Error('right');"
      "press('ArrowLeft');if(video.currentTime!==25||stopped!==4)throw Error('left');"
      "video.currentTime=3;press('ArrowLeft');if(video.currentTime!==0)throw Error('start');"
      "video.currentTime=58;press('ArrowRight');if(video.currentTime!==60)throw Error('end');"
      "video.currentTime=25;press('ArrowRight',{ctrlKey:true});press('ArrowLeft',{metaKey:true});"
      "press('ArrowLeft',{target:{closest:()=>true}});press('Space');if(video.currentTime!==25)throw Error('focus');"
      "video.seekable.length=0;press('ArrowLeft');if(video.currentTime!==25)throw Error('not seekable');"];
    if(js.exception) { NSLog(@"%@",js.exception); return 1; }
    puts("{\"passed\":true,\"suite\":\"native and web player 10-second keyboard seek\"}");
} return 0; }
