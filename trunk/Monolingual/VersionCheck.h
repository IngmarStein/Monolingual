/*
#    VersionCheck.h
#    Copyright (C) 2001, 2002 Joshua Schrier (jschrier@mac.com),
#    2004 Ingmar Stein
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
####################################################################### */


#import <Foundation/Foundation.h>
#import <Appkit/Appkit.h>

@interface VersionCheck : NSObject {

}

+ (void) downloadSelector: (NSWindow *)sheet returnCode: (int)returnCode contextInfo: (id)contextInfo;
+ (void) checkVersionAtURL: (NSString *)url displayText: (NSString *)message downloadURL: (NSString *)goURL;
+ (void) checkInfrequentVersionAtURL: (NSString *)url displayText: (NSString *)message downloadURL: (NSString *)goURL;
+ (void) checkVersionAtURL: (NSString *)url withDayInterval: (int)minDays displayText: (NSString *)message downloadURL: (NSString *)goURL;

@end
