/* 
 *  Copyright (C) 2001, 2002  Joshua Schrier (jschrier@mac.com),
 *  2004 Ingmar Stein
 *  Released under the GNU GPL.  For more information, see the header file.
 */

#import "MyResponder.h"
#import "ProgressWindowController.h"
#import "PreferencesController.h"
#import "VersionCheck.h"
#include <Security/Authorization.h>
#include <Security/AuthorizationTags.h>

@implementation MyResponder
ProgressWindowController *myProgress;
PreferencesController    *myPreferences;
NSWindow                 *parentWindow;
NSFileHandle             *pipeHandle;
CFMutableDataRef         pipeBuffer;
CFMutableArrayRef        languages;
CFMutableArrayRef        layouts;
CFDictionaryRef          startedNotificationInfo;
CFDictionaryRef          finishedNotificationInfo;
unsigned long long       bytesSaved;
BOOL                     cancelled;

+ (void) initialize
{
	NSNumber *enabled = [[NSNumber alloc] initWithBool:YES];
	NSDictionary *applications = [[NSDictionary alloc] initWithObjectsAndKeys:@"/Applications", @"Path", enabled, @"Enabled", nil];
	NSDictionary *developer = [[NSDictionary alloc] initWithObjectsAndKeys:@"/Developer", @"Path", enabled, @"Enabled", nil];
	NSDictionary *library = [[NSDictionary alloc] initWithObjectsAndKeys:@"/Library", @"Path", enabled, @"Enabled", nil];
	NSDictionary *systemPath = [[NSDictionary alloc] initWithObjectsAndKeys:@"/System", @"Path", enabled, @"Enabled", nil];
	NSArray *defaultRoots = [[NSArray alloc] initWithObjects:applications, developer, library, systemPath, nil];
	NSDictionary *defaultValues = [[NSDictionary alloc] initWithObjectsAndKeys:defaultRoots, @"Roots", nil];
	[[NSUserDefaults standardUserDefaults] registerDefaults: defaultValues];
	[defaultValues release];
	[defaultRoots release];
	[systemPath release];
	[library release];
	[developer release];
	[applications release];
	[enabled release];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed: (NSApplication *)theApplication
{
#pragma unused(theApplication)
	return YES;
}

- (void) cancelRemove
{
	const unsigned char bytes[1] = {'\0'};
	CFDataRef data = CFDataCreateWithBytesNoCopy(kCFAllocatorDefault, bytes, sizeof(bytes), kCFAllocatorNull);
	[pipeHandle writeData:(NSData *)data];
	[pipeHandle closeFile];
	[pipeHandle release];
	CFRelease(data);
	pipeHandle = nil;
	CFRelease(pipeBuffer);

	[NSApp endSheet: [myProgress window]];
	[[myProgress window] orderOut: self]; 
	[myProgress stop];

	[GrowlApplicationBridge notifyWithDictionary:(NSDictionary *)finishedNotificationInfo];

	NSBeginAlertSheet(NSLocalizedString(@"Removal cancelled",@""),@"OK",nil,nil,
			[NSApp mainWindow],self,NULL,NULL,self,
			NSLocalizedString(@"You cancelled the removal.  Some files were erased, some were not.",@""), nil);  
}

- (IBAction) documentationBundler: (id)sender
{
	NSString *myPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:[sender title]];
	[[NSWorkspace sharedWorkspace] openFile: myPath];
}

- (IBAction) openWebsite: (id)sender
{
#pragma unused(sender)
	CFURLRef url = CFURLCreateWithString(kCFAllocatorDefault, CFSTR("http://monolingual.sourceforge.net/"), NULL);
	[[NSWorkspace sharedWorkspace] openURL:(NSURL *)url];
	CFRelease(url);
}

