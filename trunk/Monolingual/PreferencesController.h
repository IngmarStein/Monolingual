//
//  PreferencesController.h
//  Monolingual
//
//  Created by Ingmar Stein on Mon Apr 19 2004.
//  Copyright (c) 2004 __MyCompanyName__. All rights reserved.
//

#import <AppKit/AppKit.h>


@interface PreferencesController : NSWindowController {
	IBOutlet NSTableView *rootDirView;
	IBOutlet NSButton *removeButton;
	NSMutableArray *roots;
}
- (IBAction) add: (id)sender;
- (IBAction) remove: (id)sender;
- (id) init;
- (void) update;
- (void) awakeFromNib;
- (int) numberOfRowsInTableView: (NSTableView *)aTableView;
- (id) tableView: (NSTableView *)aTableView objectValueForTableColumn: (NSTableColumn *)aTableColumn row: (int)rowIndex;
@end
