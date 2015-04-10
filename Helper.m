//
//  Helper.m
//  Monolingual
//
//  Created by Ingmar Stein on 08.04.15.
//
//

#import "Helper.h"

@import Foundation;
@import XPC;
@import Darwin.POSIX.syslog;
@import MachO.fat;
@import MachO.loader;
#import "lipo.h"

@interface HelperContext : NSObject <NSFileManagerDelegate>

@property(nonatomic, assign) BOOL dryRun;
@property(nonatomic, assign) BOOL doStrip;
@property(nonatomic, assign) BOOL trash;
@property(nonatomic, assign) uid_t uid;
@property(nonatomic, strong) NSProgress *progress;
@property(nonatomic, strong) NSSet *directories;
@property(nonatomic, strong) NSArray *excludes;
@property(nonatomic, strong) NSSet *bundleBlacklist;
@property(nonatomic, strong) NSMutableSet *fileBlacklist;
@property(nonatomic, strong) NSFileManager *fileManager;

@end

@implementation HelperContext

- (instancetype)init {
	self = [super init];
	if (self) {
		_fileBlacklist = [NSMutableSet set];
		_fileManager = [[NSFileManager alloc] init];
		_fileManager.delegate = self;
	}
	return self;
}

- (BOOL)isExcluded:(NSString *)path {
	BOOL exclusion = NO;

	for (NSString *exclude in self.excludes) {
		if ([path hasPrefix:exclude]) {
			exclusion = YES;
			break;
		}
	}

	return exclusion;
}

- (BOOL)isDirectoryBlacklisted:(NSURL *)path {
	BOOL result = NO;

	NSString *bundleID = [NSBundle bundleWithURL:path].bundleIdentifier;
	if (bundleID) {
		// check bundle blacklist
		result = [self.bundleBlacklist containsObject:bundleID];
	}

	return result;
}

- (BOOL)isFileBlacklisted:(NSURL *)url {
	return [self.fileBlacklist containsObject:url];
}

- (void)addCodeResourcesToBlacklist:(NSURL *)url {
	NSString *codeResourcesPath = [NSString stringWithFormat:@"%@/_CodeSignature/CodeResources", url.path];
	NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:codeResourcesPath];
	if (plist) {
		__block void(^addFileToBlacklist)(NSString *key, NSDictionary *value, BOOL *stop) = ^(NSString *key, NSDictionary *value, BOOL *stop) {
			if (![value[@"optional"] boolValue]) {
				[self.fileBlacklist addObject:[url URLByAppendingPathComponent:key]];
			}
		};
		[plist[@"files"] enumerateKeysAndObjectsUsingBlock:addFileToBlacklist];
		[plist[@"files2"] enumerateKeysAndObjectsUsingBlock:addFileToBlacklist];
	}
}

- (void)reportProgress:(NSURL *)url size:(NSInteger)size {
	NSNumber *count = self.progress.userInfo[NSProgressFileCompletedCountKey];
	[self.progress setUserInfoObject:@(count.integerValue + 1) forKey:NSProgressFileCompletedCountKey];
	[self.progress setUserInfoObject:url forKey:NSProgressFileURLKey];
	self.progress.completedUnitCount += size;
}

- (void)remove:(NSURL *)url {
	NSError *error = nil;
	if (self.trash) {
		NSURL *dstURL = nil;

		// try to move the file to the user's trash
		BOOL success = NO;
		seteuid(self.uid);
		success = [self.fileManager trashItemAtURL:url resultingItemURL:&dstURL error:&error];
		seteuid(0);
		if (!success) {
			// move the file to root's trash
			success = [self.fileManager trashItemAtURL:url resultingItemURL:&dstURL error:&error];
		}
		if (success) {
			// trashItemAtURL does not call any delegate methods (radar 20481813)
			NSDirectoryEnumerator *dirEnumerator = [self.fileManager enumeratorAtURL:dstURL
															 includingPropertiesForKeys:@[NSURLTotalFileAllocatedSizeKey, NSURLFileAllocatedSizeKey]
																				options:(NSDirectoryEnumerationOptions)0
																		   errorHandler:nil];
			for (NSURL *theURL in dirEnumerator) {
				NSNumber *size = nil;
				if (![theURL getResourceValue:&size forKey:NSURLTotalFileAllocatedSizeKey error:nil]) {
					[theURL getResourceValue:&size forKey:NSURLFileAllocatedSizeKey error:nil];
				}
				if (size) {
					[self reportProgress:theURL size:size.integerValue];
				}
			}
		} else {
			syslog(LOG_ERR, "Error trashing '%s': %s", url.fileSystemRepresentation, error.description.UTF8String);
		}
	} else {
		if (![self.fileManager removeItemAtURL:url error:&error]) {
			syslog(LOG_ERR, "Error removing '%s': %s", url.fileSystemRepresentation, error.description.UTF8String);
		}
	}
}

