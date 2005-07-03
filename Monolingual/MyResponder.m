/* 
 *  Copyright (C) 2001, 2002  Joshua Schrier (jschrier@mac.com),
 *  2004 Ingmar Stein
 *  Released under the GNU GPL.  For more information, see the header file.
 */

#import "MyResponder.h"
#import "ProgressWindowController.h"
#import "PreferencesController.h"
#import "VersionCheck.h"
#import <Growl/Growl.h>
#import <Security/Authorization.h>
#import <Security/AuthorizationTags.h>

@implementation MyResponder
ProgressWindowController *myProgress;
PreferencesController    *myPreferences;
NSWindow                 *parentWindow;
NSFileHandle             *pipeHandle;
NSMutableData            *pipeBuffer;
NSMutableArray           *languages;
NSMutableArray           *layouts;
NSDictionary             *startedNotificationInfo;
NSDictionary             *finishedNotificationInfo;
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
	const char bytes[1] = {'\0'};
	NSData *data = [[NSData alloc] initWithBytes:bytes length:1];
	[pipeHandle writeData:data];
	[pipeHandle closeFile];
	[pipeHandle release];
	[data release];
	pipeHandle = nil;
	[pipeBuffer release];

	[NSApp endSheet: [myProgress window]];
	[[myProgress window] orderOut: self]; 
	[myProgress stop];

	[GrowlApplicationBridge notifyWithDictionary:finishedNotificationInfo];

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
	NSURL *url = [[NSURL alloc] initWithString: @"http://monolingual.sourceforge.net/"];
	[[NSWorkspace sharedWorkspace] openURL:url];
	[url release];
}

- (id) init
{
	if( (self = [super init]) ) {
		parentWindow = nil;
		pipeHandle = nil;
	}
	return self;
}

- (void) scanLayouts
{
	unsigned int i;
	unsigned int length;
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSString *layoutPath = @"/System/Library/Keyboard Layouts";
	NSArray *files = [fileManager directoryContentsAtPath: layoutPath];
	length = [files count];
	NSMutableArray *scannedLayouts = [[NSMutableArray alloc] initWithCapacity:length+6];
	NSNumber *disabled = [[NSNumber alloc] initWithBool:NO];
	for( i=0; i<length; ++i ) {
		NSString *file = [files objectAtIndex: i];
		if( [[file pathExtension] isEqualToString:@"bundle"] && ![file isEqualToString:@"Roman.bundle"] )
			[scannedLayouts addObject: [NSMutableDictionary dictionaryWithObjectsAndKeys: disabled, @"enabled", NSLocalizedString([file stringByDeletingPathExtension],@""), @"displayName", NSLocalizedString(@"Keyboard Layout",@""), @"type", [layoutPath stringByAppendingPathComponent: file], @"path", nil]];
	}
	if( [fileManager fileExistsAtPath:@"/System/Library/Components/Kotoeri.component"] )
		[scannedLayouts addObject: [NSMutableDictionary dictionaryWithObjectsAndKeys: disabled, @"enabled", NSLocalizedString(@"Kotoeri",@""),             @"displayName", NSLocalizedString(@"Input Method",@""), @"type", @"/System/Library/Components/Kotoeri.component",  @"path", nil]];
	if( [fileManager fileExistsAtPath:@"/System/Library/Components/XPIM.component"] )
		[scannedLayouts addObject: [NSMutableDictionary dictionaryWithObjectsAndKeys: disabled, @"enabled", NSLocalizedString(@"Hangul",@""),              @"displayName", NSLocalizedString(@"Input Method",@""), @"type", @"/System/Library/Components/XPIM.component",     @"path", nil]];
	if( [fileManager fileExistsAtPath:@"/System/Library/Components/TCIM.component"] )
		[scannedLayouts addObject: [NSMutableDictionary dictionaryWithObjectsAndKeys: disabled, @"enabled", NSLocalizedString(@"Traditional Chinese",@""), @"displayName", NSLocalizedString(@"Input Method",@""), @"type", @"/System/Library/Components/TCIM.component",     @"path", nil]];
	if( [fileManager fileExistsAtPath:@"/System/Library/Components/SCIM.component"] )
		[scannedLayouts addObject: [NSMutableDictionary dictionaryWithObjectsAndKeys: disabled, @"enabled", NSLocalizedString(@"Simplified Chinese",@""),  @"displayName", NSLocalizedString(@"Input Method",@""), @"type", @"/System/Library/Components/SCIM.component",     @"path", nil]];
	if( [fileManager fileExistsAtPath:@"/System/Library/Components/AnjalIM.component"] )
		[scannedLayouts addObject: [NSMutableDictionary dictionaryWithObjectsAndKeys: disabled, @"enabled", NSLocalizedString(@"Murasu Anjal Tamil",@""),  @"displayName", NSLocalizedString(@"Input Method",@""), @"type", @"/System/Library/Components/AnjalIM.component",  @"path", nil]];
	if( [fileManager fileExistsAtPath:@"/System/Library/Components/HangulIM.component"] )
		[scannedLayouts addObject: [NSMutableDictionary dictionaryWithObjectsAndKeys: disabled, @"enabled", NSLocalizedString(@"Hangul",@""),              @"displayName", NSLocalizedString(@"Input Method",@""), @"type", @"/System/Library/Components/HangulIM.component", @"path", nil]];
	[disabled release];
	[self setLayouts:scannedLayouts];
}

