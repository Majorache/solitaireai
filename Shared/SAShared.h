// SAShared.h — types shared between the Solitaire AI app and its
// ReplayKit screen-recorder extension.
//
// A free Apple ID cannot create an App Group, so the two processes do NOT
// share a container. Instead the dashboard is the shared channel: both sides
// talk to /api/public/bot-sync using the same per-device key. No private APIs,
// no special entitlements, nothing that needs a paid developer account.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

/// Dashboard that hosts the AI and the shared state. Compiled in so the
/// recorder extension can reach it without any shared storage.
extern NSString *const SADashboardBaseURL;

/// Stable identifier shared by the app and its extension (same vendor).
NSString *SADeviceKey(void);

/// Reads the whole shared session: config, status, log, pending action.
NSDictionary *_Nullable SASyncFetch(void);

/// Posts a partial update (any of config / status / log / action / clear).
NSDictionary *_Nullable SASyncPost(NSDictionary *body);

/// Appends one timestamped line to the shared activity log.
void SALog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

/// One decision returned by the dashboard AI.
@interface SAAction : NSObject
@property (nonatomic, copy) NSString *type;      // tap | swipe | drag | wait | none
@property (nonatomic, assign) CGPoint start;
@property (nonatomic, assign) CGPoint end;
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, copy) NSString *label;
@property (nonatomic, copy) NSString *game;
@property (nonatomic, assign) double confidence;
@property (nonatomic, copy) NSString *reasoning;
+ (nullable instancetype)actionFromJSON:(NSDictionary *)json;
@end

/// Posts frames to /api/public/analyze on the dashboard.
@interface SABrainClient : NSObject
- (instancetype)initWithServer:(NSURL *)server token:(nullable NSString *)token;
- (nullable SAAction *)analyzePNG:(NSData *)png
                             hint:(nullable NSString *)hint
                            error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
