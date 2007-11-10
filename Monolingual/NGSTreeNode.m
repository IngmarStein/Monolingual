//
//  NGSTreeNode.m
//  Monolingual
//
//  Created by Nicholas Shanks on 4/11/07.
//  Copyright 2007 Nicholas Shanks.
//	Released under the MIT license.
//

#import "NGSTreeNode.h"

@interface NGSTreeNode (Private)
- (id)initWithName:(NSString *)name locale:(NSLocale *)locale size:(unsigned long long)size;
- (NSLocale *)locale;
@end

@implementation NGSTreeNode

- (id) initWithName:(NSString *)name
{
	return [self initWithName: name locale: nil size: 0];
}

- (id) initWithLocale:(NSLocale *)locale size:(unsigned long long)size
{
	return [self initWithName: nil locale: locale size: size];
}

- (id) initWithName:(NSString *)name locale:(NSLocale *)locale size:(unsigned long long)size
{
	self = [super init];
	if (self) {
		if (name)
			_name   = [name copy];
		if (locale)
			_locale = [locale retain];
		if (!_name && _locale)
			_name = [[[NSLocale currentLocale] displayNameForKey: NSLocaleIdentifier value: [_locale localeIdentifier]] copy];
		_intrinsicSize = size;
		_children = [[NSMutableArray alloc] init];
	}
	return self;
}

- (void) dealloc
{
	[_name release];
	[_locale release];
	[_children release];
	[super dealloc];
}

- (int) numberOfChildren
{
	return (int)[_children count];
}

- (id) childAtIndex:(unsigned)i
{
	return [_children objectAtIndex: i];
}

- (void) addChild:(NGSTreeNode *)node
{
	[_children addObject: node];
}

- (void) sortChildrenByKey:(NSString *)key ascending:(BOOL)asc
{
	NSSortDescriptor *descriptor = [[NSSortDescriptor alloc] initWithKey: key ascending: asc];
	[_children sortUsingDescriptors: [NSArray arrayWithObject: descriptor]];
	[descriptor release];
}

- (NSString *) name
{
	return _name;
}

- (NSCellStateValue) state
{
	return _state;
}

- (unsigned long long) size
{
	unsigned long long size = _intrinsicSize;
	NSUInteger i;
	NSUInteger count = [_children count];

	for (i = 0U; i < count; i++)
		size += [(NGSTreeNode *)[_children objectAtIndex: i] size];
	return size;
}

- (id) localeIdentifier
{
	if (_locale)
	     return [_locale localeIdentifier];
	else if ([NSNumber respondsToSelector:@selector(numberWithUnsignedInteger:)])
		return [NSNumber numberWithUnsignedInteger: [_children count]];
	else
		return [NSNumber numberWithUnsignedInt: (unsigned)[_children count]];
}

- (NSLocale *)locale
{
	return _locale;
}

- (void)organiseSubLocales
{
	// this method puts pt_PT inside of pt, and so on
	//	it relies on the _children array being sorted by localeIdentifier
	NGSTreeNode *currentNode, *currentLanguageNode = nil;
	NSUInteger i;
	NSUInteger count = [_children count];
	NSMutableArray *removals = [NSMutableArray arrayWithCapacity: count];
	NSMutableArray *additions = [NSMutableArray arrayWithCapacity: count];
	for (i = 0U; i < count; i++) {
		currentNode = [_children objectAtIndex: i];
		if (currentLanguageNode && [[[currentLanguageNode locale] objectForKey: NSLocaleLanguageCode] isEqual: [[currentNode locale] objectForKey: NSLocaleLanguageCode]]) {
			if (![[[currentLanguageNode locale] objectForKey: NSLocaleLanguageCode] isEqual: [[currentLanguageNode locale] objectForKey: NSLocaleIdentifier]]) {
				NSLocale *wrapperLocale = [[NSLocale alloc] initWithLocaleIdentifier: [[currentLanguageNode locale] objectForKey: NSLocaleLanguageCode]];
				NGSTreeNode *wrapperNode = [[NGSTreeNode alloc] initWithName: nil locale: wrapperLocale size: 0];
				[wrapperNode addChild: currentLanguageNode];
				[removals addObject: currentLanguageNode];
				[additions addObject: wrapperNode];		// can't modify _children whilst iterating it!
				currentLanguageNode = wrapperNode;
				[wrapperLocale release];
			}
			[currentLanguageNode addChild: currentNode];
			[removals addObject: currentNode];		// can't modify _children whilst iterating it!
		} else
			currentLanguageNode = currentNode;
	}
	[_children removeObjectsInArray: removals];
	[_children addObjectsFromArray: additions];
	[self sortChildrenByKey: @"localeIdentifier" ascending: YES];
}

- (BOOL) isDisabled
{
	return _disabled;
}

- (BOOL) isDisabledOrHasDisabledSubLocale
{
	if (_disabled)
		return YES;
	if (!_locale)
		return NO;
	
	NSUInteger i;
	NSUInteger count = [_children count];
	for (i = 0U; i < count; i++) {
		NGSTreeNode *node = [_children objectAtIndex: i];
		if ([node isDisabled])
			return YES;
	}
	return NO;
}

- (void) setDisabled:(BOOL)flag
{
	_disabled = flag;
}

@end
