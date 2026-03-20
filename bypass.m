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
        // Base64 Success Payload (Simplified to avoid URIError)
        mockData = [@"eyJjb2RlIjoxLCJkYXRhIjp7InZlcmlmeSI6MX0sIm1lc3NhZ2Ijoic3VjY2VzcyJ9" dataUsingEncoding:NSUTF8StringEncoding];
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
        NSLog(@"[EYS-Bypass] 正在启动全局协议引擎 v2.1...");
        
        // 1. 注册协议
        [NSURLProtocol registerClass:[EYSBypassProtocol class]];
        
        // 2. 注入所有 Session 配置（关键修复：使用更安全的 Block 挂钩）
        [self eys_safeSwizzleSessionConfig];
    });
}

+ (void)eys_safeSwizzleSessionConfig {
    Class cls = [NSURLSessionConfiguration class];
    SEL sel = @selector(defaultSessionConfiguration);
    Method method = class_getClassMethod(cls, sel);
    
    if (!method) return;

    // 保存原始实现
    __block IMP (*originalImp)(id, SEL) = (IMP (*)(id, SEL))method_getImplementation(method);

    // 创建新实现
    IMP newImp = imp_implementationWithBlock(^NSURLSessionConfiguration *(id _self) {
        // 调用原函数
        NSURLSessionConfiguration *config = originalImp(_self, sel);
        
        // 注入我们的拦截协议
        if (config) {
            NSMutableArray *protocols = [NSMutableArray arrayWithArray:config.protocolClasses];
            if (![protocols containsObject:[EYSBypassProtocol class]]) {
                [protocols insertObject:[EYSBypassProtocol class] atIndex:0];
                config.protocolClasses = protocols;
            }
        }
        return config;
    });

    // 替换
    method_setImplementation(method, newImp);
    
    // 同样挂钩 ephemeralSessionConfiguration
    SEL sel2 = @selector(ephemeralSessionConfiguration);
    Method method2 = class_getClassMethod(cls, sel2);
    if (method2) {
        __block IMP (*originalImp2)(id, SEL) = (IMP (*)(id, SEL))method_getImplementation(method2);
        IMP newImp2 = imp_implementationWithBlock(^NSURLSessionConfiguration *(id _self) {
            NSURLSessionConfiguration *config = originalImp2(_self, sel2);
            if (config) {
                NSMutableArray *protocols = [NSMutableArray arrayWithArray:config.protocolClasses];
                [protocols insertObject:[EYSBypassProtocol class] atIndex:0];
                config.protocolClasses = protocols;
            }
            return config;
        });
        method_setImplementation(method2, newImp2);
    }
}

@end
