/*
 *  Copyright (C) 2001, 2002  Joshua Schrier (jschrier@mac.com),
 *                2004-2013 Ingmar Stein
 *  Released under the GNU GPL.  For more information, see the header file.
 */

#import "MyResponder.h"
#import "ProgressWindowController.h"
#import "PreferencesController.h"
#import "MonolingualHelperClient.h"
#import <Growl/GrowlDefines.h>
@import Darwin.POSIX.sys.types;
@import Darwin.POSIX.sys.stat;
@import Darwin.sys.param;
@import Darwin.sys.sysctl;
@import Darwin.C.string;
@import Darwin.C.stdlib;
@import Darwin.POSIX.unistd;
@import Darwin.Mach.mach_host;
@import Darwin.Mach.mach_port;
@import Darwin.Mach.machine;
@import MachO.arch;
@import Darwin.POSIX.pwd;

typedef enum {
	ModeLanguages = 0,
	ModeArchitectures = 1
} MonolingualMode;

#ifndef NELEMS
# define NELEMS(x) sizeof((x))/sizeof((x)[0])
#endif

typedef struct arch_info_s {
	const char    *name;
	const char    *displayName;
	cpu_type_t    cpu_type;
	cpu_subtype_t cpu_subtype;
} arch_info_t;

static FILE *logFile;
static char logFileName[PATH_MAX];

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

#define LONGEST_HUMAN_READABLE ((sizeof (uintmax_t) + sizeof (int)) * CHAR_BIT / 3)

