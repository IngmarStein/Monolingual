//
//  PreferencesController.h
//  Monolingual
//
//  Created by Ingmar Stein on Mon Apr 19 2004.
//  Copyright (c) 2004-2014 Ingmar Stein. All rights reserved.
//

@import Cocoa;

@interface PreferencesController : NSWindowController {
}

@property(nonatomic, strong) IBOutlet NSArrayController *roots;

- (IBAction) add: (id)sender;

@end
