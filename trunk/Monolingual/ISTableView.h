//
//  ISTableView.h
//  Monolingual
//
//  Created by Ingmar Stein on 27.01.06.
//  Copyright 2006-2010 Ingmar Stein. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface ISTableView : NSTableView {
	IBOutlet NSArrayController *arrayController;
}

@end
