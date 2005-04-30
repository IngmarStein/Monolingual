/* 
 *  Copyright (C) 2001, 2002  Joshua Schrier (jschrier@mac.com),
 *  2004 Ingmar Stein
 *  Released under the GNU GPL.  For more information, see the header file.
 */

#import "ProgressWindowController.h"
#import "MyResponder.h"

@implementation ProgressWindowController
id parent;
NSMutableParagraphStyle *fileParagraphStyle;
NSDictionary *fileAttributes;

- (IBAction) cancelButton: (id)sender
{
#pragma unused(sender)
	[applicationText setStringValue: NSLocalizedString(@"Canceling operation...",@"")];
	[fileText setStringValue: @""];
	[NSApp updateWindows];
	[parent cancelRemove];
}

- (id) init
{
	if( (self = [self initWithWindowNibName:@"ProgressWindow"]) ) {
		fileParagraphStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
		[fileParagraphStyle setLineBreakMode:NSLineBreakByTruncatingMiddle];
		fileAttributes = [[NSDictionary alloc] initWithObjectsAndKeys:fileParagraphStyle, NSParagraphStyleAttributeName, nil];
	}
	return self;
}

- (void) dealloc
{
	[fileAttributes release];
	[fileParagraphStyle release];
	[super dealloc];
}

+ (id) sharedProgressWindowController: (id)sender
{
	static ProgressWindowController *_sharedProgressWindowController = nil;

	if( !_sharedProgressWindowController ) {
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
	[self setFile: @""];
}

- (void) stop
{
	[progressBar stopAnimation: self];
}

- (void) setFile: (NSString *)file
{
	NSAttributedString *attrStr = [[NSAttributedString alloc] initWithString:file attributes:fileAttributes];
	[[fileText cell] setAttributedStringValue:attrStr];
	[fileText updateCell:[fileText cell]];
	[attrStr release];
	//[fileText setStringValue: file];
}

- (void) setText: (NSString *)text
{
	[applicationText setStringValue: text];
}

@end
