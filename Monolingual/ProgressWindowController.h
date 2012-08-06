/*
 * monolingual -
 *  front end for monolingual.pl (included in this package), which
 *  strips away extra language .lproj from OSX to save space
 *
 *   Copyright (C) 2001, 2002 Joshua Schrier (jschrier@mac.com),
 *   2004-2012 Ingmar Stein
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation; either version 2 of the License, or
 *   (at your option) any later version.
 *
 *   This program is distributed in the hope that it will be useful,
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *   GNU General Public License for more details.
 *
 *   You should have received a copy of the GNU General Public License
 *   along with this program; if not, write to the Free Software
 *   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */

#import <Cocoa/Cocoa.h>

@class MyResponder;

@interface ProgressWindowController : NSWindowController
{
}

@property (nonatomic, weak) IBOutlet NSProgressIndicator *progressBar;
@property (nonatomic, weak) IBOutlet NSTextField *applicationText;
@property (nonatomic, weak) IBOutlet NSTextField * fileText;

// cannot use weak properties to NSWindowControllers on OS X 10.7
@property (nonatomic, unsafe_unretained) IBOutlet MyResponder *parent;

- (IBAction) cancelButton: (id)sender;
- (void) start;
- (void) stop;
- (void) setText:(NSString *)text;
- (void) setFile:(NSString *)file;
- (void) windowDidLoad;

@end
