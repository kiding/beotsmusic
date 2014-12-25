#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import <WebKit/WebScriptObject.h>
#import "BMJSFunctionProxy.h"

NSString * const BMJSException;

/**
 * @warning Currently this class only loads BM.js.
 */
@interface BMJSBridge : NSObject

/**
 * @exception BMJSException Throws when failed to load BM.js.
 */
- (instancetype) init;

/**
 * @param method Name of the method to be called.
 * @param arguments The array accepts the types specified in <WebKit/WebScriptObject.h>:91.
 * Also, BMJSFunctionBlock => function object.
 * @return The object follows the types specified in <WebKit/WebScriptObject.h>:74.
 * Also, array object => NSArray, object without its own method => NSDictionary.
 * @exception BMJSException Throws when failed to evaluate the script.
 */
- (id) callMethod: (NSString *) method withArguments: (NSArray *) arguments;

/**
 * @see callMethod:withArguments:
 */
- (id) callMethod: (NSString *) method;

@property (weak) WebFrame *webFrame;

@end