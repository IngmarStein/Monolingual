//
//  helper.m
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

#include <stdlib.h>
#import "DeleteHelper.h"

int main( int argc, const char *argv[] )
{
	int i;
	BOOL trash;

	if( argc <= 2 )
		return EXIT_FAILURE;

	trash = FALSE;

	CFMutableSetRef directories = CFSetCreateMutable(kCFAllocatorDefault, argc-1, &kCFTypeSetCallBacks);
	CFMutableArrayRef roots = CFArrayCreateMutable(kCFAllocatorDefault, argc-1, &kCFTypeArrayCallBacks);
	CFMutableArrayRef excludes = CFArrayCreateMutable(kCFAllocatorDefault, argc-1, &kCFTypeArrayCallBacks);
	CFMutableArrayRef files = CFArrayCreateMutable(kCFAllocatorDefault, argc-1, &kCFTypeArrayCallBacks);
	for( i=1; i<argc; ++i ) {
		if( !strcmp( argv[i], "-r" ) ) {
			++i;
			if( i == argc ) {
				printf( "Argument expected for -r\n" );
				return EXIT_FAILURE;
			} else {
				CFStringRef dir = CFStringCreateWithCString(kCFAllocatorDefault, argv[i], kCFStringEncodingUTF8);
				CFArrayAppendValue(roots, dir);
				CFRelease(dir);
			}
		} else if( !strcmp( argv[i], "-x" ) ) {
			++i;
			if( i == argc ) {
				printf( "Argument expected for -x\n" );
				return EXIT_FAILURE;
			} else {
				CFStringRef dir = CFStringCreateWithCString(kCFAllocatorDefault, argv[i], kCFStringEncodingUTF8);
				CFArrayAppendValue(excludes, dir);
				CFRelease(dir);
			}
		} else if( !strcmp( argv[i], "-t" ) ) {
			trash = TRUE;
		} else if( !strcmp( argv[i], "-f" ) ) {
			++i;
			if( i == argc ) {
				printf( "Argument expected for -f\n" );
				return EXIT_FAILURE;
			} else {
				CFStringRef dir = CFStringCreateWithCString(kCFAllocatorDefault, argv[i], kCFStringEncodingUTF8);
				CFArrayAppendValue(files, dir);
				CFRelease(dir);
			}
		} else {
			CFStringRef dir = CFStringCreateWithCString(kCFAllocatorDefault, argv[i], kCFStringEncodingUTF8);
			CFSetAddValue(directories, dir);
			CFRelease(dir);
		}
	}

	DeleteHelper *deleteHelper = [[DeleteHelper alloc] initWithDirectories:directories
																	 roots:roots
																  excludes:excludes
																	 files:files
															   moveToTrash:trash];
	[deleteHelper removeDirectories];
	[deleteHelper release];

	return EXIT_SUCCESS;
}
