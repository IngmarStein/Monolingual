/* 
 *  Copyright (C) 2001, 2002  Joshua Schrier (jschrier@mac.com),
 *  2004 Ingmar Stein
 *  Released under the GNU GPL.  For more information, see the header file.
 */

#import "MyResponder.h"
#import "ProgressWindowController.h"
#import "VersionCheck.h"
#import <Security/Authorization.h>
#import <Security/AuthorizationTags.h>

@implementation MyResponder
ProgressWindowController *myProgress;
NSWindow *parentWindow;
NSFileHandle *pipeHandle;
NSMutableData *pipeBuffer;
NSMutableArray *languages;
unsigned long long bytesSaved;
int sortAscending;
NSTableColumn* sortColumn;

- (BOOL)applicationShouldTerminateAfterLastWindowClosed: (NSApplication *)theApplication
{
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

	NSBeginAlertSheet(NSLocalizedString(@"Removal cancelled",@""),@"OK",nil,nil,
			[NSApp mainWindow],self,NULL,NULL,self,
			NSLocalizedString(@"You cancelled the removal.  Some files were erased, some were not.",@""), nil);  
}

- (IBAction) documentationBundler: (id) sender
{
	NSMutableString *myPath = [[NSMutableString alloc] initWithString: [[NSBundle mainBundle] resourcePath]];
	[myPath appendString: @"/"];
	[myPath appendString: [sender title]];
	[[NSWorkspace sharedWorkspace] openFile: myPath];
	[myPath release];
}

- (IBAction) openWebsite: (id) sender
{
	[[NSWorkspace sharedWorkspace] openURL: [NSURL URLWithString: @"http://monolingual.sourceforge.net/"]];
}

- (id) init
{
	self = [super init];
	parentWindow = nil;
	pipeHandle = nil;
	return self;
}

