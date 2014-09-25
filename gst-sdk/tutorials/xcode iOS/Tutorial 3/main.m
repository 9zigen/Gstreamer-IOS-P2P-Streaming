#import <UIKit/UIKit.h>

#import "AppDelegate.h"
#include "gst_ios_init.h"

int main(int argc, char *argv[])
{
	@autoreleasepool {

		/* IOS gstreamer init */
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^ {
			       gst_ios_init();
			       }
		);

		return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
	}
}
