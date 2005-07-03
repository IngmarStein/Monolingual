//
//  PreferencesController.h
//  Monolingual
//
//  Created by Ingmar Stein on Mon Apr 19 2004.
//  Copyright (c) 2004 __MyCompanyName__. All rights reserved.
//

#import <AppKit/AppKit.h>

@interface PreferencesController : NSWindowController {
	IBOutlet NSArrayController *roots;
}
- (IBAction) add: (id)sender;
- (id) init;
@end
