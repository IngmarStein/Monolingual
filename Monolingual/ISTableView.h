//
//  ISTableView.h
//  Monolingual
//
//  Created by Ingmar Stein on 27.01.06.
//  Copyright 2006-2012 Ingmar Stein. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface ISTableView : NSTableView {
}

@property (nonatomic, strong) IBOutlet NSArrayController *arrayController;

@end
