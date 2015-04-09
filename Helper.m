//
//  Helper.m
//  Monolingual
//
//  Created by Ingmar Stein on 08.04.15.
//
//

#import "Helper.h"

@import Darwin.C.stdlib;
@import Darwin.C.stdio;
@import Darwin.POSIX.fcntl;
@import Darwin.C.string;
@import Darwin.C.limits;
@import Darwin.POSIX.sys.types;
@import Darwin.POSIX.sys.stat;
@import Darwin.POSIX.sys.time;
@import Darwin.POSIX.unistd;
@import Darwin.POSIX.dirent;
@import Darwin.POSIX.pwd;
@import Darwin.POSIX.syslog;
@import CoreFoundation;
@import MachO.fat;
@import MachO.loader;
@import MachO.swap;
@import Darwin.POSIX.sys.mman;
@import XPC;
#include "lipo.h"

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

- (BOOL)isDirectoryBlacklisted:(NSString *)path {
	BOOL result = NO;

	NSString *infoPlistPath = [NSString stringWithFormat:@"%@/Contents/Info.plist", path];
	NSDictionary *infoPlist = [NSDictionary dictionaryWithContentsOfFile:infoPlistPath];
	if (!infoPlist) {
		// frameworks store the Info.plist under a different path
		infoPlistPath = [NSString stringWithFormat:@"%@/Resources/Info.plist", path];
		infoPlist = [NSDictionary dictionaryWithContentsOfFile:infoPlistPath];
	}
	if (infoPlist) {
		NSString *bundleId = infoPlist[@"CFBundleIdentifier"];
		if (bundleId) {
			// check bundle blacklist
			result = [self.bundleBlacklist containsObject:bundleId];
		}
	}

	return result;
}

- (BOOL)isFileBlacklisted:(NSString *)path {
	return [self.fileBlacklist containsObject:path];
}

- (void)addCodeResourcesToBlacklist:(NSString *)path {
	NSString *codeResourcesPath = [NSString stringWithFormat:@"%@/_CodeSignature/CodeResources", path];
	NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:codeResourcesPath];
	if (plist) {
		__block void(^addFileToBlacklist)(NSString *key, NSDictionary *value, BOOL *stop) = ^(NSString *key, NSDictionary *value, BOOL *stop) {
			if (![value[@"optional"] boolValue]) {
				NSString *path = [NSString stringWithFormat:@"%@/%@", path, key];
				[self.fileBlacklist addObject:path];
			}
		};
		[plist[@"files"] enumerateKeysAndObjectsUsingBlock:addFileToBlacklist];
		[plist[@"files2"] enumerateKeysAndObjectsUsingBlock:addFileToBlacklist];
	}
}

- (void)remove:(NSString *)path {
	NSError *error = nil;
	NSURL *url = [NSURL fileURLWithPath:path];
	if (self.trash) {
		NSURL *dstURL = nil;

		// try to move the file to the user's trash
		BOOL success = NO;
		seteuid(self.uid);
		success = [self.fileManager trashItemAtURL:url resultingItemURL:nil error:&error];
		seteuid(0);
		if (!success) {
			// move the file to root's trash
			success = [self.fileManager trashItemAtURL:url resultingItemURL:nil error:&error];
		}
		if (!success) {
			syslog(LOG_ERR, "Error trashing '%s': %s", url.fileSystemRepresentation, error.description.UTF8String);
		}
	} else {
		if (![self.fileManager removeItemAtURL:url error:&error]) {
			syslog(LOG_ERR, "Error removing '%s': %s", url.fileSystemRepresentation, error.description.UTF8String);
		}
	}
}

