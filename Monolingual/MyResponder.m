/*
 *  Copyright (C) 2001, 2002  Joshua Schrier (jschrier@mac.com),
 *  2004-2006 Ingmar Stein
 *  Released under the GNU GPL.  For more information, see the header file.
 */

#import "MyResponder.h"
#import "ProgressWindowController.h"
#import "PreferencesController.h"
#import "VersionCheck.h"
#include <Security/Authorization.h>
#include <Security/AuthorizationTags.h>
#include <sys/types.h>
#include <unistd.h>
#include <mach/mach_host.h>
#include <mach/machine.h>

#define MODE_LANGUAGES		0
#define MODE_LAYOUTS		1
#define MODE_ARCHITECTURES	2

typedef struct arch_info_s {
	CFStringRef   name;
	CFStringRef   displayName;
	cpu_type_t    cpu_type;
	cpu_subtype_t cpu_subtype;
} arch_info_t;

@implementation MyResponder
ProgressWindowController *myProgress;
PreferencesController    *myPreferences;
NSWindow                 *parentWindow;
NSFileHandle             *pipeHandle;
CFMutableDataRef         pipeBuffer;
CFMutableArrayRef        languages;
CFMutableArrayRef        layouts;
CFMutableArrayRef        architectures;
CFDictionaryRef          startedNotificationInfo;
CFDictionaryRef          finishedNotificationInfo;
CFURLRef                 versionURL;
CFURLRef                 downloadURL;
unsigned long long       bytesSaved;
BOOL                     cancelled;
int                      mode;

