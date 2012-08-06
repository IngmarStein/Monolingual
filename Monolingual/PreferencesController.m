//
//  PreferencesController.m
//  Monolingual
//
//  Created by Ingmar Stein on Mon Apr 19 2004.
//  Copyright (c) 2004-2012 Ingmar Stein. All rights reserved.
//

#import "PreferencesController.h"

@implementation PreferencesController

@synthesize roots;

- (void) awakeFromNib
{
	[[self window] setFrameAutosaveName:@"PreferencesWindow"];
}

- (IBAction) add: (id)sender
{
    NSOpenPanel *oPanel = [NSOpenPanel openPanel];

    [oPanel setAllowsMultipleSelection:YES];
	[oPanel setCanChooseDirectories:YES];
	[oPanel setCanChooseFiles:NO];
	[oPanel setTreatsFilePackagesAsDirectories:YES];

	[oPanel beginWithCompletionHandler:^(NSInteger result) {
		if (NSOKButton == result) {
			for (NSURL *url in [oPanel URLs]) {
				[self.roots addObject:@{ @"Path" : [url path],
										 @"Languages" : @YES,
										 @"Architectures" : @YES}];
			}
		}
	}];
}

@end
