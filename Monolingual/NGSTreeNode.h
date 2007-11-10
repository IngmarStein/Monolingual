//
//  NGSTreeNode.h
//  Monolingual
//
//  Created by Nicholas Shanks on 4/11/07.
//  Copyright 2007 Nicholas Shanks.
//	Released under the MIT license.
//

#import <Cocoa/Cocoa.h>

@interface NGSTreeNode : NSObject
{
	NSMutableArray *_children;

	NSString *_name;
	NSLocale *_locale;
	NSCellStateValue _state;
	unsigned long long _intrinsicSize;
	BOOL _disabled;
}
- (id) initWithName:(NSString *)name;
- (id) initWithLocale:(NSLocale *)locale size:(unsigned long long)size;
- (int) numberOfChildren;
- (id) childAtIndex:(unsigned)index;
- (void) addChild:(NGSTreeNode *)node;
- (void) sortChildrenByKey:(NSString *)key ascending:(BOOL)asc;
- (void) organiseSubLocales;

- (NSString *) name;
- (id) localeIdentifier;
- (NSCellStateValue) state;
- (unsigned long long) size;

- (BOOL) isDisabled;
- (BOOL) isDisabledOrHasDisabledSubLocale;
- (void) setDisabled:(BOOL)flag;
@end