- (BOOL)fileManager:(NSFileManager *)fileManager shouldProcessItemAtURL:(NSURL *)URL {
	if (self.dryRun || [self isFileBlacklisted:URL]) {
		return NO;
	}

	NSNumber *size = nil;
	if (![URL getResourceValue:&size forKey:NSURLTotalFileAllocatedSizeKey error:nil]) {
		[URL getResourceValue:&size forKey:NSURLFileAllocatedSizeKey error:nil];
	}

	[self reportProgress:URL size:size.integerValue];

	syslog(LOG_WARNING, "processing '%s' size=%lld", URL.fileSystemRepresentation, (long long int)size.integerValue);

	return YES;
}

#pragma mark - NSFileManagerDelegate

- (BOOL)fileManager:(NSFileManager *)fileManager shouldRemoveItemAtURL:(NSURL *)URL {
	return [self fileManager:fileManager shouldProcessItemAtURL:URL];
}

- (BOOL)fileManager:(NSFileManager *)fileManager shouldMoveItemAtURL:(NSURL *)srcURL toURL:(NSURL *)dstURL {
	return [self fileManager:fileManager shouldProcessItemAtURL:srcURL];
}

@end

@interface Helper () <NSXPCListenerDelegate>

@property (atomic, strong) NSXPCListener *listener;

@end

@implementation Helper

- (id)init {
	self = [super init];
	if (self) {
		_listener = [[NSXPCListener alloc] initWithMachServiceName:@"net.sourceforge.MonolingualHelper"];
		_listener.delegate = self;
	}
	return self;
}

- (void)run
{
	syslog(LOG_NOTICE, "MonolingualHelper started");

	[self.listener resume];
	[[NSRunLoop currentRunLoop] run];
}

- (void)connectWithEndpointReply:(void(^)(NSXPCListenerEndpoint * endpoint))reply {
	reply([self.listener endpoint]);
}

- (void)getVersionWithReply:(void(^)(NSString * version))reply {
	reply([self version]);
}

// see https://devforums.apple.com/message/1004420#1004420
- (void)uninstall {
	execl("/bin/launchctl", "unload", "-wF", "/Library/LaunchDaemons/net.sourceforge.MonolingualHelper.plist", NULL);
	unlink("/Library/PrivilegedHelperTools/net.sourceforge.MonolingualHelper");
	unlink("/Library/LaunchDaemons/net.sourceforge.MonolingualHelper.plist");
//	execl("/bin/launchctl", "remove", "net.sourceforge.MonolingualHelper", NULL);
}

- (void)exitWithCode:(NSNumber *)exitCode __attribute__((noreturn)) {
	syslog(LOG_NOTICE, "exiting with exit status %d", [exitCode intValue]);
	exit(exitCode.integerValue);
}

