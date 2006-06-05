//
//  ISTableView.m
//  Monolingual
//
//  Created by Ingmar Stein on 27.01.06.
//  Copyright 2006 Ingmar Stein. All rights reserved.
//

#import "ISTableView.h"

@implementation ISTableView

- (void) keyDown:(NSEvent *)theEvent
{
	int row;
	unichar key = [[theEvent charactersIgnoringModifiers] characterAtIndex:0];

	switch (key) {
		case ' ':
			row = [self selectedRow];
			if (row != -1) {
				CFMutableDictionaryRef dict = (CFMutableDictionaryRef)[[arrayController arrangedObjects] objectAtIndex:row];
				if (dict) {
					CFBooleanRef value = CFDictionaryGetValue(dict, CFSTR("enabled"));
					CFDictionarySetValue(dict, CFSTR("enabled"), CFBooleanGetValue(value) ? kCFBooleanFalse : kCFBooleanTrue);
				}
			}
			break;
		default:
			[super keyDown:theEvent];
			break;
	}
}

@end
