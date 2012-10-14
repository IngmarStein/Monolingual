#import "SMJError.h"

@implementation SMJError

+ (NSError*) errorWithCode:(NSInteger)code message:(NSString*)message
{
  NSDictionary* userInfo = [NSDictionary dictionaryWithObjectsAndKeys:message, NSLocalizedDescriptionKey, nil];
  
  return [self errorWithDomain:@"SMJobKit" code:code userInfo:userInfo];
}

@end
