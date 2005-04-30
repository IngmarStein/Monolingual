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

typedef struct tableSort_s {
	int sortAscending;
	NSTableColumn* sortColumn;
} tableSort_t;

@implementation MyResponder
ProgressWindowController *myProgress;
PreferencesController *myPreferences;
NSWindow *parentWindow;
NSFileHandle *pipeHandle;
NSMutableData *pipeBuffer;
NSMutableArray *languages;
NSMutableArray *layouts;
unsigned long long bytesSaved;
BOOL cancelled;
tableSort_t languageSort;
tableSort_t layoutSort;
NSDictionary *startedNotificationInfo;
NSDictionary *finishedNotificationInfo;

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
	const char bytes[1] = {0};
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
	[[NSWorkspace sharedWorkspace] openURL: [NSURL URLWithString: @"http://monolingual.sourceforge.net/"]];
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
	int i;
	int length;
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSString *layoutPath = @"/System/Library/Keyboard Layouts";
	NSArray *files = [fileManager directoryContentsAtPath: layoutPath];
	length = [files count];
	[layouts removeAllObjects];
	for( i=0; i<length; ++i ) {
		NSString *file = [files objectAtIndex: i];
		if( [[file pathExtension] isEqualToString:@"bundle"] ) {
			[layouts addObject: [NSMutableArray arrayWithObjects: [NSNumber numberWithBool: NO], NSLocalizedString([file stringByDeletingPathExtension],@""), NSLocalizedString(@"Keyboard Layout",@""), [layoutPath stringByAppendingPathComponent: file], nil]];
		}
	}
	if( [fileManager fileExistsAtPath:@"/System/Library/Components/Kotoeri.component"] ) {
		[layouts addObject: [NSMutableArray arrayWithObjects: [NSNumber numberWithBool: NO], NSLocalizedString(@"Kotoeri",@""), NSLocalizedString(@"Input Method",@""), @"/System/Library/Components/Kotoeri.component", nil]];
	}
	if( [fileManager fileExistsAtPath:@"/System/Library/Components/XPIM.component"] ) {
		[layouts addObject: [NSMutableArray arrayWithObjects: [NSNumber numberWithBool: NO], NSLocalizedString(@"Hangul",@""), NSLocalizedString(@"Input Method",@""), @"/System/Library/Components/XPIM.component", nil]];
	}
	if( [fileManager fileExistsAtPath:@"/System/Library/Components/TCIM.component"] ) {
		[layouts addObject: [NSMutableArray arrayWithObjects: [NSNumber numberWithBool: NO], NSLocalizedString(@"Traditional Chinese",@""), NSLocalizedString(@"Input Method",@""), @"/System/Library/Components/TCIM.component", nil]];
	}
	if( [fileManager fileExistsAtPath:@"/System/Library/Components/SCIM.component"] ) {
		[layouts addObject: [NSMutableArray arrayWithObjects: [NSNumber numberWithBool: NO], NSLocalizedString(@"Simplified Chinese",@""), NSLocalizedString(@"Input Method",@""), @"/System/Library/Components/SCIM.component", nil]];
	}
	if( [fileManager fileExistsAtPath:@"/System/Library/Components/AnjalIM.component"] ) {
		[layouts addObject: [NSMutableArray arrayWithObjects: [NSNumber numberWithBool: NO], NSLocalizedString(@"Murasu Anjal Tamil",@""), NSLocalizedString(@"Input Method",@""), @"/System/Library/Components/AnjalIM.component", nil]];
	}
	if( [fileManager fileExistsAtPath:@"/System/Library/Components/HangulIM.component"] ) {
		[layouts addObject: [NSMutableArray arrayWithObjects: [NSNumber numberWithBool: NO], NSLocalizedString(@"Hangul",@""), NSLocalizedString(@"Input Method",@""), @"/System/Library/Components/HangulIM.component", nil]];
	}
	[layoutView reloadData];
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

