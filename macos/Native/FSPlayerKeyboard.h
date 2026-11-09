#import <Foundation/Foundation.h>

static inline int64_t FSKeyboardSeekTarget(int64_t position, int64_t duration, BOOL forward) {
    return MAX((int64_t)0,MIN(duration,position+(forward ? 10000 : -10000)));
}

// Run in each video frame. Capture prevents the website's own shortcut from
// applying a second seek. Text fields, menus and modified keys stay untouched.
static inline NSString *FSPlayerKeyboardScript(void) {
    return @"(()=>{window.addEventListener('keydown',event=>{"
      "if(!['ArrowLeft','ArrowRight'].includes(event.key)||event.altKey||event.ctrlKey||event.metaKey||event.shiftKey)return;"
      "const target=event.target;if(target?.closest?.('input,textarea,select,[contenteditable],[role=slider],[role=menu],[role=listbox]'))return;"
      "const video=[...document.querySelectorAll('video')].find(v=>v.getBoundingClientRect().width>0&&v.readyState>0&&v.seekable.length);"
      "if(!video)return;const start=video.seekable.start(0),end=video.seekable.end(video.seekable.length-1);"
      "video.currentTime=Math.max(start,Math.min(end,video.currentTime+(event.key==='ArrowLeft'?-10:10)));"
      "event.preventDefault();event.stopImmediatePropagation();},true);})()";
}
