#import "SAAppDelegate.h"
#import "SARootViewController.h"

@implementation SAAppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
  UINavigationController *nav = [[UINavigationController alloc]
      initWithRootViewController:[SARootViewController new]];
  self.window.rootViewController = nav;
  [self.window makeKeyAndVisible];
  return YES;
}

@end
