#pragma once
#import "FSUpdateSecurity.h"

typedef void (^FSGitHubHTTPReply)(NSData *data,NSString *error);

@interface FSGitHubHTTP : NSObject <NSURLSessionDataDelegate,NSURLSessionDownloadDelegate>
@property NSURLSession *session;
@property NSURLSessionTask *task;
@property NSMutableData *bytes;
@property NSURL *destination;
@property long long expectedSize;
@property NSUInteger redirects;
@property (copy) FSGitHubHTTPReply reply;
@property (copy) void (^progress)(double);
- (void)get:(NSURL *)url downloadTo:(NSURL *)destination size:(long long)size completion:(FSGitHubHTTPReply)completion;
- (void)cancel;
@end
@implementation FSGitHubHTTP
- (void)get:(NSURL *)url downloadTo:(NSURL *)destination size:(long long)size completion:(FSGitHubHTTPReply)completion {
    if(!FSUpdateAPIURLAllowed(url)){completion(nil,@"redirect");return;}
    self.reply=completion;self.destination=destination;self.expectedSize=size;self.bytes=[NSMutableData new];
    NSURLSessionConfiguration *config=NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.HTTPShouldSetCookies=NO;config.HTTPCookieStorage=nil;config.URLCredentialStorage=nil;config.URLCache=nil;
    config.timeoutIntervalForRequest=30;config.timeoutIntervalForResource=destination ? 600 : 45;
    self.session=[NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:NSOperationQueue.mainQueue];
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:30];
    [request setValue:destination ? @"application/octet-stream" : @"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"2026-03-10" forHTTPHeaderField:@"X-GitHub-Api-Version"];
    [request setValue:@"FreeScene" forHTTPHeaderField:@"User-Agent"];
    self.task=destination ? [self.session downloadTaskWithRequest:request] : [self.session dataTaskWithRequest:request];
    [self.task resume];
}
- (void)finish:(NSData *)data error:(NSString *)error {
    FSGitHubHTTPReply callback=self.reply;if(!callback)return;self.reply=nil;
    [self.session invalidateAndCancel];self.task=nil;self.session=nil;self.bytes=nil;
    callback(data,error);
}
- (void)cancel {[self finish:nil error:@"cancelled"];}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completion {
    NSURLRequest *safe=++self.redirects<=5 ? FSUpdateRedirectRequest(request,self.destination!=nil) : nil;
    completion(safe);if(!safe)[self finish:nil error:@"redirect"];
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completion {
    if(response.expectedContentLength>2*1024*1024){completion(NSURLSessionResponseCancel);[self finish:nil error:@"network"];return;}
    completion(NSURLSessionResponseAllow);
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    if(self.bytes.length+data.length>2*1024*1024){[self finish:nil error:@"network"];return;}[self.bytes appendData:data];
}
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task didWriteData:(int64_t)written totalBytesWritten:(int64_t)total totalBytesExpectedToWrite:(int64_t)expected {
    if(total>self.expectedSize || total>512LL*1024*1024 || (expected>0 && expected!=self.expectedSize)){[self finish:nil error:@"size"];return;}
    if(self.progress && self.expectedSize>0)self.progress((double)total/self.expectedSize);
}
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task didFinishDownloadingToURL:(NSURL *)location {
    if(!self.reply)return;
    NSInteger status=[(NSHTTPURLResponse *)task.response statusCode];
    NSNumber *size=nil;[location getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
    if(status!=200){[self finish:nil error:status==401 ? @"auth" : status==403 || status==404 ? @"repo_access" : @"network"];return;}
    if(size.longLongValue!=self.expectedSize){[self finish:nil error:@"size"];return;}
    if(![NSFileManager.defaultManager copyItemAtURL:location toURL:self.destination error:nil]){[self finish:nil error:@"disk"];return;}
    [self finish:NSData.data error:nil];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if(!self.reply)return;
    NSInteger status=[(NSHTTPURLResponse *)task.response statusCode];
    if(error){[self finish:nil error:error.code==NSURLErrorCancelled ? @"cancelled" : @"network"];return;}
    if(status!=200){[self finish:nil error:status==401 ? @"auth" : status==403 || status==404 ? @"repo_access" : @"network"];return;}
    if(!self.destination)[self finish:self.bytes error:nil];
}
@end
