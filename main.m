//
//  main.m
//  Monolingual
//
//  Created by Ingmar Stein on 08.04.15.
//
//

@import Foundation;
#import "Helper.h"

int main(int argc, const char *argv[])
{
	@autoreleasepool {

		Helper *helper = [[Helper alloc] init];

		if (argc == 2 && !strcmp(argv[1], "--uninstall")) {
			[helper uninstall];
			return EXIT_SUCCESS;
		}

		if (argc == 2 && !strcmp(argv[1], "--version")) {
			printf("MonolingualHelper version %s\n", [[helper version] UTF8String]);
			return EXIT_SUCCESS;
		}

		[helper run];
	}

	return EXIT_SUCCESS;
}
