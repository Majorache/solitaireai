// SABrainClient.m — posts frames to the dashboard and parses the returned gesture.
#import "SAShared.h"
#import <UIKit/UIKit.h>

@implementation SAAction

+ (nullable instancetype)actionFromJSON:(NSDictionary *)json {
  if (![json isKindOfClass:NSDictionary.class]) return nil;
  NSDictionary *a = json[@"action"];
  if (![a isKindOfClass:NSDictionary.class]) return nil;

  SAAction *action = [SAAction new];
  action.type = [a[@"type"] isKindOfClass:NSString.class] ? a[@"type"] : @"none";
  action.start = CGPointMake([a[@"x"] doubleValue], [a[@"y"] doubleValue]);
  action.end = CGPointMake([a[@"x2"] doubleValue], [a[@"y2"] doubleValue]);
  action.duration = [a[@"durationMs"] doubleValue] / 1000.0;
  action.label = [a[@"label"] isKindOfClass:NSString.class] ? a[@"label"] : @"";
  action.game = [json[@"game"] isKindOfClass:NSString.class] ? json[@"game"] : @"unknown";
  action.confidence = [json[@"confidence"] doubleValue];
  action.reasoning = [json[@"reasoning"] isKindOfClass:NSString.class] ? json[@"reasoning"] : @"";
  return action;
}

@end

@implementation SABrainClient {
  NSURL *_endpoint;
  NSString *_token;
  NSURLSession *_session;
}

- (instancetype)initWithServer:(NSURL *)server token:(nullable NSString *)token {
  if ((self = [super init])) {
    _endpoint = [server URLByAppendingPathComponent:@"api/public/analyze"];
    _token = [token copy];
    NSURLSessionConfiguration *cfg = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    // Vision + reasoning can take a while; never abort a generation early.
    cfg.timeoutIntervalForRequest = 120;
    cfg.timeoutIntervalForResource = 180;
    _session = [NSURLSession sessionWithConfiguration:cfg];
  }
  return self;
}

- (nullable SAAction *)analyzePNG:(NSData *)png
                             hint:(nullable NSString *)hint
                            error:(NSError **)error {
  NSMutableDictionary *body = [@{
    @"image": [NSString stringWithFormat:@"data:image/png;base64,%@",
                                         [png base64EncodedStringWithOptions:0]],
    @"device": @"iPhone",
  } mutableCopy];
  if (hint.length) body[@"hint"] = hint;

  NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:_endpoint];
  req.HTTPMethod = @"POST";
  [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
  if (_token.length) [req setValue:_token forHTTPHeaderField:@"x-bot-token"];
  req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

  __block NSData *data = nil;
  __block NSHTTPURLResponse *response = nil;
  __block NSError *taskError = nil;
  dispatch_semaphore_t done = dispatch_semaphore_create(0);

  [[_session dataTaskWithRequest:req
               completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
                 data = d;
                 response = (NSHTTPURLResponse *)r;
                 taskError = e;
                 dispatch_semaphore_signal(done);
               }] resume];
  dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);

  if (taskError) { if (error) *error = taskError; return nil; }

  NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;

  if (response.statusCode != 200) {
    NSString *msg = json[@"error"] ?: [NSString stringWithFormat:@"HTTP %ld",
                                                                 (long)response.statusCode];
    if (error) {
      *error = [NSError errorWithDomain:@"SolitaireAI"
                                   code:response.statusCode
                               userInfo:@{NSLocalizedDescriptionKey: msg}];
    }
    return nil;
  }

  SAAction *action = [SAAction actionFromJSON:json];
  if (!action && error) {
    *error = [NSError errorWithDomain:@"SolitaireAI"
                                 code:-1
                             userInfo:@{NSLocalizedDescriptionKey: @"Malformed response"}];
  }
  return action;
}

@end
