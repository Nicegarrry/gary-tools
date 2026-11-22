#import "MenuBarBridge.h"
#import <dlfcn.h>

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
