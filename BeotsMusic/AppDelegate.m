//
//  AppDelegate.m
//  SoundCleod
//
//  Created by Márton Salomváry on 2012/12/11.
//  Copyright (c) 2012 Márton Salomváry. All rights reserved.
//

#import "AppConstants.h"
#import "AppDelegate.h"

NSString *const SCNavigateJS = @"history.replaceState(null, null, '%@');$(window).trigger('popstate')";

@interface WebPreferences (WebPreferencesPrivate)
- (void)_setLocalStorageDatabasePath:(NSString *)path;
- (void) setLocalStorageEnabled: (BOOL) localStorageEnabled;
@end

/**
 * http://stackoverflow.com/questions/19797841
 * http://stackoverflow.com/questions/11676017
 */
@interface NSUserNotification (NSUserNotificationPrivate)
- (void)set_identityImage:(NSImage *)image;
@end

@implementation AppDelegate

@synthesize webView;
@synthesize popupController;
@synthesize window;
@synthesize urlPromptController;

id contentView;
id tmpHostWindow;

+ (void)initialize;
{
	if([self class] != [AppDelegate class]) return;
    
	// Register defaults for the whitelist of apps that want to use media keys
	[[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
                                                             [SPMediaKeyTap defaultMediaKeyUserBundleIdentifiers], kMediaKeyUsingBundleIdentifiersDefaultsKey,
                                                             nil]];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    [window setFrameAutosaveName:@"BeotsMusic"];
    
    keyTap = [[SPMediaKeyTap alloc] initWithDelegate:self];
	if([SPMediaKeyTap usesGlobalMediaKeyTap])
		[keyTap startWatchingMediaKeys];
	else
		NSLog(@"Media key monitoring disabled");
    
    mikeyManager = [[BMAppleMikeyManager alloc] init];
    if(mikeyManager) {
        mikeyManager.delegate = self;
        [mikeyManager startListening];
    } else
        NSLog(@"AppDelegate: mikeyManager failed to initalize.");
    
    if(NSClassFromString(@"NSUserNotificationCenter")) {
        defaultCenter = [NSUserNotificationCenter defaultUserNotificationCenter];
        [defaultCenter removeAllDeliveredNotifications];
        defaultCenter.delegate = self;
    }

    NSString *currentVersion = [[NSBundle mainBundle] infoDictionary][@"CFBundleShortVersionString"];
    [webView setApplicationNameForUserAgent:[NSString stringWithFormat:@"BeotsMusic/%@", currentVersion ? currentVersion : @"1.0"]];
    [webView setMainFrameURL:[@"https://" stringByAppendingString:BMHost]];

    WebPreferences* prefs = [WebPreferences standardPreferences];
    
    [prefs setCacheModel:WebCacheModelPrimaryWebBrowser];
    [prefs setPlugInsEnabled:TRUE]; // Flash is required
    
    [prefs _setLocalStorageDatabasePath:@"~/Library/Application Support/BeotsMusic"];
    [prefs setLocalStorageEnabled:YES];
    
    [prefs setJavaScriptEnabled:YES];
    [prefs setPrivateBrowsingEnabled:NO];
    
    [webView setPreferences:prefs];
    
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self
                                                           selector: @selector(receiveSleepNotification:)
                                                               name: NSWorkspaceWillSleepNotification object: NULL];

    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self
                                                           selector: @selector(didPressSpaceBarKey:)
                                                               name: BMApplicationDidPressSpaceBarKey object: NULL];

    [window setCollectionBehavior:NSWindowCollectionBehaviorFullScreenPrimary];
}


- (BOOL)applicationShouldHandleReopen:(NSApplication *)theApplication hasVisibleWindows:(BOOL)flag
{
    if (flag == NO)
    {
        [window makeKeyAndOrderFront:self];
    }

    return YES;
}


- (void)awakeFromNib
{
    [window setDelegate:self];
    [webView setUIDelegate:self];
    [webView setFrameLoadDelegate:self];
    [webView setPolicyDelegate:self];

    [urlPromptController setNavigateDelegate:self];
    
    // stored for adding back later, see windowWillClose
    contentView = [window contentView];
}

