@interface SMJClientUtility : NSObject

+ (NSString*) versionForBundlePath:(NSString*)bundlePath;
+ (NSString*) versionForBundlePath:(NSString*)bundlePath error:(NSError**)error;

+ (AuthorizationRef) authWithRight:(AuthorizationString)rightName prompt:(NSString*)prompt error:(NSError**)error;

@end
