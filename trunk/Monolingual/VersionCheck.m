/*
 *  VersionCheck.m
 *  Copyright (C) 2001, 2002  Joshua Schrier (jschrier@mac.com),
 *  2004-2006 Ingmar Stein
 *  Released under the GNU GPL.  For more information, see the header file.
 */

#import "VersionCheck.h"

@implementation VersionCheck

/* Implemented new version, after being inspired by 
http://www.cocoadevcentral.com/tutorials/showpage.php?show=00000047.php
The old way used a perl script, curl, and a NSTask, and was quite ugly;  
see the Monolingual or Swap Cop source code for how this used to be
*/

+ (void) checkVersionAtURL:(NSURL *)url withDayInterval:(int)minDays displayText:(NSString *)message downloadURL:(NSURL *)goURL
{
	int days;
	NSCalendarDate *lastCheck = [[NSUserDefaults standardUserDefaults] objectForKey:@"lastVersionCheckDate"];
	NSCalendarDate *now = [NSCalendarDate calendarDate];

	if (lastCheck)
		[now years:NULL months:NULL days:&days hours:NULL minutes:NULL seconds:NULL sinceDate:lastCheck]; 

	if (!lastCheck || (days > minDays)) {
		NSLog(@"Going online to check version...");
		CFBundleRef bundle = CFBundleGetMainBundle();
		CFStringRef currVersionNumber = CFBundleGetValueForInfoDictionaryKey(bundle, kCFBundleVersionKey);
		CFDictionaryRef productVersionDict = (CFDictionaryRef)[[NSDictionary alloc] initWithContentsOfURL:url];

		if (!productVersionDict)
			return;
		
		CFStringRef latestVersionNumber = CFDictionaryGetValue(productVersionDict, CFBundleGetValueForInfoDictionaryKey(bundle, kCFBundleExecutableKey));

		// do nothing--be quiet if there is no active connection or if the
		// version number could not be downloaded
		if( latestVersionNumber ) {
			if (!CFEqual(latestVersionNumber, currVersionNumber)) {
				NSBeginAlertSheet(NSLocalizedString(@"Update Available",@""),
								  NSLocalizedString(@"OK",@""), 
								  NSLocalizedString(@"Cancel",@""), nil, nil,
								  self, NULL, 
								  @selector(downloadSelector:returnCode:contextInfo:),
								  goURL, message, nil);
				[[NSUserDefaults standardUserDefaults] removeObjectForKey:@"lastVersionCheckDate"];
			} else {
				// Everything is fine, update the counter
				[[NSUserDefaults standardUserDefaults] setObject:now forKey:@"lastVersionCheckDate"];
			}
		}
		CFRelease(productVersionDict);
	}
}

+ (void) checkVersionAtURL: (NSURL *)url displayText: (NSString *)message downloadURL: (NSURL *)goURL
{
	CFBundleRef bundle = CFBundleGetMainBundle();
	CFStringRef currVersionNumber = CFBundleGetValueForInfoDictionaryKey(bundle, kCFBundleVersionKey);
	CFDictionaryRef productVersionDict = (CFDictionaryRef)[[NSDictionary alloc] initWithContentsOfURL:url];

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
		NSBeginAlertSheet(NSLocalizedString(@"Update Available",@""),
						  NSLocalizedString(@"OK",@""), 
						  NSLocalizedString(@"Cancel",@""), nil, nil, self,
						  NULL, 
						  @selector(downloadSelector:returnCode:contextInfo:),
						  goURL, message, nil);
	}
	CFRelease(productVersionDict);
}

+ (void) downloadSelector:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(id)contextInfo
{
#pragma unused(sheet)
	if (returnCode == NSAlertDefaultReturn)
		[[NSWorkspace sharedWorkspace] openURL:contextInfo];
}

@end
