typedef enum {
  
  // A failure when referencing a bundle that doesn't exist (or bad perms)
  SMJErrorCodeBundleNotFound = 1000,
  // A failure when trying to get the SecStaticCode for a bundle, but it is unsigned
  SMJErrorCodeUnsignedBundle = 1001,
  // Unknown failure when calling SecStaticCodeCreateWithPath
  SMJErrorCodeBadBundleSecurity = 1002,
  // Unknown failure when calling SecCodeCopySigningInformation for a bundle
  SMJErrorCodeBadBundleCodeSigningDictionary = 1003,
  
  // Failure when calling SMJobBless
  SMJErrorUnableToBless = 1010,
  
  // Authorization was denied by the system when asking a user for authorization
  SMJAuthorizationDenied = 1020,
  // The user canceled a prompt for authorization
  SMJAuthorizationCanceled = 1021,
  // Unable to prompt the user (interaction disallowed)
  SMJAuthorizationInteractionNotAllowed = 1022,
  // Unknown failure when prompting the user for authorization
  SMJAuthorizationFailed = 1023,
  
} SMJErrorCode;
