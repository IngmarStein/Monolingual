/*
 *  VersionCheck.m
 *  Copyright (C) 2001, 2002  Joshua Schrier (jschrier@mac.com),
 *  2004 Ingmar Stein
 *  Released under the GNU GPL.  For more information, see the header file.
 */

#import "VersionCheck.h"

@implementation VersionCheck

/* Implemented new version, after being inspired by 
http://www.cocoadevcentral.com/tutorials/showpage.php?show=00000047.php
The old way used a perl script, curl, and a NSTask, and was quite ugly;  
see the Monolingual or Swap Cop source code for how this used to be
*/

+ (void) checkInfrequentVersionAtURL: (NSURL *)url displayText: (NSString *)message downloadURL: (NSURL *)goURL
{
	[VersionCheck checkVersionAtURL: url withDayInterval:30 displayText: message downloadURL: goURL];
}

+ (void) checkVersionAtURL: (NSURL *)url withDayInterval: (int)minDays displayText: (NSString *)message downloadURL: (NSURL *)goURL
{
	NSString *currVersionNumber = [[[NSBundle bundleForClass:[self class]] infoDictionary] objectForKey:@"CFBundleVersion"];
	NSDictionary *productVersionDict;
	NSCalendarDate *lastCheck = [[NSUserDefaults standardUserDefaults] objectForKey:@"lastVersionCheckDate"];
	int days;
	NSString *latestVersionNumber;

	[[NSCalendarDate calendarDate] 
		years: NULL months: NULL days: &days hours: NULL minutes: NULL seconds: NULL sinceDate: lastCheck]; 

	if ((lastCheck == nil) || (days> minDays)) {
		NSLog(@"Going online to check version...");
		productVersionDict = [NSDictionary dictionaryWithContentsOfURL: url];
		latestVersionNumber = [productVersionDict valueForKey:
			[[[NSBundle bundleForClass:[self class]] infoDictionary] objectForKey:@"CFBundleExecutable"] ];

		// do nothing--be quiet if there is no active connection or if the
		// version number could not be downloaded
		if( latestVersionNumber ) {
			if (![latestVersionNumber isEqualToString: currVersionNumber]) {
				NSBeginAlertSheet(
							  NSLocalizedString(@"Update Available",@""), NSLocalizedString(@"OK",@""), 
							  NSLocalizedString(@"Cancel",@""), nil, nil, self, NULL, 
							  @selector(downloadSelector: returnCode: contextInfo:), goURL, message,nil);
				[[NSUserDefaults standardUserDefaults] setObject: nil forKey:@"lastVersionCheckDate"];
			} else {
				// Everything is fine, update the counter
				[[NSUserDefaults standardUserDefaults] setObject: [NSCalendarDate calendarDate] forKey:@"lastVersionCheckDate"];
			}
		}
	}
}

+ (void) checkVersionAtURL: (NSURL *)url displayText: (NSString *)message downloadURL: (NSURL *)goURL
{
	NSString *currVersionNumber = [[[NSBundle bundleForClass:[self class]] infoDictionary] objectForKey:@"CFBundleVersion"];
	NSDictionary *productVersionDict = [NSDictionary dictionaryWithContentsOfURL: url];
	NSString *latestVersionNumber = [productVersionDict valueForKey:
		[[[NSBundle bundleForClass:[self class]] infoDictionary] objectForKey:@"CFBundleExecutable"] ];

/*
	NSLog([[[NSBundle bundleForClass:[self class]] infoDictionary] objectForKey:@"CFBundleExecutable"] );
	NSLog(currVersionNumber);
	NSLog(latestVersionNumber);
*/

	// do nothing--be quiet if there is no active connection or if the
	// version number could not be downloaded
	if ((latestVersionNumber != nil) && (![latestVersionNumber isEqualToString: currVersionNumber])) {
		NSBeginAlertSheet(
			NSLocalizedString(@"Update Available",@""), NSLocalizedString(@"OK",@""), 
			NSLocalizedString(@"Cancel",@""), nil, nil, self, NULL, 
			@selector(downloadSelector: returnCode: contextInfo:), goURL, message,nil);
	}
}

+ (void) downloadSelector: (NSWindow *)sheet returnCode: (int)returnCode contextInfo: (id)contextInfo
{
	if (returnCode == NSAlertDefaultReturn) { 
		[[NSWorkspace sharedWorkspace] openURL: contextInfo];
	}
}

@end
