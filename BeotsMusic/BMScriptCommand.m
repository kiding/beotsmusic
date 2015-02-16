#import "BMScriptCommand.h"
#import "AppDelegate.h"

@implementation BMScriptCommand

- (id)performDefaultImplementation
{
    NSApplication *application = [NSApplication sharedApplication];
    AppDelegate *delegate = (AppDelegate *)[application delegate];
    
    FourCharCode appleEventCode = [[self commandDescription] appleEventCode];
    switch (appleEventCode) {
        case 'Love': // love
            [delegate love:self];
            break;
        case 'Hate': // hate
            [delegate hate:self];
            break;
        case 'ATML': // add to my library
            [delegate addToMyLibrary:self];
            break;
        case 'NeTr': // next track
            [delegate next];
            break;
        case 'BaTr': // back track
            [delegate prev];
            break;
        case 'Paus': // pause
            [delegate pause];
            break;
        case 'Play': // play
            [delegate play];
            break;
        case 'PlPa': // playpause
            [delegate playPause];
            break;
        default:
            NSLog(@"Unknown Apple Event Code: %@", NSFileTypeForHFSTypeCode(appleEventCode));
    }
    
    return nil;
}

@end
