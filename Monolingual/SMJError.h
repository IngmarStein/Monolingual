@interface SMJError : NSError

+ (NSError*) errorWithCode:(NSInteger)code message:(NSString*)message;

@end

#define SET_ERROR(code, messageFormat...)\
  if (error != NULL)\
  {\
    NSString* message = [NSString stringWithFormat:messageFormat];\
    NSLog(@"[SMJKit Error] %@", message);\
    *error = [SMJError errorWithCode:code message:message];\
  }\