- (BOOL)fileManager:(NSFileManager *)fileManager shouldProcessItemAtURL:(NSURL *)URL {
	if (self.dryRun || [self isFileBlacklisted:URL.path]) {
		return NO;
	}

	NSNumber *size = nil;
	if (![URL getResourceValue:&size forKey:NSURLTotalFileAllocatedSizeKey error:nil]) {
		[URL getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
	}

	[self.progress setUserInfoObject:URL.path forKey:@"file"];
	self.progress.completedUnitCount += size.integerValue;

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

static void thin_file(const char *path, HelperContext *context)
{
	size_t size_diff;
	if (!run_lipo(path, &size_diff)) {
		if (size_diff > 0) {
			[context.progress setUserInfoObject:@(path) forKey:@"file"];
			context.progress.completedUnitCount += size_diff;
		}
	}
}

static int thin_has_code_signature(char *addr, size_t size)
{
	uint32_t i;
	size_t   mh_size = 0;
	uint32_t ncmds = 0;
	int      swapped = 0;

	if (size >= sizeof(struct mach_header) && (*(uint32_t *)addr == MH_MAGIC || *(uint32_t *)addr == MH_CIGAM)) {
		struct mach_header *mh = (struct mach_header *)addr;
		if (mh->magic == MH_CIGAM) {
			swapped = 1;
			swap_mach_header(mh, NXHostByteOrder());
		}
		mh_size = sizeof(*mh);
		ncmds = mh->ncmds;
	} else if (size >= sizeof(struct mach_header_64) && (*(uint32_t *)addr == MH_MAGIC_64 || *(uint32_t *)addr == MH_CIGAM_64)) {
		struct mach_header_64 *mh = (struct mach_header_64 *)addr;
		if (mh->magic == MH_CIGAM_64) {
			swapped = 1;
			swap_mach_header_64(mh, NXHostByteOrder());
		}
		mh_size = sizeof(*mh);
		ncmds = mh->ncmds;
	}
	if (mh_size) {
		struct load_command *lc = (struct load_command *)(addr + mh_size);
		for (i=0; i<ncmds; ++i) {
			if (swapped)
				swap_load_command(lc, NXHostByteOrder());
			if (LC_CODE_SIGNATURE == lc->cmd)
				return 1;
			lc = (struct load_command *)((char *)lc + lc->cmdsize);
		}
	}

	return 0;
}

static BOOL has_code_signature(const char *path)
{
	int         fd;
	struct stat stat_buf;
	size_t      size;
	BOOL        found_sig;
	char        *addr;
	uint32_t    i;

	/* Open the input file and map it in */
	if ((fd = open(path, O_RDONLY)) == -1) {
		syslog(LOG_ERR, "can't open input file: %s", path);
		return -1;
	}
	if (fstat(fd, &stat_buf) == -1) {
		close(fd);
		syslog(LOG_ERR, "Can't stat input file: %s", path);
		return -1;
	}
	size = (size_t)stat_buf.st_size;
	fcntl(fd, F_NOCACHE, 1);

	addr = mmap(NULL, size, PROT_READ|PROT_WRITE, MAP_PRIVATE, fd, 0);
	if (MAP_FAILED == addr) {
		syslog(LOG_ERR, "Can't map input file: %s", path);
		close(fd);
		return -1;
	}
	close(fd);

	found_sig = 0;

	/* see if this file is a fat file */
	if ((size_t)size >= sizeof(struct fat_header) &&
#ifdef __BIG_ENDIAN__
		*((uint32_t *)addr) == FAT_MAGIC)
#endif /* __BIG_ENDIAN__ */
#ifdef __LITTLE_ENDIAN__
		*((uint32_t *)addr) == FAT_CIGAM)
#endif /* __LITTLE_ENDIAN__ */
	{
		struct fat_header *fat_header = (struct fat_header *)addr;
#ifdef __LITTLE_ENDIAN__
		swap_fat_header(fat_header, NX_LittleEndian);
#endif /* __LITTLE_ENDIAN__ */
		struct fat_arch *fat_arches = (struct fat_arch *)(addr + sizeof(struct fat_header));
#ifdef __LITTLE_ENDIAN__
		swap_fat_arch(fat_arches, fat_header->nfat_arch, NX_LittleEndian);
#endif /* __LITTLE_ENDIAN__ */
		for (i = 0; i < fat_header->nfat_arch; ++i) {
			if (thin_has_code_signature(addr + fat_arches[i].offset, fat_arches[i].size)) {
				found_sig = YES;
				break;
			}
		}
	} else if (thin_has_code_signature(addr, size)) {
		found_sig = YES;
	}

	if (munmap(addr, size)) {
		syslog(LOG_ERR, "munmap: %s", strerror(errno));
	}

	return found_sig;
}

static void strip_file(const char *path, HelperContext *context)
{
	struct stat st;

	if (!stat(path, &st)) {
		char const *argv[7];
		int stat_loc;
		pid_t child;
		off_t old_size;

		// do not modify executables with code signatures
		if (has_code_signature(path)) {
			return;
		}

		old_size = st.st_size;
		child = fork();
		switch (child) {
			case -1:
				syslog(LOG_ERR, "fork() failed: %s", strerror(errno));
				return;
			case 0:
				argv[0] = "/usr/bin/strip";
				argv[1] = "-u";
				argv[2] = "-x";
				argv[3] = "-S";
				argv[4] = "-";
				argv[5] = path;
				argv[6] = NULL;
				execv("/usr/bin/strip", (char * const *)argv);
				syslog(LOG_ERR, "execv(\"/usr/bin/strip\") failed");
				break;
		}
		waitpid(child, &stat_loc, 0);
		chmod(path, st.st_mode & 0777);
		if (chown(path, st.st_uid, st.st_gid) >= 0)
			chmod(path, st.st_mode & 07777);
		if (!stat(path, &st)) {
			if (old_size > st.st_size) {
				size_t size_diff = (size_t)(old_size - st.st_size);
				[context.progress setUserInfoObject:@(path) forKey:@"file"];
				context.progress.completedUnitCount += size_diff;
			}
		}
	}
}

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

- (void)processRequest:(NSDictionary *)request reply:(void(^)(NSNumber *))reply {
	HelperContext *context = [[HelperContext alloc] init];

	syslog(LOG_NOTICE, "Received request: %s", [request description].UTF8String);

	// https://developer.apple.com/library/mac/releasenotes/Foundation/RN-Foundation/#10_10NSXPC
	NSProgress *progress = [NSProgress progressWithTotalUnitCount:-1];
	progress.completedUnitCount = 0;
	progress.cancellationHandler = ^{
		syslog(LOG_NOTICE, "Stopping MonolingualHelper");
	};

	context.dryRun = [[request objectForKey:@"dry_run"] boolValue];
	context.doStrip = [[request objectForKey:@"strip"] boolValue];
	context.uid = [[request objectForKey:@"uid"] integerValue];
	context.trash = [[request objectForKey:@"trash"] boolValue];

	context.excludes = [request objectForKey:@"excludes"];

	NSArray *blacklist = [request objectForKey:@"blacklist"];
	context.bundleBlacklist = [NSSet setWithArray:blacklist];

	NSArray *dirs = [request objectForKey:@"directories"];
	context.directories = [NSSet setWithArray:dirs];

	if (context.doStrip) {
		// check if /usr/bin/strip is present
		struct stat st;
		if (stat("/usr/bin/strip", &st)) {
			context.doStrip = NO;
		}
	}

	// delete regular files
	NSArray *files = [request objectForKey:@"files"];
	for (NSString *file in files) {
		if (context.progress.cancelled) {
			break;
		}
		[context remove:file];
	}

	NSArray *roots = [request objectForKey:@"includes"];

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
	NSArray *thin = [request objectForKey:@"thin"];
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

	if ([context isExcluded:path] || [context isDirectoryBlacklisted:path]) {
		return;
	}

	NSURL *pathURL = [NSURL fileURLWithPath:path isDirectory:YES];
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

			if ([context isExcluded:thePath] || [context isDirectoryBlacklisted:thePath]) {
				[dirEnumerator skipDescendents];
				continue;
			}

			[context addCodeResourcesToBlacklist:thePath];

			NSString *lastComponent = [theURL lastPathComponent];
			if (lastComponent) {
				if ([context.directories containsObject:lastComponent]) {
					[context remove:thePath];
					[dirEnumerator skipDescendents];
				}
			}
		}
	}
}

