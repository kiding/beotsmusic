//
//  AppDelegate.m
//  SoundCleod
//
//  Created by Márton Salomváry on 2012/12/11.
//  Copyright (c) 2012 Márton Salomváry. All rights reserved.
//

#import "AppConstants.h"
#import "AppDelegate.h"
#import <Sparkle/Sparkle.h>

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
    
    // Detect notification capability.
    capability = BMNotificationCapabilityUnsupported;
    if (NSClassFromString(@"NSUserNotificationCenter")) {
        capability = BMNotificationCapabilityNoImage;

        NSUserNotification *tester = [[NSUserNotification alloc] init];
        if ([tester respondsToSelector:@selector(setContentImage:)]) {
            capability = BMNotificationCapabilityContentImage;
        }
        if ([tester respondsToSelector:@selector(set_identityImage:)]) {
            capability = BMNotificationCapabilityIdentityImage;
        }
        
        // Set AppDelegate to the delegate of NSUserNotificationCenter.
        NSUserNotificationCenter *defaultCenter = [NSUserNotificationCenter defaultUserNotificationCenter];
        [defaultCenter removeAllDeliveredNotifications];
        defaultCenter.delegate = self;
    }
    
    bmJS = [[BMJSBridge alloc] init];
    bmJS.webFrame = [webView mainFrame];

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
}

