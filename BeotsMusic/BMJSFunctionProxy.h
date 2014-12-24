#import <Foundation/Foundation.h>

@class WebFrame;
@class WebScriptObject;

typedef void(^BMJSFunctionBlock)(NSArray *arguments);

@interface BMJSFunctionProxy : NSObject

+ (WebScriptObject *)scriptObjectWithBlock:(BMJSFunctionBlock)block inWebFrame:(WebFrame *)webFrame;
- (instancetype)init __unavailable;

@end
