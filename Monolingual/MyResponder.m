/*
 *  Copyright (C) 2001, 2002  Joshua Schrier (jschrier@mac.com),
 *                2004-2007 Ingmar Stein
 *                2007 Nicholas Shanks (contact@nickshanks.com)
 *  Released under the GNU GPL.  For more information, see the header file.
 */

#import "MyResponder.h"
#import "ProgressWindowController.h"
#import "PreferencesController.h"
#import "NGSTreeNode.h"
#include <Growl/GrowlDefines.h>
#include <Growl/GrowlApplicationBridge-Carbon.h>
#include <Security/Authorization.h>
#include <Security/AuthorizationTags.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/param.h>
#include <sys/sysctl.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <mach/mach_host.h>
#include <mach/mach_port.h>
#include <mach/machine.h>
#include <mach-o/arch.h>
#include <pwd.h>

#define MODE_LANGUAGES		0
#define MODE_LAYOUTS		1
#define MODE_ARCHITECTURES	2

typedef struct arch_info_s {
	CFStringRef   name;
	CFStringRef   displayName;
	cpu_type_t    cpu_type;
	cpu_subtype_t cpu_subtype;
} arch_info_t;

static int                pipeDescriptor;
static CFSocketRef        pipeSocket;
static CFMutableDataRef   pipeBuffer;
static CFRunLoopSourceRef pipeRunLoopSource;
static CFArrayRef         processApplication;
static FILE               *logFile;
static char               logFileName[PATH_MAX];

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

static CFComparisonResult languageCompare(const void *val1, const void *val2, void *context)
{
#pragma unused(context)
	return CFStringCompare(CFDictionaryGetValue((CFDictionaryRef)val1, CFSTR("DisplayName")), CFDictionaryGetValue((CFDictionaryRef)val2, CFSTR("DisplayName")), kCFCompareLocalized);
}

@implementation MyResponder
struct Growl_Delegate    growlDelegate;
NSWindow                 *parentWindow;
CFMutableArrayRef        languages;
CFMutableArrayRef        layouts;
CFMutableArrayRef        architectures;
CFDictionaryRef          startedNotificationInfo;
CFDictionaryRef          finishedNotificationInfo;
CFURLRef                 versionURL;
CFURLRef                 downloadURL;
CFURLRef                 donateURL;
unsigned long long       bytesSaved;
int                      mode;
NGSTreeNode              *rootNode;

