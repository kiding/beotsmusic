#import "BMJSBridge.h"

@interface BMJSBridge ()
{
    NSString *_script;
    
    JSGlobalContextRef _globalContext;
    WebScriptObject *_object;
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

    // Call the method and return.
    return [_object callWebScriptMethod:method withArguments:arguments];
}

- (id) callMethod: (NSString *) method
{
    return [self callMethod:method withArguments:nil];
}

@end
