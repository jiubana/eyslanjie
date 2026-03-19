#import <Foundation/Foundation.h>
#import <objc/runtime.h>

/**
 * 鹅鸭杀全自动验证绕过插件 (Standalone Dylib)
 * 功能：在系统层面拦截并伪造验证服务器的返回数据
 * 目标：无需小火箭，直接注入游戏即可使用
 */

@interface EYSBypassHook : NSObject
@end

@implementation EYSBypassHook

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSLog(@"[EYS-Bypass] 正在启动安全拦截引擎...");
        [self eys_hookNSURLSession];
    });
}

+ (void)eys_hookNSURLSession {
    Class sessionClass = [NSURLSession class];
    SEL originalSelector = @selector(dataTaskWithRequest:completionHandler:);
    SEL swizzledSelector = @selector(eys_dataTaskWithRequest:completionHandler:);

    Method originalMethod = class_getInstanceMethod(sessionClass, originalSelector);
    Method swizzledMethod = class_getInstanceMethod(self, swizzledSelector);

    if (class_addMethod(sessionClass, swizzledSelector, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod))) {
        class_replaceMethod(sessionClass, originalSelector, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod));
    } else {
        method_exchangeImplementations(originalMethod, swizzledMethod);
    }
}

- (NSURLSessionDataTask *)eys_dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error))completionHandler {
    
    NSString *url = request.URL.absoluteString;
    
    // 拦截 鹅鸭杀/群鸿 验证接口
    if ([url containsString:@"qunhongtech.com/auth/"]) {
        NSLog(@"[EYS-Bypass] 拦截并模拟成功响应: %@", url);
        
        // 模拟延迟回调，避免“秒回”导致的游戏逻辑异常
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSData *mockData = nil;
            NSString *contentType = @"application/json";
            
            if ([url containsString:@"Notice"]) {
                mockData = [@"{\"code\":1,\"message\":\"success\",\"data\":{\"notice\":0}}" dataUsingEncoding:NSUTF8StringEncoding];
            } else {
                // Base64 Success Payload
                mockData = [@"eyJjb2RlIjoxLCJkYXRhIjp7ImFsZXJ0IjowLCJlbmR0aXAiOjAsImhpbnQiOiIiLCJ2ZXJpZnkiOjEsImp1bXAiOjB9LCJtZXNzYWdlIjoic3VjY2VzcyJ9" dataUsingEncoding:NSUTF8StringEncoding];
                contentType = @"text/plain";
            }
            
            NSHTTPURLResponse *mockResponse = [[NSHTTPURLResponse alloc] initWithURL:request.URL 
                                                                        statusCode:200 
                                                                       HTTPVersion:@"HTTP/1.1" 
                                                                      headerFields:@{@"Content-Type": contentType, @"Access-Control-Allow-Origin": @"*"}];
            
            if (completionHandler) {
                completionHandler(mockData, mockResponse, nil);
            }
        });
        
        /**
         * 【关键修复】防止闪退
         * 我们不能直接返回 nil，因为游戏可能对返回的 Task 进行了引用计数或状态检查。
         * 我们调用原函数但传入空的 completion，这样既满足了返回值要求，又不会真正执行多余的回调。
         */
        return [self eys_dataTaskWithRequest:request completionHandler:nil]; 
    }
    
    // 正常请求走原逻辑
    return [self eys_dataTaskWithRequest:request completionHandler:completionHandler];
}

@end
