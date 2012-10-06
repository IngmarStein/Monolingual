//
//  PreferencesController.m
//  Monolingual
//
//  Created by Ingmar Stein on Mon Apr 19 2004.
//  Copyright (c) 2004-2012 Ingmar Stein. All rights reserved.
//

#import "PreferencesController.h"

@implementation PreferencesController

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

	// Weak references to NSWindowControllers are not supported on 10.7
	//__weak __typeof__(self) wself = self;
	__unsafe_unretained __typeof__(self) wself = self;
	[oPanel beginWithCompletionHandler:^(NSInteger result) {
		if (NSOKButton == result) {
			for (NSURL *url in [oPanel URLs]) {
				[wself.roots addObject:@{ @"Path" : [url path],
										  @"Languages" : @YES,
										  @"Architectures" : @YES}];
			}
		}
	}];
}

@end
