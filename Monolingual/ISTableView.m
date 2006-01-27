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
				NSMutableDictionary *dict = [[arrayController arrangedObjects] objectAtIndex:row];
				if (dict) {
					id oldValue = [dict objectForKey:@"enabled"];
					NSNumber *newValue = [[NSNumber alloc] initWithBool:![oldValue boolValue]];
					[dict setObject:newValue forKey:@"enabled"];
					[newValue release];
				}
			}
			break;
		default:
			[super keyDown:theEvent];
	}
}

@end