- (void)windowDidBecomeKey:(NSNotification *)notification
{
    // restore "hidden" webview, see windowShouldClose
    // (would be better to do it in applicationShouldHandleReopen
    // but that seems to be too early (has no effect)
    if ([window contentView] != contentView) {
        [window setContentView:contentView];
        [webView setHostWindow:nil];
        tmpHostWindow = nil;
    }
}

- (BOOL)windowShouldClose:(NSNotification *)notification
{
    // set temporary hostWindow on WebView and remove it from
    // the closed window to prevent stopping flash plugin
    // (windowWillClose would be better but that doesn't always work)
    // http://stackoverflow.com/questions/5307423/plugin-objects-in-webview-getting-destroyed
    // https://developer.apple.com/library/mac/documentation/Cocoa/Reference/WebKit/Classes/WebView_Class/Reference/Reference.html#//apple_ref/occ/instm/WebView/setHostWindow%3a
    tmpHostWindow = [[NSWindow alloc] init];
    [webView setHostWindow:tmpHostWindow];
    [window setContentView:nil];
    [contentView removeFromSuperview];
    
    return TRUE;
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
    if(mikeyManager && mikeyManager.isListening) {
        [mikeyManager stopListening];
    }
}

- (WebView *)webView:(WebView *)sender createWebViewWithRequest:(NSURLRequest *)request
{
    // request will always be null (probably a bug)
    return [popupController show];
}

// http://stackoverflow.com/questions/7020842/
- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame {
    NSScrollView *mainScrollView = sender.mainFrame.frameView.documentView.enclosingScrollView;
    [mainScrollView setVerticalScrollElasticity:NSScrollElasticityNone];
    [mainScrollView setHorizontalScrollElasticity:NSScrollElasticityNone];
	
	NSURL *url = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"CustomStylesheet" ofType: @"css"]];
	webView.preferences.userStyleSheetLocation = url;
	webView.preferences.userStyleSheetEnabled = YES;

} 

- (void)webView:(WebView *)sender didReceiveTitle:(NSString *)title forFrame:(WebFrame *)frame
{
    if (frame == [webView mainFrame]) {
        [window setTitle:title];
        if ([self isPlaying]) {
            // main.js:17889 "Song: " + i + " by " + n + " | Beats Music"
            title = [title stringByReplacingOccurrencesOfString:@"Song: " withString:@""];
            title = [title stringByReplacingOccurrencesOfString:@" | Beats Music" withString:@""];
            NSArray *info = [title componentsSeparatedByString:@" by "];
            if (info.count == 2 && defaultCenter) {
                // Remove all delivered notifications.
                [defaultCenter removeAllDeliveredNotifications];
                
                // Make a new notification.
                NSUserNotification *notification = [[NSUserNotification alloc] init];
                notification.title = info[0]; // track
                notification.subtitle = info[1]; // artist
                notification.actionButtonTitle = @"Skip"; // Skip button
                [notification setValue:@YES forKey:@"_showsButtons"]; // Force-show buttons
                
                // Check if the OS can handle an image in a notification.
                BOOL canAcceptIdentityImage = [notification respondsToSelector:@selector(set_identityImage:)];
                BOOL canAcceptContentImage = [notification respondsToSelector:@selector(setContentImage:)];
                if(canAcceptIdentityImage || canAcceptContentImage) {
                    // Get the album image URL.
                    NSString *css = [webView stringByEvaluatingJavaScriptFromString:@"$('#t-art').css('background-image')"];
                    if(![css isEqualToString:@""]) {
                        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"url\\s*\\(\\s*['\"]?\\s*(.+?)\\s*['\"]?\\s*\\)"
                                                                                               options:NSRegularExpressionCaseInsensitive
                                                                                                 error:nil];
                        NSTextCheckingResult *result = [regex firstMatchInString:css options:0 range:NSMakeRange(0, [css length])];
                        if(result) {
                            NSRange range = [result rangeAtIndex:1];
                            NSURL *url = [NSURL URLWithString:[css substringWithRange:range]];
                            
                            NSURLRequest *request = [[NSURLRequest alloc] initWithURL:url cachePolicy:0 timeoutInterval:60];
                            [NSURLConnection sendAsynchronousRequest:request
                                                               queue:[NSOperationQueue mainQueue]
                                                   completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
                                                       // Make data an image, put it in the notification.
                                                       if (!connectionError && data) {
                                                           NSImage *image = [[NSImage alloc] initWithData:data];
                                                           
                                                           if(canAcceptIdentityImage) {
                                                               [notification set_identityImage:image];
                                                           } else {
                                                               [notification setContentImage:image];
                                                           }
                                                       }

                                                       // Deliver the notification.
                                                       [defaultCenter deliverNotification:notification];
                                                   }];
                        }
                    }
                }
                // It can't.
                else {
                    // Deliver the notification.
                    [defaultCenter deliverNotification:notification];
                }
            }
        }
    }
}

