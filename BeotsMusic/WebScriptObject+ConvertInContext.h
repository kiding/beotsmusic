#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import <JavaScriptCore/JavaScriptCore.h>

@interface WebScriptObject (ConvertInContext)

- (id)valueForUndefinedKey:(NSString *)key;
- (id)convertInContext:(JSContextRef)context;

@end