- (void)thin:(NSString *)path context:(HelperContext *)context {
	struct stat st;

	if (context.progress.cancelled) {
		return;
	}

	if ([path isEqualToString:@"/dev"]) {
		return;
	}

	if ([context isExcluded:path] || [context isDirectoryBlacklisted:path]) {
		return;
	}

	NSURL *pathURL = [NSURL fileURLWithPath:path isDirectory:YES];
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
			if ([context isDirectoryBlacklisted:thePath]) {
				[dirEnumerator skipDescendents];
				continue;
			}
			[context addCodeResourcesToBlacklist:thePath];
		} else if (isExecutable && isRegularFile) {
			if (![context isFileBlacklisted:thePath]) {
				const char *fsPath = theURL.fileSystemRepresentation;

				int fd = open(fsPath, O_RDONLY, 0);
				if (fd >= 0) {
					unsigned int magic;
					ssize_t num;
					fcntl(fd, F_NOCACHE, 1);
					num = read(fd, &magic, sizeof(magic));
					close(fd);

					if (num == sizeof(magic)) {
						if (magic == FAT_MAGIC || magic == FAT_CIGAM)
							thin_file(fsPath, context);
						if (context.doStrip && (magic == FAT_MAGIC || magic == FAT_CIGAM || magic == MH_MAGIC || magic == MH_CIGAM || magic == MH_MAGIC_64 || magic == MH_CIGAM_64))
							strip_file(fsPath, context);
					}
				}
			}
		}
	}
}



@end
