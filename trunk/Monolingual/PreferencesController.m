//
//  PreferencesController.m
//  Monolingual
//
//  Created by Ingmar Stein on Mon Apr 19 2004.
//  Copyright (c) 2004-2007 Ingmar Stein. All rights reserved.
//

#import "PreferencesController.h"

@implementation PreferencesController

- (IBAction) add: (id)sender
{
#pragma unused(sender)
    NSOpenPanel *oPanel = [NSOpenPanel openPanel];

    [oPanel setAllowsMultipleSelection:YES];
	[oPanel setCanChooseDirectories:YES];
	[oPanel setCanChooseFiles:NO];

	if (NSOKButton == [oPanel runModalForDirectory:nil file:nil types:nil]) {
		NSEnumerator *filenameEnum = [[oPanel filenames] objectEnumerator];
		NSString *filename;
		while ((filename = [filenameEnum nextObject])) {
			CFMutableDictionaryRef root = CFDictionaryCreateMutable(kCFAllocatorDefault, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
			CFDictionarySetValue(root, CFSTR("Path"), filename);
			CFDictionarySetValue(root, CFSTR("Enabled"), kCFBooleanTrue);
			[roots addObject:(NSMutableDictionary *)root];
			CFRelease(root);
		}
	}
}

@end
