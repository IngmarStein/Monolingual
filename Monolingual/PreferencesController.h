//
//  PreferencesController.h
//  Monolingual
//
//  Created by Ingmar Stein on Mon Apr 19 2004.
//  Copyright (c) 2004-2010 Ingmar Stein. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface PreferencesController : NSWindowController {
	IBOutlet NSArrayController *roots;
}
- (IBAction) add: (id)sender;
@end
