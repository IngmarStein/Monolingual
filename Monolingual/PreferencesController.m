//
//  PreferencesController.m
//  Monolingual
//
//  Created by Ingmar Stein on Mon Apr 19 2004.
//  Copyright (c) 2004-2006 Ingmar Stein. All rights reserved.
//

#import "PreferencesController.h"

@implementation PreferencesController

- (id) init
{
	self = [self initWithWindowNibName:@"Preferences"];
	return self;
}

- (IBAction) add: (id)sender
{
#pragma unused(sender)
    NSOpenPanel *oPanel = [NSOpenPanel openPanel];

    [oPanel setAllowsMultipleSelection:YES];
	[oPanel setCanChooseDirectories:YES];
	[oPanel setCanChooseFiles:NO];

	if( NSOKButton == [oPanel runModalForDirectory:nil file:nil types:nil] ) {
		NSEnumerator *filenameEnum = [[oPanel filenames] objectEnumerator];
		NSString *filename;
		while ((filename = [filenameEnum nextObject]))
			[roots addObject:[NSMutableDictionary dictionaryWithObjectsAndKeys:filename, @"Path", kCFBooleanTrue, @"Enabled", nil]];
	}
}

@end
