//
//  AppDelegate.h
//  SoundCleod
//
//  Created by Márton Salomváry on 2012/12/11.
//  Copyright (c) 2012 Márton Salomváry. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import "PopupController.h"
#import "UrlPromptController.h"
#import "../SPMediaKeyTap/SPMediaKeyTap.h"
#import "../DHSwipeWebView/DHSwipeWebView.h"
#import "BMAppleMikeyManager.h"
#import "BMJSBridge.h"
#import "AppDelegate.h"

typedef enum : NSUInteger {
    BMNotificationCapabilityUnsupported = 0,
    BMNotificationCapabilityNoImage,
    BMNotificationCapabilityContentImage,
    BMNotificationCapabilityIdentityImage
} BMNotificationCapability;

@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate, BMAppleMikeyManagerDelegate, NSUserNotificationCenterDelegate> {
    SPMediaKeyTap *keyTap;
    BMAppleMikeyManager *mikeyManager;
    BMNotificationCapability capability;
    BMJSBridge *bmJS;
    BOOL didFailPlayingWithoutFlash;
}

@property (assign) IBOutlet NSWindow *window;
@property (weak) IBOutlet DHSwipeWebView *webView;
@property (weak) IBOutlet PopupController *popupController;
@property (weak) IBOutlet UrlPromptController *urlPromptController;

+ (BOOL)isBMURL:(NSURL *)url;
+ (void)initialize;
- (void)awakeFromNib;

#pragma mark - NSApplicationDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification;
- (BOOL)applicationShouldHandleReopen:(NSApplication *)theApplication hasVisibleWindows:(BOOL)flag;
- (BOOL)windowShouldClose:(NSNotification *)notification;
- (void)applicationWillTerminate:(NSNotification *)aNotification;

#pragma mark - WebFrameLoadDelegate

- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame;
- (void)webView:(WebView *)sender didReceiveTitle:(NSString *)title forFrame:(WebFrame *)frame;
- (void)webView:(WebView *)sender didClearWindowObject:(WebScriptObject *)windowObject forFrame:(WebFrame *)frame;
- (void)deliverNotificationWithTitle:(NSString *)title subtitle:(NSString *)subtitle image:(NSURL *)imageURL;

#pragma mark - WebPolicyDelegate

- (void)webView:(WebView *)sender decidePolicyForNavigationAction:(NSDictionary *)actionInformation
        request:(NSURLRequest *)request frame:(WebFrame *)frame decisionListener:(id)listener;
- (void)webView:(WebView *)webView decidePolicyForNewWindowAction:(NSDictionary *)actionInformation request:(NSURLRequest *)request newFrameName:(NSString *)frameName decisionListener:(id < WebPolicyDecisionListener >)listener;

#pragma mark - WebUIDelegate

- (WebView *)webView:(WebView *)sender createWebViewWithRequest:(NSURLRequest *)request;
- (void)webView:(WebView *)sender runOpenPanelForFileButtonWithResultListener:(id < WebOpenPanelResultListener >)resultListener allowMultipleFiles:(BOOL)allowMultipleFiles;
- (BOOL)webView:(WebView *)sender runJavaScriptConfirmPanelWithMessage:(NSString *)message initiatedByFrame:(WebFrame *)frame;

#pragma mark - SPMediaKeyTapDelegate

- (void)mediaKeyTap:(SPMediaKeyTap*)keyTap receivedMediaKeyEvent:(NSEvent*)event;

#pragma mark - User Actions

- (void)next;
- (void)prev;
- (void)pause;
- (void)play;
- (BOOL)isPlaying;
- (void)playPause;
- (void)navigate:(NSString*)permalink;
- (IBAction)deleteCookies:(id)sender;
- (void)deleteCookies;
- (IBAction)search:(id)sender;
- (IBAction)love:(id)sender;
- (IBAction)hate:(id)sender;
- (IBAction)addToMyLibrary:(id)sender;
- (IBAction)reload:(id)sender;
- (IBAction)restoreWindow:(id)sender;

#pragma mark - NSNotificationCenter Observers

- (void)receiveSleepNotification:(NSNotification*)note;
- (void)didPressSpaceBarKey:(NSNotification *)notification;

#pragma mark - BMAppleMikeyManagerDelegate

- (void)mikeyDidPlayPause;
- (void)mikeyDidNext;
- (void)mikeyDidPrevious;

#pragma mark - NSUserNotificationCenterDelegate

- (void)userNotificationCenter:(NSUserNotificationCenter *)center didActivateNotification:(NSUserNotification *)notification;
- (BOOL)userNotificationCenter:(NSUserNotificationCenter *)center shouldActivateForNotification:(NSUserNotification *)notification;

#pragma mark - NSBeginAlertSheet Modal Delegate

- (void)sheetDidDismiss:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
- (void)waitForFlash;
@end
