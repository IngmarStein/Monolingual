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
		_dryRun = [coder decodeBoolForKey:@"dryRun"];
		_doStrip = [coder decodeBoolForKey:@"doStrip"];
		_uid = [coder decodeIntegerForKey:@"uid"];
		_trash = [coder decodeBoolForKey:@"trash"];
		_includes = [coder decodeObjectOfClass:[NSArray class] forKey:@"includes"];
		_excludes = [coder decodeObjectOfClass:[NSArray class] forKey:@"excludes"];
		_bundleBlacklist = [coder decodeObjectOfClass:[NSSet class] forKey:@"bundleBlacklist"];
		_directories = [coder decodeObjectOfClass:[NSSet class] forKey:@"directories"];
		_files = [coder decodeObjectOfClass:[NSArray class] forKey:@"files"];
		_thin = [coder decodeObjectOfClass:[NSArray class] forKey:@"thin"];
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
