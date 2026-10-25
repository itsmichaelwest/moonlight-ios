//
//  ControlsPreviewViewController.h
//  Moonlight
//
//  Copyright © 2026 Moonlight Stream. All rights reserved.
//

#import <UIKit/UIKit.h>

#if DEBUG && !TARGET_OS_TV

// Shows the stream screen with a test pattern instead of a host, so the on-screen controls,
// the foldable layout, and the hinge reflection can be tried without a PC. Debug builds only.
@interface ControlsPreviewViewController : UIViewController

// Shows the preview in its own window above the app, so the app's screens can't cover it
+ (void)showInScene:(UIWindowScene*)scene;

@end

#endif