/* Convert AMT to a human readable format in BUF. */
static char * human_readable(unsigned long long amt, char *buf, unsigned int base)
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

	if (base) {
		if (base <= amt) {
			power = 0U;

			do {
				long long r10 = (amt % base) * 10U + tenths;
				unsigned int r2 = (unsigned)(((r10 % base) << 1) + (rounding >> 1));
				amt /= base;
				tenths = (unsigned)(r10 / base);
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

	if (5U < tenths + (2 < rounding + (amt & 1))) {
		amt++;

		if (amt == base && power < sizeof suffixes - 1) {
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

@interface MyResponder() {
}

@property(nonatomic, strong) NSArray *blacklist;
@property(nonatomic, strong) NSArray *languages;
@property(nonatomic, strong) NSArray *architectures;

@property(nonatomic, strong) NSWindow           *parentWindow;
@property(nonatomic, strong) NSDictionary       *startedNotificationInfo;
@property(nonatomic, strong) NSDictionary       *finishedNotificationInfo;
@property(nonatomic, strong) NSURL              *donateURL;
@property(nonatomic, assign) unsigned long long bytesSaved;
@property(nonatomic, assign) MonolingualMode    mode;
@property(nonatomic, strong) NSArray            *processApplication;
@property(nonatomic, assign) dispatch_queue_t   listener_queue;
@property(nonatomic, assign) dispatch_queue_t   peer_event_queue;
@property(nonatomic, assign) xpc_connection_t   connection;
@property(nonatomic, assign) xpc_connection_t   progressConnection;

@end

@implementation MyResponder

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
	NSDictionary *applications = @{ @"Path" : @"/Applications", @"Languages" : @YES, @"Architectures" : @YES };
	NSDictionary *developer    = @{ @"Path" : @"/Developer",    @"Languages" : @YES, @"Architectures" : @YES };
	NSDictionary *library      = @{ @"Path" : @"/Library",      @"Languages" : @YES, @"Architectures" : @YES };
	NSDictionary *systemPath   = @{ @"Path" : @"/System",       @"Languages" : @YES, @"Architectures" : @NO  };
	NSArray *defaultRoots = @[ applications, developer, library, systemPath ];
	NSDictionary *defaultDict = @{ @"Roots" : defaultRoots, @"Trash" : @NO, @"Strip" : @NO };
	[[NSUserDefaults standardUserDefaults] registerDefaults:defaultDict];

	struct passwd *pwd = getpwuid(getuid());
	if (pwd && pwd->pw_dir)
		snprintf(logFileName, sizeof(logFileName), "%s/Library/Logs/Monolingual.log", pwd->pw_dir);
	else
		strncpy(logFileName, "/var/log/Monolingual.log", sizeof(logFileName));
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)theApplication
{
	return YES;
}

- (BOOL)application:(NSApplication *)theApplication openFile:(NSString *)filename
{
	NSDictionary *dict = @{ @"Path" : filename, @"Language" : @YES, @"Architectures" : @YES };

	self.processApplication = @[ dict ];

	[self warningSelector:nil returnCode:NSAlertAlternateReturn contextInfo:nil];

	return YES;
}

- (void) finishProcessing {
	[[self.progressWindowController window] orderOut:self];
	[self.progressWindowController stop];
	[NSApp endSheet:[self.progressWindowController window] returnCode:0];
}

- (IBAction) documentationBundler:(id)sender
{
	NSURL *docURL = [[NSBundle mainBundle] URLForResource:[sender title] withExtension:nil];
	[[NSWorkspace sharedWorkspace] openURL:docURL];
}

- (IBAction) openWebsite:(id)sender
{
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://monolingual.sourceforge.net/"]];
}

- (IBAction) showPreferences:(id)sender
{
	[self.preferencesController showWindow:self];
}

- (IBAction) donate:(id)sender
{
	[[NSWorkspace sharedWorkspace] openURL:self.donateURL];
}

- (IBAction) removeLanguages:(id)sender
{
	/* Display a warning first */
	NSBeginAlertSheet(NSLocalizedString(@"WARNING!", ""),
					  NSLocalizedString(@"Stop", ""),
					  NSLocalizedString(@"Continue", ""),
					  nil,
					  [NSApp mainWindow],
					  self, NULL,
					  @selector(warningSelector:returnCode:contextInfo:),
					  nil,
					  NSLocalizedString(@"Are you sure you want to remove these languages? You will not be able to restore them without reinstalling OS X.", ""));
}

- (IBAction) removeArchitectures:(id)sender
{
	self.mode = ModeArchitectures;

	logFile = fopen(logFileName, "at");
	if (logFile) {
		time_t now = time(NULL);
		fprintf(logFile, "Monolingual started at %sRemoving architectures: ", ctime(&now));
	}

	NSArray *roots = self.processApplication ? self.processApplication : [[NSUserDefaults standardUserDefaults] arrayForKey:@"Roots"];

	xpc_object_t archs = xpc_array_create(NULL, 0);
	[self.architectures enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
		if ([obj[@"Enabled"] boolValue]) {
			const char *arch = [obj[@"Name"] UTF8String];
			xpc_array_set_string(archs, XPC_ARRAY_APPEND, arch);
			if (logFile) {
				fputs(" ", logFile);
				fputs(arch, logFile);
			}
		}
	}];

	if (logFile)
		fputs("\nModified files:\n", logFile);

	size_t num_archs = xpc_array_get_count(archs);
	if (num_archs == self.architectures.count) {
		NSBeginAlertSheet(NSLocalizedString(@"Cannot remove all architectures", ""),
						  nil, nil, nil, [NSApp mainWindow], self, NULL,
						  NULL, nil,
						  NSLocalizedString(@"Removing all architectures will make OS X inoperable. Please keep at least one architecture and try again.", ""));
		if (logFile) {
			fclose(logFile);
			logFile = NULL;
		}
	} else if (num_archs) {
		/* start things off if we have something to remove! */
		xpc_object_t includes = xpc_array_create(NULL, 0);
		xpc_object_t excludes = xpc_array_create(NULL, 0);
		for (NSDictionary *root in roots) {
			NSString *path = root[@"Path"];
			if ([root[@"Architectures"] boolValue]) {
				NSLog(@"Adding root %@", path);
				xpc_array_set_string(includes, XPC_ARRAY_APPEND, [path UTF8String]);
			} else {
				NSLog(@"Excluding root %@", path);
				xpc_array_set_string(excludes, XPC_ARRAY_APPEND, [path UTF8String]);
			}
		}
		xpc_array_set_string(excludes, XPC_ARRAY_APPEND, "/System/Library/Frameworks");
		xpc_array_set_string(excludes, XPC_ARRAY_APPEND, "/System/Library/PrivateFrameworks");

		xpc_object_t bl = xpc_array_create(NULL, 0);
		for (NSDictionary *item in self.blacklist) {
			if ([item[@"architectures"] boolValue]) {
				xpc_array_set_string(bl, XPC_ARRAY_APPEND, [item[@"bundle"] UTF8String]);
			}
		}

		xpc_object_t xpc_message = xpc_dictionary_create(NULL, NULL, 0);
		xpc_dictionary_set_bool(xpc_message, "strip", [[NSUserDefaults standardUserDefaults] boolForKey:@"Strip"]);
		xpc_dictionary_set_value(xpc_message, "blacklist", bl);
		xpc_dictionary_set_value(xpc_message, "includes", includes);
		xpc_dictionary_set_value(xpc_message, "excludes", excludes);
		xpc_dictionary_set_value(xpc_message, "thin", archs);
		xpc_release(bl);
		xpc_release(includes);
		xpc_release(excludes);

		[self runDeleteHelperWithArgs:xpc_message];
		
		xpc_release(xpc_message);
	} else {
		if (logFile) {
			fclose(logFile);
			logFile = NULL;
		}
	}
	
	xpc_release(archs);
}

- (void)processProgress:(xpc_object_t)progress {
	if (!xpc_dictionary_get_count(progress))
		return;
	
	NSString *file = [NSString stringWithUTF8String:xpc_dictionary_get_string(progress, "file")];
	uint64_t size = xpc_dictionary_get_uint64(progress, "size");
	self.bytesSaved += size;
	
	if (logFile)
		fprintf(logFile, "%s: %llu\n", [file UTF8String], size);

	NSString *message;
	if (self.mode == ModeArchitectures) {
		message = NSLocalizedString(@"Removing architecture from universal binary", "");
	} else {
		/* parse file name */
		NSString *lang = nil;
		NSString *app = nil;

		if (self.mode == ModeLanguages) {
			NSArray *pathComponents = [file componentsSeparatedByString:@"/"];
			for (NSString *pathComponent in pathComponents) {
				if ([pathComponent hasSuffix:@".app"]) {
					app = [pathComponent substringToIndex:pathComponent.length - 4];
				} else if ([pathComponent hasSuffix:@".lproj"]) {
					for (NSDictionary *language in self.languages) {
						NSArray *folders = [language objectForKey:@"Folders"];
						if ([folders containsObject:pathComponent]) {
							lang = [language objectForKey:@"DisplayName"];
							break;
						}
					}
				}
			}
		}
		if (app) {
			message = [NSString stringWithFormat:@"%@ %@ %@ %@%C", NSLocalizedString(@"Removing language", ""), lang, NSLocalizedString(@"from", ""), app, (unsigned short)0x2026];
		} else if (lang) {
			message = [NSString stringWithFormat:@"%@ %@%C", NSLocalizedString(@"Removing language", ""), lang, (unsigned short)0x2026];
		} else {
			message = [NSString stringWithFormat:@"%@ %@%C", NSLocalizedString(@"Removing", ""), file, (unsigned short)0x2026];
		}
	}

	[self.progressWindowController setText:message];
	[self.progressWindowController setFile:file];
	[NSApp setWindowsNeedUpdate:YES];
}

- (void) runDeleteHelperWithArgs:(xpc_object_t)arguments
{
	self.bytesSaved = 0ULL;

	NSError *error = nil;
	if (![MonolingualHelperClient installWithPrompt:nil error:&error]) {
		switch (error.code) {
			default:
			case SMJErrorCodeBundleNotFound:
			case SMJErrorCodeUnsignedBundle:
			case SMJErrorCodeBadBundleSecurity:
			case SMJErrorCodeBadBundleCodeSigningDictionary:
			case SMJErrorUnableToBless:
				NSLog(@"Failed to bless helper. Error: %@", error);
				return;
			case SMJAuthorizationDenied:
				/* If you can't do it because you're not administrator, then let the user know! */
				NSBeginAlertSheet(NSLocalizedString(@"Permission Error", ""), nil, nil, nil,
								  [NSApp mainWindow], self, NULL, NULL, NULL,
								  NSLocalizedString(@"You entered an incorrect administrator password.", ""));
				if (logFile) {
					fclose(logFile);
					logFile = NULL;
				}
				break;
			case SMJAuthorizationCanceled:
				NSBeginAlertSheet(NSLocalizedString(@"Nothing done", ""), nil, nil, nil,
								  [NSApp mainWindow], self, NULL, NULL, NULL,
								  NSLocalizedString(@"Monolingual is stopping without making any changes. Your OS has not been modified.", ""));
				if (logFile) {
					fclose(logFile);
					logFile = NULL;
				}
				break;
			case SMJAuthorizationInteractionNotAllowed:
			case SMJAuthorizationFailed:
				NSBeginAlertSheet(NSLocalizedString(@"Authorization Error", ""), nil, nil, nil,
								  [NSApp mainWindow], self, NULL, NULL, NULL,
								  NSLocalizedString(@"Failed to authorize as an administrator.", ""));
				if (logFile) {
					fclose(logFile);
					logFile = NULL;
				}
				break;
		}
		return;
	}

	self.connection = xpc_connection_create_mach_service("net.sourceforge.MonolingualHelper", NULL, XPC_CONNECTION_MACH_SERVICE_PRIVILEGED);

	if (!self.connection) {
		NSLog(@"Failed to create XPC connection.");
		return;
	}

	[[NSProcessInfo processInfo] disableSuddenTermination];

	xpc_connection_set_event_handler(self.connection, ^(xpc_object_t event) {
		xpc_type_t type = xpc_get_type(event);

		if (type == XPC_TYPE_ERROR) {
			if (event == XPC_ERROR_CONNECTION_INTERRUPTED) {
				NSLog(@"XPC connection interrupted.");
			} else if (event == XPC_ERROR_CONNECTION_INVALID) {
				NSLog(@"XPC connection invalid.");
			} else {
				NSLog(@"Unexpected XPC connection error.");
			}
		} else {
			NSLog(@"Unexpected XPC connection event.");
		}
	});

	// Create an anonymous listener connection that collects progress updates.
	self.progressConnection = xpc_connection_create(NULL, self.listener_queue);

	// Weak references to NSWindowControllers are not supported on 10.7
	//__weak __typeof__(self) wself = self;
	__unsafe_unretained __typeof__(self) wself = self;
	if (self.progressConnection) {
		xpc_connection_set_event_handler(self.progressConnection, ^(xpc_object_t event) {
			xpc_type_t type = xpc_get_type(event);
			
			if (type == XPC_TYPE_ERROR) {
				if (event == XPC_ERROR_TERMINATION_IMMINENT) {
					NSLog(@"received XPC_ERROR_TERMINATION_IMMINENT");
				} else if (event == XPC_ERROR_CONNECTION_INVALID) {
					NSLog(@"progress connection is closed");
				}
			} else if (XPC_TYPE_CONNECTION == type) {
				xpc_connection_t peer = (xpc_connection_t)event;
				
				xpc_connection_set_target_queue(peer, self.peer_event_queue);
				xpc_connection_set_event_handler(peer, ^(xpc_object_t nevent) {
					xpc_type_t ntype = xpc_get_type(nevent);

					if (XPC_TYPE_DICTIONARY == ntype) {
						[wself processProgress:nevent];
					}
				});
				xpc_connection_resume(peer);
			}
		});
		xpc_connection_resume(self.progressConnection);

		xpc_dictionary_set_connection(arguments, "connection", self.progressConnection);
	} else {
		NSLog(@"Couldn't create progress connection");
	}

	xpc_connection_resume(self.connection);
	
	// DEBUG
	//xpc_dictionary_set_bool(arguments, "dry_run", TRUE);

	xpc_connection_send_message_with_reply(self.connection, arguments, dispatch_get_main_queue(), ^(xpc_object_t event) {
		xpc_type_t type = xpc_get_type(event);
		if (XPC_TYPE_DICTIONARY == type) {
			int64_t exit_code = xpc_dictionary_get_int64(event, "exit_code");
			NSLog(@"helper finished with exit code: %lld", exit_code);

			if (self.connection) {
				xpc_object_t exit_message = xpc_dictionary_create(NULL, NULL, 0);
				xpc_dictionary_set_int64(exit_message, "exit_code", exit_code);
				xpc_connection_send_message(self.connection, exit_message);
				xpc_release(exit_message);
			}

			if (!exit_code)
				[wself finishProcessing];
		}
	});

	[self.progressWindowController start];
	[NSApp beginSheet:self.progressWindowController.window
	   modalForWindow:self.window
		modalDelegate:self
	   didEndSelector:@selector(progressDidEnd:returnCode:contextInfo:)
		  contextInfo:nil];

	if ([NSUserNotificationCenter class]) {
		NSUserNotification *notification = [NSUserNotification new];
		notification.title = NSLocalizedString(@"Monolingual started", "");
		notification.informativeText = NSLocalizedString(@"Started removing files", "");
		
		NSUserNotificationCenter *center = [NSUserNotificationCenter defaultUserNotificationCenter];
		[center deliverNotification:notification];
	} else {
		[GrowlApplicationBridge notifyWithDictionary:self.startedNotificationInfo];
	}
}

- (void) progressDidEnd:(NSWindow *)panel returnCode:(int)returnCode contextInfo:(void *)context
{
	if (self.processApplication) {
		self.processApplication = nil;
	}
	
	NSString *byteCount;
	char hbuf[LONGEST_HUMAN_READABLE + 1];
	if ([NSByteCountFormatter class] && [[NSByteCountFormatter class] respondsToSelector:@selector(stringFromByteCount:countStyle:)]) {
		byteCount = [NSByteCountFormatter stringFromByteCount:self.bytesSaved countStyle:NSByteCountFormatterCountStyleFile];
	} else {
		byteCount = @(human_readable(self.bytesSaved, hbuf, 1000));
	}
	
	if (returnCode == 1) {
		if (self.progressConnection) {
			if (self.connection) {
				xpc_object_t exit_message = xpc_dictionary_create(NULL, NULL, 0);
				xpc_dictionary_set_int64(exit_message, "exit_code", EXIT_FAILURE);
				xpc_connection_send_message(self.connection, exit_message);
				xpc_release(exit_message);
			}

			// Cancel and release the anonymous connection which signals the remote
			// service to stop, if working.
			NSLog(@"Closing progress connection");
			xpc_connection_cancel(self.progressConnection);
			xpc_release(self.progressConnection);
			self.progressConnection = NULL;
		}

		NSBeginAlertSheet(NSLocalizedString(@"Removal cancelled", ""), nil, nil, nil,
						  [NSApp mainWindow], self, NULL, NULL, NULL,
						  NSLocalizedString(@"You cancelled the removal. Some files were erased, some were not. Space saved: %@.", ""),
						  byteCount);
	} else {
		NSBeginAlertSheet(NSLocalizedString(@"Removal completed", ""),
						  nil, nil, nil, self.parentWindow, self, NULL, NULL,
						  NULL,
						  NSLocalizedString(@"Files removed. Space saved: %@.", ""),
						  byteCount);
		
		if ([NSUserNotificationCenter class]) {
			NSUserNotification *notification = [NSUserNotification new];
			notification.title = NSLocalizedString(@"Monolingual finished", "");
			notification.informativeText = NSLocalizedString(@"Finished removing files", "");
			
			NSUserNotificationCenter *center = [NSUserNotificationCenter defaultUserNotificationCenter];
			[center deliverNotification:notification];
		} else {
			[GrowlApplicationBridge notifyWithDictionary:self.finishedNotificationInfo];
		}
	}

	if (self.connection) {
		NSLog(@"Closing connection");
		xpc_connection_cancel(self.connection);
		xpc_release(self.connection);
		self.connection = NULL;
	}
	
	if (logFile) {
		fclose(logFile);
		logFile = NULL;
	}

	[[NSProcessInfo processInfo] enableSuddenTermination];
}

- (void) warningSelector:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	if (NSAlertDefaultReturn != returnCode) {
		for (NSDictionary *language in self.languages) {
			if ([language[@"Enabled"] boolValue] && [language[@"Folders"][0U] isEqualToString:@"en.lproj"]) {
				/* Display a warning */
				NSBeginCriticalAlertSheet(NSLocalizedString(@"WARNING!", ""),
										  NSLocalizedString(@"Stop", ""),
										  NSLocalizedString(@"Continue", ""),
										  nil,
										  [NSApp mainWindow], self, NULL,
										  @selector(englishWarningSelector:returnCode:contextInfo:),
										  nil,
										  NSLocalizedString(@"You are about to delete the English language files. Are you sure you want to do that?", ""));
				return;
			}
		}
		[self englishWarningSelector:nil returnCode:NSAlertAlternateReturn contextInfo:nil];
	}
}

- (void) englishWarningSelector:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	self.mode = ModeLanguages;

	logFile = fopen(logFileName, "at");
	if (logFile) {
		time_t now = time(NULL);
		fprintf(logFile, "Monolingual started at %sRemoving languages: ", ctime(&now));
	}

	NSArray *roots = self.processApplication ? self.processApplication : [[NSUserDefaults standardUserDefaults] arrayForKey:@"Roots"];

	BOOL languageEnabled = NO;
	for (NSDictionary *root in roots) {
		if ([root[@"Languages"] boolValue]) {
			languageEnabled = YES;
			break;
		}
	}

	if (NSAlertDefaultReturn == returnCode || !languageEnabled) {
		NSBeginAlertSheet(NSLocalizedString(@"Nothing done", ""), nil, nil, nil,
						  [NSApp mainWindow], self, NULL, NULL, NULL,
						  NSLocalizedString(@"Monolingual is stopping without making any changes. Your OS has not been modified.", ""));
	} else {
		xpc_object_t includes = xpc_array_create(NULL, 0);
		xpc_object_t excludes = xpc_array_create(NULL, 0);
		for (NSDictionary *root in roots) {
			NSString *path = root[@"Path"];
			if ([root[@"Languages"] boolValue]) {
				NSLog(@"Adding root %@", path);
				xpc_array_set_string(includes, XPC_ARRAY_APPEND, [path fileSystemRepresentation]);
			} else {
				NSLog(@"Excluding root %@", path);
				xpc_array_set_string(excludes, XPC_ARRAY_APPEND, [path fileSystemRepresentation]);
			}
		}
		xpc_object_t bl = xpc_array_create(NULL, 0);
		for (NSDictionary *item in self.blacklist) {
			if ([item[@"languages"] boolValue]) {
				NSString *bundle = item[@"bundle"];
				NSLog(@"Blacklisting %@", bundle);
				xpc_array_set_string(bl, XPC_ARRAY_APPEND, [bundle UTF8String]);
			}
		}

		NSUInteger rCount = 0;
		xpc_object_t files = xpc_array_create(NULL, 0);
		for (NSDictionary *language in self.languages) {
			if ([language[@"Enabled"] boolValue]) {
				NSArray *paths = language[@"Folders"];
				for (NSString *path in paths) {
					xpc_array_set_string(files, XPC_ARRAY_APPEND, [path fileSystemRepresentation]);
					if (logFile) {
						if (rCount)
							fputs(" ", logFile);
						fputs([path fileSystemRepresentation], logFile);
					}
					rCount++;
				}
			}
		}
		if ([[NSUserDefaults standardUserDefaults] boolForKey:@"NIB"])
			xpc_array_set_string(files, XPC_ARRAY_APPEND, "designable.nib");

		if (logFile)
			fputs("\nDeleted files: \n", logFile);
		if (rCount == self.languages.count)  {
			NSBeginAlertSheet(NSLocalizedString(@"Cannot remove all languages", ""), nil, nil, nil,
							  [NSApp mainWindow], self, NULL, NULL, NULL,
							  NSLocalizedString(@"Removing all languages will make OS X inoperable. Please keep at least one language and try again.", ""));
			if (logFile) {
				fclose(logFile);
				logFile = NULL;
			}
		} else if (rCount) {
			/* start things off if we have something to remove! */
			
			xpc_object_t xpc_message = xpc_dictionary_create(NULL, NULL, 0);
			xpc_dictionary_set_bool(xpc_message, "trash", [[NSUserDefaults standardUserDefaults] boolForKey:@"Trash"]);
			xpc_dictionary_set_value(xpc_message, "blacklist", bl);
			xpc_dictionary_set_value(xpc_message, "includes", includes);
			xpc_dictionary_set_value(xpc_message, "excludes", excludes);
			xpc_dictionary_set_value(xpc_message, "directories", files);

			[self runDeleteHelperWithArgs:xpc_message];
			
			xpc_release(xpc_message);
		} else {
			if (logFile) {
				fclose(logFile);
				logFile = NULL;
			}
		}

		xpc_release(bl);
		xpc_release(includes);
		xpc_release(excludes);
		xpc_release(files);
	}
}

- (void) awakeFromNib
{
	self.donateURL = [NSURL URLWithString:@"http://monolingual.sourceforge.net/donate.php"];

	self.listener_queue = dispatch_queue_create("net.sourceforge.Monolingual.ProgressQueue", NULL);
	assert(self.listener_queue != NULL);

	self.peer_event_queue = dispatch_queue_create("net.sourceforge.Monolingual.ProgressPanel", NULL);
	assert(self.peer_event_queue != NULL);
	
	NSArray *languagePref = [[NSUserDefaults standardUserDefaults] objectForKey:@"AppleLanguages"];
	NSMutableSet *userLanguages = [NSMutableSet setWithArray:languagePref];
	
	// never check "English" by default
	[userLanguages addObject:@"en"];

	[[self window] setFrameAutosaveName:@"MainWindow"];

#define NUM_KNOWN_LANGUAGES	134
	NSMutableArray *knownLanguages = [NSMutableArray arrayWithCapacity:NUM_KNOWN_LANGUAGES];

#define ADD_LANGUAGE(code, name, ...) [knownLanguages addObject:[@{ @"DisplayName" : NSLocalizedString(name, ""), @"Folders" : @[ __VA_ARGS__ ], @"Enabled" : [userLanguages containsObject:(code)] ? @NO : @YES } mutableCopy]];

	ADD_LANGUAGE(@"af",      @"Afrikaans",            @"af.lproj", @"Afrikaans.lproj");
	ADD_LANGUAGE(@"am",      @"Amharic",              @"am.lproj", @"Amharic.lproj");
	ADD_LANGUAGE(@"ar",      @"Arabic",               @"ar.lproj", @"Arabic.lproj");
	ADD_LANGUAGE(@"as",      @"Assamese",             @"as.lproj", @"Assamese.lproj");
	ADD_LANGUAGE(@"ay",      @"Aymara",               @"ay.lproj", @"Aymara.lproj.lproj");
	ADD_LANGUAGE(@"az",      @"Azerbaijani",          @"az.lproj", @"Azerbaijani.lproj");
	ADD_LANGUAGE(@"be",      @"Byelorussian",         @"be.lproj", @"Byelorussian.lproj");
	ADD_LANGUAGE(@"bg",      @"Bulgarian",            @"bg.lproj", @"Bulgarian.lproj");
	ADD_LANGUAGE(@"bi",      @"Bislama",              @"bi.lproj", @"Bislama.lproj");
	ADD_LANGUAGE(@"bn",      @"Bengali",              @"bn.lproj", @"Bengali.lproj");
	ADD_LANGUAGE(@"bo",      @"Tibetan",              @"bo.lproj", @"Tibetan.lproj");
	ADD_LANGUAGE(@"br",      @"Breton",               @"bt.lproj", @"Breton.lproj");
	ADD_LANGUAGE(@"ca",      @"Catalan",              @"ca.lproj", @"Catalan.lproj");
	ADD_LANGUAGE(@"chr",     @"Cherokee",             @"chr.lproj", @"Cherokee.lproj");
	ADD_LANGUAGE(@"cs",      @"Czech",                @"cs.lproj", @"cs_CZ.lproj", @"Czech.lproj");
	ADD_LANGUAGE(@"cy",      @"Welsh",                @"cy.lproj", @"Welsh.lproj");
	ADD_LANGUAGE(@"da",      @"Danish",               @"da.lproj", @"da_DK.lproj", @"Danish.lproj");
	ADD_LANGUAGE(@"de",      @"German",               @"de.lproj", @"de_DE.lproj", @"German.lproj");
	ADD_LANGUAGE(@"de-AT",   @"German (Austria)",     @"de_AT.lproj");
	ADD_LANGUAGE(@"de-CH",   @"German (Switzerland)", @"de_CH.lproj");
	ADD_LANGUAGE(@"dz",      @"Dzongkha",             @"dz.lproj", @"Dzongkha.lproj");
	ADD_LANGUAGE(@"el",      @"Greek",                @"el.lproj", @"el_GR.lproj", @"Greek.lproj");
	ADD_LANGUAGE(@"en",      @"English",              @"en.lproj", @"English.lproj");
	ADD_LANGUAGE(@"en-AU",   @"English (Australia)",      @"en_AU.lproj");
	ADD_LANGUAGE(@"en-CA",   @"English (Canada)",         @"en_CA.lproj");
	ADD_LANGUAGE(@"en-GB",   @"English (United Kingdom)", @"en_GB.lproj");
	ADD_LANGUAGE(@"en-NZ",   @"English (New Zealand)",    @"en_NZ.lproj");
	ADD_LANGUAGE(@"en-US",   @"English (United States)",  @"en_US.lproj");
	ADD_LANGUAGE(@"eo",      @"Esperanto",            @"eo.lproj", @"Esperanto.lproj");
	ADD_LANGUAGE(@"es",      @"Spanish",              @"es.lproj", @"es_ES.lproj", @"es_419.lproj", @"Spanish.lproj");
	ADD_LANGUAGE(@"et",      @"Estonian",             @"et.lproj", @"Estonian.lproj");
	ADD_LANGUAGE(@"eu",      @"Basque",               @"eu.lproj", @"Basque.lproj");
	ADD_LANGUAGE(@"fa",      @"Farsi",                @"fa.lproj", @"Farsi.lproj");
	ADD_LANGUAGE(@"fi",      @"Finnish",              @"fi.lproj", @"fi_FI.lproj", @"Finnish.lproj");
	ADD_LANGUAGE(@"fil",     @"Filipino",             @"fil.lproj");
	ADD_LANGUAGE(@"fo",      @"Faroese",              @"fo.lproj", @"Faroese.lproj");
	ADD_LANGUAGE(@"fr",      @"French",               @"fr.lproj", @"fr_FR.lproj", @"French.lproj");
	ADD_LANGUAGE(@"fr-CA",   @"French (Canada)",      @"fr_CA.lproj");
	ADD_LANGUAGE(@"fr-CH",   @"French (Switzerland)", @"fr_CH.lproj");
	ADD_LANGUAGE(@"ga",      @"Irish",                @"ga.lproj", @"Irish.lproj");
	ADD_LANGUAGE(@"gd",      @"Scottish",             @"gd.lproj", @"Scottish.lproj");
	ADD_LANGUAGE(@"gl",      @"Galician",             @"gl.lproj", @"Galician.lproj");
	ADD_LANGUAGE(@"gn",      @"Guarani",              @"gn.lproj", @"Guarani.lproj");
	ADD_LANGUAGE(@"gu",      @"Gujarati",             @"gu.lproj", @"Gujarati.lproj");
	ADD_LANGUAGE(@"gv",      @"Manx",                 @"gv.lproj", @"Manx.lproj");
	ADD_LANGUAGE(@"haw",     @"Hawaiian",             @"haw.lproj", @"Hawaiian.lproj");
	ADD_LANGUAGE(@"he",      @"Hebrew",               @"he.lproj", @"Hebrew.lproj");
	ADD_LANGUAGE(@"hi",      @"Hindi",                @"hi.lproj", @"Hindi.lproj");
	ADD_LANGUAGE(@"hr",      @"Croatian",             @"hr.lproj", @"Croatian.lproj");
	ADD_LANGUAGE(@"hu",      @"Hungarian",            @"hu.lproj", @"hu_HU.lproj", @"Hungarian.lproj");
	ADD_LANGUAGE(@"hy",      @"Armenian",             @"hy.lproj", @"Armenian.lproj");
	ADD_LANGUAGE(@"id",      @"Indonesian",           @"id.lproj", @"Indonesian.lproj");
	ADD_LANGUAGE(@"is",      @"Icelandic",            @"is.lproj", @"Icelandic.lproj");
	ADD_LANGUAGE(@"it",      @"Italian",              @"it.lproj", @"it_IT.lproj", @"Italian.lproj");
	ADD_LANGUAGE(@"iu",      @"Inuktitut",            @"iu.lproj", @"Inuktitut.lproj");
	ADD_LANGUAGE(@"ja",      @"Japanese",             @"ja.lproj", @"ja_JP.lproj", @"Japanese.lproj");
	ADD_LANGUAGE(@"jv",      @"Javanese",             @"jv.lproj", @"Javanese.lproj");
	ADD_LANGUAGE(@"ka",      @"Georgian",             @"ka.lproj", @"Georgian.lproj");
	ADD_LANGUAGE(@"kk",      @"Kazakh",               @"kk.lproj", @"Kazakh.lproj");
	ADD_LANGUAGE(@"kk-Cyrl", @"Kazakh (Cyrillic)",    @"kk-Cyrl.lproj");
	ADD_LANGUAGE(@"kl",      @"Greenlandic",          @"kl.lproj", @"Greenlandic.lproj");
	ADD_LANGUAGE(@"km",      @"Khmer",                @"km.lproj", @"Khmer.lproj");
	ADD_LANGUAGE(@"kn",      @"Kannada",              @"kn.lproj", @"Kannada.lproj");
	ADD_LANGUAGE(@"ko",      @"Korean",               @"ko.lproj", @"ko_KR.lproj", @"Korean.lproj");
	ADD_LANGUAGE(@"ks",      @"Kashmiri",             @"ks.lproj", @"Kashmiri.lproj");
	ADD_LANGUAGE(@"ku",      @"Kurdish",              @"ku.lproj", @"Kurdish.lproj");
	ADD_LANGUAGE(@"kw",      @"Kernowek",             @"kw.lproj", @"Kernowek.lproj");
	ADD_LANGUAGE(@"ky",      @"Kirghiz",              @"ky.lproj", @"Kirghiz.lproj");
	ADD_LANGUAGE(@"la",      @"Latin",                @"la.lproj", @"Latin.lproj");
	ADD_LANGUAGE(@"lo",      @"Lao",                  @"lo.lproj", @"Lao.lproj");
	ADD_LANGUAGE(@"lt",      @"Lithuanian",           @"lt.lproj", @"Lithuanian.lproj");
	ADD_LANGUAGE(@"lv",      @"Latvian",              @"lv.lproj", @"Latvian.lproj");
	ADD_LANGUAGE(@"mg",      @"Malagasy",             @"mg.lproj", @"Malagasy.lproj");
	ADD_LANGUAGE(@"mi",      @"Maori",                @"mi.lproj", @"Maori.lproj");
	ADD_LANGUAGE(@"mk",      @"Macedonian",           @"mk.lproj", @"Macedonian.lproj");
	ADD_LANGUAGE(@"mr",      @"Marathi",              @"mr.lproj", @"Marathi.lproj");
	ADD_LANGUAGE(@"ml",      @"Malayalam",            @"ml.lproj", @"Malayalam.lproj");
	ADD_LANGUAGE(@"mn",      @"Mongolian",            @"mn.lproj", @"Mongolian.lproj");
	ADD_LANGUAGE(@"mo",      @"Moldavian",            @"mo.lproj", @"Moldavian.lproj");
	ADD_LANGUAGE(@"ms",      @"Malay",                @"ms.lproj", @"Malay.lproj");
	ADD_LANGUAGE(@"mt",      @"Maltese",              @"mt.lproj", @"Maltese.lproj");
	ADD_LANGUAGE(@"my",      @"Burmese",              @"my.lproj", @"Burmese.lproj");
	ADD_LANGUAGE(@"ne",      @"Nepali",               @"ne.lproj", @"Nepali.lproj");
	ADD_LANGUAGE(@"nl",      @"Dutch",                @"nl.lproj", @"nl_NL.lproj", @"Dutch.lproj");
	ADD_LANGUAGE(@"nl-BE",   @"Flemish",              @"nl_BE.lproj");
	ADD_LANGUAGE(@"no",      @"Norwegian",            @"no.lproj", @"no_NO.lproj", @"Norwegian.lproj");
	ADD_LANGUAGE(@"nb",      @"Norwegian Bokmal",     @"nb.lproj");
	ADD_LANGUAGE(@"nn",      @"Norwegian Nynorsk",    @"nn.lproj");
	ADD_LANGUAGE(@"om",      @"Oromo",                @"om.lproj", @"Oromo.lproj");
	ADD_LANGUAGE(@"or",      @"Oriya",                @"or.lproj", @"Oriya.lproj");
	ADD_LANGUAGE(@"pa",      @"Punjabi",              @"pa.lproj", @"Punjabi.lproj");
	ADD_LANGUAGE(@"pl",      @"Polish",               @"pl.lproj", @"pl_PL.lproj", @"Polish.lproj");
	ADD_LANGUAGE(@"ps",      @"Pashto",               @"ps.lproj", @"Pashto.lproj");
	ADD_LANGUAGE(@"pt",      @"Portuguese",           @"pt.lproj", @"pt_PT.lproj", @"pt-PT.lproj", @"Portuguese.lproj");
	ADD_LANGUAGE(@"pt-BR",   @"Portuguese (Brazil)",  @"pt_BR.lproj", @"PT_br.lproj", @"pt-BR.lproj");
	ADD_LANGUAGE(@"qu",      @"Quechua",              @"qu.lproj", @"Quechua.lproj");
	ADD_LANGUAGE(@"rn",      @"Rundi",                @"rn.lproj", @"Rundi.lproj");
	ADD_LANGUAGE(@"ro",      @"Romanian",             @"ro.lproj", @"Romanian.lproj");
	ADD_LANGUAGE(@"ru",      @"Russian",              @"ru.lproj", @"Russian.lproj");
	ADD_LANGUAGE(@"rw",      @"Kinyarwanda",          @"rw.lproj", @"Kinyarwanda.lproj");
	ADD_LANGUAGE(@"sa",      @"Sanskrit",             @"sa.lproj", @"Sanskrit.lproj");
	ADD_LANGUAGE(@"sd",      @"Sindhi",               @"sd.lproj", @"Sindhi.lproj");
	ADD_LANGUAGE(@"se",      @"Sami",                 @"se.lproj", @"Sami.lproj");
	ADD_LANGUAGE(@"si",      @"Sinhalese",            @"si.lproj", @"Sinhalese.lproj");
	ADD_LANGUAGE(@"sk",      @"Slovak",               @"sk.lproj", @"sk_SK.lproj", @"Slovak.lproj");
	ADD_LANGUAGE(@"sl",      @"Slovenian",            @"sl.lproj", @"Slovenian.lproj");
	ADD_LANGUAGE(@"so",      @"Somali",               @"so.lproj", @"Somali.lproj");
	ADD_LANGUAGE(@"sq",      @"Albanian",             @"sq.lproj", @"Albanian.lproj");
	ADD_LANGUAGE(@"sr",      @"Serbian",              @"sr.lproj", @"Serbian.lproj");
	ADD_LANGUAGE(@"su",      @"Sundanese",            @"su.lproj", @"Sundanese.lproj");
	ADD_LANGUAGE(@"sv",      @"Swedish",              @"sv.lproj", @"sv_SE.lproj", @"Swedish.lproj");
	ADD_LANGUAGE(@"sw",      @"Swahili",              @"sw.lproj", @"Swahili.lproj");
	ADD_LANGUAGE(@"ta",      @"Tamil",                @"ta.lproj", @"Tamil.lproj");
	ADD_LANGUAGE(@"te",      @"Telugu",               @"te.lproj", @"Telugu.lproj");
	ADD_LANGUAGE(@"tg",      @"Tajiki",               @"tg.lproj", @"Tajiki.lproj");
	ADD_LANGUAGE(@"th",      @"Thai",                 @"th.lproj", @"Thai.lproj");
	ADD_LANGUAGE(@"ti",      @"Tigrinya",             @"ti.lproj", @"Tigrinya.lproj");
	ADD_LANGUAGE(@"tk",      @"Turkmen",              @"tk.lproj", @"Turkmen.lproj");
	ADD_LANGUAGE(@"tk-Cyrl", @"Turkmen (Cyrillic)",   @"tk-Cyrl.lproj");
	ADD_LANGUAGE(@"tk-Latn", @"Turkmen (Latin)",      @"tk-Latn.lproj");
	ADD_LANGUAGE(@"tl",      @"Tagalog",              @"tl.lproj", @"Tagalog.lproj");
	ADD_LANGUAGE(@"tlh",     @"Klingon",              @"tlh.lproj", @"Klingon.lproj");
	ADD_LANGUAGE(@"tr",      @"Turkish",              @"tr.lproj", @"tr_TR.lproj", @"Turkish.lproj");
	ADD_LANGUAGE(@"tt",      @"Tatar",                @"tt.lproj", @"Tatar.lproj");
	ADD_LANGUAGE(@"to",      @"Tongan",               @"to.lproj", @"Tongan.lproj");
	ADD_LANGUAGE(@"ug",      @"Uighur",               @"ug.lproj", @"Uighur.lproj");
	ADD_LANGUAGE(@"uk",      @"Ukrainian",            @"uk.lproj", @"Ukrainian.lproj");
	ADD_LANGUAGE(@"ur",      @"Urdu",                 @"ur.lproj", @"Urdu.lproj");
	ADD_LANGUAGE(@"uz",      @"Uzbek",                @"uz.lproj", @"Uzbek.lproj");
	ADD_LANGUAGE(@"vi",      @"Vietnamese",           @"vi.lproj", @"Vietnamese.lproj");
	ADD_LANGUAGE(@"yi",      @"Yiddish",              @"yi.lproj", @"Yiddish.lproj");
	ADD_LANGUAGE(@"zh",      @"Chinese",              @"zh.lproj");
	ADD_LANGUAGE(@"zh-Hans", @"Chinese (Simplified Han)",   @"zh_Hans.lproj", @"zh-Hans.lproj", @"zh_CN.lproj", @"zh_SC.lproj");
	ADD_LANGUAGE(@"zh-Hant", @"Chinese (Traditional Han)",  @"zh_Hant.lproj", @"zh-Hant.lproj", @"zh_TW.lproj", @"zh_HK.lproj");

	[knownLanguages sortUsingComparator:^NSComparisonResult(id obj1, id obj2) {
		NSDictionary *lang1 = (NSDictionary *)obj1;
		NSDictionary *lang2 = (NSDictionary *)obj2;
		return [lang1[@"DisplayName"] compare:lang2[@"DisplayName"]];
	}];
	self.languages = knownLanguages;

	const arch_info_t archs[10] = {
		{ "arm",       "ARM",               CPU_TYPE_ARM,       CPU_SUBTYPE_ARM_ALL},
		{ "ppc",       "PowerPC",           CPU_TYPE_POWERPC,   CPU_SUBTYPE_POWERPC_ALL},
		{ "ppc750",    "PowerPC G3",        CPU_TYPE_POWERPC,   CPU_SUBTYPE_POWERPC_750},
		{ "ppc7400",   "PowerPC G4",        CPU_TYPE_POWERPC,   CPU_SUBTYPE_POWERPC_7400},
		{ "ppc7450",   "PowerPC G4+",       CPU_TYPE_POWERPC,   CPU_SUBTYPE_POWERPC_7450},
		{ "ppc970",    "PowerPC G5",        CPU_TYPE_POWERPC,   CPU_SUBTYPE_POWERPC_970},
		{ "ppc64",     "PowerPC 64-bit",    CPU_TYPE_POWERPC64, CPU_SUBTYPE_POWERPC_ALL},
		{ "ppc970-64", "PowerPC G5 64-bit", CPU_TYPE_POWERPC64, CPU_SUBTYPE_POWERPC_970},
		{ "x86",       "Intel",             CPU_TYPE_X86,       CPU_SUBTYPE_X86_ALL},
		{ "x86_64",    "Intel 64-bit",      CPU_TYPE_X86_64,    CPU_SUBTYPE_X86_64_ALL}
	};

	host_basic_info_data_t hostInfo;
	mach_msg_type_number_t infoCount = HOST_BASIC_INFO_COUNT;
	mach_port_t my_mach_host_self;
	my_mach_host_self = mach_host_self();
	kern_return_t ret = host_info(my_mach_host_self, HOST_BASIC_INFO, (host_info_t)&hostInfo, &infoCount);
	mach_port_deallocate(mach_task_self(), my_mach_host_self);

	if (hostInfo.cpu_type == CPU_TYPE_X86) {
		// fix host_info
		int x86_64;
		size_t x86_64_size = sizeof(x86_64);
		if (!sysctlbyname("hw.optional.x86_64", &x86_64, &x86_64_size, NULL, 0)) {
			if (x86_64) {
				hostInfo.cpu_type = CPU_TYPE_X86_64;
				hostInfo.cpu_subtype = CPU_SUBTYPE_X86_64_ALL;
			}
		}
	}

	[self.currentArchitecture setStringValue:@"unknown"];

	NSMutableArray *knownArchitectures = [NSMutableArray arrayWithCapacity:NELEMS(archs)];
	for (unsigned i=0U; i<NELEMS(archs); ++i) {
		NSDictionary *architecture = @{
			@"Enabled" : (ret == KERN_SUCCESS && (hostInfo.cpu_type != archs[i].cpu_type || hostInfo.cpu_subtype < archs[i].cpu_subtype) && (!(hostInfo.cpu_type & CPU_ARCH_ABI64) || (archs[i].cpu_type != (hostInfo.cpu_type & ~CPU_ARCH_ABI64)))) ? @YES : @NO,
			@"Name" : @(archs[i].name),
			@"DisplayName" : @(archs[i].displayName)
		};
		[knownArchitectures addObject:[architecture mutableCopy]];
		if (hostInfo.cpu_type == archs[i].cpu_type && hostInfo.cpu_subtype == archs[i].cpu_subtype) {
			NSString *label = [NSString stringWithFormat:NSLocalizedString(@"Current architecture: %@", ""), @(archs[i].displayName)];
			[self.currentArchitecture setStringValue:label];
		}
	}
	self.architectures = knownArchitectures;

	// set ourself as the Growl delegate
	[GrowlApplicationBridge setGrowlDelegate:self];

	NSString *startedNotificationName = NSLocalizedString(@"Monolingual started", "");
	NSString *finishedNotificationName = NSLocalizedString(@"Monolingual finished", "");

	self.startedNotificationInfo = @{ GROWL_APP_NAME : @"Monolingual", GROWL_NOTIFICATION_NAME : startedNotificationName, GROWL_NOTIFICATION_TITLE : startedNotificationName, GROWL_NOTIFICATION_DESCRIPTION : NSLocalizedString(@"Started removing files", "") };
	self.finishedNotificationInfo = @{ GROWL_APP_NAME : @"Monolingual", GROWL_NOTIFICATION_NAME : finishedNotificationName, GROWL_NOTIFICATION_TITLE : finishedNotificationName, GROWL_NOTIFICATION_DESCRIPTION : NSLocalizedString(@"Finished removing files", "") };

	// load blacklist from URL
	NSURL *blacklistURL = [NSURL URLWithString:@"http://monolingual.sourceforge.net/blacklist.plist"];
	self.blacklist = [NSArray arrayWithContentsOfURL:blacklistURL];

	// use blacklist from bundle as a fallback
	if (!self.blacklist) {
		NSString *blacklistBundle = [[NSBundle mainBundle] pathForResource:@"blacklist" ofType:@"plist"];
		self.blacklist = [NSArray arrayWithContentsOfFile:blacklistBundle];
	}
}

- (NSDictionary *) registrationDictionaryForGrowl
{
	NSArray *defaultAndAllNotifications = @[ NSLocalizedString(@"Monolingual started", ""), NSLocalizedString(@"Monolingual finished", "") ];

	return @{
		GROWL_APP_NAME : @"Monolingual",
		GROWL_APP_ID : @"net.sourceforge.Monolingual",
		GROWL_NOTIFICATIONS_ALL : defaultAndAllNotifications,
		GROWL_NOTIFICATIONS_DEFAULT : defaultAndAllNotifications
	};
}

- (BOOL) hasNetworkClientEntitlement {
	return YES;
}

- (void)dealloc {
	dispatch_release(self.listener_queue);
	dispatch_release(self.peer_event_queue);
}

@end