static const char suffixes[] =
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
	1 means AMT.TENTHS < adjusted N < AMT.TENTHS + 0.05;
	2 means adjusted N == AMT.TENTHS + 0.05;
	3 means AMT.TENTHS + 0.05 < adjusted N < AMT.TENTHS + 0.1.  */
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
			for( i=0; i<length; ++i ) {
				if( !bytes[i] ) {
					++num;
				}
			}

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
								NSArray *language = [languages objectAtIndex: k];
								if( NSNotFound != [language indexOfObject: pathComponent] ) {
									lang = [language objectAtIndex: 1U];
									break;
								}
							}
						} else if( [pathExtension hasPrefix: @"com.apple.IntlDataCache"] ) {
							cache = YES;
						}
					}
					NSString *message;
					if( layout && [file hasPrefix:@"/System/Library/"] ) {
						message = [[NSString alloc] initWithFormat: @"%@ %@%@", NSLocalizedString(@"Removing keyboard layout", @""), layout, NSLocalizedString(@"...",@"")];
					} else if( im && [file hasPrefix:@"/System/Library/"] ) {
						message = [[NSString alloc] initWithFormat: @"%@ %@%@", NSLocalizedString(@"Removing input method", @""), layout, NSLocalizedString(@"...",@"")];
					} else if( cache ) {
						message = [[NSString alloc] initWithFormat: @"%@%@", NSLocalizedString(@"Clearing cache", @""), NSLocalizedString(@"...",@"")];
					} else if( app ) {
						message = [[NSString alloc] initWithFormat: @"%@ %@ %@ %@%@", NSLocalizedString(@"Removing language", @""), lang, NSLocalizedString(@"from", @""), app, NSLocalizedString(@"...",@"")];
					} else if( lang ) {
						message = [[NSString alloc] initWithFormat: @"%@ %@%@", NSLocalizedString(@"Removing language", @""), lang, NSLocalizedString(@"...",@"")];
					} else {
						message = [[NSString alloc] initWithFormat: @"%@ %@%@", NSLocalizedString(@"Removing", @""), file, NSLocalizedString(@"...",@"")];
					}
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
							  @"OK",nil,nil,parentWindow,self,NULL,NULL,self,
							  [NSString stringWithFormat: NSLocalizedString(@"Language resources removed. Space saved: %s.",@""), human_readable( bytesSaved, hbuf, 1024 )],
							  nil);
			[self scanLayouts];
			[layoutView reloadData];
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
	int i;
	int count;
	int idx;
	NSArray *row;
	BOOL trash;
	const char **argv;

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
		if( trash ) {
			argv[idx++] = "-t";
		}
		for( i=0; i<count; ++i ) {
			row = [layouts objectAtIndex: i];
			if( [[row objectAtIndex: 0] boolValue] ) {
				argv[idx++] = "-f";
				argv[idx++] = [[row objectAtIndex: 3U] fileSystemRepresentation];
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
	int i;
	int lCount;

	if( NSAlertDefaultReturn != returnCode ) {
		lCount = [languages count];
		for( i=0; i<lCount; ++i ) {
			NSArray *language = [languages objectAtIndex: i];
			if( [[language objectAtIndex: 0U] boolValue] && [[language objectAtIndex: 2U] isEqualToString: @"en.lproj"] ) {
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
	int i;
	int j;
	int k;
	int rCount;
	int lCount;
	int idx;
	const char **argv;
	NSArray *roots;
	int roots_count;
	BOOL trash;

	roots = [[NSUserDefaults standardUserDefaults] arrayForKey:@"Roots"];
	roots_count = [roots count];

	for( i=0; i<roots_count; ++i ) {
		if( [[[roots objectAtIndex: i] objectForKey:@"Enabled"] boolValue] ) {
			break;
		}
	}
	if( i==roots_count ) {
		// No active roots
		roots_count = 0;
	}

	if( NSAlertDefaultReturn == returnCode || !roots_count ) {
		NSBeginAlertSheet(NSLocalizedString(@"Nothing done",@""),@"OK",nil,nil,[NSApp mainWindow],self,
						  NULL,NULL,contextInfo,
						  NSLocalizedString(@"Monolingual is stopping without making any changes.  Your OS has not been modified.",@""),nil);
	} else {
		rCount = 0;
		lCount = [languages count];
		argv = (const char **)malloc( (3+3*lCount+roots_count+roots_count)*sizeof(char *) );
		idx = 1;
		trash = [[NSUserDefaults standardUserDefaults] boolForKey:@"Trash"];
		if( trash ) {
			argv[idx++] = "-t";
		}
		for( i=0; i<roots_count; ++i ) {
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
		for( i=0; i<lCount; ++i ) {
			NSArray *language = [languages objectAtIndex: i];
			if( [[language objectAtIndex: 0U] boolValue] ) {
				k = [language count];
				for( j=2; j<k; ++j ) {
					NSLog( @"Will remove %@", [language objectAtIndex: j] );
					argv[idx++] = [[language objectAtIndex: j] cString];
				}
				++rCount;
			}
		}

		if( rCount == lCount)  {
			NSBeginAlertSheet(NSLocalizedString(@"Cannot remove all languages",@""),@"OK",nil,nil,[NSApp mainWindow],self,NULL,NULL,nil,NSLocalizedString(@"Removing all languages will make OS X inoperable.  Please keep at least one language and try again.",@""),nil);
		} else if( rCount ) {
			// start things off if we have something to remove!
			argv[idx] = NULL;
			[self runDeleteHelperWithArgs: argv];
		}
		free( argv );
	}
}

- (int) numberOfRowsInTableView: (NSTableView *)aTableView
{
	NSArray *dataArray;
	
	if( aTableView == languageView ) {
		dataArray = languages;
	} else {
		dataArray = layouts;
	}

	return( [dataArray count] );
}

- (id) tableView: (NSTableView *)aTableView objectValueForTableColumn: (NSTableColumn *)aTableColumn row: (int)rowIndex
{
	NSArray *dataArray;
	
	if( aTableView == languageView ) {
		dataArray = languages;
	} else {
		dataArray = layouts;
	}

	NSString *identifier = [aTableColumn identifier];
	NSArray *row = [dataArray objectAtIndex: rowIndex];
	if( [identifier isEqualToString:@"Remove"] ) {
		return( [row objectAtIndex: 0U] );
	} else if( [identifier isEqualToString:@"Type"] ) {
		return( [row objectAtIndex: 2U] );
	} else {
		return( [row objectAtIndex: 1U] );
	}
}

- (void) tableView: (NSTableView *)aTableView setObjectValue: (id)anObject forTableColumn: (NSTableColumn *)aTableColumn row: (int)rowIndex
{
#pragma unused(aTableColumn)
	NSArray *dataArray;

	if( aTableView == languageView ) {
		dataArray = languages;
	} else {
		dataArray = layouts;
	}

	NSMutableArray *row = [dataArray objectAtIndex: rowIndex];
	[row replaceObjectAtIndex: 0U withObject: anObject];
}

- (void) dealloc
{
	[myProgress release];
	[myPreferences release];
	[languageSort.sortColumn release];
	[layoutSort.sortColumn release];
	[layouts release];
	[languages release];
	[startedNotificationInfo release];
	[finishedNotificationInfo release];
	[super dealloc];
}

static NSComparisonResult sortSelected( NSArray *l1, NSArray *l2, void *context )
{
	NSComparisonResult result;
	int ascending;

	ascending = (int)context;
	result = [((NSNumber *)[l1 objectAtIndex: 0U]) compare: (NSNumber *)[l2 objectAtIndex: 0U]];
	switch( result ) {
		case NSOrderedSame:
			break;
		case NSOrderedAscending:
			result = ascending ? NSOrderedAscending : NSOrderedDescending;
			break;
		case NSOrderedDescending:
			result = ascending ? NSOrderedDescending : NSOrderedAscending;
			break;
	}
	return( result );
}

static NSComparisonResult sortNames( NSArray *l1, NSArray *l2, void *context )
{
	NSComparisonResult result;
	int ascending;

	ascending = (int)context;
	result = [((NSString *)[l1 objectAtIndex: 1U]) compare: (NSString *)[l2 objectAtIndex: 1U]];
	switch( result ) {
		case NSOrderedSame:
			break;
		case NSOrderedAscending:
			result = ascending ? NSOrderedAscending : NSOrderedDescending;
			break;
		case NSOrderedDescending:
			result = ascending ? NSOrderedDescending : NSOrderedAscending;
			break;
	}
	return( result );
}

static NSComparisonResult sortTypes( NSArray *l1, NSArray *l2, void *context )
{
	NSComparisonResult result;
	int ascending;
	
	ascending = (int)context;
	result = [((NSString *)[l1 objectAtIndex: 2U]) compare: (NSString *)[l2 objectAtIndex: 2U]];
	switch( result ) {
		case NSOrderedSame:
			break;
		case NSOrderedAscending:
			result = ascending ? NSOrderedAscending : NSOrderedDescending;
			break;
		case NSOrderedDescending:
			result = ascending ? NSOrderedDescending : NSOrderedAscending;
			break;
	}
	return( result );
}

- (void) tableView: (NSTableView *)tableView mouseDownInHeaderOfTableColumn: (NSTableColumn *)tableColumn
{
	tableSort_t *tableSort;
	NSMutableArray *dataArray;
	NSString *identifier = [tableColumn identifier];

	if( tableView == languageView ) {
		dataArray = languages;
		tableSort = &languageSort;
	} else {
		dataArray = layouts;
		tableSort = &layoutSort;
	}

	if( tableColumn == tableSort->sortColumn ) {
		tableSort->sortAscending = !tableSort->sortAscending;
	} else {
		[tableView setIndicatorImage:nil inTableColumn:tableSort->sortColumn];
		[tableSort->sortColumn release];
		tableSort->sortColumn = [tableColumn retain];
		[tableView setHighlightedTableColumn: tableColumn];
	}

	if( [identifier isEqualToString: @"Remove"] ) {
		[dataArray sortUsingFunction: sortSelected context: (void *)tableSort->sortAscending];
	} else if( [identifier isEqualToString: @"Type"] ) {
		[dataArray sortUsingFunction: sortTypes context: (void *)tableSort->sortAscending];
	} else {
		[dataArray sortUsingFunction: sortNames context: (void *)tableSort->sortAscending];
	}
	[tableView setIndicatorImage:[NSImage imageNamed:(tableSort->sortAscending) ? (@"NSAscendingSortIndicator"):(@"NSDescendingSortIndicator")] inTableColumn:tableColumn];
	[tableView reloadData];
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
	NSTableColumn *nameColumn;
	NSTableColumn *removeColumn;
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

	languages = [[NSMutableArray alloc] initWithObjects:
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"af"]], NSLocalizedString(@"Afrikaans", @""), @"af.lproj", @"Afrikaans.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"am"]], NSLocalizedString(@"Amharic", @""), @"am.lproj", @"Amharic.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ar"]], NSLocalizedString(@"Arabic", @""), @"ar.lproj", @"Arabic.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"as"]], NSLocalizedString(@"Assamese", @""), @"as.lproj", @"Assamese.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ay"]], NSLocalizedString(@"Aymara", @""), @"ay.lproj", @"Aymara.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"az"]], NSLocalizedString(@"Azerbaijani", @""), @"az.lproj", @"Azerbaijani.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"be"]], NSLocalizedString(@"Byelorussian", @""), @"be.lproj", @"Byelorussian.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"bg"]], NSLocalizedString(@"Bulgarian", @""), @"bg.lproj", @"Bulgarian.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"bi"]], NSLocalizedString(@"Bislama", @""), @"bi.lproj", @"Bislama.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"bn"]], NSLocalizedString(@"Bengali", @""), @"bn.lproj", @"Bengali.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"bo"]], NSLocalizedString(@"Tibetan", @""), @"bo.lproj", @"Tibetan.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"br"]], NSLocalizedString(@"Breton", @""), @"br.lproj", @"Breton.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ca"]], NSLocalizedString(@"Catalan", @""), @"ca.lproj", @"Catalan.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"cs"]], NSLocalizedString(@"Czech", @""), @"cs.lproj", @"cs_CZ.lproj", @"Czech.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"cy"]], NSLocalizedString(@"Welsh", @""), @"cy.lproj", @"Welsh.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"da"]], NSLocalizedString(@"Danish", @""), @"da.lproj", @"da_DK.lproj", @"Danish.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"de"]], NSLocalizedString(@"German", @""), @"de.lproj", @"de_DE.lproj", @"German.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"de_AT"]], NSLocalizedString(@"Austrian German", @""), @"de_AT.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"de_CH"]], NSLocalizedString(@"Swiss German", @""), @"de_CH.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"dz"]], NSLocalizedString(@"Dzongkha", @""), @"dz.lproj", @"Dzongkha.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"el"]], NSLocalizedString(@"Greek", @""), @"el.lproj", @"el_GR.lproj", @"Greek.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: NO], NSLocalizedString(@"English", @""), @"en.lproj", @"English.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"en_AU"]], NSLocalizedString(@"Australian English", @""), @"en_AU.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"en_CA"]], NSLocalizedString(@"Canadian English", @""), @"en_CA.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"en_GB"]], NSLocalizedString(@"British English", @""), @"en_GB.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"en_US"]], NSLocalizedString(@"U.S. English", @""), @"en_US.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"eo"]], NSLocalizedString(@"Esperanto", @""), @"eo.lproj", @"Esperanto.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"es"]], NSLocalizedString(@"Spanish", @""), @"es.lproj", @"es_ES.lproj", @"Spanish.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"et"]], NSLocalizedString(@"Estonian", @""), @"et.lproj", @"Estonian.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"eu"]], NSLocalizedString(@"Basque", @""), @"eu.lproj", @"Basque.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"fa"]], NSLocalizedString(@"Farsi", @""), @"fa.lproj", @"Farsi.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"fi"]], NSLocalizedString(@"Finnish", @""), @"fi.lproj", @"fi_FI.lproj", @"Finnish.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"fo"]], NSLocalizedString(@"Faroese", @""), @"fo.lproj", @"Faroese.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"fr"]], NSLocalizedString(@"French", @""), @"fr.lproj", @"fr_FR.lproj", @"French.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"fr_CA"]], NSLocalizedString(@"Canadian French", @""), @"fr_CA.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"fr_CH"]], NSLocalizedString(@"Swiss French", @""), @"fr_CH.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ga"]], NSLocalizedString(@"Irish", @""), @"ga.lproj", @"Irish.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"gd"]], NSLocalizedString(@"Scottish", @""), @"gd.lproj", @"Scottish.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"gl"]], NSLocalizedString(@"Galician", @""), @"gl.lproj", @"Galician.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"gn"]], NSLocalizedString(@"Guarani", @""), @"gn.lproj", @"Guarani.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"gu"]], NSLocalizedString(@"Gujarati", @""), @"gu.lproj", @"Gujarati.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"gv"]], NSLocalizedString(@"Manx", @""), @"gv.lproj", @"Manx.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"haw"]], NSLocalizedString(@"Hawaiian", @""), @"haw.lproj", @"Hawaiian.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"he"]], NSLocalizedString(@"Hebrew", @""), @"he.lproj", @"Hebrew.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"hi"]], NSLocalizedString(@"Hindi", @""), @"hi.lproj", @"Hindi.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"hr"]], NSLocalizedString(@"Croatian", @""), @"hr.lproj", @"Croatian.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"hu"]], NSLocalizedString(@"Hungarian", @""), @"hu.lproj", @"hu_HU.lproj", @"Hungarian.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"hy"]], NSLocalizedString(@"Armenian", @""), @"hy.lproj", @"Armenian.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"id"]], NSLocalizedString(@"Indonesian", @""), @"id.lproj", @"Indonesian.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"is"]], NSLocalizedString(@"Icelandic", @""), @"is.lproj", @"Icelandic.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"it"]], NSLocalizedString(@"Italian", @""), @"it.lproj", @"it_IT.lproj", @"Italian.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"iu"]], NSLocalizedString(@"Inuktitut", @""), @"iu.lproj", @"Inuktitut.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ja"]], NSLocalizedString(@"Japanese", @""), @"ja.lproj", @"ja_JP.lproj", @"Japanese.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"jv"]], NSLocalizedString(@"Javanese", @""), @"jv.lproj", @"Javanese.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ka"]], NSLocalizedString(@"Georgian", @""), @"ka.lproj", @"Georgian.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"kk"]], NSLocalizedString(@"Kazakh", @""), @"kk.lproj", @"Kazakh.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"kl"]], NSLocalizedString(@"Greenlandic", @""), @"kl.lproj", @"Greenlandic.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"km"]], NSLocalizedString(@"Khmer", @""), @"km.lproj", @"Khmer.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"kn"]], NSLocalizedString(@"Kannada", @""), @"kn.lproj", @"Kannada.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ko"]], NSLocalizedString(@"Korean", @""), @"ko.lproj", @"ko_KR.lproj", @"Korean.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ks"]], NSLocalizedString(@"Kashmiri", @""), @"ks.lproj", @"Kashmiri.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ku"]], NSLocalizedString(@"Kurdish", @""), @"ku.lproj", @"Kurdish.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ky"]], NSLocalizedString(@"Kirghiz", @""), @"ky.lproj", @"Kirghiz.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"la"]], NSLocalizedString(@"Latin", @""), @"la.lproj", @"Latin.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"lo"]], NSLocalizedString(@"Lao", @""), @"lo.lproj", @"Lao.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"lt"]], NSLocalizedString(@"Lithuanian", @""), @"lt.lproj", @"Lithuanian.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"lv"]], NSLocalizedString(@"Latvian", @""), @"lv.lproj", @"Latvian.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"mg"]], NSLocalizedString(@"Malagasy", @""), @"mg.lproj", @"Malagasy.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"mk"]], NSLocalizedString(@"Macedonian", @""), @"mk.lproj", @"Macedonian.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ml"]], NSLocalizedString(@"Malayalam", @""), @"ml.lproj", @"Malayalam.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"mn"]], NSLocalizedString(@"Mongolian", @""), @"mn.lproj", @"Mongolian.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"mo"]], NSLocalizedString(@"Moldavian", @""), @"mo.lproj", @"Moldavian.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"mr"]], NSLocalizedString(@"Marathi", @""), @"mr.lproj", @"Marathi.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ms"]], NSLocalizedString(@"Malay", @""), @"ms.lproj", @"Malay.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"mt"]], NSLocalizedString(@"Maltese", @""), @"mt.lproj", @"Maltese.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"my"]], NSLocalizedString(@"Burmese", @""), @"my.lproj", @"Burmese.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ne"]], NSLocalizedString(@"Nepali", @""), @"ne.lproj", @"Nepali.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"nl"]], NSLocalizedString(@"Dutch", @""), @"nl.lproj", @"nl_NL.lproj", @"Dutch.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"nl_BE"]], NSLocalizedString(@"Flemish", @""), @"nl_BE.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"no"]], NSLocalizedString(@"Norwegian", @""), @"no.lproj", @"no_NO.lproj", @"Norwegian.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"nb"]], NSLocalizedString(@"Norwegian Bokmal", @""), @"nb.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"nn"]], NSLocalizedString(@"Norwegian Nynorsk", @""), @"nn.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"om"]], NSLocalizedString(@"Oromo", @""), @"om.lproj", @"Oromo.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"or"]], NSLocalizedString(@"Oriya", @""), @"or.lproj", @"Oriya.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"pa"]], NSLocalizedString(@"Punjabi", @""), @"pa.lproj", @"Punjabi.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"pl"]], NSLocalizedString(@"Polish", @""), @"pl.lproj", @"pl_PL.lproj", @"Polish.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ps"]], NSLocalizedString(@"Pashto", @""), @"ps.lproj", @"Pashto.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"pt"]], NSLocalizedString(@"Portuguese", @""), @"pt.lproj", @"Portuguese.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"pt_BR"]], NSLocalizedString(@"Brazilian Portoguese", @""), @"pt_BR.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"qu"]], NSLocalizedString(@"Quechua", @""), @"qu.lproj", @"Quechua.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"rn"]], NSLocalizedString(@"Rundi", @""), @"rn.lproj", @"Rundi.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ro"]], NSLocalizedString(@"Romanian", @""), @"ro.lproj", @"Romanian.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ru"]], NSLocalizedString(@"Russian", @""), @"ru.lproj", @"Russian.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"rw"]], NSLocalizedString(@"Kinyarwanda", @""), @"rw.lproj", @"Kinyarwanda.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"sa"]], NSLocalizedString(@"Sanskrit", @""), @"sa.lproj", @"Sanskrit.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"sd"]], NSLocalizedString(@"Sindhi", @""), @"sd.lproj", @"Sindhi.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"se"]], NSLocalizedString(@"Sami", @""), @"se.lproj", @"Sami.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"si"]], NSLocalizedString(@"Sinhalese", @""), @"si.lproj", @"Sinhalese.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"sk"]], NSLocalizedString(@"Slovak", @""), @"sk.lproj", @"Slovak.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"sl"]], NSLocalizedString(@"Slovenian", @""), @"sl.lproj", @"Slovenian.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"so"]], NSLocalizedString(@"Somali", @""), @"so.lproj", @"Somali.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"sq"]], NSLocalizedString(@"Albanian", @""), @"sq.lproj", @"Albanian.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"sr"]], NSLocalizedString(@"Serbian", @""), @"sr.lproj", @"Serbian.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"su"]], NSLocalizedString(@"Sundanese", @""), @"su.lproj", @"Sundanese.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"sv"]], NSLocalizedString(@"Swedish", @""), @"sv.lproj", @"sv_SE.lproj", @"Swedish.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"sw"]], NSLocalizedString(@"Swahili", @""), @"sw.lproj", @"Swahili.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ta"]], NSLocalizedString(@"Tamil", @""), @"ta.lproj", @"Tamil.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"te"]], NSLocalizedString(@"Telugu", @""), @"te.lproj", @"Telugu.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"tg"]], NSLocalizedString(@"Tajiki", @""), @"tg.lproj", @"Tajiki.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"th"]], NSLocalizedString(@"Thai", @""), @"th.lproj", @"Thai.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ti"]], NSLocalizedString(@"Tigrinya", @""), @"ti.lproj", @"Tigrinya.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"tk"]], NSLocalizedString(@"Turkmen", @""), @"tk.lproj", @"Turkmen.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"tl"]], NSLocalizedString(@"Tagalog", @""), @"tl.lproj", @"Tagalog.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"tr"]], NSLocalizedString(@"Turkish", @""), @"tr.lproj", @"tr_TR.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"tt"]], NSLocalizedString(@"Tatar", @""), @"tt.lproj", @"Tatar.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"to"]], NSLocalizedString(@"Tongan", @""), @"to.lproj", @"Tongan.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ug"]], NSLocalizedString(@"Uighur", @""), @"ug.lproj", @"Uighur.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"uk"]], NSLocalizedString(@"Ukrainian", @""), @"uk.lproj", @"Ukrainian.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ur"]], NSLocalizedString(@"Urdu", @""), @"ur.lproj", @"Urdu.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"uz"]], NSLocalizedString(@"Uzbek", @""), @"uz.lproj", @"Uzbek.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"vi"]], NSLocalizedString(@"Vietnamese", @""), @"vi.lproj", @"Vietnamese.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"yi"]], NSLocalizedString(@"Yiddish", @""), @"yi.lproj", @"Yiddish.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"zh"]], NSLocalizedString(@"Chinese", @""), @"zh.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"zh_CN"]], NSLocalizedString(@"Simplified Chinese", @""), @"zh_CN.lproj", @"zh_SC.lproj", nil],
		[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"zh_TW"]], NSLocalizedString(@"Traditional Chinese", @""), @"zh_TW.lproj", nil],
		nil];
	[userLanguagesSet release];

	removeColumn = [languageView tableColumnWithIdentifier:@"Remove"];
	[[removeColumn dataCell] setImagePosition:NSImageOnly]; // Center the checkbox 
	nameColumn = [languageView tableColumnWithIdentifier:@"Name"];
	languageSort.sortAscending = 1;
	languageSort.sortColumn = [nameColumn retain];
	[languages sortUsingFunction: sortNames context: (void *)languageSort.sortAscending];
	[languageView setHighlightedTableColumn: nameColumn];
	[languageView setIndicatorImage: [NSImage imageNamed: @"NSAscendingSortIndicator"] inTableColumn: nameColumn];
	[languageView reloadData];

	layouts = [[NSMutableArray alloc] initWithCapacity:14];
	[self scanLayouts];

	removeColumn = [layoutView tableColumnWithIdentifier:@"Remove"];
	[[removeColumn dataCell] setImagePosition:NSImageOnly]; // Center the checkbox 
	nameColumn = [layoutView tableColumnWithIdentifier:@"Name"];
	languageSort.sortAscending = 1;
	languageSort.sortColumn = [nameColumn retain];
	[layouts sortUsingFunction: sortNames context: (void *)layoutSort.sortAscending];
	[layoutView setHighlightedTableColumn: nameColumn];
	[layoutView setIndicatorImage: [NSImage imageNamed: @"NSAscendingSortIndicator"] inTableColumn: nameColumn];

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

@end
