#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import <WebKit/WebScriptObject.h>

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
 * @param arguments Go to <WebKit/WebScriptObject.h>:91 for argument types.
 * @return Go to <WebKit/WebScriptObject.h>:74 for return types.
 * @exception BMJSException Throws when failed to evaluate the script.
 */
- (id) callMethod: (NSString *) method withArguments: (NSArray *) arguments;

/**
 * @see callMethod:withArguments:
 */
- (id) callMethod: (NSString *) method;

@property (weak) WebFrame *webFrame;

@end