+ (void) initialize
{
	CFTypeRef defaultKeys[3] = {
		CFSTR("Roots"),
		CFSTR("Trash"),
		CFSTR("Strip")
	};
	CFTypeRef keys[5] = {
		CFSTR("Path"),
		CFSTR("Languages"),
		CFSTR("Architectures")
	};
	CFTypeRef applicationsValues[3] = {
		CFSTR("/Applications"),
		kCFBooleanTrue,
		kCFBooleanTrue
	};
	CFTypeRef developerValues[3] = {
		CFSTR("/Developer"),
		kCFBooleanTrue,
		kCFBooleanTrue
	};
	CFTypeRef libraryValues[3] = {
		CFSTR("/Library"),
		kCFBooleanTrue,
		kCFBooleanTrue
	};
	CFTypeRef systemValues[3] = {
		CFSTR("/System"),
		kCFBooleanTrue,
		kCFBooleanFalse
	};
	CFDictionaryRef applications = CFDictionaryCreate(kCFAllocatorDefault, keys, applicationsValues, 3, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	CFDictionaryRef developer = CFDictionaryCreate(kCFAllocatorDefault, keys, developerValues, 3, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	CFDictionaryRef library = CFDictionaryCreate(kCFAllocatorDefault, keys, libraryValues, 3, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	CFDictionaryRef systemPath = CFDictionaryCreate(kCFAllocatorDefault, keys, systemValues, 3, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	CFTypeRef roots[4] = {
		applications,
		developer,
		library,
		systemPath
	};
	CFTypeRef defaultValues[3];
	CFArrayRef defaultRoots = CFArrayCreate(kCFAllocatorDefault, roots, 4, &kCFTypeArrayCallBacks);
	CFRelease(applications);
	CFRelease(developer);
	CFRelease(library);
	CFRelease(systemPath);
	defaultValues[0] = defaultRoots;
	defaultValues[1] = kCFBooleanFalse;
	defaultValues[2] = kCFBooleanFalse;
	CFDictionaryRef defaultDict = CFDictionaryCreate(kCFAllocatorDefault, defaultKeys, defaultValues, 3, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	[[NSUserDefaults standardUserDefaults] registerDefaults:(NSDictionary *)defaultDict];
	CFRelease(defaultDict);
	CFRelease(defaultRoots);

	struct passwd *pwd = getpwuid(getuid());
	if (pwd && pwd->pw_dir)
		snprintf(logFileName, sizeof(logFileName), "%s/Library/Logs/Monolingual.log", pwd->pw_dir);
	else
		strncpy(logFileName, "/var/log/Monolingual.log", sizeof(logFileName));
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)theApplication
{
#pragma unused(theApplication)
	return YES;
}

- (BOOL)application:(NSApplication *)theApplication openFile:(NSString *)filename
{
#pragma unused(theApplication)
	CFTypeRef keys[3] = {
		CFSTR("Path"),
		CFSTR("Languages"),
		CFSTR("Architectures")
	};
	CFTypeRef values[3];
	values[0] = (CFStringRef)filename;
	values[1] = kCFBooleanTrue;
	values[2] = kCFBooleanTrue;
	CFDictionaryRef dict = CFDictionaryCreate(kCFAllocatorDefault, keys, values, 3, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

	values[0] = (CFTypeRef)dict;
	processApplication = CFArrayCreate(kCFAllocatorDefault, values, 1, &kCFTypeArrayCallBacks);
	CFRelease(dict);

	[self warningSelector:nil returnCode:NSAlertAlternateReturn contextInfo:nil];

	return YES;
}

- (void) cancelRemove
{
	const unsigned char bytes[1] = {'\0'};
	write(pipeDescriptor, bytes, sizeof(bytes));
	CFRunLoopRemoveSource(CFRunLoopGetCurrent(), pipeRunLoopSource, kCFRunLoopCommonModes);
	CFRelease(pipeRunLoopSource);
	CFSocketInvalidate(pipeSocket);
	CFRelease(pipeSocket);
	CFRelease(pipeBuffer);
	pipeSocket = NULL;

	[NSApp endSheet:[progressWindowController window]];
	[[progressWindowController window] orderOut:self];
	[progressWindowController stop];

	Growl_PostNotificationWithDictionary(finishedNotificationInfo);

	CFStringRef title = CFCopyLocalizedString(CFSTR("Removal cancelled"), "");
	CFStringRef msg = CFCopyLocalizedString(CFSTR("You cancelled the removal. Some files were erased, some were not."), "");
	NSBeginAlertSheet((NSString *)title, nil, nil, nil,
					  [NSApp mainWindow], self, NULL, NULL, self,
					  (NSString *)msg);
	CFRelease(msg);
	CFRelease(title);

	if (processApplication) {
		CFRelease(processApplication);
		processApplication = nil;
	}

	if (logFile) {
		fclose(logFile);
		logFile = NULL;
	}
}

- (IBAction) documentationBundler:(id)sender
{
	CFURLRef docURL = CFBundleCopyResourceURL(CFBundleGetMainBundle(), (CFStringRef)[sender title], NULL, NULL);
	LSOpenCFURLRef(docURL, NULL);
	CFRelease(docURL);
}

- (IBAction) openWebsite:(id)sender
{
#pragma unused(sender)
	CFURLRef url = CFURLCreateWithString(kCFAllocatorDefault, CFSTR("http://monolingual.sourceforge.net/"), NULL);
	LSOpenCFURLRef(url, NULL);
	CFRelease(url);
}

- (void) scanLayouts
{
	struct stat st;
	NSString *layoutPath = @"/System/Library/Keyboard Layouts";
	CFArrayRef files = (CFArrayRef)[[NSFileManager defaultManager] directoryContentsAtPath:layoutPath];
	CFIndex length = CFArrayGetCount(files);
	CFMutableArrayRef scannedLayouts = CFArrayCreateMutable(kCFAllocatorDefault, length+6, &kCFTypeArrayCallBacks);
	for (CFIndex i=0; i<length; ++i) {
		CFStringRef file = CFArrayGetValueAtIndex(files, i);
		if (CFStringHasSuffix(file, CFSTR(".bundle")) && !CFEqual(file, CFSTR("Roman.bundle"))) {
			CFStringRef displayName = CFCopyLocalizedString((CFStringRef)[(NSString *)file stringByDeletingPathExtension], "");
			CFStringRef type = CFCopyLocalizedString(CFSTR("Keyboard Layout"), "");
			CFMutableDictionaryRef layout = CFDictionaryCreateMutable(kCFAllocatorDefault, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
			CFDictionarySetValue(layout, CFSTR("Enabled"), kCFBooleanFalse);
			CFDictionarySetValue(layout, CFSTR("DisplayName"), displayName);
			CFDictionarySetValue(layout, CFSTR("Type"), type);
			CFDictionarySetValue(layout, CFSTR("Path"), [layoutPath stringByAppendingPathComponent:(NSString *)file]);
			CFArrayAppendValue(scannedLayouts, layout);
			CFRelease(layout);
			CFRelease(type);
			CFRelease(displayName);
		}
	}
	CFStringRef inputMethod = CFCopyLocalizedString(CFSTR("Input Method"),"");
	if (stat("/System/Library/Components/Kotoeri.component", &st) != -1) {
		CFStringRef displayName = CFCopyLocalizedString(CFSTR("Kotoeri"),"");
		CFMutableDictionaryRef layout = CFDictionaryCreateMutable(kCFAllocatorDefault, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
		CFDictionarySetValue(layout, CFSTR("Enabled"), kCFBooleanFalse);
		CFDictionarySetValue(layout, CFSTR("DisplayName"), displayName);
		CFDictionarySetValue(layout, CFSTR("Type"), inputMethod);
		CFDictionarySetValue(layout, CFSTR("Path"), CFSTR("/System/Library/Components/Kotoeri.component"));
		CFRelease(displayName);
		CFArrayAppendValue(scannedLayouts, layout);
		CFRelease(layout);
	}
	if (stat("/System/Library/Components/XPIM.component", &st) != -1) {
		CFStringRef displayName = CFCopyLocalizedString(CFSTR("Hangul"),"");
		CFMutableDictionaryRef layout = CFDictionaryCreateMutable(kCFAllocatorDefault, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
		CFDictionarySetValue(layout, CFSTR("Enabled"), kCFBooleanFalse);
		CFDictionarySetValue(layout, CFSTR("DisplayName"), displayName);
		CFDictionarySetValue(layout, CFSTR("Type"), inputMethod);
		CFDictionarySetValue(layout, CFSTR("Path"), CFSTR("/System/Library/Components/XPIM.component"));
		CFRelease(displayName);
		CFArrayAppendValue(scannedLayouts, layout);
		CFRelease(layout);
	}
	if (stat("/System/Library/Components/TCIM.component", &st) != -1) {
		CFStringRef displayName = CFCopyLocalizedString(CFSTR("Traditional Chinese"),"");
		CFMutableDictionaryRef layout = CFDictionaryCreateMutable(kCFAllocatorDefault, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
		CFDictionarySetValue(layout, CFSTR("Enabled"), kCFBooleanFalse);
		CFDictionarySetValue(layout, CFSTR("DisplayName"), displayName);
		CFDictionarySetValue(layout, CFSTR("Type"), inputMethod);
		CFDictionarySetValue(layout, CFSTR("Path"), CFSTR("/System/Library/Components/TCIM.component"));
		CFRelease(displayName);
		CFArrayAppendValue(scannedLayouts, layout);
		CFRelease(layout);
	}
	if (stat("/System/Library/Components/SCIM.component", &st) != -1) {
		CFStringRef displayName = CFCopyLocalizedString(CFSTR("Simplified Chinese"),"");
		CFMutableDictionaryRef layout = CFDictionaryCreateMutable(kCFAllocatorDefault, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
		CFDictionarySetValue(layout, CFSTR("Enabled"), kCFBooleanFalse);
		CFDictionarySetValue(layout, CFSTR("DisplayName"), displayName);
		CFDictionarySetValue(layout, CFSTR("Type"), inputMethod);
		CFDictionarySetValue(layout, CFSTR("Path"), CFSTR("/System/Library/Components/SCIM.component"));
		CFRelease(displayName);
		CFArrayAppendValue(scannedLayouts, layout);
		CFRelease(layout);
	}
	if (stat("/System/Library/Components/AnjalIM.component", &st) != -1) {
		CFStringRef displayName = CFCopyLocalizedString(CFSTR("Murasu Anjal Tamil"),"");
		CFMutableDictionaryRef layout = CFDictionaryCreateMutable(kCFAllocatorDefault, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
		CFDictionarySetValue(layout, CFSTR("Enabled"), kCFBooleanFalse);
		CFDictionarySetValue(layout, CFSTR("DisplayName"), displayName);
		CFDictionarySetValue(layout, CFSTR("Type"), inputMethod);
		CFDictionarySetValue(layout, CFSTR("Path"), CFSTR("/System/Library/Components/AnjalIM.component"));
		CFRelease(displayName);
		CFArrayAppendValue(scannedLayouts, layout);
		CFRelease(layout);
	}
	if (stat("/System/Library/Components/HangulIM.component", &st) != -1) {
		CFStringRef displayName = CFCopyLocalizedString(CFSTR("Hangul"),"");
		CFMutableDictionaryRef layout = CFDictionaryCreateMutable(kCFAllocatorDefault, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
		CFDictionarySetValue(layout, CFSTR("Enabled"), kCFBooleanFalse);
		CFDictionarySetValue(layout, CFSTR("DisplayName"), displayName);
		CFDictionarySetValue(layout, CFSTR("Type"), inputMethod);
		CFDictionarySetValue(layout, CFSTR("Path"), CFSTR("/System/Library/Components/HangulIM.component"));
		CFRelease(displayName);
		CFArrayAppendValue(scannedLayouts, layout);
		CFRelease(layout);
	}
	if (stat("/System/Library/Input Methods/KoreanIM.app", &st) != -1) {
		CFStringRef displayName = CFCopyLocalizedString(CFSTR("Korean"),"");
		CFMutableDictionaryRef layout = CFDictionaryCreateMutable(kCFAllocatorDefault, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
		CFDictionarySetValue(layout, CFSTR("Enabled"), kCFBooleanFalse);
		CFDictionarySetValue(layout, CFSTR("DisplayName"), displayName);
		CFDictionarySetValue(layout, CFSTR("Type"), inputMethod);
		CFDictionarySetValue(layout, CFSTR("Path"), CFSTR("/System/Library/Input Methods/KoreanIM.app"));
		CFRelease(displayName);
		CFArrayAppendValue(scannedLayouts, layout);
		CFRelease(layout);
	}
	if (stat("/System/Library/Input Methods/Kotoeri.app", &st) != -1) {
		CFStringRef displayName = CFCopyLocalizedString(CFSTR("Kotoeri"),"");
		CFMutableDictionaryRef layout = CFDictionaryCreateMutable(kCFAllocatorDefault, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
		CFDictionarySetValue(layout, CFSTR("Enabled"), kCFBooleanFalse);
		CFDictionarySetValue(layout, CFSTR("DisplayName"), displayName);
		CFDictionarySetValue(layout, CFSTR("Type"), inputMethod);
		CFDictionarySetValue(layout, CFSTR("Path"), CFSTR("/System/Library/Input Methods/Kotoeri.app"));
		CFRelease(displayName);
		CFArrayAppendValue(scannedLayouts, layout);
		CFRelease(layout);
	}
	if (stat("/System/Library/Input Methods/SCIM.app", &st) != -1) {
		CFStringRef displayName = CFCopyLocalizedString(CFSTR("Simplified Chinese"),"");
		CFMutableDictionaryRef layout = CFDictionaryCreateMutable(kCFAllocatorDefault, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
		CFDictionarySetValue(layout, CFSTR("Enabled"), kCFBooleanFalse);
		CFDictionarySetValue(layout, CFSTR("DisplayName"), displayName);
		CFDictionarySetValue(layout, CFSTR("Type"), inputMethod);
		CFDictionarySetValue(layout, CFSTR("Path"), CFSTR("/System/Library/Input Methods/SCIM.app"));
		CFRelease(displayName);
		CFArrayAppendValue(scannedLayouts, layout);
		CFRelease(layout);
	}
	if (stat("/System/Library/Input Methods/TCIM.app", &st) != -1) {
		CFStringRef displayName = CFCopyLocalizedString(CFSTR("Traditional Chinese"),"");
		CFMutableDictionaryRef layout = CFDictionaryCreateMutable(kCFAllocatorDefault, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
		CFDictionarySetValue(layout, CFSTR("Enabled"), kCFBooleanFalse);
		CFDictionarySetValue(layout, CFSTR("DisplayName"), displayName);
		CFDictionarySetValue(layout, CFSTR("Type"), inputMethod);
		CFDictionarySetValue(layout, CFSTR("Path"), CFSTR("/System/Library/Input Methods/TCIM.app"));
		CFRelease(displayName);
		CFArrayAppendValue(scannedLayouts, layout);
		CFRelease(layout);
	}
	if (stat("/System/Library/Input Methods/TamilIM.app", &st) != -1) {
		CFStringRef displayName = CFCopyLocalizedString(CFSTR("Tamil"),"");
		CFMutableDictionaryRef layout = CFDictionaryCreateMutable(kCFAllocatorDefault, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
		CFDictionarySetValue(layout, CFSTR("Enabled"), kCFBooleanFalse);
		CFDictionarySetValue(layout, CFSTR("DisplayName"), displayName);
		CFDictionarySetValue(layout, CFSTR("Type"), inputMethod);
		CFDictionarySetValue(layout, CFSTR("Path"), CFSTR("/System/Library/Input Methods/TamilIM.app"));
		CFRelease(displayName);
		CFArrayAppendValue(scannedLayouts, layout);
		CFRelease(layout);
	}
	if (stat("/System/Library/Input Methods/VietnameseIM.app", &st) != -1) {
		CFStringRef displayName = CFCopyLocalizedString(CFSTR("Vietnamese"),"");
		CFMutableDictionaryRef layout = CFDictionaryCreateMutable(kCFAllocatorDefault, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
		CFDictionarySetValue(layout, CFSTR("Enabled"), kCFBooleanFalse);
		CFDictionarySetValue(layout, CFSTR("DisplayName"), displayName);
		CFDictionarySetValue(layout, CFSTR("Type"), inputMethod);
		CFDictionarySetValue(layout, CFSTR("Path"), CFSTR("/System/Library/Input Methods/VietnameseIM.app"));
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
	[preferencesController showWindow:self];
}

- (IBAction) donate:(id)sender {
#pragma unused(sender)
	LSOpenCFURLRef(donateURL, NULL);
}

- (IBAction) removeLanguages:(id)sender
{
#pragma unused(sender)
	/* Display a warning first */
	CFStringRef title = CFCopyLocalizedString(CFSTR("WARNING!"), "");
	CFStringRef defaultButton = CFCopyLocalizedString(CFSTR("Stop"), "");
	CFStringRef alternateButton = CFCopyLocalizedString(CFSTR("Continue"), "");
	CFStringRef msg = CFCopyLocalizedString(CFSTR("Are you sure you want to remove these languages? You will not be able to restore them without reinstalling Mac OS X."), "");
	NSBeginAlertSheet((NSString *)title, (NSString *)defaultButton,
					  (NSString *)alternateButton, nil, [NSApp mainWindow],
					  self, NULL,
					  @selector(warningSelector:returnCode:contextInfo:),
					  nil,
					  (NSString *)msg);
	CFRelease(msg);
	CFRelease(alternateButton);
	CFRelease(defaultButton);
	CFRelease(title);
}

- (IBAction) removeLayouts:(id)sender
{
#pragma unused(sender)
	/* Display a warning first */
	CFStringRef title = CFCopyLocalizedString(CFSTR("WARNING!"), "");
	CFStringRef defaultButton = CFCopyLocalizedString(CFSTR("Stop"), "");
	CFStringRef alternateButton = CFCopyLocalizedString(CFSTR("Continue"), "");
	CFStringRef msg = CFCopyLocalizedString(CFSTR("Are you sure you want to remove these languages? You will not be able to restore them without reinstalling Mac OS X."), "");
	NSBeginAlertSheet((NSString *)title, (NSString *)defaultButton,
					  (NSString *)alternateButton, nil, [NSApp mainWindow],
					  self, NULL,
					  @selector(removeLayoutsWarning:returnCode:contextInfo:),self,
					  (NSString *)msg);
	CFRelease(msg);
	CFRelease(alternateButton);
	CFRelease(defaultButton);
	CFRelease(title);
}

- (IBAction) removeArchitectures:(id)sender
{
#pragma unused(sender)
	CFArrayRef	roots;
	CFIndex		roots_count;
	CFIndex		archs_count;
	const char	**argv;

	mode = MODE_ARCHITECTURES;

	logFile = fopen(logFileName, "at");
	if (logFile) {
		time_t now = time(NULL);
		fprintf(logFile, "Monolingual started at %sRemoving architectures: ", ctime(&now));
	}

	if (processApplication)
		roots = processApplication;
	else
		roots = (CFArrayRef)[[NSUserDefaults standardUserDefaults] arrayForKey:@"Roots"];
	roots_count = CFArrayGetCount(roots);
	archs_count = CFArrayGetCount(architectures);
	BOOL strip = [[NSUserDefaults standardUserDefaults] boolForKey:@"Strip"];
	CFIndex num_args = 21+archs_count+archs_count+roots_count+roots_count;
	if (strip)
		++num_args;
	argv = (const char **)malloc(num_args*sizeof(char *));
	int idx = 1;

	CFIndex remove_count = 0;
	for (CFIndex i=0; i<archs_count; ++i) {
		CFDictionaryRef architecture = CFArrayGetValueAtIndex(architectures, i);
		if (CFBooleanGetValue(CFDictionaryGetValue(architecture, CFSTR("Enabled")))) {
			CFStringRef name = CFDictionaryGetValue(architecture, CFSTR("Name"));
			char const *arch = [(NSString *)name UTF8String];
			argv[idx++] = "--thin";
			argv[idx++] = arch;
			if (logFile) {
				if (remove_count)
					fputs(" ", logFile);
				fputs(arch, logFile);
			}
			++remove_count;
		}
	}
	if (logFile)
		fputs("\nModified files:\n", logFile);

	if (remove_count == archs_count) {
		CFStringRef title = CFCopyLocalizedString(CFSTR("Cannot remove all architectures"), "");
		CFStringRef msg = CFCopyLocalizedString(CFSTR("Removing all architectures will make Mac OS X inoperable. Please keep at least one architecture and try again."), "");
		NSBeginAlertSheet((NSString *)title,
						  nil, nil, nil, [NSApp mainWindow], self, NULL,
						  NULL, nil,
						  (NSString *)msg);
		CFRelease(msg);
		CFRelease(title);
		if (logFile) {
			fclose(logFile);
			logFile = NULL;
		}
	} else if (remove_count) {
		/* start things off if we have something to remove! */
		for (CFIndex i=0; i<roots_count; ++i) {
			CFDictionaryRef root = CFArrayGetValueAtIndex(roots, i);
			CFBooleanRef archEnabled = CFDictionaryGetValue(root, CFSTR("Architectures"));
			Boolean enabled = archEnabled ? CFBooleanGetValue(archEnabled) : false;
			NSString *path = (NSString *)CFDictionaryGetValue(root, CFSTR("Path"));
			if (enabled) {
				NSLog(@"Adding root %@", path);
				argv[idx++] = "-r";
			} else {
				NSLog(@"Excluding root %@", path);
				argv[idx++] = "-x";
			}
			argv[idx++] = [path fileSystemRepresentation];
		}
		argv[idx++] = "-b";
		argv[idx++] = "com.charlessoft.pacifist";
		argv[idx++] = "-b";
		argv[idx++] = "com.skype.skype";
		argv[idx++] = "-b";
		argv[idx++] = "com.yazsoft.SpeedDownload";
		argv[idx++] = "-b";
		argv[idx++] = "org.xlife.Acquisition";
		argv[idx++] = "-b";
		argv[idx++] = "com.linotype.FontExplorerX";
		argv[idx++] = "-b";
		argv[idx++] = "com.alsoft.diskwarrior";
		argv[idx++] = "-b";
		argv[idx++] = "com.StarryNight.StarryNight";
		argv[idx++] = "-b";
		argv[idx++] = "com.blizzard.worldofwarcraft";
		argv[idx++] = "-x";
		argv[idx++] = "/System/Library/Frameworks";
		argv[idx++] = "-x";
		argv[idx++] = "/System/Library/PrivateFrameworks";
		if (strip)
			argv[idx++] = "-s";
		argv[idx] = NULL;
		[self runDeleteHelperWithArgs:argv];
	} else {
		if (logFile) {
			fclose(logFile);
			logFile = NULL;
		}
	}
	free(argv);
}

static void dataCallback(CFSocketRef s, CFSocketCallBackType callbackType, 
						 CFDataRef address, const void *data, void *info)
{
#pragma unused(s,callbackType,address)
	CFIndex i;
	unsigned int j;
	unsigned int num;
	CFIndex length;
	const unsigned char *bytes;
	char hbuf[LONGEST_HUMAN_READABLE + 1];
	MyResponder *responder = (MyResponder *)info;

	length = CFDataGetLength((CFDataRef)data);
	if (length) {
		/* append new data */
		CFDataAppendBytes(pipeBuffer, CFDataGetBytePtr((CFDataRef)data), length);
		bytes = CFDataGetBytePtr(pipeBuffer);
		length = CFDataGetLength(pipeBuffer);

		/* count number of '\0' characters */
		num = 0;
		for (i=0; i<length; ++i)
			if (!bytes[i])
				++num;

		for (i=0, j=0; num > 1 && i<length; ++i, ++j) {
			if (!bytes[j]) {
				unsigned char const *pfile;
				unsigned char const *psize;

				/* read file name */
				pfile = bytes;
				CFStringRef file = CFStringCreateWithBytes(kCFAllocatorDefault, bytes, j, kCFStringEncodingUTF8, false);
				bytes += j + 1;

				/* skip to next zero character */
				for (j=0; bytes[j]; ++j) {}

				/* read file size */
				psize = bytes;
				CFStringRef size = CFStringCreateWithBytes(kCFAllocatorDefault, bytes, j, kCFStringEncodingUTF8, false);
				bytesSaved += CFStringGetIntValue(size);
				bytes += j + 1;
				i += j + 1;
				num -= 2;

				if (logFile)
					fprintf(logFile, "%s: %s\n", pfile, psize);

				CFStringRef message;
				if (mode == MODE_ARCHITECTURES) {
					message = CFCopyLocalizedString(CFSTR("Removing architecture from universal binary"), "");
				} else {
					/* parse file name */
					CFArrayRef pathComponents = CFStringCreateArrayBySeparatingStrings(kCFAllocatorDefault, file, CFSTR("/"));
					CFIndex componentCount = CFArrayGetCount(pathComponents);
					CFStringRef lang = NULL;
					CFStringRef app = NULL;
					CFStringRef layout = NULL;
					CFStringRef im = NULL;
					BOOL cache = NO;
					if (mode == MODE_LANGUAGES) {
						for (CFIndex k=0; k<componentCount; ++k) {
							CFStringRef pathComponent = CFArrayGetValueAtIndex(pathComponents, k);
							if (CFStringHasSuffix(pathComponent, CFSTR(".app"))) {
								if (app)
									CFRelease(app);
								app = CFStringCreateWithSubstring(kCFAllocatorDefault, pathComponent, CFRangeMake(0,CFStringGetLength(pathComponent)-4));
							} else if (CFStringHasSuffix(pathComponent, CFSTR(".bundle"))) {
								if (layout)
									CFRelease(layout);
								layout = CFStringCreateWithSubstring(kCFAllocatorDefault, pathComponent, CFRangeMake(0,CFStringGetLength(pathComponent)-7));
							} else if (CFStringHasSuffix(pathComponent, CFSTR(".component"))) {
								if (im)
									CFRelease(im);
								im = CFStringCreateWithSubstring(kCFAllocatorDefault, pathComponent, CFRangeMake(0,CFStringGetLength(pathComponent)-10));
							} else if (CFStringHasSuffix(pathComponent, CFSTR(".lproj"))) {
								CFIndex count = CFArrayGetCount(languages);
								for (CFIndex l=0; l<count; ++l) {
									CFDictionaryRef language = CFArrayGetValueAtIndex(languages, l);
									CFArrayRef folders = CFDictionaryGetValue(language, CFSTR("Folders"));
									if (-1 != CFArrayGetFirstIndexOfValue(folders, CFRangeMake(0, CFArrayGetCount(folders)), pathComponent)) {
										lang = CFDictionaryGetValue(language, CFSTR("DisplayName"));
										break;
									}
								}
							} else if (CFStringHasPrefix(pathComponent, CFSTR("com.apple.IntlDataCache"))) {
								cache = YES;
							}
						}
						CFRelease(pathComponents);
					}
					if (layout && CFStringHasPrefix(file, CFSTR("/System/Library/"))) {
						CFStringRef description = CFCopyLocalizedString(CFSTR("Removing keyboard layout"), "");
						message = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%@ %@%C"), description, layout, 0x2026);
						CFRelease(description);
					} else if (im && CFStringHasPrefix(file, CFSTR("/System/Library/"))) {
						CFStringRef description = CFCopyLocalizedString(CFSTR("Removing input method"), "");
						message = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%@ %@%C"), description, layout, 0x2026);
						CFRelease(description);
					} else if (cache) {
						CFStringRef description = CFCopyLocalizedString(CFSTR("Clearing cache"), "");
						message = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%@%C"), description, 0x2026);
						CFRelease(description);
					} else if (app) {
						CFStringRef description = CFCopyLocalizedString(CFSTR("Removing language"), "");
						CFStringRef from = CFCopyLocalizedString(CFSTR("from"), "");
						message = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%@ %@ %@ %@%C"), description, lang, from, app, 0x2026);
						CFRelease(from);
						CFRelease(description);
					} else if (lang) {
						CFStringRef description = CFCopyLocalizedString(CFSTR("Removing language"), "");
						message = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%@ %@%C"), description, lang, 0x2026);
						CFRelease(description);
					} else {
						CFStringRef description = CFCopyLocalizedString(CFSTR("Removing"), "");
						message = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%@ %@%C"), description, file, 0x2026);
						CFRelease(description);
					}
					if (app)
						CFRelease(app);
					if (layout)
						CFRelease(layout);
					if (im)
						CFRelease(im);
				}

				[responder->progressWindowController setText:message];
				[responder->progressWindowController setFile:file];
				[NSApp setWindowsNeedUpdate:YES];
				CFRelease(message);
				CFRelease(file);
				CFRelease(size);
				j = -1;
			}
		}
		/* delete processed bytes */
		CFDataDeleteBytes(pipeBuffer, CFRangeMake(0, i));
	} else if (pipeSocket) {
		/* EOF */
		CFRunLoopRemoveSource(CFRunLoopGetCurrent(), pipeRunLoopSource, kCFRunLoopCommonModes);
		CFRelease(pipeRunLoopSource);
		CFSocketInvalidate(pipeSocket);
		CFRelease(pipeSocket);
		pipeSocket = NULL;
		CFRelease(pipeBuffer);
		[NSApp endSheet:[responder->progressWindowController window]];
		[[responder->progressWindowController window] orderOut:responder];
		[responder->progressWindowController stop];

		if (processApplication) {
			[responder removeArchitectures:nil];
			
			CFRelease(processApplication);
			processApplication = nil;
		} else {
			Growl_PostNotificationWithDictionary(finishedNotificationInfo);

			CFStringRef title = CFCopyLocalizedString(CFSTR("Removal completed"), "");
			CFStringRef msgFormat = CFCopyLocalizedString(CFSTR("Files removed. Space saved: %s."), "");
			CFStringRef msg = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, msgFormat, human_readable(bytesSaved, hbuf, 1024));
			CFRelease(msgFormat);
			NSBeginAlertSheet((NSString *)title,
							  nil, nil, nil, parentWindow, responder, NULL, NULL,
							  responder,
							  (NSString *)msg);
			CFRelease(msg);
			CFRelease(title);
			[responder scanLayouts];
			if (logFile) {
				fclose(logFile);
				logFile = NULL;
			}
		}
	}
}

- (void) runDeleteHelperWithArgs:(const char **)argv
{
	OSStatus status;
	FILE *fp_pipe;
	char path[PATH_MAX];

	CFURLRef helperPath = CFBundleCopyResourceURL(CFBundleGetMainBundle(), CFSTR("Helper"), NULL, NULL);
	if (!CFURLGetFileSystemRepresentation(helperPath, false, (UInt8 *)path, sizeof(path))) {
		NSLog(@"Could not get file system representation of %@", helperPath);
		/* TODO */
		NSBeep();
		return;
	}
	CFRelease(helperPath);
	AuthorizationItem right = {kAuthorizationRightExecute, strlen(path)+1, path, 0};
	AuthorizationRights rights = {1, &right};
	AuthorizationRef authorizationRef;

	status = AuthorizationCreate(&rights, kAuthorizationEmptyEnvironment, kAuthorizationFlagExtendRights | kAuthorizationFlagInteractionAllowed, &authorizationRef);
	switch (status) {
		case errAuthorizationSuccess:
			break;
		case errAuthorizationDenied: {
			/* If you can't do it because you're not administrator, then let the user know! */
			CFStringRef title = CFCopyLocalizedString(CFSTR("Permission Error"), "");
			CFStringRef msg = CFCopyLocalizedString(CFSTR("You entered an incorrect administrator password."), "");
			NSBeginAlertSheet((NSString *)title, nil, nil, nil,
							  [NSApp mainWindow], self, NULL, NULL, NULL,
							  (NSString *)msg);
			CFRelease(msg);
			CFRelease(title);
			if (logFile) {
				fclose(logFile);
				logFile = NULL;
			}
			return;
		}
		case errAuthorizationCanceled: {
			CFStringRef title = CFCopyLocalizedString(CFSTR("Nothing done"), "");
			CFStringRef msg = CFCopyLocalizedString(CFSTR("Monolingual is stopping without making any changes. Your OS has not been modified."), "");
			NSBeginAlertSheet((NSString *)title, nil, nil, nil,
							  [NSApp mainWindow], self, NULL, NULL, NULL,
							  (NSString *)msg);
			CFRelease(msg);
			CFRelease(title);
			if (logFile) {
				fclose(logFile);
				logFile = NULL;
			}
			return;
		}
		default: {
			CFStringRef title = CFCopyLocalizedString(CFSTR("Authorization Error"), "");
			CFStringRef msg = CFCopyLocalizedString(CFSTR("Failed to authorize as an administrator."), "");
			NSBeginAlertSheet((NSString *)title, nil, nil, nil,
							  [NSApp mainWindow], self, NULL, NULL, NULL,
							  (NSString *)msg);
			CFRelease(msg);
			CFRelease(title);
			if (logFile) {
				fclose(logFile);
				logFile = NULL;
			}
			return;
		}
	}

	argv[0] = path;

	parentWindow = [NSApp mainWindow];
	[progressWindowController start];
	[NSApp beginSheet:[progressWindowController window]
	   modalForWindow:parentWindow
		modalDelegate:nil
	   didEndSelector:nil
		  contextInfo:nil];

	status = AuthorizationExecuteWithPrivileges(authorizationRef, path, kAuthorizationFlagDefaults, (char * const *)argv, &fp_pipe);
	if (errAuthorizationSuccess == status) {
		CFSocketContext context = { 0, self, NULL, NULL, NULL };

		Growl_PostNotificationWithDictionary(startedNotificationInfo);

		bytesSaved = 0ULL;
		pipeBuffer = CFDataCreateMutable(kCFAllocatorDefault, 0);
		pipeDescriptor = fileno(fp_pipe);
		pipeSocket = CFSocketCreateWithNative(kCFAllocatorDefault, pipeDescriptor, kCFSocketDataCallBack, dataCallback, &context);
		pipeRunLoopSource = CFSocketCreateRunLoopSource(kCFAllocatorDefault, pipeSocket, 0);
		CFRunLoopAddSource(CFRunLoopGetCurrent(), pipeRunLoopSource, kCFRunLoopCommonModes);
	} else {
		/* TODO */
		NSBeep();
	}

	AuthorizationFree(authorizationRef, kAuthorizationFlagDefaults);
}

- (void) removeLayoutsWarning:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
#pragma unused(sheet)
	CFIndex         i;
	CFIndex         count;
	int				idx;
	CFDictionaryRef	row;
	BOOL			trash;
	const char		**argv;

	if (NSAlertDefaultReturn == returnCode) {
		CFStringRef title = CFCopyLocalizedString(CFSTR("Nothing done"), "");
		CFStringRef msg = CFCopyLocalizedString(CFSTR("Monolingual is stopping without making any changes. Your OS has not been modified."), "");
		NSBeginAlertSheet((NSString *)title, nil, nil, nil,
						  [NSApp mainWindow], self, NULL, NULL, contextInfo,
						  (NSString *)msg);
		CFRelease(msg);
		CFRelease(title);
	} else {
		CFIndex num_args;
		mode = MODE_LAYOUTS;
		logFile = fopen(logFileName, "at");
		if (logFile) {
			time_t now = time(NULL);
			fprintf(logFile, "Monolingual started at %sRemoving layouts: ", ctime(&now));
		}

		count = CFArrayGetCount(layouts);
		num_args = count + count + 9;
		trash = [[NSUserDefaults standardUserDefaults] boolForKey:@"Trash"];
		if (trash)
			++num_args;
		argv = (const char **)malloc(num_args*sizeof(char *));
		argv[1] = "-f";
		argv[2] = "/System/Library/Caches/com.apple.IntlDataCache";
		argv[3] = "-f";
		argv[4] = "/System/Library/Caches/com.apple.IntlDataCache.kbdx";
		argv[5] = "-f";
		argv[6] = "/System/Library/Caches/com.apple.IntlDataCache.sbdl";
		argv[7] = "-f";
		argv[8] = "/System/Library/Caches/com.apple.IntlDataCache.tecx";
		idx = 9;
		if (trash)
			argv[idx++] = "-t";
		int rCount = 0;
		for (i=0; i<count; ++i) {
			row = CFArrayGetValueAtIndex(layouts, i);
			if (CFBooleanGetValue(CFDictionaryGetValue(row, CFSTR("Enabled")))) {
				argv[idx++] = "-f";
				argv[idx++] = [(NSString *)CFDictionaryGetValue(row, CFSTR("Path")) fileSystemRepresentation];
				if (logFile) {
					if (rCount++)
						fputs(" ", logFile);
					NSString *displayName = (NSString *)CFDictionaryGetValue(row, CFSTR("DisplayName"));
					fputs([displayName UTF8String], logFile);
				}
			}
		}
		if (logFile)
			fputs("\nDeleted files: \n", logFile);
		if (rCount) {
			argv[idx] = NULL;
			[self runDeleteHelperWithArgs:argv];
		} else {
			if (logFile) {
				fclose(logFile);
				logFile = NULL;
			}
		}
		free(argv);
	}
}

- (void) warningSelector:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
#pragma unused(sheet,contextInfo)
	CFIndex i;
	CFIndex lCount;

	if (NSAlertDefaultReturn != returnCode) {
		lCount = CFArrayGetCount(languages);
		for (i=0; i<lCount; ++i) {
			CFDictionaryRef language = CFArrayGetValueAtIndex(languages, i);
			if (CFBooleanGetValue(CFDictionaryGetValue(language, CFSTR("Enabled"))) && CFEqual(CFArrayGetValueAtIndex(CFDictionaryGetValue(language, CFSTR("Folders")), 0U), CFSTR("en.lproj"))) {
				/* Display a warning */
				CFStringRef title = CFCopyLocalizedString(CFSTR("WARNING!"), "");
				CFStringRef defaultButton = CFCopyLocalizedString(CFSTR("Stop"), "");
				CFStringRef alternateButton = CFCopyLocalizedString(CFSTR("Continue"), "");
				CFStringRef msg = CFCopyLocalizedString(CFSTR("You are about to delete the English language files. Are you sure you want to do that?"), "");
				NSBeginCriticalAlertSheet((NSString *)title,
										  (NSString *)defaultButton,
										  (NSString *)alternateButton, nil,
										  [NSApp mainWindow], self, NULL,
										  @selector(englishWarningSelector:returnCode:contextInfo:),
										  nil,
										  (NSString *)msg);
				CFRelease(msg);
				CFRelease(alternateButton);
				CFRelease(defaultButton);
				CFRelease(title);
				return;
			}
		}
		[self englishWarningSelector:nil returnCode:NSAlertAlternateReturn contextInfo:nil];
	}
}

- (void) englishWarningSelector:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
#pragma unused(sheet,contextInfo)
	CFIndex			i;
	CFIndex			rCount;
	CFIndex			lCount;
	unsigned int	idx;
	const char		**argv;
	CFArrayRef		roots;
	CFIndex			roots_count;
	BOOL			trash;

	mode = MODE_LANGUAGES;

	logFile = fopen(logFileName, "at");
	if (logFile) {
		time_t now = time(NULL);
		fprintf(logFile, "Monolingual started at %sRemoving languages: ", ctime(&now));
	}

	if (processApplication)
		roots = processApplication;
	else
		roots = (CFArrayRef)[[NSUserDefaults standardUserDefaults] arrayForKey:@"Roots"];
	roots_count = CFArrayGetCount(roots);

	for (i=0; i<roots_count; ++i) {
		CFBooleanRef enabled = CFDictionaryGetValue(CFArrayGetValueAtIndex(roots, i), CFSTR("Languages"));
		if (enabled && CFBooleanGetValue(enabled))
			break;
	}
	if (i==roots_count)
		/* No active roots */
		roots_count = 0;

	if (NSAlertDefaultReturn == returnCode || !roots_count) {
		CFStringRef title = CFCopyLocalizedString(CFSTR("Nothing done"), "");
		CFStringRef msg = CFCopyLocalizedString(CFSTR("Monolingual is stopping without making any changes. Your OS has not been modified."), "");
		NSBeginAlertSheet((NSString *)title, nil, nil, nil,
						  [NSApp mainWindow], self, NULL, NULL, NULL,
						  (NSString *)msg);
		CFRelease(msg);
		CFRelease(title);
	} else {
		rCount = 0;
		lCount = CFArrayGetCount(languages);
		argv = (const char **)malloc((3+lCount+lCount+lCount+roots_count+roots_count)*sizeof(char *));
		idx = 1U;
		trash = [[NSUserDefaults standardUserDefaults] boolForKey:@"Trash"];
		if (trash)
			argv[idx++] = "-t";
		for (i=0; i<roots_count; ++i) {
			CFDictionaryRef root = CFArrayGetValueAtIndex(roots, i);
			CFBooleanRef langEnabled = CFDictionaryGetValue(root, CFSTR("Languages"));
			Boolean enabled = langEnabled ? CFBooleanGetValue(langEnabled) : false;
			NSString *path = (NSString *)CFDictionaryGetValue(root, CFSTR("Path"));
			if (enabled) {
				NSLog(@"Adding root %@", path);
				argv[idx++] = "-r";
			} else {
				NSLog(@"Excluding root %@", path);
				argv[idx++] = "-x";
			}
			argv[idx++] = [path fileSystemRepresentation];
		}
		for (i=0; i<lCount; ++i) {
			CFDictionaryRef language = CFArrayGetValueAtIndex(languages, i);
			if (CFBooleanGetValue(CFDictionaryGetValue(language, CFSTR("Enabled")))) {
				CFArrayRef paths = CFDictionaryGetValue(language, CFSTR("Folders"));
				CFIndex paths_count = CFArrayGetCount(paths);
				for (CFIndex j=0; j<paths_count; ++j) {
					NSString *path = (NSString *)CFArrayGetValueAtIndex(paths, j);
					char const *pathname = [path fileSystemRepresentation];
					if (logFile) {
						if (rCount || paths_count)
							fputs(" ", logFile);
						fputs(pathname, logFile);
					}
					argv[idx++] = pathname;
				}
				++rCount;
			}
		}

		if (logFile)
			fputs("\nDeleted files: \n", logFile);
		if (rCount == lCount)  {
			CFStringRef title = CFCopyLocalizedString(CFSTR("Cannot remove all languages"), "");
			CFStringRef msg = CFCopyLocalizedString(CFSTR("Removing all languages will make Mac OS X inoperable. Please keep at least one language and try again."), "");
			NSBeginAlertSheet((NSString *)title, nil, nil, nil,
							  [NSApp mainWindow], self, NULL, NULL, NULL,
							  (NSString *)msg);
			CFRelease(msg);
			CFRelease(title);
			if (logFile) {
				fclose(logFile);
				logFile = NULL;
			}
		} else if (rCount) {
			/* start things off if we have something to remove! */
			argv[idx] = NULL;
			[self runDeleteHelperWithArgs:argv];
		} else {
			if (logFile) {
				fclose(logFile);
				logFile = NULL;
			}
		}
		free(argv);
	}
}

- (void) dealloc
{
	CFRelease(versionURL);
	CFRelease(downloadURL);
	CFRelease(donateURL);
	CFRelease(layouts);
	CFRelease(languages);
	CFRelease(startedNotificationInfo);
	CFRelease(finishedNotificationInfo);
	[super dealloc];
}

- (void) awakeFromNib
{
	int    mib[2];
	size_t len;
	char   *kernelVersion;
	BOOL   isTenFourOrHigher;

	[bundlesOutlineView setAutoresizesOutlineColumn: NO];

	versionURL = CFURLCreateWithString(kCFAllocatorDefault, CFSTR("http://monolingual.sourceforge.net/version.xml"), NULL);
	downloadURL = CFURLCreateWithString(kCFAllocatorDefault, CFSTR("http://monolingual.sourceforge.net"), NULL);
	donateURL = CFURLCreateWithString(kCFAllocatorDefault, CFSTR("http://monolingual.sourceforge.net/donate.html"), NULL);

	CFArrayRef languagePref = (CFArrayRef) CFPreferencesCopyValue(CFSTR("AppleLanguages"),
																  kCFPreferencesAnyApplication,
																  kCFPreferencesCurrentUser,
																  kCFPreferencesAnyHost);
	CFIndex count = languagePref ? CFArrayGetCount(languagePref) : 0;
	CFMutableSetRef userLanguages = CFSetCreateMutable(kCFAllocatorDefault, count, &kCFTypeSetCallBacks);

	for (CFIndex i=0; i<count; ++i)
		CFSetAddValue(userLanguages, CFArrayGetValueAtIndex(languagePref, i));
	if (languagePref)
		CFRelease(languagePref);

	[[self window] setFrameAutosaveName:@"MainWindow"];

	// Get the kernel's version
	mib[0] = CTL_KERN;
	mib[1] = KERN_OSRELEASE;
	sysctl(mib, 2, NULL, &len, NULL, 0);
	kernelVersion = malloc(len * sizeof(char));
	sysctl(mib, 2, kernelVersion, &len, NULL, 0);
	isTenFourOrHigher = kernelVersion[0] >= '8';
	free(kernelVersion);

#define NUM_KNOWN_LANGUAGES	130
	CFMutableArrayRef knownLanguages = CFArrayCreateMutable(kCFAllocatorDefault, NUM_KNOWN_LANGUAGES, &kCFTypeArrayCallBacks);
#define ADD_LANGUAGE_BEGIN(name) \
	do { \
		CFMutableDictionaryRef language = CFDictionaryCreateMutable(kCFAllocatorDefault, 3, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks); \
		CFStringRef languageName = CFCopyLocalizedString(CFSTR(name), ""); \
		CFDictionarySetValue(language, CFSTR("DisplayName"), languageName); \
		CFRelease(languageName);
#define ADD_LANGUAGE_END \
		CFDictionarySetValue(language, CFSTR("Folders"), foldersArray); \
		CFRelease(foldersArray); \
		CFArrayAppendValue(knownLanguages, language); \
		CFRelease(language); \
	} while(0)
#define ADD_LANGUAGE_0(code, name, folder) \
	ADD_LANGUAGE_BEGIN(name) \
		CFDictionarySetValue(language, CFSTR("Enabled"), CFSetContainsValue(userLanguages, (code)) ? kCFBooleanFalse : kCFBooleanTrue); \
		CFStringRef folders[1]; \
		folders[0] = CFSTR(folder ".lproj"); \
		CFArrayRef foldersArray = CFArrayCreate(kCFAllocatorDefault, (const void **)folders, 1, &kCFTypeArrayCallBacks); \
	ADD_LANGUAGE_END
#define ADD_LANGUAGE_1(code, name, folder1, folder2) \
	ADD_LANGUAGE_BEGIN(name) \
		CFDictionarySetValue(language, CFSTR("Enabled"), CFSetContainsValue(userLanguages, (code)) ? kCFBooleanFalse : kCFBooleanTrue); \
		CFStringRef folders[2]; \
		folders[0] = CFSTR(folder1 ".lproj"); \
		folders[1] = CFSTR(folder2 ".lproj"); \
		CFArrayRef foldersArray = CFArrayCreate(kCFAllocatorDefault, (const void **)folders, 2, &kCFTypeArrayCallBacks); \
	ADD_LANGUAGE_END
#define ADD_LANGUAGE_2(code, name, folder1, folder2, folder3) \
	ADD_LANGUAGE_BEGIN(name) \
		CFDictionarySetValue(language, CFSTR("Enabled"), CFSetContainsValue(userLanguages, (code)) ? kCFBooleanFalse : kCFBooleanTrue); \
		CFStringRef folders[3]; \
		folders[0] = CFSTR(folder1 ".lproj"); \
		folders[1] = CFSTR(folder2 ".lproj"); \
		folders[2] = CFSTR(folder3 ".lproj"); \
		CFArrayRef foldersArray = CFArrayCreate(kCFAllocatorDefault, (const void **)folders, 3, &kCFTypeArrayCallBacks); \
	ADD_LANGUAGE_END
#define ADD_LANGUAGE_EN(code, name, folder1, folder2) \
	ADD_LANGUAGE_BEGIN(name) \
		CFDictionarySetValue(language, CFSTR("Enabled"), kCFBooleanFalse); \
		CFStringRef folders[2]; \
		folders[0] = CFSTR(folder1 ".lproj"); \
		folders[1] = CFSTR(folder2 ".lproj"); \
		CFArrayRef foldersArray = CFArrayCreate(kCFAllocatorDefault, (const void **)folders, 2, &kCFTypeArrayCallBacks); \
	ADD_LANGUAGE_END

	ADD_LANGUAGE_1(CFSTR("af"),    "Afrikaans",            "af", "Afrikaans");
	ADD_LANGUAGE_1(CFSTR("am"),    "Amharic",              "am", "Amharic");
	ADD_LANGUAGE_1(CFSTR("ar"),    "Arabic",               "ar", "Arabic");
	ADD_LANGUAGE_1(CFSTR("as"),    "Assamese",             "as", "Assamese");
	ADD_LANGUAGE_1(CFSTR("ay"),    "Aymara",               "ay", "Aymara");
	ADD_LANGUAGE_1(CFSTR("az"),    "Azerbaijani",          "az", "Azerbaijani");
	ADD_LANGUAGE_1(CFSTR("be"),    "Byelorussian",         "be", "Byelorussian");
	ADD_LANGUAGE_1(CFSTR("bg"),    "Bulgarian",            "bg", "Bulgarian");
	ADD_LANGUAGE_1(CFSTR("bi"),    "Bislama",              "bi", "Bislama");
	ADD_LANGUAGE_1(CFSTR("bn"),    "Bengali",              "bn", "Bengali");
	ADD_LANGUAGE_1(CFSTR("bo"),    "Tibetan",              "bo", "Tibetan");
	ADD_LANGUAGE_1(CFSTR("br"),    "Breton",               "bt", "Breton");
	ADD_LANGUAGE_1(CFSTR("ca"),    "Catalan",              "ca", "Catalan");
	ADD_LANGUAGE_1(CFSTR("chr"),   "Cherokee",             "chr", "Cherokee");
	ADD_LANGUAGE_2(CFSTR("cs"),    "Czech",                "cs", "cs_CZ", "Czech");
	ADD_LANGUAGE_1(CFSTR("cy"),    "Welsh",                "cy", "Welsh");
	ADD_LANGUAGE_2(CFSTR("da"),    "Danish",               "da", "da_DK", "Danish");
	ADD_LANGUAGE_2(CFSTR("de"),    "German",               "de", "de_DE", "German");
	ADD_LANGUAGE_0(isTenFourOrHigher ? CFSTR("de-AT") : CFSTR("de_AT"), "German (Austria)",      "de_AT");
	ADD_LANGUAGE_0(isTenFourOrHigher ? CFSTR("de-CH") : CFSTR("de_CH"), "German (Switzerland)",  "de_CH");
	ADD_LANGUAGE_1(CFSTR("dz"),    "Dzongkha",             "dz", "Dzongkha");
	ADD_LANGUAGE_2(CFSTR("el"),    "Greek",                "el", "el_GR", "Greek");
	ADD_LANGUAGE_EN(CFSTR("en"),   "English",              "en", "English");
	ADD_LANGUAGE_0(isTenFourOrHigher ? CFSTR("en-AU") : CFSTR("en_AU"), "English (Australia)",      "en_AU");
	ADD_LANGUAGE_0(isTenFourOrHigher ? CFSTR("en-CA") : CFSTR("en_CA"), "English (Canada)",         "en_CA");
	ADD_LANGUAGE_0(isTenFourOrHigher ? CFSTR("en-GB") : CFSTR("en_GB"), "English (United Kingdom)", "en_GB");
	ADD_LANGUAGE_0(isTenFourOrHigher ? CFSTR("en-NZ") : CFSTR("en_NZ"), "English (New Zealand)",    "en_NZ");
	ADD_LANGUAGE_0(isTenFourOrHigher ? CFSTR("en-US") : CFSTR("en_US"), "English (United States)",  "en_US");
	ADD_LANGUAGE_1(CFSTR("eo"),    "Esperanto",            "eo", "Esperanto");
	ADD_LANGUAGE_2(CFSTR("es"),    "Spanish",              "es", "es_ES", "Spanish");
	ADD_LANGUAGE_1(CFSTR("et"),    "Estonian",             "et", "Estonian");
	ADD_LANGUAGE_1(CFSTR("eu"),    "Basque",               "eu", "Basque");
	ADD_LANGUAGE_1(CFSTR("fa"),    "Farsi",                "fa", "Farsi");
	ADD_LANGUAGE_2(CFSTR("fi"),    "Finnish",              "fi", "fi_FI", "Finnish");
	ADD_LANGUAGE_1(CFSTR("fo"),    "Faroese",              "fo", "Faroese");
	ADD_LANGUAGE_2(CFSTR("fr"),    "French",               "fr", "fr_FR", "French");
	ADD_LANGUAGE_0(isTenFourOrHigher ? CFSTR("fr-CA") : CFSTR("fr_CA"), "French (Canada)",      "fr_CA");
	ADD_LANGUAGE_0(isTenFourOrHigher ? CFSTR("fr-CH") : CFSTR("fr_CH"), "French (Switzerland)", "fr_CH");
	ADD_LANGUAGE_1(CFSTR("ga"),    "Irish",                "ga", "Irish");
	ADD_LANGUAGE_1(CFSTR("gd"),    "Scottish",             "gd", "Scottish");
	ADD_LANGUAGE_1(CFSTR("gl"),    "Galician",             "gl", "Galician");
	ADD_LANGUAGE_1(CFSTR("gn"),    "Guarani",              "gn", "Guarani");
	ADD_LANGUAGE_1(CFSTR("gu"),    "Gujarati",             "gu", "Gujarati");
	ADD_LANGUAGE_1(CFSTR("gv"),    "Manx",                 "gv", "Manx");
	ADD_LANGUAGE_1(CFSTR("haw"),   "Hawaiian",             "haw", "Hawaiian");
	ADD_LANGUAGE_1(CFSTR("he"),    "Hebrew",               "he", "Hebrew");
	ADD_LANGUAGE_1(CFSTR("hi"),    "Hindi",                "hi", "Hindi");
	ADD_LANGUAGE_1(CFSTR("hr"),    "Croatian",             "hr", "Croatian");
	ADD_LANGUAGE_2(CFSTR("hu"),    "Hungarian",            "hu", "hu_HU", "Hungarian");
	ADD_LANGUAGE_1(CFSTR("hy"),    "Armenian",             "hy", "Armenian");
	ADD_LANGUAGE_1(CFSTR("id"),    "Indonesian",           "id", "Indonesian");
	ADD_LANGUAGE_1(CFSTR("is"),    "Icelandic",            "is", "Icelandic");
	ADD_LANGUAGE_2(CFSTR("it"),    "Italian",              "it", "it_IT", "Italian");
	ADD_LANGUAGE_1(CFSTR("iu"),    "Inuktitut",            "iu", "Inuktitut");
	ADD_LANGUAGE_2(CFSTR("ja"),    "Japanese",             "ja", "ja_JP", "Japanese");
	ADD_LANGUAGE_1(CFSTR("jv"),    "Javanese",             "jv", "Javanese");
	ADD_LANGUAGE_1(CFSTR("ka"),    "Georgian",             "ka", "Georgian");
	ADD_LANGUAGE_1(CFSTR("kk"),    "Kazakh",               "kk", "Kazakh");
	ADD_LANGUAGE_1(CFSTR("kl"),    "Greenlandic",          "kl", "Greenlandic");
	ADD_LANGUAGE_1(CFSTR("km"),    "Khmer",                "km", "Khmer");
	ADD_LANGUAGE_1(CFSTR("kn"),    "Kannada",              "kn", "Kannada");
	ADD_LANGUAGE_2(CFSTR("ko"),    "Korean",               "ko", "ko_KR", "Korean");
	ADD_LANGUAGE_1(CFSTR("ks"),    "Kashmiri",             "ks", "Kashmiri");
	ADD_LANGUAGE_1(CFSTR("ku"),    "Kurdish",              "ku", "Kurdish");
	ADD_LANGUAGE_1(CFSTR("kw"),    "Kernowek",             "kw", "Kernowek");
	ADD_LANGUAGE_1(CFSTR("ky"),    "Kirghiz",              "ky", "Kirghiz");
	ADD_LANGUAGE_1(CFSTR("la"),    "Latin",                "la", "Latin");
	ADD_LANGUAGE_1(CFSTR("lo"),    "Lao",                  "lo", "Lao");
	ADD_LANGUAGE_1(CFSTR("lt"),    "Lithuanian",           "lt", "Lithuanian");
	ADD_LANGUAGE_1(CFSTR("lv"),    "Latvian",              "lv", "Latvian");
	ADD_LANGUAGE_1(CFSTR("mg"),    "Malagasy",             "mg", "Malagasy");
	ADD_LANGUAGE_1(CFSTR("mi"),    "Maori",                "mi", "Maori");
	ADD_LANGUAGE_1(CFSTR("mk"),    "Macedonian",           "mk", "Macedonian");
	ADD_LANGUAGE_1(CFSTR("mr"),    "Marathi",              "mr", "Marathi");
	ADD_LANGUAGE_1(CFSTR("ml"),    "Malayalam",            "ml", "Malayalam");
	ADD_LANGUAGE_1(CFSTR("mn"),    "Mongolian",            "mn", "Mongolian");
	ADD_LANGUAGE_1(CFSTR("mo"),    "Moldavian",            "mo", "Moldavian");
	ADD_LANGUAGE_1(CFSTR("ms"),    "Malay",                "ms", "Malay");
	ADD_LANGUAGE_1(CFSTR("mt"),    "Maltese",              "mt", "Maltese");
	ADD_LANGUAGE_1(CFSTR("my"),    "Burmese",              "my", "Burmese");
	ADD_LANGUAGE_1(CFSTR("ne"),    "Nepali",               "ne", "Nepali");
	ADD_LANGUAGE_2(CFSTR("nl"),    "Dutch",                "nl", "nl_NL", "Dutch");
	ADD_LANGUAGE_0(isTenFourOrHigher ? CFSTR("nl-BE") : CFSTR("nl_BE"), "Flemish",              "nl_BE");
	ADD_LANGUAGE_2(CFSTR("no"),    "Norwegian",            "no", "no_NO", "Norwegian");
	ADD_LANGUAGE_0(CFSTR("nb"),    "Norwegian Bokmal",     "nb");
	ADD_LANGUAGE_0(CFSTR("nn"),    "Norwegian Nynorsk",    "nn");
	ADD_LANGUAGE_1(CFSTR("om"),    "Oromo",                "om", "Oromo");
	ADD_LANGUAGE_1(CFSTR("or"),    "Oriya",                "or", "Oriya");
	ADD_LANGUAGE_1(CFSTR("pa"),    "Punjabi",              "pa", "Punjabi");
	ADD_LANGUAGE_2(CFSTR("pl"),    "Polish",               "pl", "pl_PL", "Polish");
	ADD_LANGUAGE_1(CFSTR("ps"),    "Pashto",               "ps", "Pashto");
	ADD_LANGUAGE_2(CFSTR("pt"),    "Portuguese",           "pt", "pt_PT", "Portuguese");
	ADD_LANGUAGE_1(isTenFourOrHigher ? CFSTR("pt-BR") : CFSTR("pt_BR"), "Portuguese (Brazil)", "pt_BR", "PT_br");
	ADD_LANGUAGE_1(CFSTR("qu"),    "Quechua",              "qu", "Quechua");
	ADD_LANGUAGE_1(CFSTR("rn"),    "Rundi",                "rn", "Rundi");
	ADD_LANGUAGE_1(CFSTR("ro"),    "Romanian",             "ro", "Romanian");
	ADD_LANGUAGE_1(CFSTR("ru"),    "Russian",              "ru", "Russian");
	ADD_LANGUAGE_1(CFSTR("rw"),    "Kinyarwanda",          "rw", "Kinyarwanda");
	ADD_LANGUAGE_1(CFSTR("sa"),    "Sanskrit",             "sa", "Sanskrit");
	ADD_LANGUAGE_1(CFSTR("sd"),    "Sindhi",               "sd", "Sindhi");
	ADD_LANGUAGE_1(CFSTR("se"),    "Sami",                 "se", "Sami");
	ADD_LANGUAGE_1(CFSTR("si"),    "Sinhalese",            "si", "Sinhalese");
	ADD_LANGUAGE_1(CFSTR("sk"),    "Slovak",               "sk", "Slovak");
	ADD_LANGUAGE_1(CFSTR("sl"),    "Slovenian",            "sl", "Slovenian");
	ADD_LANGUAGE_1(CFSTR("so"),    "Somali",               "so", "Somali");
	ADD_LANGUAGE_1(CFSTR("sq"),    "Albanian",             "sq", "Albanian");
	ADD_LANGUAGE_1(CFSTR("sr"),    "Serbian",              "sr", "Serbian");
	ADD_LANGUAGE_1(CFSTR("su"),    "Sundanese",            "su", "Sundanese");
	ADD_LANGUAGE_2(CFSTR("sv"),    "Swedish",              "sv", "sv_SE", "Swedish");
	ADD_LANGUAGE_1(CFSTR("sw"),    "Swahili",              "sw", "Swahili");
	ADD_LANGUAGE_1(CFSTR("ta"),    "Tamil",                "ta", "Tamil");
	ADD_LANGUAGE_1(CFSTR("te"),    "Telugu",               "te", "Telugu");
	ADD_LANGUAGE_1(CFSTR("tg"),    "Tajiki",               "tg", "Tajiki");
	ADD_LANGUAGE_1(CFSTR("th"),    "Thai",                 "th", "Thai");
	ADD_LANGUAGE_1(CFSTR("ti"),    "Tigrinya",             "ti", "Tigrinya");
	ADD_LANGUAGE_1(CFSTR("tk"),    "Turkmen",              "tk", "Turkmen");
	ADD_LANGUAGE_1(CFSTR("tl"),    "Tagalog",              "tl", "Tagalog");
	ADD_LANGUAGE_1(CFSTR("tlh"),   "Klingon",              "tlh", "Klingon");
	ADD_LANGUAGE_2(CFSTR("tr"),    "Turkish",              "tr", "tr_TR", "Turkish");
	ADD_LANGUAGE_1(CFSTR("tt"),    "Tatar",                "tt", "Tatar");
	ADD_LANGUAGE_1(CFSTR("to"),    "Tongan",               "to", "Tongan");
	ADD_LANGUAGE_1(CFSTR("ug"),    "Uighur",               "ug", "Uighur");
	ADD_LANGUAGE_1(CFSTR("uk"),    "Ukrainian",            "tk", "Ukrainian");
	ADD_LANGUAGE_1(CFSTR("ur"),    "Urdu",                 "ur", "Urdu");
	ADD_LANGUAGE_1(CFSTR("uz"),    "Uzbek",                "uz", "Uzbek");
	ADD_LANGUAGE_1(CFSTR("vi"),    "Vietnamese",           "vi", "Vietnamese");
	ADD_LANGUAGE_1(CFSTR("yi"),    "Yiddish",              "yi", "Yiddish");
	ADD_LANGUAGE_0(CFSTR("zh"),    "Chinese",              "zh");
	ADD_LANGUAGE_1(isTenFourOrHigher ? CFSTR("zh-Hans") : CFSTR("zh_CN"), "Chinese (Simplified Han)",   "zh_CN", "zh_SC");
	ADD_LANGUAGE_1(isTenFourOrHigher ? CFSTR("zh-Hant") : CFSTR("zh_TW"), "Chinese (Traditional Han)",  "zh_TW", "zh_HK");
	CFRelease(userLanguages);
	CFArraySortValues(knownLanguages, CFRangeMake(0, NUM_KNOWN_LANGUAGES), languageCompare, NULL);
	[self setLanguages:(NSMutableArray *)knownLanguages];
	CFRelease(knownLanguages);

	[self scanLayouts];

	const arch_info_t archs[9] = {
		{ CFSTR("ppc"),       CFSTR("PowerPC"),           CPU_TYPE_POWERPC,   CPU_SUBTYPE_POWERPC_ALL},
		{ CFSTR("ppc750"),    CFSTR("PowerPC G3"),        CPU_TYPE_POWERPC,   CPU_SUBTYPE_POWERPC_750},
		{ CFSTR("ppc7400"),   CFSTR("PowerPC G4"),        CPU_TYPE_POWERPC,   CPU_SUBTYPE_POWERPC_7400},
		{ CFSTR("ppc7450"),   CFSTR("PowerPC G4+"),       CPU_TYPE_POWERPC,   CPU_SUBTYPE_POWERPC_7450},
		{ CFSTR("ppc970"),    CFSTR("PowerPC G5"),        CPU_TYPE_POWERPC,   CPU_SUBTYPE_POWERPC_970},
		{ CFSTR("ppc64"),     CFSTR("PowerPC 64-bit"),    CPU_TYPE_POWERPC64, CPU_SUBTYPE_POWERPC_ALL},
		{ CFSTR("ppc970-64"), CFSTR("PowerPC G5 64-bit"), CPU_TYPE_POWERPC64, CPU_SUBTYPE_POWERPC_970},
		{ CFSTR("x86"),       CFSTR("Intel"),             CPU_TYPE_X86,       CPU_SUBTYPE_X86_ALL},
		{ CFSTR("x86_64"),    CFSTR("Intel 64-bit"),      CPU_TYPE_X86_64,    CPU_SUBTYPE_X86_64_ALL}
	};

	host_basic_info_data_t hostInfo;
	mach_msg_type_number_t infoCount = HOST_BASIC_INFO_COUNT;
	mach_port_t my_mach_host_self;
	my_mach_host_self = mach_host_self();
	kern_return_t ret = host_info(my_mach_host_self, HOST_BASIC_INFO, (host_info_t)&hostInfo, &infoCount);
	mach_port_deallocate(mach_task_self(), my_mach_host_self);

	if (hostInfo.cpu_type == CPU_TYPE_X86) {
		/* fix host_info */
		int x86_64;
		size_t x86_64_size = sizeof(x86_64);
		if (!sysctlbyname("hw.optional.x86_64", &x86_64, &x86_64_size, NULL, 0)) {
			if (x86_64) {
				hostInfo.cpu_type = CPU_TYPE_X86_64;
				hostInfo.cpu_subtype = CPU_SUBTYPE_X86_64_ALL;
			}
		}
	}

	[currentArchitecture setStringValue:(NSString *)CFSTR("unknown")];
	CFMutableArrayRef knownArchitectures = CFArrayCreateMutable(kCFAllocatorDefault, 9, &kCFTypeArrayCallBacks);
	for (unsigned i=0U; i<9U; ++i) {
		CFMutableDictionaryRef architecture = CFDictionaryCreateMutable(kCFAllocatorDefault, 3, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
		CFDictionarySetValue(architecture, CFSTR("Enabled"), (ret == KERN_SUCCESS && (hostInfo.cpu_type != archs[i].cpu_type || hostInfo.cpu_subtype < archs[i].cpu_subtype) && (!(hostInfo.cpu_type & CPU_ARCH_ABI64) || (archs[i].cpu_type != (hostInfo.cpu_type & ~CPU_ARCH_ABI64)))) ? kCFBooleanTrue : kCFBooleanFalse);
		CFDictionarySetValue(architecture, CFSTR("Name"), archs[i].name);
		CFDictionarySetValue(architecture, CFSTR("DisplayName"), archs[i].displayName);
		CFArrayAppendValue(knownArchitectures, architecture);
		if (hostInfo.cpu_type == archs[i].cpu_type && hostInfo.cpu_subtype == archs[i].cpu_subtype) {
			CFStringRef format = CFCopyLocalizedString(CFSTR("Current architecture: %@"), "");
			CFStringRef label = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, format, archs[i].displayName);
			CFRelease(format);
			[currentArchitecture setStringValue:(NSString *)label];
			CFRelease(label);
		}
	}
	[self setArchitectures:(NSMutableArray *)knownArchitectures];
	CFRelease(knownArchitectures);

	CFStringRef startedNotificationName = CFCopyLocalizedString(CFSTR("Monolingual started"), "");
	CFStringRef finishedNotificationName = CFCopyLocalizedString(CFSTR("Monolingual finished"), "");
	CFTypeRef notificationNames[2] = { startedNotificationName, finishedNotificationName };

	CFArrayRef defaultAndAllNotifications = CFArrayCreate(kCFAllocatorDefault, notificationNames, 2, &kCFTypeArrayCallBacks);
	CFTypeRef registrationKeys[2] = { GROWL_NOTIFICATIONS_ALL, GROWL_NOTIFICATIONS_DEFAULT };
	CFTypeRef registrationValues[2] = { defaultAndAllNotifications, defaultAndAllNotifications };
	CFDictionaryRef registrationDictionary = CFDictionaryCreate(kCFAllocatorDefault,
																registrationKeys,
																registrationValues,
																2,
																&kCFTypeDictionaryKeyCallBacks,
																&kCFTypeDictionaryValueCallBacks);
	CFRelease(defaultAndAllNotifications);

	/* set ourself as the Growl delegate */
	InitGrowlDelegate(&growlDelegate);
	growlDelegate.applicationName = CFSTR("Monolingual");
	growlDelegate.registrationDictionary = registrationDictionary;
	Growl_SetDelegate(&growlDelegate);
	CFRelease(registrationDictionary);

	NSString *keys[4] = {
		GROWL_APP_NAME,
		GROWL_NOTIFICATION_NAME,
		GROWL_NOTIFICATION_TITLE,
		GROWL_NOTIFICATION_DESCRIPTION
	};
	CFStringRef values[4];
	CFStringRef description;

	description = CFCopyLocalizedString(CFSTR("Started removing files"), "");
	values[0] = CFSTR("Monolingual");
	values[1] = startedNotificationName;
	values[2] = startedNotificationName;
	values[3] = description;
	startedNotificationInfo = CFDictionaryCreate(kCFAllocatorDefault, (const void **)keys, (const void **)values, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	CFRelease(startedNotificationName);
	CFRelease(description);

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

- (id) outlineView:(NSOutlineView *)outlineView child:(int)i ofItem:(id)item
{
#pragma unused (outlineView)
	NGSTreeNode *node = item ? item : rootNode;
	return [node childAtIndex: i];
}

- (BOOL) outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
#pragma unused (outlineView)
	NGSTreeNode *node = item ? item : rootNode;
	return ([node numberOfChildren] != 0);
}

- (int) outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
#pragma unused (outlineView)
	NGSTreeNode *node = item ? item : rootNode;
	return [node numberOfChildren];
}

- (id) outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
#pragma unused (outlineView)
	NGSTreeNode *node = item ? item : rootNode;
	if ([[tableColumn identifier] isEqualToString: @"BundleTableColumnName"]) {
		if ([node isDisabledOrHasDisabledSubLocale]) {
			NSDictionary *attrs = [NSDictionary dictionaryWithObject: [NSColor grayColor] forKey: NSForegroundColorAttributeName];
			return [[[NSAttributedString alloc] initWithString: [node name] attributes: attrs] autorelease];
		} else
			return [node name];
	} else if ([[tableColumn identifier] isEqualToString: @"BundleTableColumnLocale"])
		return [node localeIdentifier];
	else if ([[tableColumn identifier] isEqualToString: @"BundleTableColumnSize"])
		return [NSNumber numberWithUnsignedLongLong: [node size]];

	return nil;
}

@end