- (IBAction) showPreferences: (id)sender
{
#pragma unused(sender)
	if( !myPreferences ) {
		myPreferences = [[PreferencesController alloc] init];
	}
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
	unsigned int k;
	unsigned int num;
	unsigned int length;
	const char *bytes;
	char hbuf[LONGEST_HUMAN_READABLE + 1];

	NSDictionary *userInfo = [aNotification userInfo];
	NSNumber *error = (NSNumber *)[userInfo objectForKey:@"NSFileHandleError"];
	if( ![error intValue] ) {
		NSData *data = (NSData *)[userInfo objectForKey:@"NSFileHandleNotificationDataItem"];
		if( [data length] ) {
			// append new data
			[pipeBuffer appendData: data];
			bytes = [pipeBuffer bytes];
			length = [pipeBuffer length];

			// count number of '\0' characters
			num = 0;
			for( i=0; i<length; ++i )
				if( !bytes[i] )
					++num;

			for( i=0, j=0; num > 1 && i<length; ++i, ++j ) {
				if( !bytes[j] ) {
					// read file name
					NSString *file = [[NSString alloc] initWithBytes: bytes length: j encoding: NSASCIIStringEncoding];
					bytes += j + 1;

					// skip to next zero character
					for( j=0; bytes[j]; ++j ) {}

					// read file size
					NSString *size = [[NSString alloc] initWithBytes: bytes length: j encoding: NSASCIIStringEncoding];
					bytesSaved += [size intValue];
					bytes += j + 1;
					i += j + 1;
					num -= 2;

					// parse file name
					NSArray *pathComponents = [file pathComponents];
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
							for( k=0; k<[languages count]; ++k ) {
								NSDictionary *language = [languages objectAtIndex: k];
								if( NSNotFound != [[language objectForKey:@"folders"] indexOfObject:pathComponent] ) {
									lang = [language objectForKey:@"displayName"];
									break;
								}
							}
						} else if( [pathExtension hasPrefix: @"com.apple.IntlDataCache"] ) {
							cache = YES;
						}
					}
					NSString *message;
					if( layout && [file hasPrefix:@"/System/Library/"] )
						message = [[NSString alloc] initWithFormat: @"%@ %@%@", NSLocalizedString(@"Removing keyboard layout", @""), layout, NSLocalizedString(@"...",@"")];
					else if( im && [file hasPrefix:@"/System/Library/"] )
						message = [[NSString alloc] initWithFormat: @"%@ %@%@", NSLocalizedString(@"Removing input method", @""), layout, NSLocalizedString(@"...",@"")];
					else if( cache )
						message = [[NSString alloc] initWithFormat: @"%@%@", NSLocalizedString(@"Clearing cache", @""), NSLocalizedString(@"...",@"")];
					else if( app )
						message = [[NSString alloc] initWithFormat: @"%@ %@ %@ %@%@", NSLocalizedString(@"Removing language", @""), lang, NSLocalizedString(@"from", @""), app, NSLocalizedString(@"...",@"")];
					else if( lang )
						message = [[NSString alloc] initWithFormat: @"%@ %@%@", NSLocalizedString(@"Removing language", @""), lang, NSLocalizedString(@"...",@"")];
					else
						message = [[NSString alloc] initWithFormat: @"%@ %@%@", NSLocalizedString(@"Removing", @""), file, NSLocalizedString(@"...",@"")];

					[myProgress setText: message];
					[myProgress setFile: file];
					[NSApp updateWindows];
					[message release];
					[file release];
					[size release];
					j = -1;
				}
			}
			// store any remaining bytes
			NSMutableData *newdata = [[NSMutableData alloc] initWithBytes: bytes length: length-i];
			[pipeBuffer release];
			pipeBuffer = newdata;
			[pipeHandle readInBackgroundAndNotify];
		} else if( pipeHandle ) {
			// EOF
			[pipeHandle closeFile];
			[pipeHandle release];
			pipeHandle = nil;
			[pipeBuffer release];
			[NSApp endSheet:[myProgress window]];
			[[myProgress window] orderOut:self]; 
			[myProgress stop];

			[[NSNotificationCenter defaultCenter] removeObserver:self
															name:NSFileHandleReadCompletionNotification 
														  object:nil];
			[GrowlApplicationBridge notifyWithDictionary:finishedNotificationInfo];

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
		[GrowlApplicationBridge notifyWithDictionary:startedNotificationInfo];

		bytesSaved = 0ULL;
		pipeBuffer = [[NSMutableData alloc] initWithCapacity:1024];
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
	NSDictionary	*row;
	BOOL			trash;
	const char		**argv;

	if( NSAlertDefaultReturn == returnCode ) {
		NSBeginAlertSheet(NSLocalizedString(@"Nothing done",@""),@"OK",nil,nil,[NSApp mainWindow],self,
						  NULL,NULL,contextInfo,
						  NSLocalizedString(@"Monolingual is stopping without making any changes.  Your OS has not been modified.",@""),nil);
	} else {
		count = [layouts count];
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
			row = [layouts objectAtIndex: i];
			if( [[row objectForKey:@"enabled"] boolValue] ) {
				argv[idx++] = "-f";
				argv[idx++] = [[row objectForKey:@"path"] fileSystemRepresentation];
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
		lCount = [languages count];
		for( i=0; i<lCount; ++i ) {
			NSDictionary *language = [languages objectAtIndex: i];
			if( [[language objectForKey:@"enabled"] boolValue] && [[[language objectForKey:@"folders"] objectAtIndex:0U] isEqualToString: @"en.lproj"] ) {
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
		lCount = [languages count];
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
			NSDictionary *language = [languages objectAtIndex: i];
			if( [[language objectForKey:@"enabled"] boolValue] ) {
				NSEnumerator *pathEnum = [[language objectForKey:@"folders"] objectEnumerator];
				NSString *path;
				while ((path = [pathEnum nextObject])) {
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
	[layouts                  release];
	[languages                release];
	[startedNotificationInfo  release];
	[finishedNotificationInfo release];
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

- (void) awakeFromNib
{
	NSMutableArray *userLanguages = [[[NSUserDefaults standardUserDefaults] objectForKey:@"AppleLanguages"] mutableCopy];

	// the localization variants have changed from en_US (<= 10.3) to en-US (>= 10.4)
	for (unsigned i=0U, count=[userLanguages count]; i<count; ++i) {
		NSMutableString *language = [[userLanguages objectAtIndex:i] mutableCopy];
		[language replaceOccurrencesOfString:@"-"
								  withString:@"_"
									 options:NSLiteralSearch
									   range:NSMakeRange(0U, [language length])];
		[userLanguages replaceObjectAtIndex:i withObject:language];
		[language release];
	}

	NSSet *userLanguagesSet = [[NSSet alloc] initWithArray:userLanguages];
	[userLanguages release];

	[[self window] setFrameAutosaveName:@"MainWindow"];

	[VersionCheck checkVersionAtURL: [NSURL URLWithString:@"http://monolingual.sourceforge.net/version.xml"]
						displayText: NSLocalizedString(@"A newer version of Monolingual is available online.  Would you like to download it now?",@"")
						downloadURL: [NSURL URLWithString:@"http://monolingual.sourceforge.net"]];

	[self setLanguages:[[NSMutableArray alloc] initWithObjects:
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"af"]],    @"enabled", NSLocalizedString(@"Afrikaans", @""),            @"displayName", [NSArray arrayWithObjects:@"af.lproj", @"Afrikaans.lproj", nil],                 @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"am"]],    @"enabled", NSLocalizedString(@"Amharic", @""),              @"displayName", [NSArray arrayWithObjects:@"am.lproj", @"Amharic.lproj", nil],                   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ar"]],    @"enabled", NSLocalizedString(@"Arabic", @""),               @"displayName", [NSArray arrayWithObjects:@"ar.lproj", @"Arabic.lproj", nil],                    @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"as"]],    @"enabled", NSLocalizedString(@"Assamese", @""),             @"displayName", [NSArray arrayWithObjects:@"as.lproj", @"Assamese.lproj", nil],                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ay"]],    @"enabled", NSLocalizedString(@"Aymara", @""),               @"displayName", [NSArray arrayWithObjects:@"ay.lproj", @"Aymara.lproj", nil],                    @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"az"]],    @"enabled", NSLocalizedString(@"Azerbaijani", @""),          @"displayName", [NSArray arrayWithObjects:@"az.lproj", @"Azerbaijani.lproj", nil],               @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"be"]],    @"enabled", NSLocalizedString(@"Byelorussian", @""),         @"displayName", [NSArray arrayWithObjects:@"be.lproj", @"Byelorussian.lproj", nil],              @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"bg"]],    @"enabled", NSLocalizedString(@"Bulgarian", @""),            @"displayName", [NSArray arrayWithObjects:@"bg.lproj", @"Bulgarian.lproj", nil],                 @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"bi"]],    @"enabled", NSLocalizedString(@"Bislama", @""),              @"displayName", [NSArray arrayWithObjects:@"bi.lproj", @"Bislama.lproj", nil],                   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"bn"]],    @"enabled", NSLocalizedString(@"Bengali", @""),              @"displayName", [NSArray arrayWithObjects:@"bn.lproj", @"Bengali.lproj", nil],                   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"bo"]],    @"enabled", NSLocalizedString(@"Tibetan", @""),              @"displayName", [NSArray arrayWithObjects:@"bo.lproj", @"Tibetan.lproj", nil],                   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"br"]],    @"enabled", NSLocalizedString(@"Breton", @""),               @"displayName", [NSArray arrayWithObjects:@"br.lproj", @"Breton.lproj", nil],                    @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ca"]],    @"enabled", NSLocalizedString(@"Catalan", @""),              @"displayName", [NSArray arrayWithObjects:@"ca.lproj", @"Catalan.lproj", nil],                   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"cs"]],    @"enabled", NSLocalizedString(@"Czech", @""),                @"displayName", [NSArray arrayWithObjects:@"cs.lproj", @"cs_CZ.lproj", @"Czech.lproj", nil],     @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"cy"]],    @"enabled", NSLocalizedString(@"Welsh", @""),                @"displayName", [NSArray arrayWithObjects:@"cy.lproj", @"Welsh.lproj", nil],                     @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"da"]],    @"enabled", NSLocalizedString(@"Danish", @""),               @"displayName", [NSArray arrayWithObjects:@"da.lproj", @"da_DK.lproj", @"Danish.lproj", nil],    @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"de"]],    @"enabled", NSLocalizedString(@"German", @""),               @"displayName", [NSArray arrayWithObjects:@"de.lproj", @"de_DE.lproj", @"German.lproj", nil],    @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"de_AT"]], @"enabled", NSLocalizedString(@"Austrian German", @""),      @"displayName", [NSArray arrayWithObjects:@"de_AT.lproj", nil],                                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"de_CH"]], @"enabled", NSLocalizedString(@"Swiss German", @""),         @"displayName", [NSArray arrayWithObjects:@"de_CH.lproj", nil],                                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"dz"]],    @"enabled", NSLocalizedString(@"Dzongkha", @""),             @"displayName", [NSArray arrayWithObjects:@"dz.lproj", @"Dzongkha.lproj", nil],                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"el"]],    @"enabled", NSLocalizedString(@"Greek", @""),                @"displayName", [NSArray arrayWithObjects:@"el.lproj", @"el_GR.lproj", @"Greek.lproj", nil],     @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: NO],                                          @"enabled", NSLocalizedString(@"English", @""),              @"displayName", [NSArray arrayWithObjects:@"en.lproj", @"English.lproj", nil],                   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"en_AU"]], @"enabled", NSLocalizedString(@"Australian English", @""),   @"displayName", [NSArray arrayWithObjects:@"en_AU.lproj", nil],                                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"en_CA"]], @"enabled", NSLocalizedString(@"Canadian English", @""),     @"displayName", [NSArray arrayWithObjects:@"en_CA.lproj", nil],                                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"en_GB"]], @"enabled", NSLocalizedString(@"British English", @""),      @"displayName", [NSArray arrayWithObjects:@"en_GB.lproj", nil],                                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"en_US"]], @"enabled", NSLocalizedString(@"U.S. English", @""),         @"displayName", [NSArray arrayWithObjects:@"en_US.lproj", nil],                                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"eo"]],    @"enabled", NSLocalizedString(@"Esperanto", @""),            @"displayName", [NSArray arrayWithObjects:@"eo.lproj", @"Esperanto.lproj", nil],                 @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"es"]],    @"enabled", NSLocalizedString(@"Spanish", @""),              @"displayName", [NSArray arrayWithObjects:@"es.lproj", @"es_ES.lproj", @"Spanish.lproj", nil],   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"et"]],    @"enabled", NSLocalizedString(@"Estonian", @""),             @"displayName", [NSArray arrayWithObjects:@"et.lproj", @"Estonian.lproj", nil],                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"eu"]],    @"enabled", NSLocalizedString(@"Basque", @""),               @"displayName", [NSArray arrayWithObjects:@"eu.lproj", @"Basque.lproj", nil],                    @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"fa"]],    @"enabled", NSLocalizedString(@"Farsi", @""),                @"displayName", [NSArray arrayWithObjects:@"fa.lproj", @"Farsi.lproj", nil],                     @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"fi"]],    @"enabled", NSLocalizedString(@"Finnish", @""),              @"displayName", [NSArray arrayWithObjects:@"fi.lproj", @"fi_FI.lproj", @"Finnish.lproj", nil],   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"fo"]],    @"enabled", NSLocalizedString(@"Faroese", @""),              @"displayName", [NSArray arrayWithObjects:@"fo.lproj", @"Faroese.lproj", nil],                   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"fr"]],    @"enabled", NSLocalizedString(@"French", @""),               @"displayName", [NSArray arrayWithObjects:@"fr.lproj", @"fr_FR.lproj", @"French.lproj", nil],    @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"fr_CA"]], @"enabled", NSLocalizedString(@"Canadian French", @""),      @"displayName", [NSArray arrayWithObjects:@"fr_CA.lproj", nil],                                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"fr_CH"]], @"enabled", NSLocalizedString(@"Swiss French", @""),         @"displayName", [NSArray arrayWithObjects:@"fr_CH.lproj", nil],                                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ga"]],    @"enabled", NSLocalizedString(@"Irish", @""),                @"displayName", [NSArray arrayWithObjects:@"ga.lproj", @"Irish.lproj", nil],                     @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"gd"]],    @"enabled", NSLocalizedString(@"Scottish", @""),             @"displayName", [NSArray arrayWithObjects:@"gd.lproj", @"Scottish.lproj", nil],                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"gl"]],    @"enabled", NSLocalizedString(@"Galician", @""),             @"displayName", [NSArray arrayWithObjects:@"gl.lproj", @"Galician.lproj", nil],                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"gn"]],    @"enabled", NSLocalizedString(@"Guarani", @""),              @"displayName", [NSArray arrayWithObjects:@"gn.lproj", @"Guarani.lproj", nil],                   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"gu"]],    @"enabled", NSLocalizedString(@"Gujarati", @""),             @"displayName", [NSArray arrayWithObjects:@"gu.lproj", @"Gujarati.lproj", nil],                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"gv"]],    @"enabled", NSLocalizedString(@"Manx", @""),                 @"displayName", [NSArray arrayWithObjects:@"gv.lproj", @"Manx.lproj", nil],                      @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"haw"]],   @"enabled", NSLocalizedString(@"Hawaiian", @""),             @"displayName", [NSArray arrayWithObjects:@"haw.lproj", @"Hawaiian.lproj", nil],                 @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"he"]],    @"enabled", NSLocalizedString(@"Hebrew", @""),               @"displayName", [NSArray arrayWithObjects:@"he.lproj", @"Hebrew.lproj", nil],                    @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"hi"]],    @"enabled", NSLocalizedString(@"Hindi", @""),                @"displayName", [NSArray arrayWithObjects:@"hi.lproj", @"Hindi.lproj", nil],                     @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"hr"]],    @"enabled", NSLocalizedString(@"Croatian", @""),             @"displayName", [NSArray arrayWithObjects:@"hr.lproj", @"Croatian.lproj", nil],                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"hu"]],    @"enabled", NSLocalizedString(@"Hungarian", @""),            @"displayName", [NSArray arrayWithObjects:@"hu.lproj", @"hu_HU.lproj", @"Hungarian.lproj", nil], @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"hy"]],    @"enabled", NSLocalizedString(@"Armenian", @""),             @"displayName", [NSArray arrayWithObjects:@"hy.lproj", @"Armenian.lproj", nil],                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"id"]],    @"enabled", NSLocalizedString(@"Indonesian", @""),           @"displayName", [NSArray arrayWithObjects:@"id.lproj", @"Indonesian.lproj", nil],                @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"is"]],    @"enabled", NSLocalizedString(@"Icelandic", @""),            @"displayName", [NSArray arrayWithObjects:@"is.lproj", @"Icelandic.lproj", nil],                 @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"it"]],    @"enabled", NSLocalizedString(@"Italian", @""),              @"displayName", [NSArray arrayWithObjects:@"it.lproj", @"it_IT.lproj", @"Italian.lproj", nil],   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"iu"]],    @"enabled", NSLocalizedString(@"Inuktitut", @""),            @"displayName", [NSArray arrayWithObjects:@"iu.lproj", @"Inuktitut.lproj", nil],                 @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ja"]],    @"enabled", NSLocalizedString(@"Japanese", @""),             @"displayName", [NSArray arrayWithObjects:@"ja.lproj", @"ja_JP.lproj", @"Japanese.lproj", nil],  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"jv"]],    @"enabled", NSLocalizedString(@"Javanese", @""),             @"displayName", [NSArray arrayWithObjects:@"jv.lproj", @"Javanese.lproj", nil],                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ka"]],    @"enabled", NSLocalizedString(@"Georgian", @""),             @"displayName", [NSArray arrayWithObjects:@"ka.lproj", @"Georgian.lproj", nil],                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"kk"]],    @"enabled", NSLocalizedString(@"Kazakh", @""),               @"displayName", [NSArray arrayWithObjects:@"kk.lproj", @"Kazakh.lproj", nil],                    @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"kl"]],    @"enabled", NSLocalizedString(@"Greenlandic", @""),          @"displayName", [NSArray arrayWithObjects:@"kl.lproj", @"Greenlandic.lproj", nil],               @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"km"]],    @"enabled", NSLocalizedString(@"Khmer", @""),                @"displayName", [NSArray arrayWithObjects:@"km.lproj", @"Khmer.lproj", nil],                     @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"kn"]],    @"enabled", NSLocalizedString(@"Kannada", @""),              @"displayName", [NSArray arrayWithObjects:@"kn.lproj", @"Kannada.lproj", nil],                   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ko"]],    @"enabled", NSLocalizedString(@"Korean", @""),               @"displayName", [NSArray arrayWithObjects:@"ko.lproj", @"ko_KR.lproj", @"Korean.lproj", nil],    @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ks"]],    @"enabled", NSLocalizedString(@"Kashmiri", @""),             @"displayName", [NSArray arrayWithObjects:@"ks.lproj", @"Kashmiri.lproj", nil],                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ku"]],    @"enabled", NSLocalizedString(@"Kurdish", @""),              @"displayName", [NSArray arrayWithObjects:@"ku.lproj", @"Kurdish.lproj", nil],                   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ky"]],    @"enabled", NSLocalizedString(@"Kirghiz", @""),              @"displayName", [NSArray arrayWithObjects:@"ky.lproj", @"Kirghiz.lproj", nil],                   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"la"]],    @"enabled", NSLocalizedString(@"Latin", @""),                @"displayName", [NSArray arrayWithObjects:@"la.lproj", @"Latin.lproj", nil],                     @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"lo"]],    @"enabled", NSLocalizedString(@"Lao", @""),                  @"displayName", [NSArray arrayWithObjects:@"lo.lproj", @"Lao.lproj", nil],                       @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"lt"]],    @"enabled", NSLocalizedString(@"Lithuanian", @""),           @"displayName", [NSArray arrayWithObjects:@"lt.lproj", @"Lithuanian.lproj", nil],                @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"lv"]],    @"enabled", NSLocalizedString(@"Latvian", @""),              @"displayName", [NSArray arrayWithObjects:@"lv.lproj", @"Latvian.lproj", nil],                   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"mg"]],    @"enabled", NSLocalizedString(@"Malagasy", @""),             @"displayName", [NSArray arrayWithObjects:@"mg.lproj", @"Malagasy.lproj", nil],                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"mk"]],    @"enabled", NSLocalizedString(@"Macedonian", @""),           @"displayName", [NSArray arrayWithObjects:@"mk.lproj", @"Macedonian.lproj", nil],                @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ml"]],    @"enabled", NSLocalizedString(@"Malayalam", @""),            @"displayName", [NSArray arrayWithObjects:@"ml.lproj", @"Malayalam.lproj", nil],                 @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"mn"]],    @"enabled", NSLocalizedString(@"Mongolian", @""),            @"displayName", [NSArray arrayWithObjects:@"mn.lproj", @"Mongolian.lproj", nil],                 @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"mo"]],    @"enabled", NSLocalizedString(@"Moldavian", @""),            @"displayName", [NSArray arrayWithObjects:@"mo.lproj", @"Moldavian.lproj", nil],                 @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"mr"]],    @"enabled", NSLocalizedString(@"Marathi", @""),              @"displayName", [NSArray arrayWithObjects:@"mr.lproj", @"Marathi.lproj", nil],                   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ms"]],    @"enabled", NSLocalizedString(@"Malay", @""),                @"displayName", [NSArray arrayWithObjects:@"ms.lproj", @"Malay.lproj", nil],                     @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"mt"]],    @"enabled", NSLocalizedString(@"Maltese", @""),              @"displayName", [NSArray arrayWithObjects:@"mt.lproj", @"Maltese.lproj", nil],                   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"my"]],    @"enabled", NSLocalizedString(@"Burmese", @""),              @"displayName", [NSArray arrayWithObjects:@"my.lproj", @"Burmese.lproj", nil],                   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ne"]],    @"enabled", NSLocalizedString(@"Nepali", @""),               @"displayName", [NSArray arrayWithObjects:@"ne.lproj", @"Nepali.lproj", nil],                    @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"nl"]],    @"enabled", NSLocalizedString(@"Dutch", @""),                @"displayName", [NSArray arrayWithObjects:@"nl.lproj", @"nl_NL.lproj", @"Dutch.lproj", nil],     @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"nl_BE"]], @"enabled", NSLocalizedString(@"Flemish", @""),              @"displayName", [NSArray arrayWithObjects:@"nl_BE.lproj", nil],                                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"no"]],    @"enabled", NSLocalizedString(@"Norwegian", @""),            @"displayName", [NSArray arrayWithObjects:@"no.lproj", @"no_NO.lproj", @"Norwegian.lproj", nil], @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"nb"]],    @"enabled", NSLocalizedString(@"Norwegian Bokmal", @""),     @"displayName", [NSArray arrayWithObjects:@"nb.lproj", nil],                                     @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"nn"]],    @"enabled", NSLocalizedString(@"Norwegian Nynorsk", @""),    @"displayName", [NSArray arrayWithObjects:@"nn.lproj", nil],                                     @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"om"]],    @"enabled", NSLocalizedString(@"Oromo", @""),                @"displayName", [NSArray arrayWithObjects:@"om.lproj", @"Oromo.lproj", nil],                     @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"or"]],    @"enabled", NSLocalizedString(@"Oriya", @""),                @"displayName", [NSArray arrayWithObjects:@"or.lproj", @"Oriya.lproj", nil],                     @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"pa"]],    @"enabled", NSLocalizedString(@"Punjabi", @""),              @"displayName", [NSArray arrayWithObjects:@"pa.lproj", @"Punjabi.lproj", nil],                   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"pl"]],    @"enabled", NSLocalizedString(@"Polish", @""),               @"displayName", [NSArray arrayWithObjects:@"pl.lproj", @"pl_PL.lproj", @"Polish.lproj", nil],    @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ps"]],    @"enabled", NSLocalizedString(@"Pashto", @""),               @"displayName", [NSArray arrayWithObjects:@"ps.lproj", @"Pashto.lproj", nil],                    @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"pt"]],    @"enabled", NSLocalizedString(@"Portuguese", @""),           @"displayName", [NSArray arrayWithObjects:@"pt.lproj", @"Portuguese.lproj", nil],                @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"pt_BR"]], @"enabled", NSLocalizedString(@"Brazilian Portoguese", @""), @"displayName", [NSArray arrayWithObjects:@"pt_BR.lproj", nil],                                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"qu"]],    @"enabled", NSLocalizedString(@"Quechua", @""),              @"displayName", [NSArray arrayWithObjects:@"qu.lproj", @"Quechua.lproj", nil],                   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"rn"]],    @"enabled", NSLocalizedString(@"Rundi", @""),                @"displayName", [NSArray arrayWithObjects:@"rn.lproj", @"Rundi.lproj", nil],                     @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ro"]],    @"enabled", NSLocalizedString(@"Romanian", @""),             @"displayName", [NSArray arrayWithObjects:@"ro.lproj", @"Romanian.lproj", nil],                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ru"]],    @"enabled", NSLocalizedString(@"Russian", @""),              @"displayName", [NSArray arrayWithObjects:@"ru.lproj", @"Russian.lproj", nil],                   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"rw"]],    @"enabled", NSLocalizedString(@"Kinyarwanda", @""),          @"displayName", [NSArray arrayWithObjects:@"rw.lproj", @"Kinyarwanda.lproj", nil],               @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"sa"]],    @"enabled", NSLocalizedString(@"Sanskrit", @""),             @"displayName", [NSArray arrayWithObjects:@"sa.lproj", @"Sanskrit.lproj", nil],                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"sd"]],    @"enabled", NSLocalizedString(@"Sindhi", @""),               @"displayName", [NSArray arrayWithObjects:@"sd.lproj", @"Sindhi.lproj", nil],                    @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"se"]],    @"enabled", NSLocalizedString(@"Sami", @""),                 @"displayName", [NSArray arrayWithObjects:@"se.lproj", @"Sami.lproj", nil],                      @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"si"]],    @"enabled", NSLocalizedString(@"Sinhalese", @""),            @"displayName", [NSArray arrayWithObjects:@"si.lproj", @"Sinhalese.lproj", nil],                 @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"sk"]],    @"enabled", NSLocalizedString(@"Slovak", @""),               @"displayName", [NSArray arrayWithObjects:@"sk.lproj", @"Slovak.lproj", nil],                    @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"sl"]],    @"enabled", NSLocalizedString(@"Slovenian", @""),            @"displayName", [NSArray arrayWithObjects:@"sl.lproj", @"Slovenian.lproj", nil],                 @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"so"]],    @"enabled", NSLocalizedString(@"Somali", @""),               @"displayName", [NSArray arrayWithObjects:@"so.lproj", @"Somali.lproj", nil],                    @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"sq"]],    @"enabled", NSLocalizedString(@"Albanian", @""),             @"displayName", [NSArray arrayWithObjects:@"sq.lproj", @"Albanian.lproj", nil],                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"sr"]],    @"enabled", NSLocalizedString(@"Serbian", @""),              @"displayName", [NSArray arrayWithObjects:@"sr.lproj", @"Serbian.lproj", nil],                   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"su"]],    @"enabled", NSLocalizedString(@"Sundanese", @""),            @"displayName", [NSArray arrayWithObjects:@"su.lproj", @"Sundanese.lproj", nil],                 @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"sv"]],    @"enabled", NSLocalizedString(@"Swedish", @""),              @"displayName", [NSArray arrayWithObjects:@"sv.lproj", @"sv_SE.lproj", @"Swedish.lproj", nil],   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"sw"]],    @"enabled", NSLocalizedString(@"Swahili", @""),              @"displayName", [NSArray arrayWithObjects:@"sw.lproj", @"Swahili.lproj", nil],                   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ta"]],    @"enabled", NSLocalizedString(@"Tamil", @""),                @"displayName", [NSArray arrayWithObjects:@"ta.lproj", @"Tamil.lproj", nil],                     @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"te"]],    @"enabled", NSLocalizedString(@"Telugu", @""),               @"displayName", [NSArray arrayWithObjects:@"te.lproj", @"Telugu.lproj", nil],                    @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"tg"]],    @"enabled", NSLocalizedString(@"Tajiki", @""),               @"displayName", [NSArray arrayWithObjects:@"tg.lproj", @"Tajiki.lproj", nil],                    @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"th"]],    @"enabled", NSLocalizedString(@"Thai", @""),                 @"displayName", [NSArray arrayWithObjects:@"th.lproj", @"Thai.lproj", nil],                      @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ti"]],    @"enabled", NSLocalizedString(@"Tigrinya", @""),             @"displayName", [NSArray arrayWithObjects:@"ti.lproj", @"Tigrinya.lproj", nil],                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"tk"]],    @"enabled", NSLocalizedString(@"Turkmen", @""),              @"displayName", [NSArray arrayWithObjects:@"tk.lproj", @"Turkmen.lproj", nil],                   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"tl"]],    @"enabled", NSLocalizedString(@"Tagalog", @""),              @"displayName", [NSArray arrayWithObjects:@"tl.lproj", @"Tagalog.lproj", nil],                   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"tr"]],    @"enabled", NSLocalizedString(@"Turkish", @""),              @"displayName", [NSArray arrayWithObjects:@"tr.lproj", @"tr_TR.lproj", nil],                     @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"tt"]],    @"enabled", NSLocalizedString(@"Tatar", @""),                @"displayName", [NSArray arrayWithObjects:@"tt.lproj", @"Tatar.lproj", nil],                     @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"to"]],    @"enabled", NSLocalizedString(@"Tongan", @""),               @"displayName", [NSArray arrayWithObjects:@"to.lproj", @"Tongan.lproj", nil],                    @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ug"]],    @"enabled", NSLocalizedString(@"Uighur", @""),               @"displayName", [NSArray arrayWithObjects:@"ug.lproj", @"Uighur.lproj", nil],                    @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"uk"]],    @"enabled", NSLocalizedString(@"Ukrainian", @""),            @"displayName", [NSArray arrayWithObjects:@"uk.lproj", @"Ukrainian.lproj", nil],                 @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ur"]],    @"enabled", NSLocalizedString(@"Urdu", @""),                 @"displayName", [NSArray arrayWithObjects:@"ur.lproj", @"Urdu.lproj", nil],                      @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"uz"]],    @"enabled", NSLocalizedString(@"Uzbek", @""),                @"displayName", [NSArray arrayWithObjects:@"uz.lproj", @"Uzbek.lproj", nil],                     @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"vi"]],    @"enabled", NSLocalizedString(@"Vietnamese", @""),           @"displayName", [NSArray arrayWithObjects:@"vi.lproj", @"Vietnamese.lproj", nil],                @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"yi"]],    @"enabled", NSLocalizedString(@"Yiddish", @""),              @"displayName", [NSArray arrayWithObjects:@"yi.lproj", @"Yiddish.lproj", nil],                   @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"zh"]],    @"enabled", NSLocalizedString(@"Chinese", @""),              @"displayName", [NSArray arrayWithObjects:@"zh.lproj", nil],                                     @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"zh_CN"]], @"enabled", NSLocalizedString(@"Simplified Chinese", @""),   @"displayName", [NSArray arrayWithObjects:@"zh_CN.lproj", @"zh_SC.lproj", nil],                  @"folders", nil],
		[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"zh_TW"]], @"enabled", NSLocalizedString(@"Traditional Chinese", @""),  @"displayName", [NSArray arrayWithObjects:@"zh_TW.lproj", nil],                                  @"folders", nil],
		nil]];
	[userLanguagesSet release];

	[self scanLayouts];

	// set ourself as the Growl delegate
	[GrowlApplicationBridge setGrowlDelegate:self];

	NSString *startedNotificationName = NSLocalizedString(@"Monolingual started", @"");
	NSString *finishedNotificationName = NSLocalizedString(@"Monolingual finished", @"");

	startedNotificationInfo = [[NSDictionary alloc] initWithObjectsAndKeys:
		@"Monolingual", GROWL_APP_NAME,
		startedNotificationName, GROWL_NOTIFICATION_NAME,
		startedNotificationName, GROWL_NOTIFICATION_TITLE,
		NSLocalizedString(@"Started removing language files",@""), GROWL_NOTIFICATION_DESCRIPTION,
		nil];

	finishedNotificationInfo = [[NSDictionary alloc] initWithObjectsAndKeys:
		@"Monolingual", GROWL_APP_NAME,
		finishedNotificationName, GROWL_NOTIFICATION_NAME,
		finishedNotificationName, GROWL_NOTIFICATION_TITLE,
		NSLocalizedString(@"Finished removing language files",@""), GROWL_NOTIFICATION_DESCRIPTION,
		nil];
}

- (NSMutableArray *) languages {
	return languages;
}

- (void) setLanguages:(NSMutableArray *)inArray {
	if (inArray != languages) {
		[languages release];
		languages = [inArray retain];
	}
}

- (NSMutableArray *) layouts {
	return layouts;
}

- (void) setLayouts:(NSMutableArray *)inArray {
	if (inArray != layouts) {
		[layouts release];
		layouts = [inArray retain];
	}
}

@end
