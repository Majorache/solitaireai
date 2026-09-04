#import "SAShared.h"
#import <UIKit/UIKit.h>

NSString *const SADashboardBaseURL =
    @"https://project--d2fdc6ce-ede5-4102-aa14-aee9a05c034c-dev.lovable.app";

NSString *SADeviceKey(void) {
  static NSString *key = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    NSString *vendor = UIDevice.currentDevice.identifierForVendor.UUIDString;
    key = vendor.length ? vendor : @"solitaire-ai-default-device";
  });
  return key;
}

static NSURLSession *SASession(void) {
  static NSURLSession *session = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    NSURLSessionConfiguration *cfg =
        NSURLSessionConfiguration.ephemeralSessionConfiguration;
    cfg.timeoutIntervalForRequest = 20;
    cfg.timeoutIntervalForResource = 30;
    session = [NSURLSession sessionWithConfiguration:cfg];
  });
  return session;
}

static NSDictionary *SASend(NSURLRequest *request) {
  __block NSData *data = nil;
  dispatch_semaphore_t done = dispatch_semaphore_create(0);
  [[SASession() dataTaskWithRequest:request
                  completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
                    data = d;
                    dispatch_semaphore_signal(done);
                  }] resume];
  dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
  if (!data) return nil;
  NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data
                                                       options:0
                                                         error:nil];
  return [json isKindOfClass:NSDictionary.class] ? json : nil;
}

NSDictionary *SASyncFetch(void) {
  NSString *url = [NSString
      stringWithFormat:@"%@/api/public/bot-sync?key=%@", SADashboardBaseURL,
                       [SADeviceKey()
                           stringByAddingPercentEncodingWithAllowedCharacters:
                               NSCharacterSet.URLQueryAllowedCharacterSet]];
  NSMutableURLRequest *req =
      [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
  req.HTTPMethod = @"GET";
  return SASend(req);
}

NSDictionary *SASyncPost(NSDictionary *body) {
  NSMutableDictionary *payload = [body mutableCopy];
  payload[@"key"] = SADeviceKey();
  NSMutableURLRequest *req = [NSMutableURLRequest
      requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:
                                                        @"%@/api/public/bot-sync",
                                                        SADashboardBaseURL]]];
  req.HTTPMethod = @"POST";
  [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
  req.HTTPBody = [NSJSONSerialization dataWithJSONObject:payload
                                                 options:0
                                                   error:nil];
  return SASend(req);
}

void SALog(NSString *format, ...) {
  va_list args;
  va_start(args, format);
  NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);

  static NSDateFormatter *fmt = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    fmt = [NSDateFormatter new];
    fmt.dateFormat = @"HH:mm:ss";
  });
  NSString *line = [NSString stringWithFormat:@"%@  %@",
                                              [fmt stringFromDate:NSDate.date],
                                              message];
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    SASyncPost(@{@"log": @[ line ]});
  });
}
