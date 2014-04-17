/*
 *  Copyright (C) 2001, 2002  Joshua Schrier (jschrier@mac.com),
 *  2004-2014 Ingmar Stein
 *  Released under the GNU GPL.  For more information, see the header file.
 */

#import "ProgressWindowController.h"

@implementation ProgressWindowController

- (IBAction)cancelButton:(id)sender
{
	[self.applicationText setStringValue:NSLocalizedString(@"Canceling operation...", "")];
	[self.fileText setStringValue:@""];

	[self.window orderOut:sender];
	[NSApp endSheet:self.window returnCode:1];
}

- (void) start
{
	[self.progressBar setUsesThreadedAnimation:YES];
	[self.progressBar startAnimation:self];
	[self.applicationText setStringValue:NSLocalizedString(@"Removing...", "")];
	[self.fileText setStringValue:@""];
}

- (void) stop
{
	[self.progressBar stopAnimation:self];
}

- (void) setFile:(NSString *)file
{
	[self.fileText setStringValue:file];
}

- (void) setText:(NSString *)text
{
	[self.applicationText setStringValue:text];
}

@end
