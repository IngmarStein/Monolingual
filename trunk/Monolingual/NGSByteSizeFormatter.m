//
//  NGSByteSizeFormatter.m
//  ResKnife & Monolingual
//
//  Copyright 2000, 2001, 2007 Nicholas Shanks.
//	Released under the MIT license.
//

#import "NGSByteSizeFormatter.h"

@implementation NGSByteSizeFormatter

- (void) awakeFromNib
{
	[self setFormat: @"#,##0.0"];
	[self setLocalizesFormat: YES];
	[self setAllowsFloats: YES];
}

- (NSString *) stringForObjectValue:(id)obj
{
	float value = [obj floatValue];
	int power = 0;

	while (value >= 1024 && power <= 30) {
		power += 10;	// 10 == KB, 20 == MB, 30+ == GB
		value /= 1024.0f;
	}

	switch (power) {
		case 0:  return [NSString stringWithFormat: NSLocalizedString(@"NGSByteSizeBytes",     nil), value];
		case 10: return [NSString stringWithFormat: NSLocalizedString(@"NGSByteSizeKilobytes", nil), value];
		case 20: return [NSString stringWithFormat: NSLocalizedString(@"NGSByteSizeMegabytes", nil), value];
		default: return [NSString stringWithFormat: NSLocalizedString(@"NGSByteSizeGigabytes", nil), value];
	}
}

@end
