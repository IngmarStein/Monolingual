//
//  DeleteHelper.m
//  Monolingual
//
//  Created by Ingmar Stein on Tue Mar 23 2004.
//  Copyright (c) 2004 Ingmar Stein. All rights reserved.
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
//

#import "DeleteHelper.h"

@implementation DeleteHelper
//NSLock *statusLock;
BOOL removeTaskStatus;
NSSet *directories;

- (id) initWithDirectories: (NSSet *)dirs
{
	self = [super init];
	NSFileHandle *inputHandle = [NSFileHandle fileHandleWithStandardInput];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(cancelRemoval:) 
												 name:NSFileHandleReadCompletionNotification 
											   object:inputHandle];
	[[NSNotificationCenter defaultCenter] addObserver:self 
											 selector:@selector(finishedTask:) 
												 name:NSThreadWillExitNotification 
											   object:nil];
	[inputHandle readInBackgroundAndNotify];
	removeTaskStatus = FALSE;
	directories = dirs;
	//statusLock = [[NSLock alloc] init];
	return self;
}

- (void) finishedTask: (NSNotification *)aNotification
{
	//[statusLock release];
	[directories release];
	[NSApp terminate: self];
}

- (void) cancelRemoval: (NSNotification *)aNotification
{
	//while( ![statusLock tryLock] ) {}
	removeTaskStatus = FALSE;
	//[statusLock unlock];
}

- (void) applicationDidFinishLaunching: (NSNotification *)notification
{
	removeTaskStatus = TRUE;
	[NSThread detachNewThreadSelector: @selector(removeDirectories:) toTarget: self withObject: directories];
}

- (void) fileManager: (NSFileManager *)manager willProcessPath: (NSString *)path
{
	NSDictionary *fattrs = [manager fileAttributesAtPath: path traverseLink: YES];
	printf( "%s%c%llu%c", [path fileSystemRepresentation], '\0', [fattrs fileSize], '\0' );
	fflush( stdout );
}

- (BOOL) fileManager: (NSFileManager *)manager shouldProceedAfterError: (NSDictionary *)errorInfo
{
	return( TRUE );
}

- (void) removeDirectories: (NSSet *)directories atRoot: (NSString *)root
{
	NSString *file;
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSDirectoryEnumerator *enumerator = [fileManager enumeratorAtPath:root];
	while( (file = [enumerator nextObject]) ) {
		//if( [statusLock tryLock] ) {
			if( !removeTaskStatus ) {
		//		[statusLock unlock];
				return;
			}
		//	[statusLock unlock];
		//}
		if( [directories containsObject: [file lastPathComponent]] ) {
			[enumerator skipDescendents];
			NSString *path = [root stringByAppendingPathComponent:file];
			[fileManager removeFileAtPath:path handler:self];
		}
	}
}

- (void) removeDirectories: (NSSet *)directories
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	if( removeTaskStatus ) { [self removeDirectories: directories atRoot: @"/Applications"]; }
	if( removeTaskStatus ) { [self removeDirectories: directories atRoot: @"/Developer"]; }
	if( removeTaskStatus ) { [self removeDirectories: directories atRoot: @"/Library"]; }
	if( removeTaskStatus ) { [self removeDirectories: directories atRoot: @"/System"]; }
	[pool release];
}

@end
