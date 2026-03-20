#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

/**
 * 鹅鸭杀 验证绕过 + 品牌修改插件 v3.0
 * 功能1: 拦截 qunhongtech.com 请求，伪造验证通过
 * 功能2: Hook WKWebView，注入 JS 替换菜单中的品牌文字
 */

// ============================================================
// 功能1: NSURLProtocol 网络拦截 (验证绕过)
// ============================================================

@interface EYSBypassProtocol : NSURLProtocol
@end

@implementation EYSBypassProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    NSString *url = request.URL.absoluteString;
    if ([url containsString:@"qunhongtech.com"]) {
        return YES;
    }
    return NO;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    NSString *url = self.request.URL.absoluteString;
    
    // 构建验证通过的 JSON (晚风电竞品牌)
    NSString *jsonStr = @"{\"code\":1,\"data\":{\"alert\":\"\\u665a\\u98ce\\u7535\\u7ade\\u5168\\u80fd\\u7248IOS\",\"endtip\":0,\"hint\":\"QQ\\u4ea4\\u6d41\\u7fa41079837419 \\uff08\\u95f2\\u9c7c\\u665a\\u98ce\\u7535\\u7ade)\",\"verify\":1,\"jump\":0},\"message\":\"success\"}";
    
    NSData *responseData;
    
    // 关键：verifyAuthCode 端点的客户端 JS 使用 decodeBase64(atob) 解码
    // 所以必须返回 Base64 编码的 JSON，否则 atob 会抛出 InvalidCharacterError
    if ([url containsString:@"verify"] || [url containsString:@"auth"]) {
        NSData *jsonData = [jsonStr dataUsingEncoding:NSUTF8StringEncoding];
        NSString *base64Str = [jsonData base64EncodedStringWithOptions:0];
        responseData = [base64Str dataUsingEncoding:NSUTF8StringEncoding];
        NSLog(@"[EYS-Bypass] 返回 Base64 编码的验证数据: %@", url);
    } else {
        // notice 等其他端点直接返回 JSON
        responseData = [jsonStr dataUsingEncoding:NSUTF8StringEncoding];
        NSLog(@"[EYS-Bypass] 返回原始 JSON 数据: %@", url);
    }

    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL
                                                               statusCode:200
                                                              HTTPVersion:@"HTTP/1.1"
                                                             headerFields:@{@"Content-Type": @"text/plain", @"Access-Control-Allow-Origin": @"*"}];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:responseData];
    [self.client URLProtocolDidFinishLoading:self];
}

- (void)stopLoading {}

@end

// ============================================================
// 功能2: WKWebView Hook (品牌文字替换)
// ============================================================

// 用于替换 WebView 中的品牌文字的 JavaScript (使用 Unicode 转义避免二进制编码问题)
static NSString *kBrandingReplaceJS = @"\
(function() {\
    var replacements = [\
        ['\\u4FCA\\u4FCA\\u7535\\u7ade\\u5168\\u80FD\\u7248IOS', '\\u665A\\u98CE\\u7535\\u7ade\\u5168\\u80FD\\u7248IOS'],\
        ['\\u4FCA\\u4FCA\\u7535\\u7ade\\u5168\\u80FD\\u7248', '\\u665A\\u98CE\\u7535\\u7ade\\u5168\\u80FD\\u7248'],\
        ['\\u4FCA\\u4FCA\\u7535\\u7ade', '\\u665A\\u98CE\\u7535\\u7ade'],\
        ['\\u95F2\\u9C7C\\u4FCA\\u4FCA\\u7535\\u7ade', '\\u95F2\\u9C7C\\u665A\\u98CE\\u7535\\u7ade'],\
        ['10352435', '1079837419']\
    ];\
    function replaceInTextNodes(node) {\
        if (node.nodeType === 3) {\
            var text = node.textContent;\
            for (var i = 0; i < replacements.length; i++) {\
                text = text.split(replacements[i][0]).join(replacements[i][1]);\
            }\
            if (text !== node.textContent) node.textContent = text;\
        } else {\
            for (var j = 0; j < node.childNodes.length; j++) {\
                replaceInTextNodes(node.childNodes[j]);\
            }\
        }\
    }\
    function doReplace() { if(document.body) replaceInTextNodes(document.body); }\
    doReplace();\
    if(document.body) new MutationObserver(function() { doReplace(); }).observe(document.body, {childList:true, subtree:true, characterData:true});\
    setInterval(doReplace, 500);\
})();";

// ============================================================
// 注册 & 挂钩入口
// ============================================================

@interface EYSLoader : NSObject
@end

@implementation EYSLoader

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSLog(@"[EYS-Bypass] v3.0 启动: 验证绕过 + 品牌替换...");

        // 1. 注册网络协议拦截
        [NSURLProtocol registerClass:[EYSBypassProtocol class]];

        // 2. 挂钩 Session 配置
        [self eys_safeSwizzleSessionConfig];

        // 3. 挂钩 WKWebView (延迟执行，等 WebKit 加载)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [EYSLoader eys_hookWKWebView];
        });
    });
}