- (BOOL)windowShouldClose:(NSNotification *)notification
{
    // Hide the window.
    [window orderOut:self];
    return NO;
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
    if(mikeyManager && mikeyManager.isListening) {
        [mikeyManager stopListening];
    }

    // Renew tokens right before the app terminates.
    if ((__bridge CFBooleanRef)[bmJS callMethod:@"refreshTokens"] == kCFBooleanTrue) {
        NSLog(@"New tokens are saved! You won't need to login again in 24 hours.");
    } else {
        NSLog(@"Failed to refresh tokens. You probably will need to login again.");
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
}

- (void)webView:(WebView *)sender didReceiveTitle:(NSString *)title forFrame:(WebFrame *)frame
{
    if (frame == [webView mainFrame]) {
        [window setTitle:title];
    }
}

- (void)webView:(WebView *)sender didClearWindowObject:(WebScriptObject *)windowObject forFrame:(WebFrame *)frame
{
    if (frame == [webView mainFrame]) {
        NSURL *url = [[[frame dataSource] request] URL];
        
        // Listen for new tokens right after window object is ready.
        [bmJS callMethod:@"listenForTokens"];
        
        // Check if frame is at BMHost, the web player.
        if ([[url host] isEqualToString:BMHost]) {
            // If the OS supports NSUserNotificationCenter,
            if (capability > BMNotificationCapabilityUnsupported) {
                // Listen for new current track information.
                __weak AppDelegate *weakSelf = self;
                [bmJS callMethod:@"listenForCurrentTrack" withArguments:@[^(NSArray *arguments) {
                    NSAssert(arguments && [arguments count], @"No argument given.");
                    
                    NSDictionary *track = arguments[0];
                    NSAssert([track isKindOfClass:[NSDictionary class]], @"Track information is not NSDictionary.");
                    
                    NSString *title = track[@"title"];
                    NSString *artist = track[@"artist"];
                    NSString *art = track[@"art"];
                    NSAssert(title && [title length] && artist && [artist length], @"Required fields are empty.");
                    
                    [weakSelf deliverNotificationWithTitle:title subtitle:artist image:[NSURL URLWithString:art]];
                }]];
            }
            
            // Try to play without Flash.
            if (!didFailPlayingWithoutFlash) {
                [bmJS callMethod:@"playWithoutFlash" withArguments:@[^(NSArray *arguments) {
                    NSAssert(arguments && [arguments count], @"No argument given.");

                    // Did it already fail once?
                    if (didFailPlayingWithoutFlash) {
                        return;
                    } else {
                        didFailPlayingWithoutFlash = YES;
                    }

                    // Try to work out the Flash fallback.
                    CFBooleanRef isFlashInstalled = (__bridge CFBooleanRef)arguments[0];
                    NSAssert(isFlashInstalled == kCFBooleanTrue || isFlashInstalled == kCFBooleanFalse, @"isFlashInstalled is not true nor false.");
                    
                    NSString *title = @"There was an error loading the track.";
                    NSString *msgFormat = @"The workaround to avoid Beats Music's requirement of Flash has failed.\n\n%@";
                    
                    // If Flash is installed, simply reload the page.
                    if (isFlashInstalled == kCFBooleanTrue) {
                        [frame reload];
                        
                        NSBeginCriticalAlertSheet(title, @"Close", NULL, NULL, window, self, NULL, NULL, NULL, msgFormat, @"Flash Player will be loaded from now on.");
                    }
                    // If not, ask users to download and install it, and wait for it to be installed.
                    else {
                        NSBeginCriticalAlertSheet(title, @"Install", @"Cancel", NULL, window, self, NULL, @selector(sheetDidDismiss:returnCode:contextInfo:), @"installFlash", msgFormat, @"Please install Adobe Flash Player for Safari to play music.");
                    }
                }]];
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
                
            case NX_KEYTYPE_PREVIOUS:
                [self prev];
                break;
                
            case NX_KEYTYPE_NEXT:
                [self next];
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
    [bmJS callMethod:@"search"];
}

- (IBAction)love:(id)sender
{
    [bmJS callMethod:@"love"];
}

- (IBAction)hate:(id)sender
{
    [bmJS callMethod:@"hate"];
}

- (IBAction)addToMyLibrary:(id)sender
{
    if ((__bridge CFBooleanRef)[bmJS callMethod:@"addToMyLibrary"] != kCFBooleanTrue) {
        NSBeginCriticalAlertSheet(@"There was an error adding the current track to your library.", @"Retry", @"Cancel", NULL, window, self, NULL, @selector(sheetDidDismiss:returnCode:contextInfo:), @"addToMyLibrary", @"Please try again.");
    }
}

- (IBAction)deleteCookies:(id)sender
{
    // User clicked "Delete Cookies..." menu item.
    if (sender) {
        NSBeginCriticalAlertSheet(@"Delete Cookies?", @"Proceed", @"Cancel", NULL, window, self, NULL, @selector(sheetDidDismiss:returnCode:contextInfo:), @"deleteCookies", @"This will clear cookies for Beats Music websites. Proceed if you're having trouble logging in.\nRemoving cookies will affect Safari too.");
    }
    // After the alert sheet.
    else {
        // Delete cookies for http, https and BMHost, BMAccountHost.
        NSHTTPCookieStorage *sharedStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
        for(NSString *protocol in @[@"http", @"https"]) {
            for(NSString *domain in @[BMHost, BMAccountHost]) {
                NSArray *cookies = [sharedStorage cookiesForURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@://%@", protocol, domain]]];
                
                for(NSHTTPCookie *cookie in cookies) {
                    [sharedStorage deleteCookie:cookie];
                }
            }
        }
        
        // Go back to the main page.
        [webView setMainFrameURL:[@"https://" stringByAppendingString:BMHost]];
        [webView reload:self];
    }
}

- (void)waitForFlash
{
    // Is Flash installed?
    CFBooleanRef isFlashInstalled = (__bridge CFBooleanRef)[bmJS callMethod:@"isFlashInstalled" withArguments:@[@YES]]; // Refresh!
    NSAssert(isFlashInstalled == kCFBooleanTrue || isFlashInstalled == kCFBooleanFalse, @"isFlashInstalled is not true nor false.");

    // Yes, simply reload the page.
    if (isFlashInstalled == kCFBooleanTrue) {
        [webView reload:nil];
    }
    // No, alert.
    else {
        NSBeginCriticalAlertSheet(@"Flash plugin could not be found.", @"Retry", @"Cancel", NULL, window, self, NULL, @selector(sheetDidDismiss:returnCode:contextInfo:), @"waitForFlash", @"Please install Adobe Flash Player for Safari and try again.");
    }
}

- (void)deliverNotificationWithTitle:(NSString *)title subtitle:(NSString *)subtitle image:(NSURL *)imageURL
{
    // Unsupported.
    if (capability <= BMNotificationCapabilityUnsupported) {
        return;
    }
    
    // Make a new notification.
    NSUserNotification *notification = [[NSUserNotification alloc] init];
    notification.title = title;
    notification.subtitle = subtitle;
    notification.actionButtonTitle = @"Skip"; // Skip button
    [notification setValue:@YES forKey:@"_showsButtons"]; // Force-show buttons

    // Is imageURL provided and the OS capable?
    if (imageURL && capability > BMNotificationCapabilityNoImage) {
        NSURLRequest *request = [[NSURLRequest alloc] initWithURL:imageURL cachePolicy:0 timeoutInterval:60];
        [NSURLConnection sendAsynchronousRequest:request
                                           queue:[NSOperationQueue mainQueue]
                               completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
                                   // Make data an image, put it in the notification.
                                   if (!connectionError && data) {
                                       NSImage *image = [[NSImage alloc] initWithData:data];
                                       
                                       if (capability == BMNotificationCapabilityIdentityImage) {
                                           [notification set_identityImage:image];
                                       } else if (capability == BMNotificationCapabilityContentImage) {
                                           [notification setContentImage:image];
                                       }
                                   }
                                   
                                   // Deliver the notification.
                                   NSUserNotificationCenter *defaultCenter = [NSUserNotificationCenter defaultUserNotificationCenter];
                                   [defaultCenter removeAllDeliveredNotifications];
                                   [defaultCenter deliverNotification:notification];
                               }];

    }
    // No, deliver the notification right away.
    else {
        NSUserNotificationCenter *defaultCenter = [NSUserNotificationCenter defaultUserNotificationCenter];
        [defaultCenter removeAllDeliveredNotifications];
        [defaultCenter deliverNotification:notification];
    }
}

- (void)next
{
    [bmJS callMethod:@"next"];
}

- (void)prev
{
    [bmJS callMethod:@"prev"];
}

- (void)playPause
{
    [bmJS callMethod:@"playPause"];
}

- (BOOL)isPlaying
{
    return (__bridge CFBooleanRef)[bmJS callMethod:@"isPlaying"] == kCFBooleanTrue;;
}

- (void)navigate:(NSString*)permalink
{
    [bmJS callMethod:@"navigateTo" withArguments:@[permalink]];
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

#pragma mark - NSBeginAlertSheet Modal Delegate

- (void) sheetDidDismiss:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
    NSString *method = (__bridge NSString *)(contextInfo);
    
    if ([method isEqualToString:@"addToMyLibrary"] && returnCode == NSAlertDefaultReturn) {
        [self addToMyLibrary:nil];
    }
    else if ([method isEqualToString:@"deleteCookies"] && returnCode == NSAlertDefaultReturn) {
        [self deleteCookies:nil];
    }
    else if ([method isEqualToString:@"installFlash"] && returnCode == NSAlertDefaultReturn) {
        // Open the download page.
        [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://get.adobe.com/flashplayer/"]];
        
        // Wait for Flash to be installed.
        [self performSelector:@selector(waitForFlash) withObject:nil afterDelay:10];
    }
    else if ([method isEqualToString:@"waitForFlash"] && returnCode == NSAlertDefaultReturn) {
        [self waitForFlash];
    }
}

@end
