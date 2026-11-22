#import "MenuBarBridge.h"
#import <dlfcn.h>

@interface MBAssessmentModeConfiguration : NSObject
- (instancetype)initWithAllowedSystemItems:(NSArray<NSNumber *> *)systemItems
                  allowedBundleIdentifiers:(NSArray<NSString *> *)bundleIdentifiers;
@end

@interface MBAssessmentModeAssertion : NSObject
- (void)activateWithConfiguration:(id)configuration
                completionHandler:(void (^)(NSError * _Nullable error))completionHandler;
- (void)invalidate;
@end

static Class GTAssessmentConfigClass = Nil;
static Class GTAssessmentAssertionClass = Nil;

static void GTLoadMenuBarClientCore(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dlopen("/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore", RTLD_LAZY);
        GTAssessmentConfigClass = NSClassFromString(@"MBAssessmentModeConfiguration");
        GTAssessmentAssertionClass = NSClassFromString(@"MBAssessmentModeAssertion");
    });
}

@implementation GTAssessmentRestriction {
    id _assertion;
    BOOL _invalidated;
}

+ (BOOL)isAvailable {
    GTLoadMenuBarClientCore();
    return GTAssessmentConfigClass != Nil && GTAssessmentAssertionClass != Nil;
}

+ (NSArray<NSNumber *> *)allSystemItems {
    // Official MBSystemItemIdentifier cases on macOS 27:
    // 0 battery, 1 bluetooth, 2 clock, 3 displays, 4 keyboard,
    // 5 volume, 6 wifi, 7 screenMirroring, 8 primaryBentoBox (Control Center)
    return @[@0, @1, @2, @3, @4, @5, @6, @7, @8];
}

- (void)activateWithAllowedSystemItems:(NSArray<NSNumber *> *)systemItems
              allowedBundleIdentifiers:(NSArray<NSString *> *)bundleIdentifiers
                            completion:(void (^)(NSError * _Nullable error))completion {
    GTLoadMenuBarClientCore();
    if (![GTAssessmentRestriction isAvailable]) {
        if (completion) {
            NSError *err = [NSError errorWithDomain:@"local.nicegary.GaryTools.MenuBar"
                                               code:1
                                           userInfo:@{NSLocalizedDescriptionKey: @"Menu bar visibility control is unavailable on this macOS version."}];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(err); });
        }
        return;
    }
    @try {
        id config = [[GTAssessmentConfigClass alloc]
            initWithAllowedSystemItems:(systemItems ?: @[])
              allowedBundleIdentifiers:(bundleIdentifiers ?: @[])];
        id assertion = [[GTAssessmentAssertionClass alloc] init];
        _assertion = assertion;
        _invalidated = NO;
        [assertion activateWithConfiguration:config completionHandler:^(NSError * _Nullable error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(error);
            });
        }];
    } @catch (NSException *exception) {
        _assertion = nil;
        if (completion) {
            NSString *msg = exception.reason ?: @"Menu bar visibility request threw an unexpected exception.";
            NSError *err = [NSError errorWithDomain:@"local.nicegary.GaryTools.MenuBar"
                                               code:2
                                           userInfo:@{NSLocalizedDescriptionKey: msg}];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(err); });
        }
    }
}

- (void)invalidate {
    if (_invalidated) return;
    _invalidated = YES;
    id assertion = _assertion;
    _assertion = nil;
    if (!assertion) return;
    @try {
        [assertion invalidate];
    } @catch (NSException *exception) {
        // Ignore teardown exceptions on invalidation
    }
}

- (void)dealloc {
    [self invalidate];
}

@end

// MARK: - Control Center container preferences helper

typedef CFPropertyListRef (*GTCopyContainerValue)(CFStringRef, CFStringRef, CFStringRef, CFStringRef, CFStringRef);
typedef void (*GTSetContainerValue)(CFStringRef, CFPropertyListRef, CFStringRef, CFStringRef, CFStringRef, CFStringRef);
typedef Boolean (*GTSyncContainer)(CFStringRef, CFStringRef, CFStringRef, CFStringRef);
static GTCopyContainerValue GTContainerCopy;
static GTSetContainerValue GTContainerSet;
static GTSyncContainer GTContainerSync;

@implementation GTNativePreferences
+ (BOOL)isAvailable {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *handle = dlopen("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", RTLD_LAZY);
        if (handle) {
            GTContainerCopy = (GTCopyContainerValue)dlsym(handle, "_CFPreferencesCopyValueWithContainer");
            GTContainerSet = (GTSetContainerValue)dlsym(handle, "_CFPreferencesSetValueWithContainer");
            GTContainerSync = (GTSyncContainer)dlsym(handle, "_CFPreferencesSynchronizeWithContainer");
        }
    });
    return GTContainerCopy && GTContainerSet && GTContainerSync;
}
+ (id)readTrackedApplicationsInContainer:(NSString *)container {
    if (![self isAvailable]) return nil;
    @try {
        GTContainerSync(CFSTR("group.com.apple.controlcenter"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost, (__bridge CFStringRef)container);
        return CFBridgingRelease(GTContainerCopy(CFSTR("trackedApplications"), CFSTR("group.com.apple.controlcenter"),
            kCFPreferencesCurrentUser, kCFPreferencesAnyHost, (__bridge CFStringRef)container));
    } @catch (NSException *exception) { return nil; }
}
+ (BOOL)writeTrackedApplications:(id)value inContainer:(NSString *)container {
    if (![self isAvailable]) return NO;
    @try {
        GTContainerSet(CFSTR("trackedApplications"), (__bridge CFPropertyListRef)value, CFSTR("group.com.apple.controlcenter"),
            kCFPreferencesCurrentUser, kCFPreferencesAnyHost, (__bridge CFStringRef)container);
        return GTContainerSync(CFSTR("group.com.apple.controlcenter"), kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost, (__bridge CFStringRef)container);
    } @catch (NSException *exception) { return NO; }
}
@end
