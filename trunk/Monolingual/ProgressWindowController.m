/*
 *  Copyright (C) 2001, 2002  Joshua Schrier (jschrier@mac.com),
 *  2004-2012 Ingmar Stein
 *  Released under the GNU GPL.  For more information, see the header file.
 */

#import "ProgressWindowController.h"

@implementation ProgressWindowController

@synthesize progressBar;
@synthesize applicationText;
@synthesize fileText;

- (IBAction)cancelButton:(id)sender
{
	[applicationText setStringValue:NSLocalizedString(@"Canceling operation...", "")];
	[fileText setStringValue:@""];

	[self.window orderOut:sender];
	[NSApp endSheet:self.window returnCode:1];
}

- (void) start
{
	[progressBar setUsesThreadedAnimation:YES];
	[progressBar startAnimation:self];
	[applicationText setStringValue:NSLocalizedString(@"Removing...", "")];
	[fileText setStringValue:@""];
}

- (void) stop
{
	[progressBar stopAnimation:self];
}

- (void) setFile:(NSString *)file
{
	[fileText setStringValue:file];
}

- (void) setText:(NSString *)text
{
	[applicationText setStringValue:text];
}

@end
