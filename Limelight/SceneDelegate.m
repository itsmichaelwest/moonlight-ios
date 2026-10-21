#import "SceneDelegate.h"
#import "AppDelegate.h"
#import "MainFrameViewController.h"

#if !TARGET_OS_TV
@interface MoonlightNavigationController : UINavigationController
@end

@implementation MoonlightNavigationController

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return self.topViewController.supportedInterfaceOrientations;
}

- (UIViewController*)childViewControllerForStatusBarHidden {
    return self.topViewController;
}

- (UIViewController*)childViewControllerForStatusBarStyle {
    return self.topViewController;
}

@end
#endif

@implementation SceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:[UIWindowScene class]]) {
        return;
    }

#if !TARGET_OS_TV
    // Store the launch shortcut before loading the host browser.
    AppDelegate *appDelegate = (AppDelegate *)UIApplication.sharedApplication.delegate;
    appDelegate.pcUuidToLoad = connectionOptions.shortcutItem.userInfo[@"UUID"];
#endif

    UIWindowScene* windowScene = (UIWindowScene*)scene;
    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
#if TARGET_OS_TV
    UIStoryboard* storyboard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
    self.window.rootViewController = [storyboard instantiateInitialViewController];
#else
    MainFrameViewController* browser = [[MainFrameViewController alloc] init];
    self.window.rootViewController = [[MoonlightNavigationController alloc] initWithRootViewController:browser];
#endif
    [self.window makeKeyAndVisible];
}

#if !TARGET_OS_TV
- (void)windowScene:(UIWindowScene *)windowScene performActionForShortcutItem:(UIApplicationShortcutItem *)shortcutItem completionHandler:(void (^)(BOOL succeeded))completionHandler {
    AppDelegate *appDelegate = (AppDelegate *)UIApplication.sharedApplication.delegate;
    appDelegate.pcUuidToLoad = shortcutItem.userInfo[@"UUID"];
    appDelegate.shortcutCompletionHandler = completionHandler;
}
#endif

@end
