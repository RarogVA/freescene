// Production progress script in real WebKit, including an opaque-origin player.
// Media clock values are controlled fixtures; this does not test video decoding.
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#include <cassert>

@interface ProgressRecorder : NSObject <WKScriptMessageHandler>
@property NSMutableArray *reports;
@end
@implementation ProgressRecorder
- (instancetype)init { if ((self=[super init])) self.reports=[NSMutableArray new]; return self; }
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
    NSData *data=[message.body dataUsingEncoding:NSUTF8StringEncoding];
    [self.reports addObject:[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]];
}
@end
static id evaluate(WKWebView *web,NSString *script) {
    __block BOOL done=NO;__block id result=nil;__block NSError *failure=nil;
    [web evaluateJavaScript:script completionHandler:^(id value,NSError *error){ result=value; failure=error; done=YES; }];
    NSDate *until=[NSDate dateWithTimeIntervalSinceNow:10];
    while (!done && until.timeIntervalSinceNow>0) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    assert(done && !failure); return result;
}
static void waitFor(BOOL (^condition)(void)) {
    NSDate *until=[NSDate dateWithTimeIntervalSinceNow:10];
    while (until.timeIntervalSinceNow>0) {
        if (condition()) return;
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }
    assert(!"Timed out waiting for playback progress");
}
int main() { @autoreleasepool {
    [NSApplication sharedApplication];
    NSString *source=[NSString stringWithContentsOfFile:@"assets/player/progress.js" encoding:NSUTF8StringEncoding error:nil]; assert(source.length);
    WKWebViewConfiguration *config=[WKWebViewConfiguration new];
    ProgressRecorder *recorder=[ProgressRecorder new];
    [config.userContentController addScriptMessageHandler:recorder name:@"progress"];
    NSString *script=[NSString stringWithFormat:@"window.FreeScenePlayback={postMessage:v=>window.webkit.messageHandlers.progress.postMessage(v)};(%@)({rootSelector:'#freescene-video-root',position:120000,duration:3600000});",source];
    [config.userContentController addUserScript:[[WKUserScript alloc] initWithSource:script injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO]];
    WKWebView *web=[[WKWebView alloc] initWithFrame:NSMakeRect(0,0,800,600) configuration:config];
    NSString *child=@"<body><script>setTimeout(()=>{const v=document.createElement('video');v.style.cssText='width:640px;height:360px';window.clock=0;window.done=false;Object.defineProperties(v,{duration:{get:()=>3600},readyState:{get:()=>4},currentTime:{get:()=>clock,set:n=>clock=n},ended:{get:()=>done}});document.body.append(v);addEventListener('message',e=>{if(e.data==='advance'){clock=180;v.dispatchEvent(new Event('pause'));}if(e.data==='end'){clock=3600;done=true;v.dispatchEvent(new Event('ended'));}});},50);</script>";
    // The unrelated player outside the selected root must never report progress.
    NSString *html=[NSString stringWithFormat:@"<body><iframe sandbox='allow-scripts' srcdoc=\"%@\"></iframe><div id='freescene-video-root'><iframe style='width:700px;height:400px' sandbox='allow-scripts' srcdoc=\"%@\"></iframe></div>",child,child];
    [web loadHTMLString:html baseURL:[NSURL URLWithString:@"https://fixture.invalid/"]];
    waitFor(^BOOL { return recorder.reports.count>0; });
    assert([recorder.reports.lastObject[@"position"] longLongValue]==120000);
    evaluate(web,@"document.querySelector('#freescene-video-root iframe').contentWindow.postMessage('advance','*')");
    waitFor(^BOOL { return [recorder.reports.lastObject[@"position"] longLongValue]==180000; });
    // Re-injection cannot reset the user's new position to the original bookmark.
    evaluate(web,[NSString stringWithFormat:@"(%@)({rootSelector:'#freescene-video-root',position:120000,duration:3600000})",source]);
    NSDate *until=[NSDate dateWithTimeIntervalSinceNow:1.2];
    while (until.timeIntervalSinceNow>0) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    assert([recorder.reports.lastObject[@"position"] longLongValue]==180000);
    for (NSDictionary *report in recorder.reports) assert([report[@"position"] longLongValue]>=120000);
    evaluate(web,@"document.querySelector('#freescene-video-root iframe').contentWindow.postMessage('end','*')");
    waitFor(^BOOL { return [recorder.reports.lastObject[@"ended"] boolValue]; });
    [web stopLoading];
    puts("{\"passed\":true,\"suite\":\"web progress, deferred cross-origin video, resume once, selected frame and completion\"}");
} }
