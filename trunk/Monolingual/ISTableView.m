//
//  ISTableView.m
//  Monolingual
//
//  Created by Ingmar Stein on 27.01.06.
//  Copyright 2006-2010 Ingmar Stein. All rights reserved.
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
				NSMutableDictionary *dict = [arrayController arrangedObjects][row];
				if (dict) {
					BOOL value = [dict[@"Enabled"] boolValue];
					dict[@"Enabled"] = @(!value);
				}
			}
			break;
		default:
			[super keyDown:theEvent];
			break;
	}
}

@end