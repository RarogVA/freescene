// Exercise the shared web presentation script in real WebKit, including an
// opaque-origin iframe and videos inserted after the document has loaded.
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#include <cassert>

static id evaluate(WKWebView *web,NSString *script) {
    __block BOOL done=NO;__block id result=nil;__block NSError *failure=nil;
    [web evaluateJavaScript:script completionHandler:^(id value,NSError *error){result=value;failure=error;done=YES;}];
    NSDate *until=[NSDate dateWithTimeIntervalSinceNow:10];
    while(!done && until.timeIntervalSinceNow>0) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    assert(done && !failure);return result;
}
static void waitFor(WKWebView *web,NSString *condition) {
    NSDate *until=[NSDate dateWithTimeIntervalSinceNow:10];
    while(until.timeIntervalSinceNow>0) {
        if([evaluate(web,condition) isEqual:@YES]) return;
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }
    NSLog(@"Timed out: %@",condition);abort();
}
int main() { @autoreleasepool {
    [NSApplication sharedApplication];
    NSString *source=[NSString stringWithContentsOfFile:@"assets/player/presentation.js" encoding:NSUTF8StringEncoding error:nil];assert(source.length);
    WKWebViewConfiguration *config=[WKWebViewConfiguration new];
    [config.userContentController addUserScript:[[WKUserScript alloc] initWithSource:[NSString stringWithFormat:@"(%@)(0)",source] injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO]];
    WKWebView *web=[[WKWebView alloc] initWithFrame:NSMakeRect(0,0,800,600) configuration:config];
    NSString *child=@"<body style='background:red'><div style='background:blue'><video></video></div><script>addEventListener('message',e=>{if(e.data!=='probe')return;const v=document.querySelector('video');parent.postMessage({test:true,fit:getComputedStyle(v).objectFit,background:getComputedStyle(v.parentElement).backgroundColor},'*')});</script>";
    NSString *html=[NSString stringWithFormat:@"<body style='background:white'><div style='background:red'><video id='video'></video></div><iframe sandbox='allow-scripts' srcdoc=\"%@\"></iframe><script>window.snapshot=null;addEventListener('message',e=>{if(e.data?.test)window.snapshot=e.data});</script>",child];
    [web loadHTMLString:html baseURL:[NSURL URLWithString:@"https://fixture.invalid/"]];
    waitFor(web,@"!!document.getElementById('video') && !!window.__freescenePresentation");
    waitFor(web,@"getComputedStyle(document.getElementById('video').parentElement).backgroundColor==='rgb(0, 0, 0)'");
    for(NSNumber *mode in @[@0,@1,@2,@0]) {
        NSString *fit=@[@"contain",@"cover",@"fill"][mode.integerValue];
        evaluate(web,[NSString stringWithFormat:@"window.__freescenePresentation.setMode(%@);window.snapshot=null;",mode]);
        assert([evaluate(web,@"getComputedStyle(document.getElementById('video')).backgroundColor") isEqual:@"rgb(0, 0, 0)"]);
        assert([evaluate(web,@"getComputedStyle(document.getElementById('video')).objectFit") isEqual:fit]);
        // Parent cannot read the sandboxed child's DOM. The frame reports its
        // computed style after receiving the mode through the production script.
        waitFor(web,@"(document.querySelector('iframe').contentWindow.postMessage('probe','*'),!!window.snapshot)");
        assert([evaluate(web,@"window.snapshot.fit") isEqual:fit]);
        assert([evaluate(web,@"window.snapshot.background") isEqual:@"rgb(0, 0, 0)"]);
    }
    evaluate(web,@"window.__freescenePresentation.setMode(1);const wrapper=document.createElement('div');wrapper.style.background='purple';wrapper.innerHTML='<video id=late></video>';document.body.append(wrapper);");
    waitFor(web,@"getComputedStyle(document.getElementById('late').parentElement).backgroundColor==='rgb(0, 0, 0)'");
    assert([evaluate(web,@"getComputedStyle(document.getElementById('late')).objectFit") isEqual:@"cover"]);
    // A newly navigated iframe starts in Fit, then requests the parent's current
    // mode. This also covers episode/provider changes after selecting Fill.
    evaluate(web,@"window.snapshot=null;document.querySelector('iframe').srcdoc += ' ';");
    waitFor(web,@"(document.querySelector('iframe').contentWindow.postMessage('probe','*'),window.snapshot?.fit==='cover')");
    evaluate(web,@"window.__freescenePresentation.setMode(99)");
    assert([evaluate(web,@"getComputedStyle(document.getElementById('late')).objectFit") isEqual:@"cover"]);
    [web stopLoading];
    puts("{\"passed\":true,\"suite\":\"real WebKit scale modes, black backgrounds, dynamic video and cross-origin frames\"}");
} }
