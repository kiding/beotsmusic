#import "WebScriptObject+ConvertInContext.h"

@implementation WebScriptObject (ConvertInContext)

- (id)valueForUndefinedKey:(NSString *)key
{
    return [WebUndefined undefined];
}

- (id)convertInContext:(JSContextRef)context
{
    // TODO: Circular Objects
    
    // Is context properly provided?
    NSAssert(context, @"JSContextRef must be provided.");

    // JSObject here! - kJSTypeObject.
    JSObjectRef object = [self JSObject];
    
    // window is already cleared.
    if (!object) {
        return self;
    }
    
    // Is it a function in this context?
    if (JSObjectIsFunction(context, object)) {
        return self;
    }
    
    // Is it an array in this context?
    // http://www.opensource.apple.com/source/JavaScriptCore/JavaScriptCore-576/API/tests/testapi.c
    JSObjectRef globalObject = JSContextGetGlobalObject(context);
    
    JSStringRef arrayString = JSStringCreateWithUTF8CString("Array");
    JSObjectRef Array = JSValueToObject(context, JSObjectGetProperty(context, globalObject, arrayString, NULL), NULL);
    NSAssert(Array, @"Failed to find Array constructor.");
    JSStringRelease(arrayString);
    BOOL isArray = JSValueIsInstanceOfConstructor(context, (JSValueRef)object, Array, NULL);
    BOOL isObject = isArray;
    
    // Even if it's not an array, is it still an object in this context?
    if (!isArray) {
        JSStringRef objectString = JSStringCreateWithUTF8CString("Object");
        JSObjectRef Object = JSValueToObject(context, JSObjectGetProperty(context, globalObject, objectString, NULL), NULL);
        NSAssert(Object, @"Failed to find Object constructor.");
        JSStringRelease(objectString);
        isObject = JSValueIsInstanceOfConstructor(context, (JSValueRef)object, Object, NULL);
    }
    
    // It's an array in this context!
    if (isArray) {
        // Prepare the enumeration.
        NSNumber *length = [self valueForKey:@"length"];
        int l = [length intValue];
        NSMutableArray *array = [NSMutableArray array];
        
        // Enumerate!
        for(int i=0; i<l; i++) {
            id value = [self webScriptValueAtIndex:i];
            
            // The value is WebScriptObject.
            if ([value isKindOfClass:[WebScriptObject class]]) {
                // Convert recursively.
                [array addObject:[value convertInContext:context]];
            }
            // The value is nil(null.)
            else if (value == nil) {
                // Add NSNull instead.
                [array addObject:[NSNull null]];
            }
            // Everything else.
            else {
                // Add it as-is.
                [array addObject:value];
            }
        }

        return [NSArray arrayWithArray:array];
    }
    // It's a non-array object in this context!
    else if (isObject) {
        // Prepare the loop.
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        BOOL hasMethod = NO;
        
        // Get all the properties.
        JSPropertyNameArrayRef props = JSObjectCopyPropertyNames(context, object);
        size_t length = JSPropertyNameArrayGetCount(props);
        if (length > 0) {
            // Loop through the properties. Stop when one of them is a method.
            for(size_t i=0; !hasMethod && i<length; i++) {
                CFStringRef cfKey = JSStringCopyCFString(NULL, JSPropertyNameArrayGetNameAtIndex(props, i));
                NSString *nsKey = (__bridge NSString *)cfKey;
                id value = [self valueForKey:nsKey];
                
                // The value is WebScriptObject.
                if ([value isKindOfClass:[WebScriptObject class]]) {
                    // Is it a method for obj?
                    if (JSObjectIsFunction(context, [value JSObject])) {
                        hasMethod = YES;
                    }
                    // No, convert recursively.
                    else {
                        [dict setObject:[value convertInContext:context] forKey:nsKey];
                    }
                }
                // The value is nil(null)
                else if (value == nil) {
                    // Add NSNull instead.
                    [dict setObject:[NSNull null] forKey:nsKey];
                }
                // Everything else.
                else {
                    // Add it as-is.
                    [dict setObject:value forKey:nsKey];
                }
                
                CFRelease(cfKey);
            }
        }
        JSPropertyNameArrayRelease(props);
        
        // If obj has one or more its own method, return self as-is.
        return hasMethod ? self : [NSDictionary dictionaryWithDictionary:dict];
    }
    // This object can not be converted in this context.
    else {
        return self;
    }
}

@end
