#import <UIKit/UIKit.h>

#import "AppDelegate.h"
#include "gst_ios_init.h"

int main(int argc, char *argv[])
{
    @autoreleasepool {
        gst_ios_init();
        puts("+++++++++++gstreamer init done");
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