+ (void)eys_hookWKWebView {
    // Hook WKWebView 的 loadHTMLString 和 loadRequest 来注入 JS
    Class wkClass = NSClassFromString(@"WKWebView");
    if (!wkClass) {
        NSLog(@"[EYS-Bypass] WKWebView 未加载，使用 KVO 等待...");
        // 如果 WebKit 还没加载，通过 hook evaluateJavaScript 来注入
        return;
    }

    // Hook -[WKWebView loadHTMLString:baseURL:]
    SEL loadHTMLSel = NSSelectorFromString(@"loadHTMLString:baseURL:");
    Method loadHTMLMethod = class_getInstanceMethod(wkClass, loadHTMLSel);
    if (loadHTMLMethod) {
        __block IMP origLoadHTML = method_getImplementation(loadHTMLMethod);
        IMP newLoadHTML = imp_implementationWithBlock(^id(id _self, NSString *html, NSURL *baseURL) {
            // 直接在 HTML 中注入替换脚本
            NSString *injected = [html stringByAppendingFormat:@"<script>%@</script>", kBrandingReplaceJS];
            NSLog(@"[EYS-Bypass] 注入品牌替换 JS (loadHTMLString)");
            return ((id(*)(id, SEL, NSString*, NSURL*))origLoadHTML)(_self, loadHTMLSel, injected, baseURL);
        });
        method_setImplementation(loadHTMLMethod, newLoadHTML);
    }

    // Hook -[WKWebView loadRequest:]
    SEL loadReqSel = NSSelectorFromString(@"loadRequest:");
    Method loadReqMethod = class_getInstanceMethod(wkClass, loadReqSel);
    if (loadReqMethod) {
        __block IMP origLoadReq = method_getImplementation(loadReqMethod);
        IMP newLoadReq = imp_implementationWithBlock(^id(id _self, NSURLRequest *request) {
            NSLog(@"[EYS-Bypass] 拦截 loadRequest: %@", request.URL);
            // 在 load 完成后注入 JS
            id navigation = ((id(*)(id, SEL, NSURLRequest*))origLoadReq)(_self, loadReqSel, request);
            // 延迟注入 JS 替换
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [EYSLoader eys_injectBrandingJS:_self];
            });
            return navigation;
        });
        method_setImplementation(loadReqMethod, newLoadReq);
    }

    // 也 Hook WKNavigationDelegate 的 didFinishNavigation
    [EYSLoader eys_hookNavigationDelegate];

    NSLog(@"[EYS-Bypass] WKWebView hooks 安装完成");
}

+ (void)eys_injectBrandingJS:(id)webView {
    SEL evalSel = NSSelectorFromString(@"evaluateJavaScript:completionHandler:");
    if ([webView respondsToSelector:evalSel]) {
        void (*evalFunc)(id, SEL, NSString*, id) = (void(*)(id, SEL, NSString*, id))objc_msgSend;
        evalFunc(webView, evalSel, kBrandingReplaceJS, nil);
        NSLog(@"[EYS-Bypass] 品牌替换 JS 已注入 WebView");
    }
}

+ (void)eys_hookNavigationDelegate {
    // 通过 Swizzle WKWebView 的 setNavigationDelegate 来拦截 didFinishNavigation
    Class wkClass = NSClassFromString(@"WKWebView");
    if (!wkClass) return;

    SEL setDelegateSel = NSSelectorFromString(@"setNavigationDelegate:");
    Method setDelegateMethod = class_getInstanceMethod(wkClass, setDelegateSel);
    if (!setDelegateMethod) return;

    __block IMP origSetDelegate = method_getImplementation(setDelegateMethod);
    IMP newSetDelegate = imp_implementationWithBlock(^(id _self, id delegate) {
        // 先设置原始 delegate
        ((void(*)(id, SEL, id))origSetDelegate)(_self, setDelegateSel, delegate);

        // 同时注入一个定时器来持续替换文本
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [EYSLoader eys_injectBrandingJS:_self];
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [EYSLoader eys_injectBrandingJS:_self];
        });
    });
    method_setImplementation(setDelegateMethod, newSetDelegate);
}

+ (void)eys_safeSwizzleSessionConfig {
    Class cls = [NSURLSessionConfiguration class];
    SEL sel = @selector(defaultSessionConfiguration);
    Method method = class_getClassMethod(cls, sel);
    if (!method) return;

    typedef NSURLSessionConfiguration* (*SessionConfigIMP)(id, SEL);
    __block SessionConfigIMP originalImp = (SessionConfigIMP)method_getImplementation(method);
    IMP newImp = imp_implementationWithBlock(^NSURLSessionConfiguration *(id _self) {
        NSURLSessionConfiguration *config = originalImp(_self, sel);
        if (config) {
            NSMutableArray *protocols = [NSMutableArray arrayWithArray:config.protocolClasses];
            if (![protocols containsObject:[EYSBypassProtocol class]]) {
                [protocols insertObject:[EYSBypassProtocol class] atIndex:0];
                config.protocolClasses = protocols;
            }
        }
        return config;
    });
    method_setImplementation(method, newImp);

    SEL sel2 = @selector(ephemeralSessionConfiguration);
    Method method2 = class_getClassMethod(cls, sel2);
    if (method2) {
        typedef NSURLSessionConfiguration* (*SessionConfigIMP2)(id, SEL);
        __block SessionConfigIMP2 originalImp2 = (SessionConfigIMP2)method_getImplementation(method2);
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
