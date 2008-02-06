//
//  ISTableView.m
//  Monolingual
//
//  Created by Ingmar Stein on 27.01.06.
//  Copyright 2006-2008 Ingmar Stein. All rights reserved.
//

#import "ISTableView.h"

@implementation ISTableView

- (void) keyDown:(NSEvent *)theEvent
{
	NSInteger row;
	unichar key = [[theEvent charactersIgnoringModifiers] characterAtIndex:0];

	switch (key) {
		case ' ':
			row = [self selectedRow];
			if (row != -1) {
				CFMutableDictionaryRef dict = (CFMutableDictionaryRef)[[arrayController arrangedObjects] objectAtIndex:row];
				if (dict) {
					CFBooleanRef value = CFDictionaryGetValue(dict, CFSTR("Enabled"));
					CFDictionarySetValue(dict, CFSTR("Enabled"), CFBooleanGetValue(value) ? kCFBooleanFalse : kCFBooleanTrue);
				}
			}
			break;
		default:
			[super keyDown:theEvent];
			break;
	}
}

@end
