#import <Foundation/Foundation.h>
#import <objc/runtime.h>

/**
 * 鹅鸭杀全自动验证绕过插件 (Standalone Dylib)
 * 功能：在系统层面拦截并伪造验证服务器的返回数据
 * 目标：无需小火箭，直接注入游戏即可使用
 */

/**
 * 鹅鸭杀全自动验证绕过插件 v2.0 (NSURLProtocol 版)
 * 特点：兼容性极强，支持 NSURLSession/NSURLConnection/WebView
 */

@interface EYSBypassProtocol : NSURLProtocol
@end

@implementation EYSBypassProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    NSString *url = request.URL.absoluteString;
    // 只拦截验证服务器相关的请求
    if ([url containsString:@"qunhongtech.com/auth/"]) {
        return YES;
    }
    return NO;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    NSString *url = self.request.URL.absoluteString;
    NSData *mockData = nil;
    NSString *contentType = @"application/json";

    if ([url containsString:@"Notice"]) {
        mockData = [@"{\"code\":1,\"message\":\"success\",\"data\":{\"notice\":0}}" dataUsingEncoding:NSUTF8StringEncoding];
    } else {
        // Base64 Success Payload
        mockData = [@"eyJjb2RlIjoxLCJkYXRhIjp7ImFsZXJ0IjowLCJlbmR0aXAiOjAsImhpbnQiOiIiLCJ2ZXJpZnkiOjEsImp1bXAiOjB9LCJtZXNzYWdlIjoic3VjY2VzcyJ9" dataUsingEncoding:NSUTF8StringEncoding];
        contentType = @"text/plain";
    }

    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL
                                                              statusCode:200
                                                             HTTPVersion:@"HTTP/1.1"
                                                            headerFields:@{@"Content-Type": contentType, @"Access-Control-Allow-Origin": @"*"}];

    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:mockData];
    [self.client URLProtocolDidFinishLoading:self];
}

- (void)stopLoading {}

@end

// 注册插件
@interface EYSLoader : NSObject
@end

@implementation EYSLoader

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSLog(@"[EYS-Bypass] 正在启动全局协议引擎...");
        [NSURLProtocol registerClass:[EYSBypassProtocol class]];
        [self swizzleSessionConfiguration];
    });
}

+ (void)swizzleSessionConfiguration {
    // 强制让所有 NSURLSession 也使用我们的自定义协议
    Class cls = [NSURLSessionConfiguration class];
    Method m1 = class_getClassMethod(cls, @selector(defaultSessionConfiguration));
    Method m2 = class_getClassMethod([self class], @selector(eys_defaultSessionConfiguration));
    method_exchangeImplementations(m1, m2);
}

+ (NSURLSessionConfiguration *)eys_defaultSessionConfiguration {
    NSURLSessionConfiguration *config = [self eys_defaultSessionConfiguration];
    NSMutableArray *protocols = [NSMutableArray arrayWithArray:config.protocolClasses];
    [protocols insertObject:[EYSBypassProtocol class] atIndex:0];
    config.protocolClasses = protocols;
    return config;
}

@end
