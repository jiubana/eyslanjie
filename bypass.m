#import <Foundation/Foundation.h>
#import <objc/runtime.h>

/**
 * 鹅鸭杀全自动验证绕过插件 (Standalone Dylib)
 * 功能：在系统层面拦截并伪造验证服务器的返回数据
 * 目标：无需小火箭，直接注入游戏即可使用
 */

@interface BypassHook : NSObject
@end

@implementation BypassHook

+ (void)load {
    NSLog(@"[Bypass] 插件已加载，开始挂钩网络请求...");
    [self hookNSURLSession];
}

+ (void)hookNSURLSession {
    // 挂钩 NSURLSession 的 dataTaskWithRequest:completionHandler:
    Class sessionClass = [NSURLSession class];
    SEL originalSelector = @selector(dataTaskWithRequest:completionHandler:);
    SEL swizzledSelector = @selector(bypass_dataTaskWithRequest:completionHandler:);

    Method originalMethod = class_getInstanceMethod(sessionClass, originalSelector);
    Method swizzledMethod = class_getInstanceMethod(self, swizzledSelector);

    method_exchangeImplementations(originalMethod, swizzledMethod);
}

- (NSURLSessionDataTask *)bypass_dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error))completionHandler {
    
    NSString *url = request.URL.absoluteString;
    
    // 检查是否为验证服务器地址
    if ([url containsString:@"qunhongtech.com/auth/"]) {
        NSLog(@"[Bypass] 拦截到验证请求: %@", url);
        
        NSData *mockData = nil;
        NSString *contentType = @"application/json";
        
        if ([url containsString:@"Notice"]) {
            // 公告接口返回 JSON
            NSString *json = @"{\"code\":1,\"message\":\"success\",\"data\":{\"notice\":0}}";
            mockData = [json dataUsingEncoding:NSUTF8StringEncoding];
        } else {
            // 授权接口返回 Base64
            NSString *base64 = @"eyJjb2RlIjoxLCJkYXRhIjp7ImFsZXJ0IjowLCJlbmR0aXAiOjAsImhpbnQiOiIiLCJ2ZXJpZnkiOjEsImp1bXAiOjB9LCJtZXNzYWdlIjoic3VjY2VzcyJ9";
            mockData = [base64 dataUsingEncoding:NSUTF8StringEncoding];
            contentType = @"text/plain";
        }
        
        // 伪造响应
        NSHTTPURLResponse *mockResponse = [[NSHTTPURLResponse alloc] initWithURL:request.URL 
                                                                    statusCode:200 
                                                                   HTTPVersion:@"HTTP/1.1" 
                                                                  headerFields:@{@"Content-Type": contentType, @"Access-Control-Allow-Origin": @"*"}];
        
        // 直接回调成功
        if (completionHandler) {
            completionHandler(mockData, mockResponse, nil);
        }
        
        // 返回一个空的 Task（因为我们已经手动回调了）
        return nil; 
    }
    
    // 如果不是验证请求，走原逻辑
    return [self bypass_dataTaskWithRequest:request completionHandler:completionHandler];
}

@end