- (IBAction) remove: (id) sender
{
	//Display a warning first
	NSBeginAlertSheet(NSLocalizedString(@"WARNING!",@""),NSLocalizedString(@"Stop",@""),NSLocalizedString(@"Continue",@""),nil,[NSApp mainWindow],self,NULL,
					  @selector(warningSelector:returnCode:contextInfo:),self,
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
static char * human_readable( unsigned long long amt, char *buf, int base )
{
	int tenths = 0;
	int power = 0;
	char *p;
	
	/* 0 means adjusted N == AMT.TENTHS;
	1 means AMT.TENTHS < adjusted N < AMT.TENTHS + 0.05;
	2 means adjusted N == AMT.TENTHS + 0.05;
	3 means AMT.TENTHS + 0.05 < adjusted N < AMT.TENTHS + 0.1.  */
	int rounding = 0;
	
	p = buf + LONGEST_HUMAN_READABLE;
	*p = '\0';

	/* Use power of BASE notation if adjusted AMT is large enough.  */

	if (base) {
		if(base <= amt) {
			power = 0;

			do {
				int r10 = (amt % base) * 10 + tenths;
				int r2 = (r10 % base) * 2 + (rounding >> 1);
				amt /= base;
				tenths = r10 / base;
				rounding = (r2 < base
							? 0 < r2 + rounding
							: 2 + (base < r2 + rounding));
				power++;
			} while (base <= amt && power < sizeof suffixes - 1);

			*--p = suffixes[power];

			if (amt < 10) {
				if (2 < rounding + (tenths & 1)) {
					tenths++;
					rounding = 0;
					
					if (tenths == 10) {
						amt++;
						tenths = 0;
					}
				}

				if (amt < 10) {
					*--p = '0' + tenths;
					*--p = '.';
					tenths = rounding = 0;
				}
			}
		} else {
			*--p = suffixes[0];
		}
	}

	if( 5 < tenths + (2 < rounding + (amt & 1)) ) {
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
					for( j=0; j<[pathComponents count]; ++j ) {
						NSString *pathComponent = [pathComponents objectAtIndex: j];
						if( [pathComponent hasSuffix: @".app"] ) {
							app = [pathComponent substringToIndex: [pathComponent length] - 4];
						} else if( [pathComponent hasSuffix: @".lproj"] ) {
							for( k=0; k<[languages count]; ++k ) {
								NSArray *language = [languages objectAtIndex: k];
								if( NSNotFound != [language indexOfObject: pathComponent] ) {
									lang = [language objectAtIndex: 1];
									break;
								}
							}
						}
					}
					NSString *message;
					if( app ) {
						message = [[NSString alloc] initWithFormat: @"%@ %@ %@ %@%@", NSLocalizedString(@"Removing language", @""), lang, NSLocalizedString(@"from", @""), app, NSLocalizedString(@"...",@"")];
					} else {
						message = [[NSString alloc] initWithFormat: @"%@ %@%@", NSLocalizedString(@"Removing language", @""), lang, NSLocalizedString(@"...",@"")];
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
			NSBeginAlertSheet(NSLocalizedString(@"Removal completed",@""),
							  @"OK",nil,nil,parentWindow,self,NULL,NULL,self,
							  [NSString stringWithFormat: NSLocalizedString(@"Language resources removed. Space saved: %s.",@""), human_readable( bytesSaved, hbuf, 1024 )],
							  nil);  
		}
	}
}

- (void) warningSelector: (NSWindow *)sheet returnCode: (int)returnCode contextInfo: (void *)contextInfo
{
	int i;
	int j;
	int k;
	int rCount;
	int lCount;
	int index;
	OSStatus status;
	FILE *pipe;

	if( returnCode == NSAlertDefaultReturn ) { 
		NSBeginAlertSheet(NSLocalizedString(@"Nothing done",@""),@"OK",nil,nil,[NSApp mainWindow],self,
			NULL,NULL,contextInfo,
			NSLocalizedString(@"Monolingual is stopping without making any changes.  Your OS has not been modified.",@""),nil);
	} else {
		rCount = 0;
		lCount = [languages count];
		const char **argv = alloca( 3*lCount*sizeof(char *) );
		index = 1;
		for( i=0; i<lCount; ++i ) {
			NSArray *language = [languages objectAtIndex: i];
			if( [[language objectAtIndex: 0] boolValue] ) {
				k = [language count];
				for( j=2; j<k; ++j ) {
					argv[index++] = [[language objectAtIndex: j] cString];
				}
				++rCount;
			}
		}

		if( rCount == lCount)  {
			NSBeginAlertSheet(NSLocalizedString(@"Cannot remove all languages",@""),@"OK",nil,nil,[NSApp mainWindow],self,NULL,NULL,nil,NSLocalizedString(@"Removing all languages will make OS X inoperable.  Please keep at least one language and try again.",@""),nil);
		} else if( rCount ) {
			// start things off if we have something to remove!
			NSString *myPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingString: @"/Helper"];
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
			argv[index++] = NULL;

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
	}
}

- (int) numberOfRowsInTableView: (NSTableView *)aTableView
{
	return( [languages count] );
}

- (id) tableView: (NSTableView *)aTableView objectValueForTableColumn: (NSTableColumn *)aTableColumn row: (int)rowIndex
{
	NSString *identifier = [aTableColumn identifier];
	NSArray *language = [languages objectAtIndex: rowIndex];
	if( [identifier isEqualToString:@"Remove"] ) {
		return( [language objectAtIndex: 0] );
	} else {
		return( [language objectAtIndex: 1] );
	}
}

- (void) tableView: (NSTableView *)aTableView setObjectValue: (id)anObject forTableColumn: (NSTableColumn *)aTableColumn row: (int) rowIndex
{
	NSMutableArray *language = [languages objectAtIndex: rowIndex];
	[language replaceObjectAtIndex: 0 withObject: anObject];
}

- (void) dealloc
{
	[sortColumn release];
	[languages release];
	[super dealloc];
}

static NSComparisonResult sortSelected( NSArray *l1, NSArray *l2, void *context )
{
	NSComparisonResult result;
	int ascending;

	ascending = (int)context;
	result = [((NSNumber *)[l1 objectAtIndex: 0]) compare: (NSNumber *)[l2 objectAtIndex: 0]];
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

static NSComparisonResult sortLanguages( NSArray *l1, NSArray *l2, void *context )
{
	NSComparisonResult result;
	int ascending;

	ascending = (int)context;
	result = [((NSString *)[l1 objectAtIndex: 1]) compare: (NSString *)[l2 objectAtIndex: 1]];
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
	NSString *identifier = [tableColumn identifier];

	if( tableColumn == sortColumn ) {
		sortAscending = !sortAscending;
	} else {
		[tableView setIndicatorImage:nil inTableColumn:sortColumn];
		[sortColumn release];
		sortColumn = [tableColumn retain];
		[tableView setHighlightedTableColumn: tableColumn];
	}

	if( [identifier isEqualToString: @"Remove"] ) {
		[languages sortUsingFunction: sortSelected context: (void *)sortAscending];
	} else {
		[languages sortUsingFunction: sortLanguages context: (void *)sortAscending];
	}
	[tableView setIndicatorImage:[NSImage imageNamed:(sortAscending) ? (@"NSAscendingSortIndicator"):(@"NSDescendingSortIndicator")] inTableColumn:tableColumn];
	[tableView reloadData];
}

- (void) awakeFromNib
{
	NSArray *userLanguages = [[NSUserDefaults standardUserDefaults] objectForKey:@"AppleLanguages"];
	NSSet *userLanguagesSet = [[NSSet alloc] initWithArray:userLanguages];

	[VersionCheck checkVersionAtURL: @"http://monolingual.sourceforge.net/version.xml" 
		displayText: NSLocalizedString(@"A newer version of Monolingual is available online.  Would you like to download it now?",@"")
		downloadURL: @"http://monolingual.sourceforge.net"];

	languages = [[NSMutableArray alloc] initWithCapacity: 116];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"af"]], NSLocalizedString(@"Afrikaans", @""), @"af.lproj", @"Afrikaans.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"am"]], NSLocalizedString(@"Amharic", @""), @"am.lproj", @"Amharic.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ar"]], NSLocalizedString(@"Arabic", @""), @"ar.lproj", @"Arabic.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"as"]], NSLocalizedString(@"Assamese", @""), @"as.lproj", @"Assamese.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ay"]], NSLocalizedString(@"Aymara", @""), @"ay.lproj", @"Aymara.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"az"]], NSLocalizedString(@"Azerbaijani", @""), @"az.lproj", @"Azerbaijani.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"be"]], NSLocalizedString(@"Byelorussian", @""), @"be.lproj", @"Byelorussian.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"bg"]], NSLocalizedString(@"Bulgarian", @""), @"bg.lproj", @"Bulgarian.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"bn"]], NSLocalizedString(@"Bengali", @""), @"bn.lproj", @"Bengali.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"bo"]], NSLocalizedString(@"Tibetan", @""), @"bo.lproj", @"Tibetan.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"br"]], NSLocalizedString(@"Breton", @""), @"br.lproj", @"Breton.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ca"]], NSLocalizedString(@"Catalan", @""), @"ca.lproj", @"Catalan.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"cs"]], NSLocalizedString(@"Czech", @""), @"cs.lproj", @"cs_CZ.lproj", @"Czech.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"cy"]], NSLocalizedString(@"Welsh", @""), @"cy.lproj", @"Welsh.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"da"]], NSLocalizedString(@"Danish", @""), @"da.lproj", @"da_DK.lproj", @"Danish.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"de"]], NSLocalizedString(@"German", @""), @"de.lproj", @"de_DE.lproj", @"German.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"dz"]], NSLocalizedString(@"Dzongkha", @""), @"dz.lproj", @"Dzongkha.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"el"]], NSLocalizedString(@"Greek", @""), @"el.lproj", @"el_GR.lproj", @"Greek.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"en"]], NSLocalizedString(@"English", @""), @"en.lproj", @"English.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"en_AU"]], NSLocalizedString(@"Australian English", @""), @"en_AU.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"en_CA"]], NSLocalizedString(@"Canadian English", @""), @"en_CA.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"en_GB"]], NSLocalizedString(@"British English", @""), @"en_GB.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"en_US"]], NSLocalizedString(@"U.S. English", @""), @"en_US.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"eo"]], NSLocalizedString(@"Esperanto", @""), @"eo.lproj", @"Esperanto.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"es"]], NSLocalizedString(@"Spanish", @""), @"es.lproj", @"es_ES.lproj", @"Spanish.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"et"]], NSLocalizedString(@"Estonian", @""), @"et.lproj", @"Estonian.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"eu"]], NSLocalizedString(@"Basque", @""), @"eu.lproj", @"Basque.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"fa"]], NSLocalizedString(@"Farsi", @""), @"fa.lproj", @"Farsi.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"fi"]], NSLocalizedString(@"Finnish", @""), @"fi.lproj", @"fi_FI.lproj", @"Finnish.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"fo"]], NSLocalizedString(@"Faroese", @""), @"fo.lproj", @"Faroese.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"fr"]], NSLocalizedString(@"French", @""), @"fr.lproj", @"fr_FR.lproj", @"French.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"fr_CA"]], NSLocalizedString(@"Canadian French", @""), @"fr_CA.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ga"]], NSLocalizedString(@"Irish", @""), @"ga.lproj", @"Irish.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"gd"]], NSLocalizedString(@"Scottish", @""), @"gd.lproj", @"Scottish.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"gl"]], NSLocalizedString(@"Galician", @""), @"gl.lproj", @"Galician.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"gn"]], NSLocalizedString(@"Guarani", @""), @"gn.lproj", @"Guarani.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"gu"]], NSLocalizedString(@"Gujarati", @""), @"gu.lproj", @"Gujarati.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"gv"]], NSLocalizedString(@"Manx", @""), @"gv.lproj", @"Manx.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"he"]], NSLocalizedString(@"Hebrew", @""), @"he.lproj", @"Hebrew.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"hi"]], NSLocalizedString(@"Hindi", @""), @"hi.lproj", @"Hindi.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"hr"]], NSLocalizedString(@"Croatian", @""), @"hr.lproj", @"Croatian.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"hu"]], NSLocalizedString(@"Hungarian", @""), @"hu.lproj", @"hu_HU.lproj", @"Hungarian.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"hy"]], NSLocalizedString(@"Armenian", @""), @"hy.lproj", @"Armenian.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"id"]], NSLocalizedString(@"Indonesian", @""), @"id.lproj", @"Indonesian.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"is"]], NSLocalizedString(@"Icelandic", @""), @"is.lproj", @"Icelandic.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"it"]], NSLocalizedString(@"Italian", @""), @"it.lproj", @"it_IT.lproj", @"Italian.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"iu"]], NSLocalizedString(@"Inuktitut", @""), @"iu.lproj", @"Inuktitut.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ja"]], NSLocalizedString(@"Japanese", @""), @"ja.lproj", @"ja_JP.lproj", @"Japanese.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"jv"]], NSLocalizedString(@"Javanese", @""), @"jv.lproj", @"Javanese.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ka"]], NSLocalizedString(@"Georgian", @""), @"ka.lproj", @"Georgian.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"kk"]], NSLocalizedString(@"Kazakh", @""), @"kk.lproj", @"Kazakh.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"kl"]], NSLocalizedString(@"Greenlandic", @""), @"kl.lproj", @"Greenlandic.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"km"]], NSLocalizedString(@"Khmer", @""), @"km.lproj", @"Khmer.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"kn"]], NSLocalizedString(@"Kannada", @""), @"kn.lproj", @"Kannada.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ko"]], NSLocalizedString(@"Korean", @""), @"ko.lproj", @"ko_KR.lproj", @"Korean.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ks"]], NSLocalizedString(@"Kashmiri", @""), @"ks.lproj", @"Kashmiri.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ku"]], NSLocalizedString(@"Kurdish", @""), @"ku.lproj", @"Kurdish.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ky"]], NSLocalizedString(@"Kirghiz", @""), @"ky.lproj", @"Kirghiz.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"la"]], NSLocalizedString(@"Latin", @""), @"la.lproj", @"Latin.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"lo"]], NSLocalizedString(@"Lao", @""), @"lo.lproj", @"Lao.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"lt"]], NSLocalizedString(@"Lithuanian", @""), @"lt.lproj", @"Lithuanian.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"lv"]], NSLocalizedString(@"Latvian", @""), @"lv.lproj", @"Latvian.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"mg"]], NSLocalizedString(@"Malagasy", @""), @"mg.lproj", @"Malagasy.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"mk"]], NSLocalizedString(@"Macedonian", @""), @"mk.lproj", @"Macedonian.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ml"]], NSLocalizedString(@"Malayalam", @""), @"ml.lproj", @"Malayalam.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"mn"]], NSLocalizedString(@"Mongolian", @""), @"mn.lproj", @"Mongolian.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"mo"]], NSLocalizedString(@"Moldavian", @""), @"mo.lproj", @"Moldavian.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"mr"]], NSLocalizedString(@"Marathi", @""), @"mr.lproj", @"Marathi.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ms"]], NSLocalizedString(@"Malay", @""), @"ms.lproj", @"Malay.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"mt"]], NSLocalizedString(@"Maltese", @""), @"mt.lproj", @"Maltese.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"my"]], NSLocalizedString(@"Burmese", @""), @"my.lproj", @"Burmese.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ne"]], NSLocalizedString(@"Nepali", @""), @"ne.lproj", @"Nepali.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"nl"]], NSLocalizedString(@"Dutch", @""), @"nl.lproj", @"nl_NL.lproj", @"Dutch.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"no"]], NSLocalizedString(@"Norwegian", @""), @"no.lproj", @"no_NO.lproj", @"Norwegian.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"om"]], NSLocalizedString(@"Oromo", @""), @"om.lproj", @"Oromo.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"or"]], NSLocalizedString(@"Oriya", @""), @"or.lproj", @"Oriya.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"pa"]], NSLocalizedString(@"Punjabi", @""), @"pa.lproj", @"Punjabi.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"pl"]], NSLocalizedString(@"Polish", @""), @"pl.lproj", @"pl_PL.lproj", @"Polish.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ps"]], NSLocalizedString(@"Pashto", @""), @"ps.lproj", @"Pashto.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"pt"]], NSLocalizedString(@"Portuguese", @""), @"pt.lproj", @"Portuguese.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"pt_BR"]], NSLocalizedString(@"Brazilian Portoguese", @""), @"pt_BR.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"qu"]], NSLocalizedString(@"Quechua", @""), @"qu.lproj", @"Quechua.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"rn"]], NSLocalizedString(@"Rundi", @""), @"rn.lproj", @"Rundi.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ro"]], NSLocalizedString(@"Romanian", @""), @"ro.lproj", @"Romanian.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ru"]], NSLocalizedString(@"Russian", @""), @"ru.lproj", @"Russian.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"rw"]], NSLocalizedString(@"Kinyarwanda", @""), @"rw.lproj", @"Kinyarwanda.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"sa"]], NSLocalizedString(@"Sanskrit", @""), @"sa.lproj", @"Sanskrit.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"sd"]], NSLocalizedString(@"Sindhi", @""), @"sd.lproj", @"Sindhi.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"se"]], NSLocalizedString(@"Sami", @""), @"se.lproj", @"Sami.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"si"]], NSLocalizedString(@"Sinhalese", @""), @"si.lproj", @"Sinhalese.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"sk"]], NSLocalizedString(@"Slovak", @""), @"sk.lproj", @"Slovak.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"sl"]], NSLocalizedString(@"Slovenian", @""), @"sl.lproj", @"Slovenian.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"so"]], NSLocalizedString(@"Somali", @""), @"so.lproj", @"Somali.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"sq"]], NSLocalizedString(@"Albanian", @""), @"sq.lproj", @"Albanian.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"sr"]], NSLocalizedString(@"Serbian", @""), @"sr.lproj", @"Serbian.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"su"]], NSLocalizedString(@"Sundanese", @""), @"su.lproj", @"Sundanese.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"sv"]], NSLocalizedString(@"Swedish", @""), @"sv.lproj", @"sv_SE.lproj", @"Swedish.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"sw"]], NSLocalizedString(@"Swahili", @""), @"sw.lproj", @"Swahili.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ta"]], NSLocalizedString(@"Tamil", @""), @"ta.lproj", @"Tamil.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"te"]], NSLocalizedString(@"Telugu", @""), @"te.lproj", @"Telugu.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"tg"]], NSLocalizedString(@"Tajiki", @""), @"tg.lproj", @"Tajiki.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"th"]], NSLocalizedString(@"Thai", @""), @"th.lproj", @"Thai.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ti"]], NSLocalizedString(@"Tigrinya", @""), @"ti.lproj", @"Tigrinya.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"tk"]], NSLocalizedString(@"Turkmen", @""), @"tk.lproj", @"Turkmen.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"tl"]], NSLocalizedString(@"Tagalog", @""), @"tl.lproj", @"Tagalog.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"tr"]], NSLocalizedString(@"Turkish", @""), @"tr.lproj", @"tr_TR.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"tt"]], NSLocalizedString(@"Tatar", @""), @"tt.lproj", @"Tatar.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"to"]], NSLocalizedString(@"Tongan", @""), @"to.lproj", @"Tongan.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ug"]], NSLocalizedString(@"Uighur", @""), @"ug.lproj", @"Uighur.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"uk"]], NSLocalizedString(@"Ukrainian", @""), @"uk.lproj", @"Ukrainian.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"ur"]], NSLocalizedString(@"Urdu", @""), @"ur.lproj", @"Urdu.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"uz"]], NSLocalizedString(@"Uzbek", @""), @"uz.lproj", @"Uzbek.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"vi"]], NSLocalizedString(@"Vietnamese", @""), @"vi.lproj", @"Vietnamese.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"yi"]], NSLocalizedString(@"Yiddish", @""), @"yi.lproj", @"Yiddish.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"zh"]], NSLocalizedString(@"Chinese", @""), @"zh.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"zh_CN"]], NSLocalizedString(@"Simplified Chinese", @""), @"zh_CN.lproj", @"zh_SC.lproj", nil]];
	[languages addObject:[NSMutableArray arrayWithObjects:[NSNumber numberWithBool: ![userLanguagesSet containsObject:@"zh_TW"]], NSLocalizedString(@"Traditional Chinese", @""), @"zh_TW.lproj", nil]];

	NSButtonCell *prototypeCell = [[[NSButtonCell alloc] initTextCell: @""] autorelease]; 
	[prototypeCell setEditable: YES]; // Not sure this one is necessary 
	[prototypeCell setButtonType:NSSwitchButton]; 
	[prototypeCell setImagePosition:NSImageOnly]; // This line is useful if you want to center the checkbox 
	NSTableColumn *removeColumn = [languageView tableColumnWithIdentifier:@"Remove"];
	NSTableColumn *languageColumn = [languageView tableColumnWithIdentifier:@"Language"];
	[removeColumn setDataCell: prototypeCell];
	sortAscending = 1;
	sortColumn = [languageColumn retain];
	[languages sortUsingFunction: sortLanguages context: (void *)sortAscending];
	[languageView setHighlightedTableColumn: languageColumn];
	[languageView setIndicatorImage: [NSImage imageNamed: @"NSAscendingSortIndicator"] inTableColumn: languageColumn];
	[languageView setDataSource: self];
	[languageView setDelegate: self];
}

@end
