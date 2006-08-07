/*
 *  VersionCheck.m
 *  Copyright (C) 2001, 2002  Joshua Schrier (jschrier@mac.com),
 *  2004-2006 Ingmar Stein
 *  Released under the GNU GPL.  For more information, see the header file.
 */

#import "VersionCheck.h"
#include <SystemConfiguration/SystemConfiguration.h>

static CFPropertyListRef createPropertyListFromURL(CFURLRef url, u_int32_t mutability, CFPropertyListFormat *outFormat, CFStringRef *outErrorString) {
	CFPropertyListRef plist = NULL;

	if (!url)
		NSLog(@"in createPropertyListFromURL: cannot read from a NULL URL");
	else {
		CFHTTPMessageRef httpRequest = CFHTTPMessageCreateRequest(kCFAllocatorDefault, CFSTR("GET"), url, kCFHTTPVersion1_1);
		if (!httpRequest)
			NSLog(@"in createPropertyListFromURL: could not create request for URL %@", url);
		else {
			CFReadStreamRef stream = CFReadStreamCreateForHTTPRequest(kCFAllocatorDefault, httpRequest);
			if (!stream)
				NSLog(@"in createPropertyListFromURL: could not create stream for reading from URL %@", url);
			else {
				CFDictionaryRef proxyDict = SCDynamicStoreCopyProxies(NULL);
				if (proxyDict) {
					CFReadStreamSetProperty(stream, kCFStreamPropertyHTTPProxy, proxyDict);
					CFRelease(proxyDict);
				}
				if (!CFReadStreamOpen(stream))
					NSLog(@"in createPropertyListFromURL: could not open stream for reading from URL %@", url);
				else {
					CFPropertyListFormat format;
					CFStringRef errorString = NULL;

					plist = CFPropertyListCreateFromStream(kCFAllocatorDefault,
														   stream,
														   /*streamLength*/ 0,
														   mutability,
														   &format,
														   &errorString);
					if (!plist)
						NSLog(@"in createPropertyListFromURL: could not read property list from URL %@ (error string: %@)", url, errorString);
				
					if (outFormat) *outFormat = format;
					if (errorString) {
						if (outErrorString)
							*outErrorString = errorString;
						else
							CFRelease(errorString);
					}

					CFReadStreamClose(stream);
				}

				CFRelease(stream);
			}
			CFRelease(httpRequest);
		}
	}
	
	return plist;
}

@implementation VersionCheck

+ (void) checkVersionAtURL:(CFURLRef)url withDayInterval:(int)minDays displayText:(NSString *)message downloadURL:(CFURLRef)goURL
{
	int days;
	CFDateRef lastCheck = CFPreferencesCopyAppValue(CFSTR("lastVersionCheckDate"), kCFPreferencesCurrentApplication);
	CFDateRef now = CFDateCreate(kCFAllocatorDefault, CFAbsoluteTimeGetCurrent());

	if (lastCheck) {
		days = (int)(CFDateGetTimeIntervalSinceDate(now, lastCheck) / 86400.0);
		CFRelease(lastCheck);
	} else
		days = minDays;

	if (days >= minDays) {
		NSLog(@"Going online to check version...");
		CFBundleRef bundle = CFBundleGetMainBundle();
		CFStringRef currVersionNumber = CFBundleGetValueForInfoDictionaryKey(bundle, kCFBundleVersionKey);
		CFDictionaryRef productVersionDict = createPropertyListFromURL((CFURLRef)url, kCFPropertyListImmutable, NULL, NULL);

		if (!productVersionDict)
			return;

		CFStringRef latestVersionNumber = CFDictionaryGetValue(productVersionDict, CFBundleGetValueForInfoDictionaryKey(bundle, kCFBundleExecutableKey));

		// do nothing--be quiet if there is no active connection or if the
		// version number could not be downloaded
		if (latestVersionNumber) {
			if (CFEqual(latestVersionNumber, currVersionNumber)) {
				// Everything is fine, update the counter
				CFPreferencesSetAppValue(CFSTR("lastVersionCheckDate"), now, kCFPreferencesCurrentApplication);
			} else {
				CFStringRef title = CFCopyLocalizedString(CFSTR("Update Available"),"");
				CFStringRef alternateButton = CFCopyLocalizedString(CFSTR("Cancel"),"");
				NSBeginAlertSheet((NSString *)title,
								  nil,
								  (NSString *)alternateButton, nil, nil,
								  self, NULL,
								  @selector(downloadSelector:returnCode:contextInfo:),
								  (void *)goURL, message);
				CFRelease(alternateButton);
				CFRelease(title);
				CFPreferencesSetAppValue(CFSTR("lastVersionCheckDate"), NULL, kCFPreferencesCurrentApplication);
			}
		}
		CFRelease(productVersionDict);
	}
	CFRelease(now);
}

+ (void) checkVersionAtURL:(CFURLRef)url displayText: (NSString *)message downloadURL: (CFURLRef)goURL
{
	CFBundleRef bundle = CFBundleGetMainBundle();
	CFStringRef currVersionNumber = CFBundleGetValueForInfoDictionaryKey(bundle, kCFBundleVersionKey);
	CFDictionaryRef productVersionDict = createPropertyListFromURL((CFURLRef)url, kCFPropertyListImmutable, NULL, NULL);

	if (!productVersionDict)
		return;

	CFStringRef latestVersionNumber = CFDictionaryGetValue(productVersionDict, CFBundleGetValueForInfoDictionaryKey(bundle, kCFBundleExecutableKey));

/*
	NSLog([[[NSBundle bundleForClass:[self class]] infoDictionary] objectForKey:@"CFBundleExecutable"] );
	NSLog(currVersionNumber);
	NSLog(latestVersionNumber);
*/

	// do nothing--be quiet if there is no active connection or if the
	// version number could not be downloaded
	if (latestVersionNumber && (!CFEqual(latestVersionNumber, currVersionNumber))) {
		CFStringRef title = CFCopyLocalizedString(CFSTR("Update Available"),"");
		CFStringRef alternateButton = CFCopyLocalizedString(CFSTR("Cancel"),"");
		NSBeginAlertSheet((NSString *)title,
						  nil,
						  (NSString *)alternateButton, nil, nil, self,
						  NULL, 
						  @selector(downloadSelector:returnCode:contextInfo:),
						  (void *)goURL, message);
		CFRelease(alternateButton);
		CFRelease(title);
	}
	CFRelease(productVersionDict);
}

+ (void) downloadSelector:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(id)contextInfo
{
#pragma unused(sheet)
	if (returnCode == NSAlertDefaultReturn)
		LSOpenCFURLRef((CFURLRef)contextInfo, NULL);
}

@end