- (NSString *)version {
	return [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
}

- (void)processRequest:(HelperRequest *)request reply:(void(^)(NSNumber *))reply {
	HelperContext *context = [[HelperContext alloc] init];

	syslog(LOG_NOTICE, "Received request: %s", request.description.UTF8String);

	// https://developer.apple.com/library/mac/releasenotes/Foundation/RN-Foundation/#10_10NSXPC
	context.progress = [NSProgress currentProgress];
	context.progress.completedUnitCount = 0;
	context.progress.cancellationHandler = ^{
		syslog(LOG_NOTICE, "Stopping MonolingualHelper");
	};
	context.dryRun = request.dryRun;
	context.doStrip = request.doStrip;
	context.uid = request.uid;
	context.trash = request.trash;
	context.excludes = request.excludes;
	context.bundleBlacklist = request.bundleBlacklist;
	context.directories = request.directories;

	if (context.doStrip) {
		// check if /usr/bin/strip is present
		if (![context.fileManager fileExistsAtPath:@"/usr/bin/strip"]) {
			context.doStrip = NO;
		}
	}

	// delete regular files
	NSArray *files = request.files;
	for (NSString *file in files) {
		if (context.progress.cancelled) {
			break;
		}
		[context remove:[NSURL fileURLWithPath:file]];
	}

	NSArray *roots = request.includes;

	// recursively delete directories
	if ([context.directories count]) {
		for (NSString *root in roots) {
			if (context.progress.cancelled) {
				break;
			}
			[self processDirectory:root context:context];
		}
	}

	// thin fat binaries
	NSArray *thin = request.thin;
	NSUInteger numArchs = thin.count;
	if (numArchs) {
		const char **archs = malloc(numArchs * sizeof(char *));
		for (NSUInteger i=0; i<numArchs; ++i) {
			archs[i] = [thin[i] UTF8String];
		}

		if (setup_lipo(archs, numArchs)) {
			for (NSString *root in roots) {
				if (context.progress.cancelled) {
					break;
				}
				[self thin:root context:context];
			}
			finish_lipo();
		}

		free(archs);
	}

	reply(@(context.progress.cancelled));
}

#pragma mark - NSXPCListenerDelegate

- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)newConnection {
	assert(listener == self.listener);
	assert(newConnection != nil);

	newConnection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(HelperProtocol)];
	newConnection.exportedObject = self;
	[newConnection resume];

	return YES;
}

#pragma mark -

- (void)processDirectory:(NSString *)path context:(HelperContext *)context {
	if (context.progress.cancelled) {
		return;
	}

	if ([path isEqualToString:@"/dev"]) {
		return;
	}

	NSURL *pathURL = [NSURL fileURLWithPath:path isDirectory:YES];

	if ([context isExcluded:path] || [context isDirectoryBlacklisted:pathURL]) {
		return;
	}

	NSDirectoryEnumerator *dirEnumerator = [context.fileManager enumeratorAtURL:pathURL
											   includingPropertiesForKeys:@[NSURLIsDirectoryKey]
																  options:(NSDirectoryEnumerationOptions)0
															 errorHandler:nil];

	for (NSURL *theURL in dirEnumerator) {
		if (context.progress.cancelled) {
			return;
		}

		NSNumber *isDirectory;
		[theURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:NULL];

		if (isDirectory.boolValue) {
			NSString *thePath = theURL.path;

			if ([context isExcluded:thePath] || [context isDirectoryBlacklisted:theURL]) {
				[dirEnumerator skipDescendents];
				continue;
			}

			[context addCodeResourcesToBlacklist:theURL];

			NSString *lastComponent = [theURL lastPathComponent];
			if (lastComponent) {
				if ([context.directories containsObject:lastComponent]) {
					[context remove:theURL];
					[dirEnumerator skipDescendents];
				}
			}
		}
	}
}

- (void)thinFile:(NSURL *)url context:(HelperContext *)context {
	size_t size_diff;
	if (!run_lipo(url.fileSystemRepresentation, &size_diff)) {
		if (size_diff > 0) {
			[context reportProgress:url size:size_diff];
		}
	}
}

