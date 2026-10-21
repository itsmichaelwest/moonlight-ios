#import "SceneDelegate.h"
#import "AppDelegate.h"

@implementation SceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:[UIWindowScene class]]) {
        return;
    }

#if !TARGET_OS_TV
    // Store the launch shortcut before the storyboard loads the host browser.
    AppDelegate *appDelegate = (AppDelegate *)UIApplication.sharedApplication.delegate;
    appDelegate.pcUuidToLoad = connectionOptions.shortcutItem.userInfo[@"UUID"];
#endif

    UIWindowScene *windowScene = (UIWindowScene *)scene;
#if TARGET_OS_TV
    NSString *storyboardName = @"Main";
#else
    NSString *storyboardName = windowScene.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPad ? @"iPad" : @"iPhone";
#endif
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:storyboardName bundle:nil];
    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
    self.window.rootViewController = [storyboard instantiateInitialViewController];
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