- (void)webView:(WebView *)sender decidePolicyForNavigationAction:(NSDictionary *)actionInformation
        request:(NSURLRequest *)request frame:(WebFrame *)frame decisionListener:(id)listener
{
    // normal in-frame navigation
    if(frame != [webView mainFrame] || [AppDelegate isBMURL:[request URL]]) {
        // allow loading urls in sub-frames OR when they are sc urls
        [listener use];
    } else {
        [listener ignore];
        // open external links in external browser
        [[NSWorkspace sharedWorkspace] openURL:[actionInformation objectForKey:WebActionOriginalURLKey]];
    }
}

- (void)webView:(WebView *)sender decidePolicyForNewWindowAction:(NSDictionary *)actionInformation request:(NSURLRequest *)request newFrameName:(NSString *)frameName decisionListener:(id < WebPolicyDecisionListener >)listener
{
    // target=_blank or anything scenario
    [listener ignore];
    if([AppDelegate isBMURL:[request URL]]) {
        // open local links in the main frame
        // TODO: maybe maintain a frame stack instead?
        [[webView mainFrame] loadRequest: [NSURLRequest requestWithURL:
                                           [actionInformation objectForKey:WebActionOriginalURLKey]]];
    } else {
        // open external links in external browser
        [[NSWorkspace sharedWorkspace] openURL:[actionInformation objectForKey:WebActionOriginalURLKey]];
    }

}

// based on http://stackoverflow.com/questions/5177640
- (void)webView:(WebView *)sender runOpenPanelForFileButtonWithResultListener:(id < WebOpenPanelResultListener >)resultListener allowMultipleFiles:(BOOL)allowMultipleFiles
{
    // Create the File Open Dialog class.
    NSOpenPanel* openDlg = [NSOpenPanel openPanel];

    // Enable the selection of files in the dialog.
    [openDlg setCanChooseFiles:YES];

    // Enable the selection of directories in the dialog.
    [openDlg setCanChooseDirectories:NO];

    // Allow multiple files
    [openDlg setAllowsMultipleSelection:allowMultipleFiles];

    // Display the dialog.  If the OK button was pressed,
    // process the files.
    if ( [openDlg runModal] == NSOKButton )
    {
		NSArray *urls = [openDlg URLs];
		NSArray *filenames = [urls valueForKey:@"path"];
        // Do something with the filenames.
        [resultListener chooseFilenames:filenames];
    }
}

// stolen from MacGap
- (BOOL)webView:(WebView *)sender runJavaScriptConfirmPanelWithMessage:(NSString *)message initiatedByFrame:(WebFrame *)frame
{
    NSAlert *alert = [[NSAlert alloc] init];
    [alert addButtonWithTitle:@"Yes"];
    [alert addButtonWithTitle:@"No"];
    [alert setMessageText:message];
    [alert setAlertStyle:NSWarningAlertStyle];
    
    if ([alert runModal] == NSAlertFirstButtonReturn)
        return YES;
    else
        return NO;
}

