// SASampleHandler.m — ReplayKit screen-recorder extension.
// iOS hands us live screen frames after the user approves the recording. We
// downscale them, send them to the dashboard AI, and publish the returned
// gesture back to the dashboard, where the jailbreak tap helper picks it up.
// No private APIs and no App Group, so a free Apple ID can sign this.
#import <ReplayKit/ReplayKit.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <ImageIO/ImageIO.h>
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

/// Downscale a captured frame and encode it as PNG. Reports the factor needed
/// to map coordinates in the sent image back to native screen pixels.
- (NSData *)pngFromPixelBuffer:(CVPixelBufferRef)pixels
                      maxWidth:(CGFloat)maxWidth
                         scale:(CGFloat *)scaleOut {
  CVPixelBufferLockBaseAddress(pixels, kCVPixelBufferLock_ReadOnly);
  size_t width = CVPixelBufferGetWidth(pixels);
  size_t height = CVPixelBufferGetHeight(pixels);
  size_t rowBytes = CVPixelBufferGetBytesPerRow(pixels);
  void *base = CVPixelBufferGetBaseAddress(pixels);
  CGImageRef source = NULL;
  if (base && width && height) {
    CFDataRef copy = CFDataCreate(kCFAllocatorDefault, base, rowBytes * height);
    if (copy) {
      CGDataProviderRef provider = CGDataProviderCreateWithCFData(copy);
      CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
      if (provider && cs) {
        source = CGImageCreate(width, height, 8, 32, rowBytes, cs,
                               kCGBitmapByteOrder32Little |
                                   kCGImageAlphaNoneSkipFirst,
                               provider, NULL, NO, kCGRenderingIntentDefault);
      }
      if (cs) CGColorSpaceRelease(cs);
      if (provider) CGDataProviderRelease(provider);
      CFRelease(copy);
    }
  }
  CVPixelBufferUnlockBaseAddress(pixels, kCVPixelBufferLock_ReadOnly);
  if (!source) return nil;

  CGImageRef out = source;
  CGFloat sentWidth = (CGFloat)width;
  if (maxWidth > 0 && sentWidth > maxWidth) {
    size_t nw = (size_t)maxWidth;
    size_t nh = (size_t)((CGFloat)height * (maxWidth / (CGFloat)width));
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL, nw, nh, 8, nw * 4, cs,
                                             kCGImageAlphaPremultipliedFirst |
                                                 kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(cs);
    if (ctx) {
      CGContextSetInterpolationQuality(ctx, kCGInterpolationHigh);
      CGContextDrawImage(ctx, CGRectMake(0, 0, nw, nh), source);
      CGImageRef scaled = CGBitmapContextCreateImage(ctx);
      CGContextRelease(ctx);
      if (scaled) {
        CGImageRelease(source);
        out = scaled;
        sentWidth = (CGFloat)nw;
      }
    }
  }

  if (scaleOut) *scaleOut = sentWidth > 0 ? (CGFloat)width / sentWidth : 1.0;

  NSMutableData *png = [NSMutableData data];
  CGImageDestinationRef dest = CGImageDestinationCreateWithData(
      (__bridge CFMutableDataRef)png, CFSTR("public.png"), 1, NULL);
  BOOL ok = NO;
  if (dest) {
    CGImageDestinationAddImage(dest, out, NULL);
    ok = CGImageDestinationFinalize(dest);
    CFRelease(dest);
  }
  CGImageRelease(out);
  return ok ? png : nil;
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
  NSData *png = [self pngFromPixelBuffer:pixels maxWidth:sendWidth scale:&scale];
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
