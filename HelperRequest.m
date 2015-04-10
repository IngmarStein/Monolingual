//
//  HelperRequest.m
//  Monolingual
//
//  Created by Ingmar Stein on 09.04.15.
//
//

#import "HelperRequest.h"

@implementation HelperRequest

- (instancetype)initWithCoder:(NSCoder *)coder
{
	self = [super init];
	if (self) {
		NSSet *stringArray = [NSSet setWithObjects:[NSString class], [NSArray class], nil];
		NSSet *stringSet = [NSSet setWithObjects:[NSString class], [NSSet class], nil];

		_dryRun = [coder decodeBoolForKey:@"dryRun"];
		_doStrip = [coder decodeBoolForKey:@"doStrip"];
		_uid = [coder decodeIntegerForKey:@"uid"];
		_trash = [coder decodeBoolForKey:@"trash"];
		_includes = [coder decodeObjectOfClasses:stringArray forKey:@"includes"];
		_excludes = [coder decodeObjectOfClasses:stringArray forKey:@"excludes"];
		_bundleBlacklist = [coder decodeObjectOfClasses:stringSet forKey:@"bundleBlacklist"];
		_directories = [coder decodeObjectOfClasses:stringSet forKey:@"directories"];
		_files = [coder decodeObjectOfClasses:stringArray forKey:@"files"];
		_thin = [coder decodeObjectOfClasses:stringArray forKey:@"thin"];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeBool:self.dryRun forKey:@"dryRun"];
	[coder encodeBool:self.doStrip forKey:@"doStrip"];
	[coder encodeInteger:self.uid forKey:@"uid"];
	[coder encodeBool:self.trash forKey:@"trash"];
	[coder encodeObject:self.includes forKey:@"includes"];
	[coder encodeObject:self.excludes forKey:@"excludes"];
	[coder encodeObject:self.bundleBlacklist forKey:@"bundleBlacklist"];
	[coder encodeObject:self.directories forKey:@"directories"];
	[coder encodeObject:self.files forKey:@"files"];
	[coder encodeObject:self.thin forKey:@"thin"];
}

+ (BOOL)supportsSecureCoding {
	return YES;
}

@end
