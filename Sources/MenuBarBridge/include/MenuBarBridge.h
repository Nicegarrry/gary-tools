#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
/// Uses cfprefsd's container source, so MenuBarAgent observes the normal per-app switch.
@interface GTNativePreferences : NSObject
+ (BOOL)isAvailable;
+ (nullable id)readTrackedApplicationsInContainer:(NSString *)container;
+ (BOOL)writeTrackedApplications:(id)value inContainer:(NSString *)container;
@end
NS_ASSUME_NONNULL_END
