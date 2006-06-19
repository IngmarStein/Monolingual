/*
 *  Copyright (C) 2001, 2002  Joshua Schrier (jschrier@mac.com),
 *  2004-2006 Ingmar Stein
 *  Released under the GNU GPL.  For more information, see the header file.
 */

#import "ProgressWindowController.h"
#import "MyResponder.h"

@implementation ProgressWindowController
id parent;

- (IBAction) cancelButton: (id)sender
{
#pragma unused(sender)
	CFStringRef value = CFCopyLocalizedString(CFSTR("Canceling operation..."),"");
	[applicationText setStringValue:(NSString *)value];
	CFRelease(value);
	[fileText setStringValue:@""];
	[NSApp updateWindows];
	[parent cancelRemove];
}

- (id) init
{
	self = [self initWithWindowNibName:@"ProgressWindow"];
	return self;
}

+ (id) sharedProgressWindowController: (id)sender
{
	static ProgressWindowController *_sharedProgressWindowController = nil;

	if (!_sharedProgressWindowController) {
		_sharedProgressWindowController = [[ProgressWindowController allocWithZone:[self zone]] init];
		parent = sender;
	}
	return _sharedProgressWindowController;
}

- (void) windowDidLoad
{
	[super windowDidLoad];
	[self start];
}

- (void) start
{
	[progressBar startAnimation:self];
	CFStringRef value = CFCopyLocalizedString(CFSTR("Removing..."),"");
	[applicationText setStringValue:(NSString *)value];
	CFRelease(value);
	[fileText setStringValue:@""];
}

- (void) stop
{
	[progressBar stopAnimation:self];
}

- (void) setFile:(CFStringRef)file
{
	[fileText setStringValue:(NSString *)file];
}

- (void) setText:(CFStringRef)text
{
	[applicationText setStringValue:(NSString *)text];
}

@end
