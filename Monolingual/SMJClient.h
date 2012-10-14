#import <Foundation/NSObject.h>
#import <Foundation/NSError.h>

// An abstract superclass for system-level launchd helper jobs
@interface SMJClient : NSObject

// Abstract Interface
+ (NSString*) serviceIdentifier;

// Standard Interface
+ (NSString*) bundledVersion;
+ (NSString*) installedVersion;
+ (BOOL) isLatestVersionInstalled;

+ (BOOL) installWithPrompt:(NSString*)prompt error:(NSError **)error;
+ (BOOL) uninstallWithPrompt:(NSString*)prompt error:(NSError **)error;

// Diagnostics

// Checks your app, the service and the environment for any potential problems.
// 
// Returns an array of `NSError`s if any are found, `nil` otherwise.
+ (NSArray*) checkForProblems;

@end
