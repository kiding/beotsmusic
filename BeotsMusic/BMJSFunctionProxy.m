#import "BMJSFunctionProxy.h"
#import "WebScriptObject+ConvertInContext.h"
#import <WebKit/WebFrame.h>

NSString * const BMJSFunctionScript = @"(function(){var a=function(){a.proxy.exec([].slice.call(arguments))};return a})();";

@interface BMJSFunctionProxy ()
{
    BMJSFunctionBlock _block;
    WebFrame *_webFrame;
}

+ (BOOL)isSelectorExcludedFromWebScript:(SEL)selector;
+ (NSString *)webScriptNameForSelector:(SEL)selector;

- (instancetype)initWithBlock:(BMJSFunctionBlock)block inWebFrame:(WebFrame *)webFrame;
- (void)exec:(WebScriptObject *)arguments;

@end

@implementation BMJSFunctionProxy

+ (WebScriptObject *)scriptObjectWithBlock:(BMJSFunctionBlock)block
                                inWebFrame:(WebFrame *)webFrame
{
    NSAssert(block, @"Function block is not available.");
    NSAssert(webFrame, @"WebFrame is not available.");
    
    WebScriptObject *window = [webFrame windowObject];
    NSAssert(window, @"Failed to initialize window object. Is JavaScript disabled?");

    WebScriptObject *func = [window evaluateWebScript:BMJSFunctionScript];
    NSAssert([func isKindOfClass:[WebScriptObject class]], @"Expected a function but BMJSFunctionScript returned %@", func);
    
    BMJSFunctionProxy *proxy = [[BMJSFunctionProxy alloc] initWithBlock:block inWebFrame:webFrame];
    [func setValue:proxy forKey:@"proxy"];
    
    return func;
}

+ (BOOL)isSelectorExcludedFromWebScript:(SEL)selector
{
    if (selector == @selector(exec:)) {
        return NO;
    }
    return YES;
}

+ (NSString *)webScriptNameForSelector:(SEL)selector
{
    if (selector == @selector(exec:)) {
        return @"exec";
    }
    return nil;
}

- (instancetype)initWithBlock:(BMJSFunctionBlock) block
                   inWebFrame:(WebFrame *) webFrame
{
    if (self = [super init]) {
        _block = block;
        _webFrame = webFrame;
    }
    return self;
}

- (void)exec:(WebScriptObject *)arguments
{
    // Is arguments properly provided?
    NSAssert([arguments isKindOfClass:[WebScriptObject class]], @"arguments must be WebScriptObject.");
    
    // Result.
    NSArray *array = [arguments convertInContext:[_webFrame globalContext]];
    NSAssert([array isKindOfClass:[NSArray class]], @"arguments must be an array.");
    
    // Call the block!
    dispatch_async(dispatch_get_main_queue(), ^{
        _block(array);
    });
}
@end