- (void)mediaKeyTap:(SPMediaKeyTap*)keyTap receivedMediaKeyEvent:(NSEvent*)event;
{
	NSAssert([event type] == NSSystemDefined && [event subtype] == SPSystemDefinedEventMediaKeys, @"Unexpected NSEvent in mediaKeyTap:receivedMediaKeyEvent:");
	// here be dragons...
	int keyCode = (([event data1] & 0xFFFF0000) >> 16);
	int keyFlags = ([event data1] & 0x0000FFFF);
	BOOL keyIsPressed = (((keyFlags & 0xFF00) >> 8)) == 0xA;
	//int keyRepeat = (keyFlags & 0x1);
    
	if (keyIsPressed) {
		switch (keyCode) {
			case NX_KEYTYPE_PLAY:
                [self playPause];
				break;
                
			case NX_KEYTYPE_FAST:
				[self next];
                break;
                
			case NX_KEYTYPE_REWIND:
                [self prev];
				break;
			default:
				NSLog(@"Key %d pressed", keyCode);
				break;
		}
	}
}


- (IBAction)restoreWindow:(id)sender
{
    [window makeKeyAndOrderFront:self];
}

- (IBAction)reload:(id)sender
{
    [webView reload:self];
}

- (IBAction)search:(id)sender
{
    [webView stringByEvaluatingJavaScriptFromString:@"$('.menu_item--search').click()"];
}

- (IBAction)love:(id)sender
{
    [webView stringByEvaluatingJavaScriptFromString:@"$('#t-love').click()"];
}

- (IBAction)hate:(id)sender
{
    [webView stringByEvaluatingJavaScriptFromString:@"$('#t-hate').click()"];
}

- (IBAction)addToMyLibrary:(id)sender
{
    [webView stringByEvaluatingJavaScriptFromString:@"$('.transport__context .add_to_my_music').click()"];
}

- (void)next
{
    [webView stringByEvaluatingJavaScriptFromString:@"$('#t-next').click()"];
}

- (void)prev
{
    [webView stringByEvaluatingJavaScriptFromString:@"$('#t-prev').click()"];
}

- (void)playPause
{
    [webView stringByEvaluatingJavaScriptFromString:@"$('#t-play').click()"];
}

- (BOOL)isPlaying
{
    NSString *res = [webView stringByEvaluatingJavaScriptFromString:@"($ && $('.playing')[0] && localStorage && localStorage.player && /\"playing\"\\s*:\\s*true/.test(localStorage.player) && /\"paused\"\\s*:\\s*false/.test(localStorage.player)) ? true : false"];
    return res && [res isEqualToString:@"true"];
}

- (void)navigate:(NSString*)permalink
{
    NSString *js = [NSString stringWithFormat:SCNavigateJS, permalink];
    [webView stringByEvaluatingJavaScriptFromString:js];
}

+ (BOOL)isBMURL:(NSURL *)url
{
    if(url != nil) {
        NSString *host = [url host];
        NSString *path = [url path];
        if([host isEqualToString:BMHost]
           || ([host isEqualToString:BMAccountHost] && ([path isEqualToString:BMLoginPath] || [path isEqualToString:BMLogoutPath]))) {
            return TRUE;
        }
    }
    return FALSE;
}


#pragma mark - NSNotificationCenter Observers

- (void)receiveSleepNotification:(NSNotification*)note
{
    if([self isPlaying]) {
        [self playPause];
    }
}

- (void)didPressSpaceBarKey:(NSNotification *)notification
{
    NSEvent *event = (NSEvent *)notification.object;
    [self.window sendEvent:event];
}

#pragma mark - BMAppleMikeyManagerDelegate

- (void) mikeyDidPlayPause
{
    [self playPause];
}

- (void) mikeyDidNext
{
    [self next];
}

- (void) mikeyDidPrevious
{
    [self prev];
}

#pragma mark - NSUserNotificationCenterDelegate

- (void)userNotificationCenter:(NSUserNotificationCenter *)center
       didActivateNotification:(NSUserNotification *)notification
{
    if(notification.activationType == NSUserNotificationActivationTypeActionButtonClicked) {
        [self next];
    }
}

@end