+ (void) initialize
{
	CFTypeRef keys[2] = {
		CFSTR("Path"),
		CFSTR("Enabled")
	};
	CFTypeRef applicationsValues[2] = {
		CFSTR("/Applications"),
		kCFBooleanTrue
	};
	CFTypeRef developerValues[2] = {
		CFSTR("/Developer"),
		kCFBooleanTrue
	};
	CFTypeRef libraryValues[2] = {
		CFSTR("/Library"),
		kCFBooleanTrue
	};
	CFTypeRef systemValues[2] = {
		CFSTR("/System"),
		kCFBooleanTrue
	};
	CFDictionaryRef applications = CFDictionaryCreate(kCFAllocatorDefault, keys, applicationsValues, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	CFDictionaryRef developer = CFDictionaryCreate(kCFAllocatorDefault, keys, developerValues, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	CFDictionaryRef library = CFDictionaryCreate(kCFAllocatorDefault, keys, libraryValues, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	CFDictionaryRef systemPath = CFDictionaryCreate(kCFAllocatorDefault, keys, systemValues, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	CFTypeRef roots[4] = {
		applications,
		developer,
		library,
		systemPath
	};
	CFArrayRef defaultRoots = CFArrayCreate(kCFAllocatorDefault, roots, 4, &kCFTypeArrayCallBacks);
	CFRelease(applications);
	CFRelease(developer);
	CFRelease(library);
	CFRelease(systemPath);
	CFStringRef rootsKey = CFSTR("Roots");
	CFDictionaryRef defaultValues = CFDictionaryCreate(kCFAllocatorDefault, (const void **)&rootsKey, (const void **)&defaultRoots, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	[[NSUserDefaults standardUserDefaults] registerDefaults:(NSDictionary *)defaultValues];
	CFRelease(defaultValues);
	CFRelease(defaultRoots);
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed: (NSApplication *)theApplication
{
#pragma unused(theApplication)
	return YES;
}

- (void) cancelRemove
{
	const unsigned char bytes[1] = {'\0'};
	write([pipeHandle fileDescriptor], bytes, sizeof(bytes));
	[pipeHandle closeFile];
	[pipeHandle release];
	pipeHandle = nil;
	CFRelease(pipeBuffer);

	[NSApp endSheet:[myProgress window]];
	[[myProgress window] orderOut:self];
	[myProgress stop];

	[GrowlApplicationBridge notifyWithDictionary:(NSDictionary *)finishedNotificationInfo];

	NSBeginAlertSheet(NSLocalizedString(@"Removal cancelled",@""),nil,nil,nil,
			[NSApp mainWindow],self,NULL,NULL,self,
			NSLocalizedString(@"You cancelled the removal.  Some files were erased, some were not.",@""), nil);
}

- (IBAction) documentationBundler:(id)sender
{
	NSString *myPath = [[NSBundle mainBundle] pathForResource:[sender title] ofType:nil];
	[[NSWorkspace sharedWorkspace] openFile:myPath];
}

- (IBAction) openWebsite:(id)sender
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
	CFStringRef inputMethod = CFCopyLocalizedString(CFSTR("Input Method"),"");
	if( [fileManager fileExistsAtPath:@"/System/Library/Components/Kotoeri.component"] ) {
		CFStringRef displayName = CFCopyLocalizedString(CFSTR("Kotoeri"),"");
		CFMutableDictionaryRef layout = CFDictionaryCreateMutable(kCFAllocatorDefault, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
		CFDictionarySetValue(layout, CFSTR("enabled"), kCFBooleanFalse);
		CFDictionarySetValue(layout, CFSTR("displayName"), displayName);
		CFDictionarySetValue(layout, CFSTR("type"), inputMethod);
		CFDictionarySetValue(layout, CFSTR("path"), CFSTR("/System/Library/Components/Kotoeri.component"));
		CFRelease(displayName);
		CFArrayAppendValue(scannedLayouts, layout);
		CFRelease(layout);
	}
	if( [fileManager fileExistsAtPath:@"/System/Library/Components/XPIM.component"] ) {
		CFStringRef displayName = CFCopyLocalizedString(CFSTR("Hangul"),"");
		CFMutableDictionaryRef layout = CFDictionaryCreateMutable(kCFAllocatorDefault, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
		CFDictionarySetValue(layout, CFSTR("enabled"), kCFBooleanFalse);
		CFDictionarySetValue(layout, CFSTR("displayName"), displayName);
		CFDictionarySetValue(layout, CFSTR("type"), inputMethod);
		CFDictionarySetValue(layout, CFSTR("path"), CFSTR("/System/Library/Components/XPIM.component"));
		CFRelease(displayName);
		CFArrayAppendValue(scannedLayouts, layout);
		CFRelease(layout);
	}
	if( [fileManager fileExistsAtPath:@"/System/Library/Components/TCIM.component"] ) {
		CFStringRef displayName = CFCopyLocalizedString(CFSTR("Traditional Chinese"),"");
		CFMutableDictionaryRef layout = CFDictionaryCreateMutable(kCFAllocatorDefault, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
		CFDictionarySetValue(layout, CFSTR("enabled"), kCFBooleanFalse);
		CFDictionarySetValue(layout, CFSTR("displayName"), displayName);
		CFDictionarySetValue(layout, CFSTR("type"), inputMethod);
		CFDictionarySetValue(layout, CFSTR("path"), CFSTR("/System/Library/Components/TCIM.component"));
		CFRelease(displayName);
		CFArrayAppendValue(scannedLayouts, layout);
		CFRelease(layout);
	}
	if( [fileManager fileExistsAtPath:@"/System/Library/Components/SCIM.component"] ) {
		CFStringRef displayName = CFCopyLocalizedString(CFSTR("Simplified Chinese"),"");
		CFMutableDictionaryRef layout = CFDictionaryCreateMutable(kCFAllocatorDefault, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
		CFDictionarySetValue(layout, CFSTR("enabled"), kCFBooleanFalse);
		CFDictionarySetValue(layout, CFSTR("displayName"), displayName);
		CFDictionarySetValue(layout, CFSTR("type"), inputMethod);
		CFDictionarySetValue(layout, CFSTR("path"), CFSTR("/System/Library/Components/SCIM.component"));
		CFRelease(displayName);
		CFArrayAppendValue(scannedLayouts, layout);
		CFRelease(layout);
	}
	if( [fileManager fileExistsAtPath:@"/System/Library/Components/AnjalIM.component"] ) {
		CFStringRef displayName = CFCopyLocalizedString(CFSTR("Murasu Anjal Tamil"),"");
		CFMutableDictionaryRef layout = CFDictionaryCreateMutable(kCFAllocatorDefault, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
		CFDictionarySetValue(layout, CFSTR("enabled"), kCFBooleanFalse);
		CFDictionarySetValue(layout, CFSTR("displayName"), displayName);
		CFDictionarySetValue(layout, CFSTR("type"), inputMethod);
		CFDictionarySetValue(layout, CFSTR("path"), CFSTR("/System/Library/Components/AnjalIM.component"));
		CFRelease(displayName);
		CFArrayAppendValue(scannedLayouts, layout);
		CFRelease(layout);
	}
	if( [fileManager fileExistsAtPath:@"/System/Library/Components/HangulIM.component"] ) {
		CFStringRef displayName = CFCopyLocalizedString(CFSTR("Hangul"),"");
		CFMutableDictionaryRef layout = CFDictionaryCreateMutable(kCFAllocatorDefault, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
		CFDictionarySetValue(layout, CFSTR("enabled"), kCFBooleanFalse);
		CFDictionarySetValue(layout, CFSTR("displayName"), displayName);
		CFDictionarySetValue(layout, CFSTR("type"), inputMethod);
		CFDictionarySetValue(layout, CFSTR("path"), CFSTR("/System/Library/Components/HangulIM.component"));
		CFRelease(displayName);
		CFArrayAppendValue(scannedLayouts, layout);
		CFRelease(layout);
	}
	CFRelease(inputMethod);
	[self setLayouts:(NSMutableArray *)scannedLayouts];
	CFRelease(scannedLayouts);
}

- (IBAction) showPreferences:(id)sender
{
#pragma unused(sender)
	if( !myPreferences )
		myPreferences = [[PreferencesController alloc] init];
	[myPreferences showWindow: self];
}

- (IBAction) checkVersion:(id)sender {
#pragma unused(sender)
	[VersionCheck checkVersionAtURL:versionURL
						displayText:NSLocalizedString(@"A newer version of Monolingual is available online.  Would you like to download it now?",@"")
						downloadURL:downloadURL];
}

- (IBAction) removeLanguages:(id)sender
{
#pragma unused(sender)
	mode = MODE_LANGUAGES;
	//Display a warning first
	NSBeginAlertSheet(NSLocalizedString(@"WARNING!",@""),NSLocalizedString(@"Stop",@""),NSLocalizedString(@"Continue",@""),nil,[NSApp mainWindow],self,NULL,
					  @selector(warningSelector:returnCode:contextInfo:),self,
					  NSLocalizedString(@"Are you sure you want to remove these languages?  You will not be able to restore them without reinstalling OSX.",@""),nil);
}

- (IBAction) removeLayouts:(id)sender
{
#pragma unused(sender)
	mode = MODE_LAYOUTS;
	//Display a warning first
	NSBeginAlertSheet(NSLocalizedString(@"WARNING!",@""),NSLocalizedString(@"Stop",@""),NSLocalizedString(@"Continue",@""),nil,[NSApp mainWindow],self,NULL,
					  @selector(removeLayoutsWarning:returnCode:contextInfo:),self,
					  NSLocalizedString(@"Are you sure you want to remove these languages?  You will not be able to restore them without reinstalling OSX.",@""),nil);
}

- (IBAction) removeArchitectures:(id)sender
{
#pragma unused(sender)
	NSArray			*roots;
	unsigned int	roots_count;
	CFIndex			archs_count;
	const char		**argv;

	mode = MODE_ARCHITECTURES;

	roots = [[NSUserDefaults standardUserDefaults] arrayForKey:@"Roots"];
	roots_count = [roots count];
	archs_count = CFArrayGetCount(architectures);
	argv = (const char **)malloc( (2+archs_count+archs_count+roots_count+roots_count)*sizeof(char *) );
	int idx = 1;

	for( unsigned i=0U; i<roots_count; ++i ) {
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
	CFIndex remove_count = 0;
	for( CFIndex i=0; i<archs_count; ++i ) {
		CFDictionaryRef architecture = CFArrayGetValueAtIndex(architectures, i);
		if (CFBooleanGetValue(CFDictionaryGetValue(architecture, CFSTR("enabled")))) {
			CFStringRef name = CFDictionaryGetValue(architecture, CFSTR("name"));
			NSLog(@"Will remove architecture %@", name);
			argv[idx++] = "--thin";
			argv[idx++] = [(NSString *)name cStringUsingEncoding:NSUTF8StringEncoding];
			++remove_count;
		}
	}

	if( remove_count == archs_count )  {
		NSBeginAlertSheet(NSLocalizedString(@"Cannot remove all architectures",@""),
						  nil, nil, nil, [NSApp mainWindow], self, NULL,
						  NULL, nil,
						  NSLocalizedString(@"Removing all architectures will make OS X inoperable.  Please keep at least one architecture and try again.",@""),nil);
	} else if( remove_count ) {
		// start things off if we have something to remove!
		argv[idx] = NULL;
		[self runDeleteHelperWithArgs: argv];
	}
	free( argv );
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

					CFStringRef message;
					if (mode == MODE_ARCHITECTURES) {
						message = CFCopyLocalizedString(CFSTR("Removing architecture from universal binary"), "");
					} else {
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
					}

					[myProgress setText:message];
					[myProgress setFile:file];
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
							  nil, nil, nil, parentWindow, self, NULL, NULL,
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
	FILE *fp_pipe;

	NSString *myPath = [[NSBundle mainBundle] pathForResource:@"Helper" ofType:nil];
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
			NSBeginAlertSheet(NSLocalizedString(@"Permission Error",@""),nil,nil,nil,[NSApp mainWindow],self, NULL,
							  NULL,self,NSLocalizedString(@"You entered an incorrect administrator password.",@""),nil);
			return;
		case errAuthorizationCanceled:
			NSBeginAlertSheet(NSLocalizedString(@"Nothing done",@""),nil,nil,nil,[NSApp mainWindow],self,
							  NULL,NULL,NULL,
							  NSLocalizedString(@"Monolingual is stopping without making any changes.  Your OS has not been modified.",@""),nil);
			return;
		default:
			NSBeginAlertSheet(NSLocalizedString(@"Authorization Error",@""),nil,nil,nil,[NSApp mainWindow],self, NULL,
							  NULL,self,NSLocalizedString(@"Failed to authorize as an administrator.",@""),nil);
			return;
	}

	argv[0] = path;

	parentWindow = [NSApp mainWindow];
	myProgress = [ProgressWindowController sharedProgressWindowController: self];
	[myProgress start];
	[NSApp beginSheet:[myProgress window]
	   modalForWindow:parentWindow
		modalDelegate:nil
	   didEndSelector:nil
		  contextInfo:nil];

	status = AuthorizationExecuteWithPrivileges( authorizationRef, path, kAuthorizationFlagDefaults, (char * const *)argv, &fp_pipe );
	if( errAuthorizationSuccess == status ) {
		[GrowlApplicationBridge notifyWithDictionary:(NSDictionary *)startedNotificationInfo];

		bytesSaved = 0ULL;
		pipeBuffer = CFDataCreateMutable(kCFAllocatorDefault, 0);
		pipeHandle = [[NSFileHandle alloc] initWithFileDescriptor: fileno(fp_pipe)];
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
		NSBeginAlertSheet(NSLocalizedString(@"Nothing done",@""),nil,nil,nil,[NSApp mainWindow],self,
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
		NSBeginAlertSheet(NSLocalizedString(@"Nothing done",@""),nil,nil,nil,[NSApp mainWindow],self,
						  NULL,NULL,contextInfo,
						  NSLocalizedString(@"Monolingual is stopping without making any changes.  Your OS has not been modified.",@""),nil);
	} else {
		rCount = 0U;
		lCount = CFArrayGetCount(languages);
		argv = (const char **)malloc( (3+lCount+lCount+lCount+roots_count+roots_count)*sizeof(char *) );
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
							  nil, nil, nil, [NSApp mainWindow], self, NULL,
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
	[myProgress    release];
	[myPreferences release];
	CFRelease(versionURL);
	CFRelease(downloadURL);
	CFRelease(layouts);
	CFRelease(languages);
	CFRelease(startedNotificationInfo);
	CFRelease(finishedNotificationInfo);
	[super dealloc];
}

- (NSDictionary *) registrationDictionaryForGrowl
{
	CFStringRef startedNotificationName = CFCopyLocalizedString(CFSTR("Monolingual started"), "");
	CFStringRef finishedNotificationName = CFCopyLocalizedString(CFSTR("Monolingual finished"), "");
	CFTypeRef notificationNames[2] = { startedNotificationName, finishedNotificationName };

	CFArrayRef defaultAndAllNotifications = CFArrayCreate(kCFAllocatorDefault, notificationNames, 2, &kCFTypeArrayCallBacks);
	CFRelease(startedNotificationName);
	CFRelease(finishedNotificationName);
	NSDictionary *registrationDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
		(NSArray *)defaultAndAllNotifications, GROWL_NOTIFICATIONS_ALL,
		(NSArray *)defaultAndAllNotifications, GROWL_NOTIFICATIONS_DEFAULT,
		nil];
	CFRelease(defaultAndAllNotifications);

	return registrationDictionary;
}

- (void) applicationDidFinishLaunching:(NSNotification *)aNotification
{
#pragma unused(aNotification)
	[VersionCheck checkVersionAtURL:versionURL
					withDayInterval:7
						displayText:NSLocalizedString(@"A newer version of Monolingual is available online.  Would you like to download it now?",@"")
						downloadURL:downloadURL];
}

static CFComparisonResult languageCompare(const void *val1, const void *val2, void *context)
{
#pragma unused(context)
	return CFStringCompare(CFDictionaryGetValue((CFDictionaryRef)val1, CFSTR("displayName")), CFDictionaryGetValue((CFDictionaryRef)val2, CFSTR("displayName")), kCFCompareLocalized);
}

- (void) awakeFromNib
{
	versionURL = CFURLCreateWithString(kCFAllocatorDefault, CFSTR("http://monolingual.sourceforge.net/version.xml"), NULL);
	downloadURL = CFURLCreateWithString(kCFAllocatorDefault, CFSTR("http://monolingual.sourceforge.net"), NULL);

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

#define NUM_KNOWN_LANGUAGES	125
	CFMutableArrayRef knownLanguages = CFArrayCreateMutable(kCFAllocatorDefault, NUM_KNOWN_LANGUAGES, &kCFTypeArrayCallBacks);
#define ADD_LANGUAGE_BEGIN(code, name) \
	do { \
		CFMutableDictionaryRef language = CFDictionaryCreateMutable(kCFAllocatorDefault, 3, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks); \
		CFStringRef languageName = CFCopyLocalizedString(CFSTR(name), ""); \
		CFDictionarySetValue(language, CFSTR("displayName"), languageName); \
		CFRelease(languageName);
#define ADD_LANGUAGE_END \
		CFDictionarySetValue(language, CFSTR("folders"), foldersArray); \
		CFRelease(foldersArray); \
		CFArrayAppendValue(knownLanguages, language); \
		CFRelease(language); \
	} while(0)
#define ADD_LANGUAGE_0(code, name) \
	ADD_LANGUAGE_BEGIN(code, name) \
		CFDictionarySetValue(language, CFSTR("enabled"), CFSetContainsValue(userLanguages, CFSTR(code)) ? kCFBooleanFalse : kCFBooleanTrue); \
		CFStringRef folders[1]; \
		folders[0] = CFSTR(code ".lproj"); \
		CFArrayRef foldersArray = CFArrayCreate(kCFAllocatorDefault, (const void **)folders, 1, &kCFTypeArrayCallBacks); \
	ADD_LANGUAGE_END
#define ADD_LANGUAGE_1(code, name, folder) \
	ADD_LANGUAGE_BEGIN(code, name) \
		CFDictionarySetValue(language, CFSTR("enabled"), CFSetContainsValue(userLanguages, CFSTR(code)) ? kCFBooleanFalse : kCFBooleanTrue); \
		CFStringRef folders[2]; \
		folders[0] = CFSTR(code ".lproj"); \
		folders[1] = CFSTR(folder ".lproj"); \
		CFArrayRef foldersArray = CFArrayCreate(kCFAllocatorDefault, (const void **)folders, 2, &kCFTypeArrayCallBacks); \
	ADD_LANGUAGE_END
#define ADD_LANGUAGE_2(code, name, folder1, folder2) \
	ADD_LANGUAGE_BEGIN(code, name) \
		CFDictionarySetValue(language, CFSTR("enabled"), CFSetContainsValue(userLanguages, CFSTR(code)) ? kCFBooleanFalse : kCFBooleanTrue); \
		CFStringRef folders[3]; \
		folders[0] = CFSTR(code ".lproj"); \
		folders[1] = CFSTR(folder1 ".lproj"); \
		folders[2] = CFSTR(folder2 ".lproj"); \
		CFArrayRef foldersArray = CFArrayCreate(kCFAllocatorDefault, (const void **)folders, 3, &kCFTypeArrayCallBacks); \
	ADD_LANGUAGE_END
#define ADD_LANGUAGE_EN(code, name, folder) \
	ADD_LANGUAGE_BEGIN(code, name) \
		CFDictionarySetValue(language, CFSTR("enabled"), kCFBooleanFalse); \
		CFStringRef folders[2]; \
		folders[0] = CFSTR(code ".lproj"); \
		folders[1] = CFSTR(folder ".lproj"); \
		CFArrayRef foldersArray = CFArrayCreate(kCFAllocatorDefault, (const void **)folders, 2, &kCFTypeArrayCallBacks); \
	ADD_LANGUAGE_END
#define NUM_KNOWN_LANGUAGES	125

	ADD_LANGUAGE_1("af",    "Afrikaans",            "Afrikaans");
	ADD_LANGUAGE_1("am",    "Amharic",              "Amharic");
	ADD_LANGUAGE_1("ar",    "Arabic",               "Arabic");
	ADD_LANGUAGE_1("as",    "Assamese",             "Assamese");
	ADD_LANGUAGE_1("ay",    "Aymara",               "Aymara");
	ADD_LANGUAGE_1("az",    "Azerbaijani",          "Azerbaijani");
	ADD_LANGUAGE_1("be",    "Byelorussian",         "Byelorussian");
	ADD_LANGUAGE_1("bg",    "Bulgarian",            "Bulgarian");
	ADD_LANGUAGE_1("bi",    "Bislama",              "Bislama");
	ADD_LANGUAGE_1("bn",    "Bengali",              "Bengali");
	ADD_LANGUAGE_1("bo",    "Tibetan",              "Tibetan");
	ADD_LANGUAGE_1("br",    "Breton",               "Breton");
	ADD_LANGUAGE_1("ca",    "Catalan",              "Catalan");
	ADD_LANGUAGE_2("cs",    "Czech",                "cs_CZ", "Czech");
	ADD_LANGUAGE_1("cy",    "Welsh",                "Welsh");
	ADD_LANGUAGE_2("da",    "Danish",               "da_DK", "Danish");
	ADD_LANGUAGE_2("de",    "German",               "de_DE", "German");
	ADD_LANGUAGE_0("de_AT", "Austrian German");
	ADD_LANGUAGE_0("de_CH", "Swiss German");
	ADD_LANGUAGE_1("dz",    "Dzongkha",             "Dzongkha");
	ADD_LANGUAGE_2("el",    "Greek",                "el_GR", "Greek");
	ADD_LANGUAGE_EN("en",   "English",              "English");
	ADD_LANGUAGE_0("en_AU", "Australian English");
	ADD_LANGUAGE_0("en_CA", "Canadian English");
	ADD_LANGUAGE_0("en_GB", "British English");
	ADD_LANGUAGE_0("en_US", "U.S. English");
	ADD_LANGUAGE_1("eo",    "Esperanto",            "Esperanto");
	ADD_LANGUAGE_2("es",    "Spanish",              "es_ES", "Spanish");
	ADD_LANGUAGE_1("et",    "Estonian",             "Estonian");
	ADD_LANGUAGE_1("eu",    "Basque",               "Basque");
	ADD_LANGUAGE_1("fa",    "Farsi",                "Farsi");
	ADD_LANGUAGE_2("fi",    "Finnish",              "fi_FI", "Finnish");
	ADD_LANGUAGE_1("fo",    "Faroese",              "Faroese");
	ADD_LANGUAGE_2("fr",    "French",               "fr_FR", "French");
	ADD_LANGUAGE_0("fr_CA", "Canadian French");
	ADD_LANGUAGE_0("fr_CH", "Swiss French");
	ADD_LANGUAGE_1("ga",    "Irish",                "Irish");
	ADD_LANGUAGE_1("gd",    "Scottish",             "Scottish");
	ADD_LANGUAGE_1("gl",    "Galician",             "Galician");
	ADD_LANGUAGE_1("gn",    "Guarani",              "Guarani");
	ADD_LANGUAGE_1("gu",    "Gujarati",             "Gujarati");
	ADD_LANGUAGE_1("gv",    "Manx",                 "Manx");
	ADD_LANGUAGE_1("haw",   "Hawaiian",             "Hawaiian");
	ADD_LANGUAGE_1("he",    "Hebrew",               "Hebrew");
	ADD_LANGUAGE_1("hi",    "Hindi",                "Hindi");
	ADD_LANGUAGE_1("hr",    "Croatian",             "Croatian");
	ADD_LANGUAGE_2("hu",    "Hungarian",            "hu_HU", "Hungarian");
	ADD_LANGUAGE_1("hy",    "Armenian",             "Armenian");
	ADD_LANGUAGE_1("id",    "Indonesian",           "Indonesian");
	ADD_LANGUAGE_1("is",    "Icelandic",            "Icelandic");
	ADD_LANGUAGE_2("it",    "Italian",              "it_IT", "Italian");
	ADD_LANGUAGE_1("iu",    "Inuktitut",            "Inuktitut");
	ADD_LANGUAGE_2("ja",    "Japanese",             "ja_JP", "Japanese");
	ADD_LANGUAGE_1("jv",    "Javanese",             "Javanese");
	ADD_LANGUAGE_1("ka",    "Georgian",             "Georgian");
	ADD_LANGUAGE_1("kk",    "Kazakh",               "Kazakh");
	ADD_LANGUAGE_1("kl",    "Greenlandic",          "Greenlandic");
	ADD_LANGUAGE_1("km",    "Khmer",                "Khmer");
	ADD_LANGUAGE_1("kn",    "Kannada",              "Kannada");
	ADD_LANGUAGE_2("ko",    "Korean",               "ko_KR", "Korean");
	ADD_LANGUAGE_1("ks",    "Kashmiri",             "Kashmiri");
	ADD_LANGUAGE_1("ku",    "Kurdish",              "Kurdish");
	ADD_LANGUAGE_1("ky",    "Kirghiz",              "Kirghiz");
	ADD_LANGUAGE_1("la",    "Latin",                "Latin");
	ADD_LANGUAGE_1("lo",    "Lao",                  "Lao");
	ADD_LANGUAGE_1("lt",    "Lithuanian",           "Lithuanian");
	ADD_LANGUAGE_1("lv",    "Latvian",              "Latvian");
	ADD_LANGUAGE_1("mg",    "Malagasy",             "Malagasy");
	ADD_LANGUAGE_1("mk",    "Macedonian",           "Macedonian");
	ADD_LANGUAGE_1("ml",    "Malayalam",            "Malayalam");
	ADD_LANGUAGE_1("mn",    "Mongolian",            "Mongolian");
	ADD_LANGUAGE_1("mo",    "Moldavian",            "Moldavian");
	ADD_LANGUAGE_1("mr",    "Marathi",              "Marathi");
	ADD_LANGUAGE_1("ms",    "Malay",                "Malay");
	ADD_LANGUAGE_1("mt",    "Maltese",              "Maltese");
	ADD_LANGUAGE_1("my",    "Burmese",              "Burmese");
	ADD_LANGUAGE_1("ne",    "Nepali",               "Nepali");
	ADD_LANGUAGE_2("nl",    "Dutch",                "nl_NL", "Dutch");
	ADD_LANGUAGE_0("nl_BE", "Flemish");
	ADD_LANGUAGE_2("no",    "Norwegian",            "no_NO", "Norwegian");
	ADD_LANGUAGE_0("nb",    "Norwegian Bokmal");
	ADD_LANGUAGE_0("nn",    "Norwegian Nynorsk");
	ADD_LANGUAGE_1("om",    "Oromo",                "Oromo");
	ADD_LANGUAGE_1("or",    "Oriya",                "Oriya");
	ADD_LANGUAGE_1("pa",    "Punjabi",              "Punjabi");
	ADD_LANGUAGE_2("pl",    "Polish",               "pl_PL", "Polish");
	ADD_LANGUAGE_1("ps",    "Pashto",               "Pashto");
	ADD_LANGUAGE_1("pt",    "Portuguese",           "Portuguese");
	ADD_LANGUAGE_0("pt_BR", "Brazilian Portoguese");
	ADD_LANGUAGE_1("qu",    "Quechua",              "Quechua");
	ADD_LANGUAGE_1("rn",    "Rundi",                "Rundi");
	ADD_LANGUAGE_1("ro",    "Romanian",             "Romanian");
	ADD_LANGUAGE_1("ru",    "Russian",              "Russian");
	ADD_LANGUAGE_1("rw",    "Kinyarwanda",          "Kinyarwanda");
	ADD_LANGUAGE_1("sa",    "Sanskrit",             "Sanskrit");
	ADD_LANGUAGE_1("sd",    "Sindhi",               "Sindhi");
	ADD_LANGUAGE_1("se",    "Sami",                 "Sami");
	ADD_LANGUAGE_1("si",    "Sinhalese",            "Sinhalese");
	ADD_LANGUAGE_1("sk",    "Slovak",               "Slovak");
	ADD_LANGUAGE_1("sl",    "Slovenian",            "Slovenian");
	ADD_LANGUAGE_1("so",    "Somali",               "Somali");
	ADD_LANGUAGE_1("sq",    "Albanian",             "Albanian");
	ADD_LANGUAGE_1("sr",    "Serbian",              "Serbian");
	ADD_LANGUAGE_1("su",    "Sundanese",            "Sundanese");
	ADD_LANGUAGE_2("sv",    "Swedish",              "sv_SE", "Swedish");
	ADD_LANGUAGE_1("sw",    "Swahili",              "Swahili");
	ADD_LANGUAGE_1("ta",    "Tamil",                "Tamil");
	ADD_LANGUAGE_1("te",    "Telugu",               "Telugu");
	ADD_LANGUAGE_1("tg",    "Tajiki",               "Tajiki");
	ADD_LANGUAGE_1("th",    "Thai",                 "Thai");
	ADD_LANGUAGE_1("ti",    "Tigrinya",             "Tigrinya");
	ADD_LANGUAGE_1("tk",    "Turkmen",              "Turkmen");
	ADD_LANGUAGE_1("tl",    "Tagalog",              "Tagalog");
	ADD_LANGUAGE_1("tr",    "Turkish",              "tr_TR");
	ADD_LANGUAGE_1("tt",    "Tatar",                "Tatar");
	ADD_LANGUAGE_1("to",    "Tongan",               "Tongan");
	ADD_LANGUAGE_1("ug",    "Uighur",               "Uighur");
	ADD_LANGUAGE_1("uk",    "Ukrainian",            "Ukrainian");
	ADD_LANGUAGE_1("ur",    "Urdu",                 "Urdu");
	ADD_LANGUAGE_1("uz",    "Uzbek",                "Uzbek");
	ADD_LANGUAGE_1("vi",    "Vietnamese",           "Vietnamese");
	ADD_LANGUAGE_1("yi",    "Yiddish",              "Yiddish");
	ADD_LANGUAGE_0("zh",    "Chinese");
	ADD_LANGUAGE_1("zh_CN", "Simplified Chinese",   "zh_SC");
	ADD_LANGUAGE_0("zh_TW", "Traditional Chinese");
	CFRelease(userLanguages);
	CFArraySortValues(knownLanguages, CFRangeMake(0, NUM_KNOWN_LANGUAGES), languageCompare, NULL);
	[self setLanguages:(NSMutableArray *)knownLanguages];
	CFRelease(knownLanguages);

	[self scanLayouts];

	const arch_info_t archs[8] = {
		{ CFSTR("ppc"),       CFSTR("PowerPC"),           CPU_TYPE_POWERPC, CPU_SUBTYPE_POWERPC_ALL},
		{ CFSTR("ppc750"),    CFSTR("PowerPC G3"),        CPU_TYPE_POWERPC, CPU_SUBTYPE_POWERPC_750},
		{ CFSTR("ppc7400"),   CFSTR("PowerPC G4"),        CPU_TYPE_POWERPC, CPU_SUBTYPE_POWERPC_7400},
		{ CFSTR("ppc7450"),   CFSTR("PowerPC G4+"),       CPU_TYPE_POWERPC, CPU_SUBTYPE_POWERPC_7450},
		{ CFSTR("ppc970"),    CFSTR("PowerPC G5"),        CPU_TYPE_POWERPC, CPU_SUBTYPE_POWERPC_970},
		{ CFSTR("ppc64"),     CFSTR("PowerPC 64-bit"),    CPU_TYPE_POWERPC, CPU_SUBTYPE_POWERPC_970},
		{ CFSTR("ppc970-64"), CFSTR("PowerPC G5 64-bit"), CPU_TYPE_POWERPC, CPU_SUBTYPE_POWERPC_970},
		{ CFSTR("i386"),      CFSTR("Intel"),             CPU_TYPE_X86,     CPU_SUBTYPE_INTEL_MODEL_ALL}
	};

	host_basic_info_data_t hostInfo;
	mach_msg_type_number_t infoCount = HOST_BASIC_INFO_COUNT;
	kern_return_t ret = host_info(mach_host_self(), HOST_BASIC_INFO, (host_info_t)&hostInfo, &infoCount);

	CFMutableArrayRef knownArchitectures = CFArrayCreateMutable(kCFAllocatorDefault, 8, &kCFTypeArrayCallBacks);
	for (unsigned i=0U; i<8U; ++i) {
		CFMutableDictionaryRef architecture = CFDictionaryCreateMutable(kCFAllocatorDefault, 3, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
		CFDictionarySetValue(architecture, CFSTR("enabled"), (ret == KERN_SUCCESS && hostInfo.cpu_type == archs[i].cpu_type && (!archs[i].cpu_subtype || hostInfo.cpu_subtype == archs[i].cpu_subtype)) ? kCFBooleanFalse : kCFBooleanTrue);
		CFDictionarySetValue(architecture, CFSTR("name"), archs[i].name);
		CFDictionarySetValue(architecture, CFSTR("displayName"), archs[i].displayName);
		CFArrayAppendValue(knownArchitectures, architecture);
	}
	[self setArchitectures:(NSMutableArray *)knownArchitectures];
	CFRelease(knownArchitectures);

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
	description = CFCopyLocalizedString(CFSTR("Started removing files"), "");
	values[0] = CFSTR("Monolingual");
	values[1] = startedNotificationName;
	values[2] = startedNotificationName;
	values[3] = description;
	startedNotificationInfo = CFDictionaryCreate(kCFAllocatorDefault, (const void **)keys, (const void **)values, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	CFRelease(startedNotificationName);
	CFRelease(description);

	CFStringRef finishedNotificationName = CFCopyLocalizedString(CFSTR("Monolingual finished"), "");
	description = CFCopyLocalizedString(CFSTR("Finished removing files"), "");
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

- (NSMutableArray *) architectures {
	return (NSMutableArray *)architectures;
}

- (void) setArchitectures:(NSMutableArray *)inArray {
	if ((CFMutableArrayRef)inArray != architectures) {
		if (architectures)
			CFRelease(architectures);
		architectures = (CFMutableArrayRef)inArray;
		CFRetain(architectures);
	}
}

@end
