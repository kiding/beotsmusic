#import "AppConstants.h"
#import "BMApplication.h"


@implementation BMApplication


- (void)sendEvent:(NSEvent *)theEvent
{
    if (theEvent.type == NSKeyDown &&
        theEvent.keyCode == 49)
    {
        // Handle the space-bar, even if the window is closed
        [[[NSWorkspace sharedWorkspace] notificationCenter] postNotificationName:BMApplicationDidPressSpaceBarKey object:theEvent];
        return;
    }

    [super sendEvent:theEvent];
}


@end
