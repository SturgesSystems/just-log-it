#import <Foundation/Foundation.h>

/// Runs `block` and returns any thrown `NSException`, or `nil` on success.
NSException * _Nullable JustLogItCatchException(void (NS_NOESCAPE ^_Nonnull block)(void));
