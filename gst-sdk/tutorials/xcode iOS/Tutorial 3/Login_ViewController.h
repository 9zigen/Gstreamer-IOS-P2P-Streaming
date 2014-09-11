//
//  Login_ViewController.h
//  GStreamer iOS Tutorials
//
//  Created by cxphong on 9/4/14.
//
//

#import <UIKit/UIKit.h>

@interface Login_ViewController : UIViewController {
    __weak IBOutlet UITextField *usernameTF;
    __weak IBOutlet UITextField *passwordTF;
    __weak IBOutlet UIButton *loginBT;
}

- (IBAction)login_to_server:(id)sender;
- (IBAction)textFieldReturn:(id)sender;

@end
