// SASampleHandler.m — ReplayKit screen-recorder extension.
// iOS hands us live screen frames after the user approves the recording. We
// downscale them, send them to the dashboard AI, and publish the returned
// gesture back to the dashboard, where the jailbreak tap helper picks it up.
// No private APIs and no App Group, so a free Apple ID can sign this.
#import <ReplayKit/ReplayKit.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreImage/CoreImage.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import "SAShared.h"

@interface SASampleHandler : RPBroadcastSampleHandler
@end

@implementation SASampleHandler {
  BOOL _busy;
  NSTimeInterval _lastSent;
  NSTimeInterval _lastConfigFetch;
  NSTimeInterval _lastHeartbeat;
  NSDictionary *_config;
  NSString *_lastMove;
  NSUInteger _sequence;
  dispatch_queue_t _work;
}

- (void)broadcastStartedWithSetupInfo:(NSDictionary<NSString *, NSObject *> *)setupInfo {
  _work = dispatch_queue_create("com.solitaireai.broadcast", DISPATCH_QUEUE_SERIAL);
  _lastSent = 0;
  _sequence = 0;
  _config = @{};
  dispatch_async(_work, ^{
    SASyncPost(@{@"status": @YES});
    SALog(@"broadcast started — screen capture is live");
  });
}

- (void)broadcastPaused {
  dispatch_async(_work, ^{ SASyncPost(@{@"status": @NO}); });
}

- (void)broadcastResumed {
  dispatch_async(_work, ^{ SASyncPost(@{@"status": @YES}); });
}

- (void)broadcastFinished {
  SASyncPost(@{@"status": @NO});
  SASyncPost(@{@"log": @[ @"broadcast stopped" ]});
}

#pragma mark - Frame handling

/// Encode a captured frame as JPEG. ReplayKit hands us bi-planar YUV buffers,
/// which have no single base address, so we go through Core Image instead of
/// poking at raw bytes. Reports the factor mapping sent-image coordinates back
/// to native screen pixels.
- (NSData *)encodedFrameFromPixelBuffer:(CVPixelBufferRef)pixels
                               maxWidth:(CGFloat)maxWidth
                                  scale:(CGFloat *)scaleOut {
  static CIContext *context;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    context = [CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer: @NO}];
  });

  CIImage *image = [CIImage imageWithCVPixelBuffer:pixels];
  if (!image) return nil;

  CGFloat width = (CGFloat)CVPixelBufferGetWidth(pixels);
  CGFloat factor = (maxWidth > 0 && width > maxWidth) ? maxWidth / width : 1.0;
  if (factor < 1.0) {
    image = [image imageByApplyingTransform:CGAffineTransformMakeScale(factor, factor)];
  }
  if (scaleOut) *scaleOut = factor > 0 ? 1.0 / factor : 1.0;

  CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
  NSData *jpeg = [context JPEGRepresentationOfImage:image
                                         colorSpace:cs
                                            options:@{}];
  CGColorSpaceRelease(cs);
  return jpeg;
}

- (void)publishAction:(SAAction *)action scale:(CGFloat)scale {
  NSDictionary *payload = @{
    @"seq": @(++_sequence),
    @"type": action.type ?: @"none",
    @"x1": @(action.start.x * scale),
    @"y1": @(action.start.y * scale),
    @"x2": @(action.end.x * scale),
    @"y2": @(action.end.y * scale),
    @"duration": @(action.duration),
    @"label": action.label ?: @"",
    @"created": @(NSDate.date.timeIntervalSince1970),
  };
  SASyncPost(@{@"action": payload});
}

- (void)processSampleBuffer:(CMSampleBufferRef)sampleBuffer
                   withType:(RPSampleBufferType)sampleBufferType {
  if (sampleBufferType != RPSampleBufferTypeVideo) return;

  NSTimeInterval now = CFAbsoluteTimeGetCurrent();

  // Settings live on the dashboard; refresh them a few times a minute.
  if (now - _lastConfigFetch > 5 && !_busy) {
    _lastConfigFetch = now;
    dispatch_async(_work, ^{
      NSDictionary *session = SASyncFetch();
      NSDictionary *cfg = session[@"config"];
      if ([cfg isKindOfClass:NSDictionary.class]) self->_config = cfg;
    });
  }
  if (now - _lastHeartbeat > 5) {
    _lastHeartbeat = now;
    dispatch_async(_work, ^{ SASyncPost(@{@"status": @YES}); });
  }

  NSDictionary *cfg = _config;
  if (![cfg[@"enabled"] boolValue]) return;
  NSTimeInterval interval = [cfg[@"interval"] doubleValue] ?: 1.5;
  CGFloat sendWidth = [cfg[@"width"] doubleValue] ?: 900.0;
  BOOL dryRun = [cfg[@"dryRun"] boolValue];
  NSString *server = [cfg[@"server"] isKindOfClass:NSString.class] &&
                             [cfg[@"server"] length]
                         ? cfg[@"server"]
                         : SADashboardBaseURL;

  if (_busy || now - _lastSent < interval) return;

  CVPixelBufferRef pixels = CMSampleBufferGetImageBuffer(sampleBuffer);
  if (!pixels) return;

  CGFloat scale = 1.0;
  NSData *png = [self encodedFrameFromPixelBuffer:pixels
                                        maxWidth:sendWidth
                                           scale:&scale];
  if (!png) {
    SALog(@"frame encode failed");
    return;
  }

  _busy = YES;
  _lastSent = now;
  NSString *hint = _lastMove;
  dispatch_async(_work, ^{
    SABrainClient *brain =
        [[SABrainClient alloc] initWithServer:[NSURL URLWithString:server]
                                        token:nil];
    NSError *err = nil;
    SAAction *action = [brain analyzePNG:png hint:hint error:&err];
    if (!action) {
      SALog(@"error: %@", err.localizedDescription);
    } else {
      SALog(@"%@ [%.0f%%] %@", action.game, action.confidence * 100, action.label);
      self->_lastMove = action.label;
      if (dryRun) {
        SALog(@"dry run — move not played");
      } else {
        [self publishAction:action scale:scale];
      }
    }
    self->_busy = NO;
  });
}

@end
