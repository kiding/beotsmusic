#import "BMJSBridge.h"
#import "WebScriptObject+ConvertInContext.h"

@interface BMJSBridge ()
{
    NSString *_script;
    
    JSGlobalContextRef _globalContext;
    WebScriptObject *_object;
    
    Class _NSBlock;
}
@end

@implementation BMJSBridge

- (instancetype) init
{
    if (self = [super init]) {
        // Load BM.js to _script.
        NSString *name = @"BM.js";
        
        NSBundle *bundle = [NSBundle mainBundle];
        NSString *path = [bundle pathForResource:[name stringByDeletingPathExtension] ofType:[name pathExtension]];

        // No path found after all.
        if (!path) {
            @throw [NSException exceptionWithName:BMJSException
                                           reason:[NSString stringWithFormat:@"Failed to locate %@", name]
                                         userInfo:nil];
        }
        
        // Read the script.
        NSString *script = [[NSString alloc] initWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
        
        // Failed to read the script.
        if (!script) {
            @throw [NSException exceptionWithName:BMJSException
                                           reason:[NSString stringWithFormat:@"Failed to read %@", name]
                                         userInfo:nil];
        }
        
        _script = script;
        
        _NSBlock = NSClassFromString(@"NSBlock");
    }
    return self;
}

- (id) callMethod: (NSString *) method withArguments: (NSArray *) arguments
{
    // Is method properly provided?
    NSAssert([method isKindOfClass:[NSString class]], @"Method name is not provided.");
    
    // Is there _webFrame?
    if (!_webFrame) {
        NSLog(@"No webFrame to call the method %@.", method);
        _object = nil;
        return nil;
    }

    // Get the current context.
    JSGlobalContextRef globalContext = [_webFrame globalContext];
    NSAssert(globalContext, @"Failed to initialize global context. Is JavaScript disabled?");
    
    // Does _object exist in the current global context?
    if (!(_object && _globalContext == globalContext)) {
        // Remember the current context.
        _globalContext = globalContext;
        
        // Evaluate _script and get the object.
        id obj = [[_webFrame windowObject] evaluateWebScript:_script];
        if ([obj isKindOfClass:[WebScriptObject class]]) {
            _object = obj;
        } else {
            @throw [NSException exceptionWithName:BMJSException
                                           reason:[NSString stringWithFormat:@"Failed to evaluate the script, %@ was returned.", obj]
                                         userInfo:nil];
        }
    }

    // Check through arguments.
    if (arguments) {
        NSUInteger count = [arguments count];
        NSMutableArray *mut = [NSMutableArray array];
        for(NSUInteger i=0; i<count; i++) {
            id obj = arguments[i];
            
            // Convert BMJSFunctionBlock to WebScriptObject.
            if ([obj isKindOfClass:_NSBlock]) {
                [mut addObject:[BMJSFunctionProxy scriptObjectWithBlock:obj inWebFrame:_webFrame]];
            } else {
                [mut addObject:obj];
            }
        }
        
        arguments = [NSArray arrayWithArray:mut];
    }
    
    // Call the method, convert, and return.
    id res = [_object callWebScriptMethod:method withArguments:arguments];
    return [res isKindOfClass:[WebScriptObject class]] ? [res convertInContext:_globalContext] : res;
}

- (id) callMethod: (NSString *) method
{
    return [self callMethod:method withArguments:nil];
}

@end