- (void)thin:(NSString *)path context:(HelperContext *)context {
	if (context.progress.cancelled) {
		return;
	}

	if ([path isEqualToString:@"/dev"]) {
		return;
	}

	NSURL *pathURL = [NSURL fileURLWithPath:path isDirectory:YES];

	if ([context isExcluded:path] || [context isDirectoryBlacklisted:pathURL]) {
		return;
	}

	NSDirectoryEnumerator *dirEnumerator = [context.fileManager enumeratorAtURL:pathURL
											 includingPropertiesForKeys:@[NSURLIsDirectoryKey, NSURLIsRegularFileKey, NSURLIsExecutableKey]
																options:(NSDirectoryEnumerationOptions)0
														   errorHandler:nil];

	for (NSURL *theURL in dirEnumerator) {
		if (context.progress.cancelled) {
			return;
		}

		NSNumber *isDirectory;
		NSNumber *isRegularFile;
		NSNumber *isExecutable;

		[theURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:NULL];
		[theURL getResourceValue:&isRegularFile forKey:NSURLIsRegularFileKey error:NULL];
		[theURL getResourceValue:&isExecutable forKey:NSURLIsExecutableKey error:NULL];

		NSString *thePath = theURL.path;
		if (isDirectory.boolValue) {
			if ([context isDirectoryBlacklisted:theURL]) {
				[dirEnumerator skipDescendents];
				continue;
			}
			[context addCodeResourcesToBlacklist:theURL];
		} else if (isExecutable && isRegularFile) {
			if (![context isFileBlacklisted:theURL]) {
				NSError *error = nil;
				NSData *data = [NSData dataWithContentsOfURL:theURL options:(NSDataReadingOptions)(NSDataReadingMappedAlways|NSDataReadingUncached) error:&error];
				unsigned int magic;
				if (data.length >= sizeof(magic)) {
					[data getBytes:&magic length:sizeof(magic)];

					if (magic == FAT_MAGIC || magic == FAT_CIGAM)
						[self thinFile:theURL context:context];
					if (context.doStrip && (magic == FAT_MAGIC || magic == FAT_CIGAM || magic == MH_MAGIC || magic == MH_CIGAM || magic == MH_MAGIC_64 || magic == MH_CIGAM_64))
						[self stripFile:theURL context:context];
				}
			}
		}
	}
}

- (BOOL)hasCodeSignature:(NSURL *)url {
	SecStaticCodeRef codeRef;
	OSStatus result;

	result = SecStaticCodeCreateWithPath((__bridge CFURLRef)url, kSecCSDefaultFlags, &codeRef);
	if (result != noErr) {
		return NO;
	}

	SecRequirementRef requirement;
	result = SecCodeCopyDesignatedRequirement(codeRef, kSecCSDefaultFlags, &requirement);
	return result == noErr;
}

- (void)stripFile:(NSURL *)url context:(HelperContext *)context {
	const char *path = url.fileSystemRepresentation;

	NSError *error = nil;
	NSDictionary *attributes = [context.fileManager attributesOfItemAtPath:url.path error:&error];
	if (attributes) {
		// do not modify executables with code signatures
		if ([self hasCodeSignature:url]) {
			return;
		}

		unsigned long long oldSize = attributes.fileSize;

		NSTask *task = [NSTask launchedTaskWithLaunchPath:@"/usr/bin/strip" arguments:@[@"-u", @"-x", @"-S", @"-", url.path]];
		[task waitUntilExit];

		if (task.terminationStatus != EXIT_SUCCESS) {
			syslog(LOG_ERR, "/usr/bin/strip failed with exit status %d", task.terminationStatus);
		}

		NSDictionary *newAttributes = @{ NSFileOwnerAccountID : attributes[NSFileOwnerAccountID],
										 NSFileGroupOwnerAccountID : attributes[NSFileGroupOwnerAccountID],
										 NSFilePosixPermissions : attributes[NSFilePosixPermissions]
										 };

		if (![context.fileManager setAttributes:newAttributes ofItemAtPath:url.path error:&error]) {
			syslog(LOG_ERR, "Failed to set file attributes for '%s': %s", url.fileSystemRepresentation, error.description.UTF8String);
		}
		attributes = [context.fileManager attributesOfItemAtPath:url.path error:&error];
		if (attributes) {
			unsigned long long newSize = attributes.fileSize;
			if (oldSize > newSize) {
				NSInteger sizeDiff = oldSize - newSize;
				[context reportProgress:[NSURL fileURLWithFileSystemRepresentation:path isDirectory:NO relativeToURL:nil] size:sizeDiff];
			}
		}
	}
}

@end
