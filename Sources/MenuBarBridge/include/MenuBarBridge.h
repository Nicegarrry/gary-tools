#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Wraps macOS 27's MenuBarClientCore visibility restriction assertion.
/// Hides unpinned third-party menu bar icons immediately and auto-restores on invalidate or exit.
@interface GTAssessmentRestriction : NSObject
+ (BOOL)isAvailable;
+ (NSArray<NSNumber *> *)allSystemItems;
- (void)activateWithAllowedSystemItems:(NSArray<NSNumber *> *)systemItems
              allowedBundleIdentifiers:(NSArray<NSString *> *)bundleIdentifiers
                            completion:(void (^)(NSError * _Nullable error))completion;
- (void)invalidate;
@end

/// Uses cfprefsd's container source for Control Center preference inspection.
@interface GTNativePreferences : NSObject
+ (BOOL)isAvailable;
+ (nullable id)readTrackedApplicationsInContainer:(NSString *)container;
+ (BOOL)writeTrackedApplications:(id)value inContainer:(NSString *)container;
@end

NS_ASSUME_NONNULL_END
