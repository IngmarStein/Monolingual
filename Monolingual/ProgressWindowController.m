/* 
 *  Copyright (C) 2001, 2002  Joshua Schrier (jschrier@mac.com),
 *  2004 Ingmar Stein
 *  Released under the GNU GPL.  For more information, see the header file.
 */

#import "ProgressWindowController.h"

@implementation ProgressWindowController
id parent;

- (IBAction) cancelButton: (id)sender
{
	[applicationText setStringValue: NSLocalizedString(@"Canceling operation...",@"")];
	[fileText setStringValue: @""];
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
	static ProgressWindowController *_sharedProgressWindowController=nil;

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
	[progressBar startAnimation: self];
	[applicationText setStringValue: NSLocalizedString(@"Removing language resources...",@"")];
	[fileText setStringValue: @""];
}

- (void) stop
{
	[progressBar stopAnimation: self];
}

- (void) setFile: (NSString *)file
{
	[fileText setStringValue: file];
}

- (void) setText: (NSString *)text
{
	[applicationText setStringValue: text];
}

@end
