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
CFDictionaryRef fileAttributes;

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
	if( (self = [self initWithWindowNibName:@"ProgressWindow"]) ) {
		fileParagraphStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
		[fileParagraphStyle setLineBreakMode:NSLineBreakByTruncatingMiddle];
		fileAttributes = CFDictionaryCreate(kCFAllocatorDefault, (const void **)&NSParagraphStyleAttributeName, (const void **)&fileParagraphStyle, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	}
	return self;
}

- (void) dealloc
{
	CFRelease(fileAttributes);
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
	[progressBar startAnimation:self];
	CFStringRef value = CFCopyLocalizedString(CFSTR("Removing language resources..."),"");
	[applicationText setStringValue:(NSString *)value];
	CFRelease(value);
	[self setFile:CFSTR("")];
}

- (void) stop
{
	[progressBar stopAnimation:self];
}

- (void) setFile:(CFStringRef)file
{
	NSAttributedString *attrStr = [[NSAttributedString alloc] initWithString:(NSString *)file attributes:(NSDictionary *)fileAttributes];
	[[fileText cell] setAttributedStringValue:attrStr];
	[fileText updateCell:[fileText cell]];
	[attrStr release];
	//[fileText setStringValue:file];
}

- (void) setText:(CFStringRef)text
{
	[applicationText setStringValue:(NSString *)text];
}

@end