- (void) scanLayouts
{
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSString *layoutPath = @"/System/Library/Keyboard Layouts";
	CFArrayRef files = (CFArrayRef)[fileManager directoryContentsAtPath: layoutPath];
	CFIndex length = CFArrayGetCount(files);
	CFMutableArrayRef scannedLayouts = CFArrayCreateMutable(kCFAllocatorDefault, length+6, &kCFTypeArrayCallBacks);
	for( CFIndex i=0; i<length; ++i ) {
		CFStringRef file = CFArrayGetValueAtIndex(files, i);
		if( CFStringHasSuffix(file, CFSTR(".bundle")) && !CFEqual(file, CFSTR("Roman.bundle")) ) {
			CFMutableDictionaryRef layout = CFDictionaryCreateMutable(kCFAllocatorDefault, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
			CFDictionarySetValue(layout, CFSTR("enabled"), kCFBooleanFalse);
			CFDictionarySetValue(layout, CFSTR("displayName"), NSLocalizedString([(NSString *)file stringByDeletingPathExtension],@""));
			CFDictionarySetValue(layout, CFSTR("type"), NSLocalizedString(@"Keyboard Layout",@""));
			CFDictionarySetValue(layout, CFSTR("path"), [layoutPath stringByAppendingPathComponent:(NSString *)file]);
			CFArrayAppendValue(scannedLayouts, layout);
			CFRelease(layout);
		}
	}
	if( [fileManager fileExistsAtPath:@"/System/Library/Components/Kotoeri.component"] ) {
		CFMutableDictionaryRef layout = CFDictionaryCreateMutable(kCFAllocatorDefault, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
		CFDictionarySetValue(layout, CFSTR("enabled"), kCFBooleanFalse);
		CFDictionarySetValue(layout, CFSTR("displayName"), NSLocalizedString(@"Kotoeri",@""));
		CFDictionarySetValue(layout, CFSTR("type"), NSLocalizedString(@"Input Method",@""));
		CFDictionarySetValue(layout, CFSTR("path"), CFSTR("/System/Library/Components/Kotoeri.component"));
		CFArrayAppendValue(scannedLayouts, layout);
		CFRelease(layout);
	}
	if( [fileManager fileExistsAtPath:@"/System/Library/Components/XPIM.component"] ) {
		CFMutableDictionaryRef layout = CFDictionaryCreateMutable(kCFAllocatorDefault, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
		CFDictionarySetValue(layout, CFSTR("enabled"), kCFBooleanFalse);
		CFDictionarySetValue(layout, CFSTR("displayName"), NSLocalizedString(@"Hangul",@""));
		CFDictionarySetValue(layout, CFSTR("type"), NSLocalizedString(@"Input Method",@""));
		CFDictionarySetValue(layout, CFSTR("path"), CFSTR("/System/Library/Components/XPIM.component"));
		CFArrayAppendValue(scannedLayouts, layout);
		CFRelease(layout);
	}
	if( [fileManager fileExistsAtPath:@"/System/Library/Components/TCIM.component"] ) {
		CFMutableDictionaryRef layout = CFDictionaryCreateMutable(kCFAllocatorDefault, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
		CFDictionarySetValue(layout, CFSTR("enabled"), kCFBooleanFalse);
		CFDictionarySetValue(layout, CFSTR("displayName"), NSLocalizedString(@"Traditional Chinese",@""));
		CFDictionarySetValue(layout, CFSTR("type"), NSLocalizedString(@"Input Method",@""));
		CFDictionarySetValue(layout, CFSTR("path"), CFSTR("/System/Library/Components/TCIM.component"));
		CFArrayAppendValue(scannedLayouts, layout);
		CFRelease(layout);
	}
	if( [fileManager fileExistsAtPath:@"/System/Library/Components/SCIM.component"] ) {
		CFMutableDictionaryRef layout = CFDictionaryCreateMutable(kCFAllocatorDefault, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
		CFDictionarySetValue(layout, CFSTR("enabled"), kCFBooleanFalse);
		CFDictionarySetValue(layout, CFSTR("displayName"), NSLocalizedString(@"Simplified Chinese",@""));
		CFDictionarySetValue(layout, CFSTR("type"), NSLocalizedString(@"Input Method",@""));
		CFDictionarySetValue(layout, CFSTR("path"), CFSTR("/System/Library/Components/SCIM.component"));
		CFArrayAppendValue(scannedLayouts, layout);
		CFRelease(layout);
	}
	if( [fileManager fileExistsAtPath:@"/System/Library/Components/AnjalIM.component"] ) {
		CFMutableDictionaryRef layout = CFDictionaryCreateMutable(kCFAllocatorDefault, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
		CFDictionarySetValue(layout, CFSTR("enabled"), kCFBooleanFalse);
		CFDictionarySetValue(layout, CFSTR("displayName"), NSLocalizedString(@"Murasu Anjal Tamil",@""));
		CFDictionarySetValue(layout, CFSTR("type"), NSLocalizedString(@"Input Method",@""));
		CFDictionarySetValue(layout, CFSTR("path"), CFSTR("/System/Library/Components/AnjalIM.component"));
		CFArrayAppendValue(scannedLayouts, layout);
		CFRelease(layout);
	}
	if( [fileManager fileExistsAtPath:@"/System/Library/Components/HangulIM.component"] ) {
		CFMutableDictionaryRef layout = CFDictionaryCreateMutable(kCFAllocatorDefault, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
		CFDictionarySetValue(layout, CFSTR("enabled"), kCFBooleanFalse);
		CFDictionarySetValue(layout, CFSTR("displayName"), NSLocalizedString(@"Hangul",@""));
		CFDictionarySetValue(layout, CFSTR("type"), NSLocalizedString(@"Input Method",@""));
		CFDictionarySetValue(layout, CFSTR("path"), CFSTR("/System/Library/Components/HangulIM.component"));
		CFArrayAppendValue(scannedLayouts, layout);
		CFRelease(layout);
	}
	[self setLayouts:(NSMutableArray *)scannedLayouts];
	CFRelease(scannedLayouts);
}

- (IBAction) showPreferences: (id)sender
{
#pragma unused(sender)
	if( !myPreferences )
		myPreferences = [[PreferencesController alloc] init];
	[myPreferences showWindow: self];
}

- (IBAction) removeLanguages: (id)sender
{
#pragma unused(sender)
	//Display a warning first
	NSBeginAlertSheet(NSLocalizedString(@"WARNING!",@""),NSLocalizedString(@"Stop",@""),NSLocalizedString(@"Continue",@""),nil,[NSApp mainWindow],self,NULL,
					  @selector(warningSelector:returnCode:contextInfo:),self,
					  NSLocalizedString(@"Are you sure you want to remove these languages?  You will not be able to restore them without reinstalling OSX.",@""),nil);
}

- (IBAction) removeLayouts: (id)sender
{
#pragma unused(sender)
	//Display a warning first
	NSBeginAlertSheet(NSLocalizedString(@"WARNING!",@""),NSLocalizedString(@"Stop",@""),NSLocalizedString(@"Continue",@""),nil,[NSApp mainWindow],self,NULL,
					  @selector(removeLayoutsWarning:returnCode:contextInfo:),self,
					  NSLocalizedString(@"Are you sure you want to remove these languages?  You will not be able to restore them without reinstalling OSX.",@""),nil);
}

static const char suffixes[9] =
{
	'B',	/* Byte */
	'K',	/* Kilo */
	'M',	/* Mega */
	'G',	/* Giga */
	'T',	/* Tera */
	'P',	/* Peta */
	'E',	/* Exa */
	'Z',	/* Zetta */
	'Y'		/* Yotta */
};

# define LONGEST_HUMAN_READABLE ((sizeof (uintmax_t) + sizeof (int)) \
								 * CHAR_BIT / 3)

/* Convert AMT to a human readable format in BUF. */
static char * human_readable( unsigned long long amt, char *buf, unsigned int base )
{
	unsigned int tenths = 0U;
	unsigned int power = 0U;
	char *p;
	
	/* 0 means adjusted N == AMT.TENTHS;
	 * 1 means AMT.TENTHS < adjusted N < AMT.TENTHS + 0.05;
	 * 2 means adjusted N == AMT.TENTHS + 0.05;
	 * 3 means AMT.TENTHS + 0.05 < adjusted N < AMT.TENTHS + 0.1.
	 */
	unsigned int rounding = 0U;
	
	p = buf + LONGEST_HUMAN_READABLE;
	*p = '\0';

	/* Use power of BASE notation if adjusted AMT is large enough.  */

	if( base ) {
		if( base <= amt ) {
			power = 0U;

			do {
				int r10 = (amt % base) * 10U + tenths;
				unsigned int r2 = (r10 % base) * 2 + (rounding >> 1);
				amt /= base;
				tenths = r10 / base;
				rounding = (r2 < base
							? 0 < r2 + rounding
							: 2 + (base < r2 + rounding));
				power++;
			} while (base <= amt && power < sizeof(suffixes) - 1);

			*--p = suffixes[power];

			if (amt < 10) {
				if (2 < rounding + (tenths & 1)) {
					tenths++;
					rounding = 0;
					
					if (tenths == 10U) {
						amt++;
						tenths = 0U;
					}
				}

				if (amt < 10U) {
					*--p = '0' + tenths;
					*--p = '.';
					tenths = rounding = 0U;
				}
			}
		} else {
			*--p = suffixes[0];
		}
	}

	if( 5U < tenths + (2 < rounding + (amt & 1)) ) {
		amt++;

		if( amt == base && power < sizeof suffixes - 1) {
			*p = suffixes[power + 1];
			*--p = '0';
			*--p = '.';
			amt = 1;
		}
    }

	do {
		*--p = '0' + (int) (amt % 10);
	} while ((amt /= 10) != 0);

	return p;
}

- (void) readCompletion: (NSNotification *)aNotification
{
	unsigned int i;
	unsigned int j;
	unsigned int num;
	unsigned int length;
	const unsigned char *bytes;
	char hbuf[LONGEST_HUMAN_READABLE + 1];

	NSDictionary *userInfo = [aNotification userInfo];
	NSNumber *error = (NSNumber *)[userInfo objectForKey:@"NSFileHandleError"];
	if( ![error intValue] ) {
		CFDataRef data = (CFDataRef)[userInfo objectForKey:@"NSFileHandleNotificationDataItem"];
		length = CFDataGetLength(data);
		if( length ) {
			// append new data
			CFDataAppendBytes(pipeBuffer, CFDataGetBytePtr(data), length);
			bytes = CFDataGetBytePtr(pipeBuffer);
			length = CFDataGetLength(pipeBuffer);

			// count number of '\0' characters
			num = 0;
			for( i=0; i<length; ++i )
				if( !bytes[i] )
					++num;

			for( i=0, j=0; num > 1 && i<length; ++i, ++j ) {
				if( !bytes[j] ) {
					// read file name
					CFStringRef file = CFStringCreateWithBytes(kCFAllocatorDefault, bytes, j, kCFStringEncodingUTF8, false);
					bytes += j + 1;

					// skip to next zero character
					for( j=0; bytes[j]; ++j ) {}

					// read file size
					CFStringRef size = CFStringCreateWithBytes(kCFAllocatorDefault, bytes, j, kCFStringEncodingUTF8, false);
					bytesSaved += CFStringGetIntValue(size);
					bytes += j + 1;
					i += j + 1;
					num -= 2;

					// parse file name
					NSArray *pathComponents = [(NSString *)file pathComponents];
					NSString *lang = nil;
					NSString *app = nil;
					NSString *layout = nil;
					NSString *im = nil;
					BOOL cache = NO;
					for( j=0; j<[pathComponents count]; ++j ) {
						NSString *pathComponent = [pathComponents objectAtIndex: j];
						NSString *pathExtension = [pathComponent pathExtension];
						if( [pathExtension isEqualToString: @"app"] ) {
							app = [pathComponent stringByDeletingPathExtension];
						} else if( [pathExtension isEqualToString: @"bundle"] ) {
							layout = [pathComponent stringByDeletingPathExtension];
						} else if( [pathExtension isEqualToString: @"component"] ) {
							im = [pathComponent stringByDeletingPathExtension];
						} else if( [pathExtension isEqualToString: @"lproj"] ) {
							CFIndex count = CFArrayGetCount(languages);
							for( CFIndex k=0; k<count; ++k ) {
								CFDictionaryRef language = CFArrayGetValueAtIndex(languages, k);
								if( NSNotFound != [(NSArray *)CFDictionaryGetValue(language, CFSTR("folders")) indexOfObject:pathComponent] ) {
									lang = (NSString *)CFDictionaryGetValue(language, CFSTR("displayName"));
									break;
								}
							}
						} else if( [pathExtension hasPrefix: @"com.apple.IntlDataCache"] ) {
							cache = YES;
						}
					}
					CFStringRef message;
					if( layout && CFStringHasPrefix(file, CFSTR("/System/Library/")) )
						message = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%@ %@%@"), NSLocalizedString(@"Removing keyboard layout", @""), layout, NSLocalizedString(@"...",@""));
					else if( im && CFStringHasPrefix(file, CFSTR("/System/Library/")) )
						message = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%@ %@%@"), NSLocalizedString(@"Removing input method", @""), layout, NSLocalizedString(@"...",@""));
					else if( cache )
						message = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%@%@"), NSLocalizedString(@"Clearing cache", @""), NSLocalizedString(@"...",@""));
					else if( app )
						message = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%@ %@ %@ %@%@"), NSLocalizedString(@"Removing language", @""), lang, NSLocalizedString(@"from", @""), app, NSLocalizedString(@"...",@""));
					else if( lang )
						message = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%@ %@%@"), NSLocalizedString(@"Removing language", @""), lang, NSLocalizedString(@"...",@""));
					else
						message = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%@ %@%@"), NSLocalizedString(@"Removing", @""), file, NSLocalizedString(@"...",@""));

					[myProgress setText:(NSString *)message];
					[myProgress setFile:(NSString *)file];
					[NSApp updateWindows];
					CFRelease(message);
					CFRelease(file);
					CFRelease(size);
					j = -1;
				}
			}
			// delete processed bytes
			CFDataDeleteBytes(pipeBuffer, CFRangeMake(0, i));
			[pipeHandle readInBackgroundAndNotify];
		} else if( pipeHandle ) {
			// EOF
			[pipeHandle closeFile];
			[pipeHandle release];
			pipeHandle = nil;
			CFRelease(pipeBuffer);
			[NSApp endSheet:[myProgress window]];
			[[myProgress window] orderOut:self]; 
			[myProgress stop];

			[[NSNotificationCenter defaultCenter] removeObserver:self
															name:NSFileHandleReadCompletionNotification 
														  object:nil];
			[GrowlApplicationBridge notifyWithDictionary:(NSDictionary *)finishedNotificationInfo];

			NSBeginAlertSheet(NSLocalizedString(@"Removal completed",@""),
							  @"OK", nil, nil, parentWindow, self, NULL, NULL,
							  self,
							  [NSString stringWithFormat: NSLocalizedString(@"Language resources removed. Space saved: %s.",@""), human_readable( bytesSaved, hbuf, 1024 )],
							  nil);
			[self scanLayouts];
		}
	}
}

- (void) runDeleteHelperWithArgs: (const char **)argv
{
	OSStatus status;
	FILE *pipe;

	NSString *myPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent: @"Helper"];
	const char *path = [myPath fileSystemRepresentation];
	AuthorizationItem right = {kAuthorizationRightExecute, strlen(path)+1, (char *)path, 0};
	AuthorizationRights rights = {1, &right};
	AuthorizationRef authorizationRef;
	
	status = AuthorizationCreate( &rights, kAuthorizationEmptyEnvironment, kAuthorizationFlagExtendRights | kAuthorizationFlagInteractionAllowed, &authorizationRef );
	switch( status ) {
		case errAuthorizationSuccess:
			break;
		case errAuthorizationDenied:
			//If you can't do it because you're not administrator, then let the user know!
			NSBeginAlertSheet(NSLocalizedString(@"Permission Error",@""),@"OK",nil,nil,[NSApp mainWindow],self, NULL,
							  NULL,self,NSLocalizedString(@"You entered an incorrect administrator password.",@""),nil);
			return;
		case errAuthorizationCanceled:
			NSBeginAlertSheet(NSLocalizedString(@"Nothing done",@""),@"OK",nil,nil,[NSApp mainWindow],self,
							  NULL,NULL,NULL,
							  NSLocalizedString(@"Monolingual is stopping without making any changes.  Your OS has not been modified.",@""),nil);
			return;
		default:
			NSBeginAlertSheet(NSLocalizedString(@"Authorization Error",@""),@"OK",nil,nil,[NSApp mainWindow],self, NULL,
							  NULL,self,NSLocalizedString(@"Failed to authorize as an administrator.",@""),nil);
			return;
	}

	argv[0] = path;

	parentWindow = [NSApp mainWindow];
	myProgress = [ProgressWindowController sharedProgressWindowController: self];
	[myProgress start];
	[NSApp beginSheet: [myProgress window]
	   modalForWindow: parentWindow
		modalDelegate: nil
	   didEndSelector: nil
		  contextInfo: nil];

	status = AuthorizationExecuteWithPrivileges( authorizationRef, path, kAuthorizationFlagDefaults, (char * const *)argv, &pipe );
	if( errAuthorizationSuccess == status ) {
		[GrowlApplicationBridge notifyWithDictionary:(NSDictionary *)startedNotificationInfo];

		bytesSaved = 0ULL;
		pipeBuffer = CFDataCreateMutable(kCFAllocatorDefault, 0);
		pipeHandle = [[NSFileHandle alloc] initWithFileDescriptor: fileno(pipe)];
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(readCompletion:) 
													 name:NSFileHandleReadCompletionNotification 
												   object:pipeHandle];
		[pipeHandle readInBackgroundAndNotify];
	} else {
		// TODO
		NSBeep();
	}

	AuthorizationFree( authorizationRef, kAuthorizationFlagDefaults );
}

- (void) removeLayoutsWarning: (NSWindow *)sheet returnCode: (int)returnCode contextInfo: (void *)contextInfo
{
#pragma unused(sheet)
	unsigned int	i;
	unsigned int	count;
	int				idx;
	CFDictionaryRef	row;
	BOOL			trash;
	const char		**argv;

	if( NSAlertDefaultReturn == returnCode ) {
		NSBeginAlertSheet(NSLocalizedString(@"Nothing done",@""),@"OK",nil,nil,[NSApp mainWindow],self,
						  NULL,NULL,contextInfo,
						  NSLocalizedString(@"Monolingual is stopping without making any changes.  Your OS has not been modified.",@""),nil);
	} else {
		count = CFArrayGetCount(layouts);
		argv = (const char **)malloc( (10+count+count)*sizeof(char *) );
		argv[1] = "-f";
		argv[2] = "/System/Library/Caches/com.apple.IntlDataCache";
		argv[3] = "-f";
		argv[4] = "/System/Library/Caches/com.apple.IntlDataCache.kbdx";
		argv[5] = "-f";
		argv[6] = "/System/Library/Caches/com.apple.IntlDataCache.sbdl";
		argv[7] = "-f";
		argv[8] = "/System/Library/Caches/com.apple.IntlDataCache.tecx";
		idx = 9;
		trash = [[NSUserDefaults standardUserDefaults] boolForKey:@"Trash"];
		if( trash )
			argv[idx++] = "-t";
		for( i=0; i<count; ++i ) {
			row = CFArrayGetValueAtIndex(layouts, i);
			if( CFBooleanGetValue(CFDictionaryGetValue(row, CFSTR("enabled"))) ) {
				argv[idx++] = "-f";
				argv[idx++] = [(NSString *)CFDictionaryGetValue(row, CFSTR("path")) fileSystemRepresentation];
			}
		}
		if( idx != 9 ) {
			argv[idx] = NULL;
			[self runDeleteHelperWithArgs: argv];
		}
		free( argv );
	}
}

- (void) warningSelector: (NSWindow *)sheet returnCode: (int)returnCode contextInfo: (void *)contextInfo
{
#pragma unused(sheet,contextInfo)
	unsigned int i;
	unsigned int lCount;

	if( NSAlertDefaultReturn != returnCode ) {
		lCount = CFArrayGetCount(languages);
		for( i=0; i<lCount; ++i ) {
			CFDictionaryRef language = CFArrayGetValueAtIndex(languages, i);
			if( CFBooleanGetValue(CFDictionaryGetValue(language, CFSTR("enabled"))) && CFEqual(CFArrayGetValueAtIndex(CFDictionaryGetValue(language, CFSTR("folders")), 0U), CFSTR("en.lproj")) ) {
				//Display a warning
				NSBeginCriticalAlertSheet(NSLocalizedString(@"WARNING!",@""),NSLocalizedString(@"Stop",@""),NSLocalizedString(@"Continue",@""),nil,[NSApp mainWindow],self,NULL,
										  @selector(englishWarningSelector:returnCode:contextInfo:),self,
										  NSLocalizedString(@"You are about to delete the English language files. Are you sure you want to do that?",@""),nil);
				return;
			}
		}
		[self englishWarningSelector:nil returnCode:NSAlertAlternateReturn contextInfo:nil];
	}
}

- (void) englishWarningSelector: (NSWindow *)sheet returnCode: (int)returnCode contextInfo: (void *)contextInfo
{
#pragma unused(sheet)
	unsigned int i;
	unsigned int rCount;
	unsigned int lCount;
	unsigned int idx;
	const char **argv;
	NSArray *roots;
	unsigned int roots_count;
	BOOL trash;

	roots = [[NSUserDefaults standardUserDefaults] arrayForKey:@"Roots"];
	roots_count = [roots count];

	for( i=0U; i<roots_count; ++i )
		if( [[[roots objectAtIndex: i] objectForKey:@"Enabled"] boolValue] )
			break;
	if( i==roots_count )
		// No active roots
		roots_count = 0U;

	if( NSAlertDefaultReturn == returnCode || !roots_count ) {
		NSBeginAlertSheet(NSLocalizedString(@"Nothing done",@""),@"OK",nil,nil,[NSApp mainWindow],self,
						  NULL,NULL,contextInfo,
						  NSLocalizedString(@"Monolingual is stopping without making any changes.  Your OS has not been modified.",@""),nil);
	} else {
		rCount = 0U;
		lCount = CFArrayGetCount(languages);
		argv = (const char **)malloc( (3+3*lCount+roots_count+roots_count)*sizeof(char *) );
		idx = 1U;
		trash = [[NSUserDefaults standardUserDefaults] boolForKey:@"Trash"];
		if( trash )
			argv[idx++] = "-t";
		for( i=0U; i<roots_count; ++i ) {
			NSDictionary *root = [roots objectAtIndex: i];
			int enabled = [[root objectForKey: @"Enabled"] intValue];
			if( enabled > 0 ) {
				NSString *path = [root objectForKey: @"Path"];
				NSLog( @"Adding root %@", path);
				argv[idx++] = "-r";
				argv[idx++] = [path fileSystemRepresentation];
			} else if( !enabled ) {
				NSString *path = [root objectForKey: @"Path"];
				NSLog( @"Excluding root %@", path);
				argv[idx++] = "-x";
				argv[idx++] = [path fileSystemRepresentation];
			}
		}
		for( i=0U; i<lCount; ++i ) {
			CFDictionaryRef language = CFArrayGetValueAtIndex(languages, i);
			if( CFBooleanGetValue(CFDictionaryGetValue(language, CFSTR("enabled"))) ) {
				CFArrayRef paths = CFDictionaryGetValue(language, CFSTR("folders"));
				CFIndex paths_count = CFArrayGetCount(paths);
				for (CFIndex j=0; j<paths_count; ++j) {
					NSString *path = (NSString *)CFArrayGetValueAtIndex(paths, j);
					NSLog( @"Will remove %@", path );
					argv[idx++] = [path fileSystemRepresentation];
				}
				++rCount;
			}
		}

		if( rCount == lCount )  {
			NSBeginAlertSheet(NSLocalizedString(@"Cannot remove all languages",@""),
							  @"OK", nil, nil, [NSApp mainWindow], self, NULL,
							  NULL, nil,
							  NSLocalizedString(@"Removing all languages will make OS X inoperable.  Please keep at least one language and try again.",@""),nil);
		} else if( rCount ) {
			// start things off if we have something to remove!
			argv[idx] = NULL;
			[self runDeleteHelperWithArgs: argv];
		}
		free( argv );
	}
}

- (void) dealloc
{
	[myProgress               release];
	[myPreferences            release];
	CFRelease(layouts);
	CFRelease(languages);
	CFRelease(startedNotificationInfo);
	CFRelease(finishedNotificationInfo);
	[super dealloc];
}

- (NSDictionary *) registrationDictionaryForGrowl
{
	NSString *startedNotificationName = NSLocalizedString(@"Monolingual started", @"");
	NSString *finishedNotificationName = NSLocalizedString(@"Monolingual finished", @"");

	NSArray *defaultAndAllNotifications = [[NSArray alloc] initWithObjects:
		startedNotificationName, finishedNotificationName, nil];
	NSDictionary *registrationDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
		defaultAndAllNotifications, GROWL_NOTIFICATIONS_ALL,
		defaultAndAllNotifications, GROWL_NOTIFICATIONS_DEFAULT,
		nil];
	[defaultAndAllNotifications release];

	return registrationDictionary;
}

- (void) applicationDidFinishLaunching:(NSNotification *)aNotification
{
#pragma unused(aNotification)
	[VersionCheck checkVersionAtURL:[NSURL URLWithString:@"http://monolingual.sourceforge.net/version.xml"]
						displayText:NSLocalizedString(@"A newer version of Monolingual is available online.  Would you like to download it now?",@"")
						downloadURL:[NSURL URLWithString:@"http://monolingual.sourceforge.net"]];
}

- (void) awakeFromNib
{
	CFArrayRef languagePref = (CFArrayRef)[[NSUserDefaults standardUserDefaults] objectForKey:@"AppleLanguages"];
	CFIndex count = CFArrayGetCount(languagePref);
	CFMutableSetRef userLanguages = CFSetCreateMutable(kCFAllocatorDefault, count, &kCFTypeSetCallBacks);

	// the localization variants have changed from en_US (<= 10.3) to en-US (>= 10.4)
	for (CFIndex i=0; i<count; ++i) {
		CFStringRef str = CFArrayGetValueAtIndex(languagePref, i);
		CFIndex length = CFStringGetLength(str);
		CFMutableStringRef language = CFStringCreateMutableCopy(kCFAllocatorDefault, length, str);
		CFStringFindAndReplace(language, CFSTR("-"), CFSTR("_"), CFRangeMake(0, length), 0);
		CFSetAddValue(userLanguages, language);
		CFRelease(language);
	}

	[[self window] setFrameAutosaveName:@"MainWindow"];

	NSMutableArray *knownLanguages = [[NSMutableArray alloc] initWithObjects:
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("af")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Afrikaans", @""),            @"displayName", [NSArray arrayWithObjects:@"af.lproj", @"Afrikaans.lproj", nil],                 @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("am")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Amharic", @""),              @"displayName", [NSArray arrayWithObjects:@"am.lproj", @"Amharic.lproj", nil],                   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("ar")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Arabic", @""),               @"displayName", [NSArray arrayWithObjects:@"ar.lproj", @"Arabic.lproj", nil],                    @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("as")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Assamese", @""),             @"displayName", [NSArray arrayWithObjects:@"as.lproj", @"Assamese.lproj", nil],                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("ay")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Aymara", @""),               @"displayName", [NSArray arrayWithObjects:@"ay.lproj", @"Aymara.lproj", nil],                    @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("az")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Azerbaijani", @""),          @"displayName", [NSArray arrayWithObjects:@"az.lproj", @"Azerbaijani.lproj", nil],               @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("be")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Byelorussian", @""),         @"displayName", [NSArray arrayWithObjects:@"be.lproj", @"Byelorussian.lproj", nil],              @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("bg")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Bulgarian", @""),            @"displayName", [NSArray arrayWithObjects:@"bg.lproj", @"Bulgarian.lproj", nil],                 @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("bi")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Bislama", @""),              @"displayName", [NSArray arrayWithObjects:@"bi.lproj", @"Bislama.lproj", nil],                   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("bn")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Bengali", @""),              @"displayName", [NSArray arrayWithObjects:@"bn.lproj", @"Bengali.lproj", nil],                   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("bo")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Tibetan", @""),              @"displayName", [NSArray arrayWithObjects:@"bo.lproj", @"Tibetan.lproj", nil],                   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("br")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Breton", @""),               @"displayName", [NSArray arrayWithObjects:@"br.lproj", @"Breton.lproj", nil],                    @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("ca")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Catalan", @""),              @"displayName", [NSArray arrayWithObjects:@"ca.lproj", @"Catalan.lproj", nil],                   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("cs")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Czech", @""),                @"displayName", [NSArray arrayWithObjects:@"cs.lproj", @"cs_CZ.lproj", @"Czech.lproj", nil],     @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("cy")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Welsh", @""),                @"displayName", [NSArray arrayWithObjects:@"cy.lproj", @"Welsh.lproj", nil],                     @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("da")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Danish", @""),               @"displayName", [NSArray arrayWithObjects:@"da.lproj", @"da_DK.lproj", @"Danish.lproj", nil],    @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("de")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"German", @""),               @"displayName", [NSArray arrayWithObjects:@"de.lproj", @"de_DE.lproj", @"German.lproj", nil],    @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("de_AT")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue, @"enabled", NSLocalizedString(@"Austrian German", @""),      @"displayName", [NSArray arrayWithObjects:@"de_AT.lproj", nil],                                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("de_CH")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue, @"enabled", NSLocalizedString(@"Swiss German", @""),         @"displayName", [NSArray arrayWithObjects:@"de_CH.lproj", nil],                                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("dz")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Dzongkha", @""),             @"displayName", [NSArray arrayWithObjects:@"dz.lproj", @"Dzongkha.lproj", nil],                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("el")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Greek", @""),                @"displayName", [NSArray arrayWithObjects:@"el.lproj", @"el_GR.lproj", @"Greek.lproj", nil],     @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:(id)kCFBooleanFalse,                                                                          @"enabled", NSLocalizedString(@"English", @""),              @"displayName", [NSArray arrayWithObjects:@"en.lproj", @"English.lproj", nil],                   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("en_AU")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue, @"enabled", NSLocalizedString(@"Australian English", @""),   @"displayName", [NSArray arrayWithObjects:@"en_AU.lproj", nil],                                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("en_CA")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue, @"enabled", NSLocalizedString(@"Canadian English", @""),     @"displayName", [NSArray arrayWithObjects:@"en_CA.lproj", nil],                                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("en_GB")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue, @"enabled", NSLocalizedString(@"British English", @""),      @"displayName", [NSArray arrayWithObjects:@"en_GB.lproj", nil],                                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("en_US")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue, @"enabled", NSLocalizedString(@"U.S. English", @""),         @"displayName", [NSArray arrayWithObjects:@"en_US.lproj", nil],                                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("eo")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Esperanto", @""),            @"displayName", [NSArray arrayWithObjects:@"eo.lproj", @"Esperanto.lproj", nil],                 @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("es")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Spanish", @""),              @"displayName", [NSArray arrayWithObjects:@"es.lproj", @"es_ES.lproj", @"Spanish.lproj", nil],   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("et")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Estonian", @""),             @"displayName", [NSArray arrayWithObjects:@"et.lproj", @"Estonian.lproj", nil],                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("eu")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Basque", @""),               @"displayName", [NSArray arrayWithObjects:@"eu.lproj", @"Basque.lproj", nil],                    @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("fa")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Farsi", @""),                @"displayName", [NSArray arrayWithObjects:@"fa.lproj", @"Farsi.lproj", nil],                     @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("fi")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Finnish", @""),              @"displayName", [NSArray arrayWithObjects:@"fi.lproj", @"fi_FI.lproj", @"Finnish.lproj", nil],   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("fo")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Faroese", @""),              @"displayName", [NSArray arrayWithObjects:@"fo.lproj", @"Faroese.lproj", nil],                   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("fr")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"French", @""),               @"displayName", [NSArray arrayWithObjects:@"fr.lproj", @"fr_FR.lproj", @"French.lproj", nil],    @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("fr_CA")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue, @"enabled", NSLocalizedString(@"Canadian French", @""),      @"displayName", [NSArray arrayWithObjects:@"fr_CA.lproj", nil],                                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("fr_CH")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue, @"enabled", NSLocalizedString(@"Swiss French", @""),         @"displayName", [NSArray arrayWithObjects:@"fr_CH.lproj", nil],                                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("ga")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Irish", @""),                @"displayName", [NSArray arrayWithObjects:@"ga.lproj", @"Irish.lproj", nil],                     @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("gd")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Scottish", @""),             @"displayName", [NSArray arrayWithObjects:@"gd.lproj", @"Scottish.lproj", nil],                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("gl")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Galician", @""),             @"displayName", [NSArray arrayWithObjects:@"gl.lproj", @"Galician.lproj", nil],                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("gn")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Guarani", @""),              @"displayName", [NSArray arrayWithObjects:@"gn.lproj", @"Guarani.lproj", nil],                   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("gu")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Gujarati", @""),             @"displayName", [NSArray arrayWithObjects:@"gu.lproj", @"Gujarati.lproj", nil],                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("gv")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Manx", @""),                 @"displayName", [NSArray arrayWithObjects:@"gv.lproj", @"Manx.lproj", nil],                      @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("haw")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,   @"enabled", NSLocalizedString(@"Hawaiian", @""),             @"displayName", [NSArray arrayWithObjects:@"haw.lproj", @"Hawaiian.lproj", nil],                 @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("he")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Hebrew", @""),               @"displayName", [NSArray arrayWithObjects:@"he.lproj", @"Hebrew.lproj", nil],                    @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("hi")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Hindi", @""),                @"displayName", [NSArray arrayWithObjects:@"hi.lproj", @"Hindi.lproj", nil],                     @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("hr")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Croatian", @""),             @"displayName", [NSArray arrayWithObjects:@"hr.lproj", @"Croatian.lproj", nil],                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("hu")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Hungarian", @""),            @"displayName", [NSArray arrayWithObjects:@"hu.lproj", @"hu_HU.lproj", @"Hungarian.lproj", nil], @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("hy")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Armenian", @""),             @"displayName", [NSArray arrayWithObjects:@"hy.lproj", @"Armenian.lproj", nil],                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("id")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Indonesian", @""),           @"displayName", [NSArray arrayWithObjects:@"id.lproj", @"Indonesian.lproj", nil],                @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("is")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Icelandic", @""),            @"displayName", [NSArray arrayWithObjects:@"is.lproj", @"Icelandic.lproj", nil],                 @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("it")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Italian", @""),              @"displayName", [NSArray arrayWithObjects:@"it.lproj", @"it_IT.lproj", @"Italian.lproj", nil],   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("iu")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Inuktitut", @""),            @"displayName", [NSArray arrayWithObjects:@"iu.lproj", @"Inuktitut.lproj", nil],                 @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("ja")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Japanese", @""),             @"displayName", [NSArray arrayWithObjects:@"ja.lproj", @"ja_JP.lproj", @"Japanese.lproj", nil],  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("jv")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Javanese", @""),             @"displayName", [NSArray arrayWithObjects:@"jv.lproj", @"Javanese.lproj", nil],                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("ka")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Georgian", @""),             @"displayName", [NSArray arrayWithObjects:@"ka.lproj", @"Georgian.lproj", nil],                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("kk")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Kazakh", @""),               @"displayName", [NSArray arrayWithObjects:@"kk.lproj", @"Kazakh.lproj", nil],                    @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("kl")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Greenlandic", @""),          @"displayName", [NSArray arrayWithObjects:@"kl.lproj", @"Greenlandic.lproj", nil],               @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("km")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Khmer", @""),                @"displayName", [NSArray arrayWithObjects:@"km.lproj", @"Khmer.lproj", nil],                     @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("kn")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Kannada", @""),              @"displayName", [NSArray arrayWithObjects:@"kn.lproj", @"Kannada.lproj", nil],                   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("ko")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Korean", @""),               @"displayName", [NSArray arrayWithObjects:@"ko.lproj", @"ko_KR.lproj", @"Korean.lproj", nil],    @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("ks")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Kashmiri", @""),             @"displayName", [NSArray arrayWithObjects:@"ks.lproj", @"Kashmiri.lproj", nil],                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("ku")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Kurdish", @""),              @"displayName", [NSArray arrayWithObjects:@"ku.lproj", @"Kurdish.lproj", nil],                   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("ky")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Kirghiz", @""),              @"displayName", [NSArray arrayWithObjects:@"ky.lproj", @"Kirghiz.lproj", nil],                   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("la")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Latin", @""),                @"displayName", [NSArray arrayWithObjects:@"la.lproj", @"Latin.lproj", nil],                     @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("lo")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Lao", @""),                  @"displayName", [NSArray arrayWithObjects:@"lo.lproj", @"Lao.lproj", nil],                       @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("lt")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Lithuanian", @""),           @"displayName", [NSArray arrayWithObjects:@"lt.lproj", @"Lithuanian.lproj", nil],                @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("lv")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Latvian", @""),              @"displayName", [NSArray arrayWithObjects:@"lv.lproj", @"Latvian.lproj", nil],                   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("mg")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Malagasy", @""),             @"displayName", [NSArray arrayWithObjects:@"mg.lproj", @"Malagasy.lproj", nil],                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("mk")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Macedonian", @""),           @"displayName", [NSArray arrayWithObjects:@"mk.lproj", @"Macedonian.lproj", nil],                @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("ml")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Malayalam", @""),            @"displayName", [NSArray arrayWithObjects:@"ml.lproj", @"Malayalam.lproj", nil],                 @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("mn")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Mongolian", @""),            @"displayName", [NSArray arrayWithObjects:@"mn.lproj", @"Mongolian.lproj", nil],                 @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("mo")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Moldavian", @""),            @"displayName", [NSArray arrayWithObjects:@"mo.lproj", @"Moldavian.lproj", nil],                 @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("mr")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Marathi", @""),              @"displayName", [NSArray arrayWithObjects:@"mr.lproj", @"Marathi.lproj", nil],                   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("ms")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Malay", @""),                @"displayName", [NSArray arrayWithObjects:@"ms.lproj", @"Malay.lproj", nil],                     @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("mt")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Maltese", @""),              @"displayName", [NSArray arrayWithObjects:@"mt.lproj", @"Maltese.lproj", nil],                   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("my")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Burmese", @""),              @"displayName", [NSArray arrayWithObjects:@"my.lproj", @"Burmese.lproj", nil],                   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("ne")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Nepali", @""),               @"displayName", [NSArray arrayWithObjects:@"ne.lproj", @"Nepali.lproj", nil],                    @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("nl")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Dutch", @""),                @"displayName", [NSArray arrayWithObjects:@"nl.lproj", @"nl_NL.lproj", @"Dutch.lproj", nil],     @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("nl_BE")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue, @"enabled", NSLocalizedString(@"Flemish", @""),              @"displayName", [NSArray arrayWithObjects:@"nl_BE.lproj", nil],                                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("no")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Norwegian", @""),            @"displayName", [NSArray arrayWithObjects:@"no.lproj", @"no_NO.lproj", @"Norwegian.lproj", nil], @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("nb")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Norwegian Bokmal", @""),     @"displayName", [NSArray arrayWithObjects:@"nb.lproj", nil],                                     @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("nn")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Norwegian Nynorsk", @""),    @"displayName", [NSArray arrayWithObjects:@"nn.lproj", nil],                                     @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("om")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Oromo", @""),                @"displayName", [NSArray arrayWithObjects:@"om.lproj", @"Oromo.lproj", nil],                     @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("or")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Oriya", @""),                @"displayName", [NSArray arrayWithObjects:@"or.lproj", @"Oriya.lproj", nil],                     @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("pa")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Punjabi", @""),              @"displayName", [NSArray arrayWithObjects:@"pa.lproj", @"Punjabi.lproj", nil],                   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("pl")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Polish", @""),               @"displayName", [NSArray arrayWithObjects:@"pl.lproj", @"pl_PL.lproj", @"Polish.lproj", nil],    @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("ps")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Pashto", @""),               @"displayName", [NSArray arrayWithObjects:@"ps.lproj", @"Pashto.lproj", nil],                    @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("pt")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Portuguese", @""),           @"displayName", [NSArray arrayWithObjects:@"pt.lproj", @"Portuguese.lproj", nil],                @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("pt_BR")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue, @"enabled", NSLocalizedString(@"Brazilian Portoguese", @""), @"displayName", [NSArray arrayWithObjects:@"pt_BR.lproj", nil],                                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("qu")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Quechua", @""),              @"displayName", [NSArray arrayWithObjects:@"qu.lproj", @"Quechua.lproj", nil],                   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("rn")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Rundi", @""),                @"displayName", [NSArray arrayWithObjects:@"rn.lproj", @"Rundi.lproj", nil],                     @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("ro")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Romanian", @""),             @"displayName", [NSArray arrayWithObjects:@"ro.lproj", @"Romanian.lproj", nil],                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("ru")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Russian", @""),              @"displayName", [NSArray arrayWithObjects:@"ru.lproj", @"Russian.lproj", nil],                   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("rw")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Kinyarwanda", @""),          @"displayName", [NSArray arrayWithObjects:@"rw.lproj", @"Kinyarwanda.lproj", nil],               @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("sa")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Sanskrit", @""),             @"displayName", [NSArray arrayWithObjects:@"sa.lproj", @"Sanskrit.lproj", nil],                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("sd")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Sindhi", @""),               @"displayName", [NSArray arrayWithObjects:@"sd.lproj", @"Sindhi.lproj", nil],                    @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("se")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Sami", @""),                 @"displayName", [NSArray arrayWithObjects:@"se.lproj", @"Sami.lproj", nil],                      @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("si")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Sinhalese", @""),            @"displayName", [NSArray arrayWithObjects:@"si.lproj", @"Sinhalese.lproj", nil],                 @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("sk")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Slovak", @""),               @"displayName", [NSArray arrayWithObjects:@"sk.lproj", @"Slovak.lproj", nil],                    @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("sl")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Slovenian", @""),            @"displayName", [NSArray arrayWithObjects:@"sl.lproj", @"Slovenian.lproj", nil],                 @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("so")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Somali", @""),               @"displayName", [NSArray arrayWithObjects:@"so.lproj", @"Somali.lproj", nil],                    @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("sq")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Albanian", @""),             @"displayName", [NSArray arrayWithObjects:@"sq.lproj", @"Albanian.lproj", nil],                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("sr")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Serbian", @""),              @"displayName", [NSArray arrayWithObjects:@"sr.lproj", @"Serbian.lproj", nil],                   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("su")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Sundanese", @""),            @"displayName", [NSArray arrayWithObjects:@"su.lproj", @"Sundanese.lproj", nil],                 @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("sv")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Swedish", @""),              @"displayName", [NSArray arrayWithObjects:@"sv.lproj", @"sv_SE.lproj", @"Swedish.lproj", nil],   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("sw")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Swahili", @""),              @"displayName", [NSArray arrayWithObjects:@"sw.lproj", @"Swahili.lproj", nil],                   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("ta")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Tamil", @""),                @"displayName", [NSArray arrayWithObjects:@"ta.lproj", @"Tamil.lproj", nil],                     @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("te")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Telugu", @""),               @"displayName", [NSArray arrayWithObjects:@"te.lproj", @"Telugu.lproj", nil],                    @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("tg")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Tajiki", @""),               @"displayName", [NSArray arrayWithObjects:@"tg.lproj", @"Tajiki.lproj", nil],                    @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("th")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Thai", @""),                 @"displayName", [NSArray arrayWithObjects:@"th.lproj", @"Thai.lproj", nil],                      @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("ti")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Tigrinya", @""),             @"displayName", [NSArray arrayWithObjects:@"ti.lproj", @"Tigrinya.lproj", nil],                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("tk")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Turkmen", @""),              @"displayName", [NSArray arrayWithObjects:@"tk.lproj", @"Turkmen.lproj", nil],                   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("tl")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Tagalog", @""),              @"displayName", [NSArray arrayWithObjects:@"tl.lproj", @"Tagalog.lproj", nil],                   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("tr")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Turkish", @""),              @"displayName", [NSArray arrayWithObjects:@"tr.lproj", @"tr_TR.lproj", nil],                     @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("tt")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Tatar", @""),                @"displayName", [NSArray arrayWithObjects:@"tt.lproj", @"Tatar.lproj", nil],                     @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("to")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Tongan", @""),               @"displayName", [NSArray arrayWithObjects:@"to.lproj", @"Tongan.lproj", nil],                    @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("ug")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Uighur", @""),               @"displayName", [NSArray arrayWithObjects:@"ug.lproj", @"Uighur.lproj", nil],                    @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("uk")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Ukrainian", @""),            @"displayName", [NSArray arrayWithObjects:@"uk.lproj", @"Ukrainian.lproj", nil],                 @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("ur")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Urdu", @""),                 @"displayName", [NSArray arrayWithObjects:@"ur.lproj", @"Urdu.lproj", nil],                      @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("uz")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Uzbek", @""),                @"displayName", [NSArray arrayWithObjects:@"uz.lproj", @"Uzbek.lproj", nil],                     @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("vi")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Vietnamese", @""),           @"displayName", [NSArray arrayWithObjects:@"vi.lproj", @"Vietnamese.lproj", nil],                @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("yi")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Yiddish", @""),              @"displayName", [NSArray arrayWithObjects:@"yi.lproj", @"Yiddish.lproj", nil],                   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("zh")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue,    @"enabled", NSLocalizedString(@"Chinese", @""),              @"displayName", [NSArray arrayWithObjects:@"zh.lproj", nil],                                     @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("zh_CN")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue, @"enabled", NSLocalizedString(@"Simplified Chinese", @""),   @"displayName", [NSArray arrayWithObjects:@"zh_CN.lproj", @"zh_SC.lproj", nil],                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:CFSetContainsValue(userLanguages, CFSTR("zh_TW")) ? (id)kCFBooleanFalse : (id)kCFBooleanTrue, @"enabled", NSLocalizedString(@"Traditional Chinese", @""),  @"displayName", [NSArray arrayWithObjects:@"zh_TW.lproj", nil],                                  @"folders", nil],
		nil];
	CFRelease(userLanguages);
	NSSortDescriptor *defaultSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"displayName" ascending:YES];
	NSArray *defaultSortDescriptors = [[NSArray alloc] initWithObjects:defaultSortDescriptor, nil];
	[defaultSortDescriptor release];
	[knownLanguages sortUsingDescriptors:defaultSortDescriptors];
	[defaultSortDescriptors release];
	[self setLanguages:knownLanguages];
	[knownLanguages release];

	[self scanLayouts];

	// set ourself as the Growl delegate
	[GrowlApplicationBridge setGrowlDelegate:self];

	NSString *keys[4] = {
		GROWL_APP_NAME,
		GROWL_NOTIFICATION_NAME,
		GROWL_NOTIFICATION_TITLE,
		GROWL_NOTIFICATION_DESCRIPTION
	};
	CFStringRef values[4];
	CFStringRef description;

	CFStringRef startedNotificationName = CFCopyLocalizedString(CFSTR("Monolingual started"), "");	
	description = CFCopyLocalizedString(CFSTR("Started removing language files"), "");
	values[0] = CFSTR("Monolingual");
	values[1] = startedNotificationName;
	values[2] = startedNotificationName;
	values[3] = description;
	startedNotificationInfo = CFDictionaryCreate(kCFAllocatorDefault, (const void **)keys, (const void **)values, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	CFRelease(startedNotificationName);
	CFRelease(description);

	CFStringRef finishedNotificationName = CFCopyLocalizedString(CFSTR("Monolingual finished"), "");
	description = CFCopyLocalizedString(CFSTR("Finished removing language files"), "");
	values[1] = finishedNotificationName;
	values[2] = finishedNotificationName;
	values[3] = description;
	finishedNotificationInfo = CFDictionaryCreate(kCFAllocatorDefault, (const void **)keys, (const void **)values, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	CFRelease(finishedNotificationName);
	CFRelease(description);
}

- (NSMutableArray *) languages {
	return (NSMutableArray *)languages;
}

- (void) setLanguages:(NSMutableArray *)inArray {
	if ((CFMutableArrayRef)inArray != languages) {
		if (languages)
			CFRelease(languages);
		languages = (CFMutableArrayRef)inArray;
		CFRetain(languages);
	}
}

- (NSMutableArray *) layouts {
	return (NSMutableArray *)layouts;
}

- (void) setLayouts:(NSMutableArray *)inArray {
	if ((CFMutableArrayRef)inArray != layouts) {
		if (layouts)
			CFRelease(layouts);
		layouts = (CFMutableArrayRef)inArray;
		CFRetain(layouts);
	}
}

@end
