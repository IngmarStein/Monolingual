//
//  helper.m
//  Monolingual
//
//  Created by Ingmar Stein on Tue Mar 23 2004.
//  Copyright (c) 2004-2014 Ingmar Stein. All rights reserved.
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
#include <stdio.h>
#include <fcntl.h>
#include <string.h>
#include <limits.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <unistd.h>
#include <dirent.h>
#include <pwd.h>
#include <syslog.h>
#include <CoreFoundation/CoreFoundation.h>
#include <mach-o/fat.h>
#include <mach-o/loader.h>
#include <mach-o/swap.h>
#include <sys/mman.h>
#include <xpc/xpc.h>
#include "lipo.h"

typedef struct helper_context_s {
	int should_exit;
	int dry_run;
	int do_strip;
	uid_t uid;
	void (*remove_func)(const char *path, const struct helper_context_s *);
	xpc_connection_t connection;
	CFMutableSetRef directories;
	xpc_object_t excludes;
	CFMutableSetRef bundle_blacklist;
	CFMutableSetRef file_blacklist;
} helper_context_t;

static void thin_file(const char *path, const helper_context_t *context)
{
	size_t size_diff;
	if (!run_lipo(path, &size_diff)) {
		if (size_diff > 0) {
			xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
			xpc_dictionary_set_string(message, "file", path);
			xpc_dictionary_set_uint64(message, "size", size_diff);
			xpc_connection_send_message(context->connection, message);
			xpc_release(message);
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

static int has_code_signature(const char *path)
{
	int         fd;
	struct stat stat_buf;
	size_t      size;
	int         found_sig;
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
				found_sig = 1;
				break;
			}
		}
	} else if (thin_has_code_signature(addr, size))
		found_sig = 1;

	if (munmap(addr, size))
		syslog(LOG_ERR, "munmap: %s", strerror(errno));

	return found_sig;
}

static void strip_file(const char *path, const helper_context_t *context)
{
	struct stat st;

	if (!stat(path, &st)) {
		char const *argv[7];
		int stat_loc;
		pid_t child;
		off_t old_size;

		/* do not modify executables with code signatures */
		if (has_code_signature(path))
			return;

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
				xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
				xpc_dictionary_set_string(message, "file", path);
				xpc_dictionary_set_uint64(message, "size", size_diff);
				xpc_connection_send_message(context->connection, message);
				xpc_release(message);
			}
		}
	}
}

typedef struct {
	const char *path;
	const helper_context_t *helper_context;
} file_blacklist_context_t;

static void add_file_to_blacklist(const void *key, const void *value, void *ctx)
{
	if (CFGetTypeID((CFTypeRef)value) == CFDictionaryGetTypeID())
		if (CFDictionaryGetValue((CFDictionaryRef)value, CFSTR("optional")) == kCFBooleanTrue)
			return;

	file_blacklist_context_t *context = (file_blacklist_context_t *)ctx;
	CFStringRef path = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%s/%@"), context->path, (CFStringRef)key);
	CFSetAddValue(context->helper_context->file_blacklist, path);
	CFRelease(path);
}

static int is_blacklisted(const char *path, const helper_context_t *context)
{
	int result = 0;
	
	// get bundle identifier
	CFStringRef infoPlistPath = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%s/Contents/Info.plist"), path);
	CFURLRef infoPlistURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, infoPlistPath, kCFURLPOSIXPathStyle, false);
	CFRelease(infoPlistPath);
	CFReadStreamRef infoPlistStream = CFReadStreamCreateWithFile(kCFAllocatorDefault, infoPlistURL);
	CFRelease(infoPlistURL);
	if (infoPlistStream) {
		Boolean streamOpened = CFReadStreamOpen(infoPlistStream);
		if (!streamOpened) {
			CFRelease(infoPlistStream);
			// frameworks store the Info.plist under a different path
			infoPlistPath = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%s/Resources/Info.plist"), path);
			infoPlistURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, infoPlistPath, kCFURLPOSIXPathStyle, false);
			CFRelease(infoPlistPath);
			infoPlistStream = CFReadStreamCreateWithFile(kCFAllocatorDefault, infoPlistURL);
			CFRelease(infoPlistURL);
			streamOpened = CFReadStreamOpen(infoPlistStream);
		}
		if (streamOpened) {
			CFPropertyListFormat format;
			CFPropertyListRef plist = CFPropertyListCreateWithStream(kCFAllocatorDefault,
																	 infoPlistStream,
																	 /*streamLength*/ 0,
																	 kCFPropertyListImmutable,
																	 &format,
																	 /*errorString*/ NULL);
			if (plist) {
				CFStringRef bundleId = CFDictionaryGetValue(plist, kCFBundleIdentifierKey);
				if (bundleId) {
					// check bundle blacklist
					result = CFSetContainsValue(context->bundle_blacklist, bundleId);
				}
				CFRelease(plist);
			}
			
			CFReadStreamClose(infoPlistStream);
		}
		
		CFRelease(infoPlistStream);
	}

	// add code resources to file blacklist
	CFStringRef codeResourcesPath = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%s/_CodeSignature/CodeResources"), path);
	CFURLRef codeResourcesURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, codeResourcesPath, kCFURLPOSIXPathStyle, false);
	CFRelease(codeResourcesPath);
	CFReadStreamRef codeResourcesStream = CFReadStreamCreateWithFile(kCFAllocatorDefault, codeResourcesURL);
	CFRelease(codeResourcesURL);
	if (codeResourcesStream) {
		if (CFReadStreamOpen(codeResourcesStream)) {
			CFPropertyListFormat format;
			CFPropertyListRef plist = CFPropertyListCreateWithStream(kCFAllocatorDefault,
																	 codeResourcesStream,
																	 /*streamLength*/ 0,
																	 kCFPropertyListImmutable,
																	 &format,
																	 /*errorString*/ NULL);
			if (plist) {
				CFDictionaryRef files = CFDictionaryGetValue(plist, CFSTR("files"));
				if (files) {
					file_blacklist_context_t blacklist_context;
					blacklist_context.path = path;
					blacklist_context.helper_context = context;
					CFDictionaryApplyFunction(files, add_file_to_blacklist, (void *)&blacklist_context);
				}

				CFDictionaryRef files2 = CFDictionaryGetValue(plist, CFSTR("files2"));
				if (files2) {
					file_blacklist_context_t blacklist_context;
					blacklist_context.path = path;
					blacklist_context.helper_context = context;
					CFDictionaryApplyFunction(files2, add_file_to_blacklist, (void *)&blacklist_context);
				}
				CFRelease(plist);
			}
			CFReadStreamClose(codeResourcesStream);
		}
		
		CFRelease(codeResourcesStream);
	}
	
	return result;
}

static void delete_recursively(const char *path, const helper_context_t *context)
{
	struct stat st;
	int result;

	if (context->should_exit)
		return;

	if (lstat(path, &st) == -1)
		return;

	CFStringRef pathString = CFStringCreateWithFileSystemRepresentation(kCFAllocatorDefault, path);
	Boolean blacklisted = CFSetContainsValue(context->file_blacklist, pathString);
	CFRelease(pathString);

	if (blacklisted)
		return;
	
	switch (st.st_mode & S_IFMT) {
		case S_IFDIR: {
			DIR *dir;
			struct dirent *ent;
			dir = opendir(path);
			if (dir) {
				size_t pathlen = strlen(path);
				while ((ent = readdir(dir))) {
					if (strcmp(ent->d_name, ".") && strcmp(ent->d_name, "..")) {
						char subdir[PATH_MAX];
						strncpy(subdir, path, sizeof(subdir));
						if (path[pathlen-1] != '/' && pathlen<sizeof(subdir)-1) {
							subdir[pathlen] = '/';
							subdir[pathlen+1] = '\0';
						}
						strncat(subdir, ent->d_name, sizeof(subdir) - strlen(subdir) - 1);
						delete_recursively(subdir, context);
					}
				}
				closedir(dir);
			}
			if (context->dry_run)
				result = 0;
			else
				result = rmdir(path);
			break;
		}
		case S_IFREG:
		case S_IFLNK:
			if (context->dry_run)
				result = 0;
			else
				result = unlink(path);
			break;
		default:
			return;
	}
	if (!result) {
		xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
		xpc_dictionary_set_string(message, "file", path);
		xpc_dictionary_set_uint64(message, "size", st.st_size);
		xpc_connection_send_message(context->connection, message);
		xpc_release(message);
	}
}

static void trash_file(const char *path, const helper_context_t *context)
{
	char resolved_path[PATH_MAX];

	if (context->dry_run)
		return;

	if (context->should_exit)
		return;

	CFStringRef pathString = CFStringCreateWithFileSystemRepresentation(kCFAllocatorDefault, path);
	Boolean blacklisted = CFSetContainsValue(context->file_blacklist, pathString);
	CFRelease(pathString);

	if (blacklisted)
		return;

	if (realpath(path, resolved_path)) {
		char userTrash[PATH_MAX];
		int validTrash = 0;
		if (!strncmp(path, "/Volumes/", 9)) {
			strncpy(userTrash, path, sizeof(userTrash));
			char *sep_pos = strchr(&userTrash[9], '/');
			if (sep_pos) {
				sep_pos[1] = '\0';
				strncat(userTrash, ".Trashes", sizeof(userTrash) - strlen(userTrash) - 1);
				mkdir(userTrash, 0700);
				snprintf(sep_pos+9, sizeof(userTrash)-(sep_pos+9-userTrash), "/%d", context->uid);
				validTrash = 1;
			}
		} else {
			struct passwd *pwd = getpwuid(context->uid);
			if (pwd) {
				strncpy(userTrash, pwd->pw_dir, sizeof(userTrash));
				strncat(userTrash, "/.Trash", sizeof(userTrash) - strlen(userTrash) - 1);
				validTrash = 1;
			}
		}
		if (validTrash) {
			char destination[PATH_MAX];
			mkdir(userTrash, 0700);
			char *filename = strrchr(path, '/');
			if (filename) {
				filename = strdup(filename);
				char *extension = strrchr(filename, '.');
				strncpy(destination, userTrash, sizeof(destination));
				strncat(destination, filename, sizeof(destination) - strlen(destination) - 1);
				while (1) {
					struct stat sb;
					struct tm *lt;
					time_t now;

					if (stat(destination, &sb)) {
						if (rename(path, destination)) {
							syslog(LOG_WARNING, "Failed to rename %s to %s: %m", path, destination);
						} else {
							xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
							xpc_dictionary_set_string(message, "file", path);
							xpc_dictionary_set_uint64(message, "size", 0);
							xpc_connection_send_message(context->connection, message);
							xpc_release(message);
						}
						break;
					}
					if (extension)
						*extension = '\0';
					now = time(NULL);
					lt = localtime(&now);
					snprintf(destination, sizeof(destination), "%s%s %d-%d-%d.%s", userTrash, filename, lt->tm_hour, lt->tm_min, lt->tm_sec, extension+1);
				}
				free(filename);
			}
		}
	}
}

static int is_excluded(const char *path, const helper_context_t *context) {
	int exclusion = 0;

	size_t num_excludes = context->excludes ? xpc_array_get_count(context->excludes) : 0;
	for (size_t i=0; i<num_excludes; ++i) {
		const char *ex = xpc_array_get_string(context->excludes, i);
		if (!strncmp(path, ex, strlen(ex))) {
			exclusion = 1;
			break;
		}
	}
	
	return exclusion;
}

static void process_directory(const char *path, int leaf, const helper_context_t *context)
{
	DIR  *dir;
	char *last_component;

	if (context->should_exit)
		return;

	if (!strcmp(path, "/dev"))
		return;

	if (is_excluded(path, context) || is_blacklisted(path, context))
		return;

	last_component = strrchr(path, '/');
	if (last_component) {
		++last_component;
		CFStringRef directory = CFStringCreateWithFileSystemRepresentation(kCFAllocatorDefault, last_component);
		if (CFSetContainsValue(context->directories, directory)) {
			CFRelease(directory);
			context->remove_func(path, context);
			return;
		}
		CFRelease(directory);
	}
	
	// don't recurse into symlinks (see tracker issue 31011269)
	if (leaf)
		return;

	dir = opendir(path);
	if (dir) {
		struct dirent *ent;
		size_t pathlen = strlen(path);
		while ((ent = readdir(dir))) {
			if (strcmp(ent->d_name, ".") && strcmp(ent->d_name, "..")) {
				struct stat st;
				char subdir[PATH_MAX];
				strncpy(subdir, path, sizeof(subdir));
				if (path[pathlen-1] != '/' && pathlen<sizeof(subdir)-1) {
					subdir[pathlen] = '/';
					subdir[pathlen+1] = '\0';
				}
				strncat(subdir, ent->d_name, sizeof(subdir) - strlen(subdir) - 1);

				if (lstat(subdir, &st) != -1) {
					// process symlinks, too (see tracker issue 3035669)
					mode_t mode = (st.st_mode & S_IFMT);
					if (mode == S_IFDIR || mode == S_IFLNK)
						process_directory(subdir, mode == S_IFLNK, context);
				}
			}
		}
		closedir(dir);
	}
}

static void thin_recursively(const char *path, const helper_context_t *context)
{
	struct stat st;

	if (context->should_exit)
		return;

	if (!strcmp(path, "/dev"))
		return;

	if (is_excluded(path, context))
		return;

	if (lstat(path, &st) == -1)
		return;

	switch (st.st_mode & S_IFMT) {
		case S_IFDIR: {
			DIR *dir;
			if (!is_blacklisted(path, context)) {
				dir = opendir(path);
				if (dir) {
					struct dirent *ent;
					size_t pathlen = strlen(path);
					while ((ent = readdir(dir))) {
						if (strcmp(ent->d_name, ".") && strcmp(ent->d_name, "..")) {
							char subdir[PATH_MAX];
							strncpy(subdir, path, sizeof(subdir));
							if (path[pathlen-1] != '/' && pathlen<sizeof(subdir)-1) {
								subdir[pathlen] = '/';
								subdir[pathlen+1] = '\0';
							}
							strncat(subdir, ent->d_name, sizeof(subdir) - strlen(subdir) - 1);
							thin_recursively(subdir, context);
						}
					}
					closedir(dir);
				}
			}
			break;
		}
		case S_IFREG:
			if (st.st_mode & (S_IXUSR|S_IXGRP|S_IXOTH)) {
				// check file blacklist
				CFStringRef pathString = CFStringCreateWithFileSystemRepresentation(kCFAllocatorDefault, path);
				if (!CFSetContainsValue(context->file_blacklist, pathString)) {
					int fd = open(path, O_RDONLY, 0);
					if (fd >= 0) {
						unsigned int magic;
						ssize_t num;
						fcntl(fd, F_NOCACHE, 1);
						num = read(fd, &magic, sizeof(magic));
						close(fd);

						if (num == sizeof(magic)) {
							if (magic == FAT_MAGIC || magic == FAT_CIGAM)
								thin_file(path, context);
							if (context->do_strip && (magic == FAT_MAGIC || magic == FAT_CIGAM || magic == MH_MAGIC || magic == MH_CIGAM || magic == MH_MAGIC_64 || magic == MH_CIGAM_64))
								strip_file(path, context);
						}
					}
				}
				CFRelease(pathString);
			}
			break;
		default:
			break;
	}
}

static void process_request(xpc_object_t request, xpc_object_t reply) {
	__block helper_context_t context;

	context.should_exit = 0;
	
	context.connection = xpc_dictionary_create_connection(request, "connection");

	// Check XPC Connection
	if (!context.connection) {
		syslog(LOG_ERR, "Invalid XPC connection");
		return;
	}

	// Set up XPC connection endpoint for sending progress reports and receiving
	// cancel notification.
	xpc_connection_set_event_handler(context.connection, ^(xpc_object_t event) {
		xpc_type_t type = xpc_get_type(event);

		// If the remote end of this connection has gone away then stop processing
		if (XPC_TYPE_ERROR == type &&
			XPC_ERROR_CONNECTION_INTERRUPTED == event) {
			syslog(LOG_NOTICE, "Stopping MonolingualHelper");
			context.should_exit = 1;
		}
	});
	xpc_connection_resume(context.connection);

	// send at least one message to allow the progress connection to be canceled
	xpc_object_t ping = xpc_dictionary_create(NULL, NULL, 0);
	xpc_connection_send_message(context.connection, ping);
	xpc_release(ping);

	context.remove_func = delete_recursively;
	
	context.dry_run = xpc_dictionary_get_bool(request, "dry_run");
	context.do_strip = xpc_dictionary_get_bool(request, "strip");
	context.uid = xpc_dictionary_get_int64(request, "uid");
	if (xpc_dictionary_get_bool(request, "trash"))
		context.remove_func = trash_file;

	xpc_object_t files = xpc_dictionary_get_value(request, "files");
	xpc_object_t roots = xpc_dictionary_get_value(request, "includes");
	context.excludes = xpc_dictionary_get_value(request, "excludes");
	xpc_object_t thin = xpc_dictionary_get_value(request, "thin");

	xpc_object_t blacklist = xpc_dictionary_get_value(request, "blacklist");
	size_t blacklist_count = blacklist ? xpc_array_get_count(blacklist) : 0;
	context.bundle_blacklist = CFSetCreateMutable(kCFAllocatorDefault, blacklist_count, &kCFTypeSetCallBacks);
	if (blacklist) {
		xpc_array_apply(blacklist, ^bool(size_t index, xpc_object_t value) {
			CFStringRef bundle = CFStringCreateWithCString(kCFAllocatorDefault, xpc_string_get_string_ptr(value), kCFStringEncodingUTF8);
			CFSetAddValue(context.bundle_blacklist, bundle);
			CFRelease(bundle);
			return true;
		});
	}
	
	xpc_object_t dirs = xpc_dictionary_get_value(request, "directories");
	size_t dirs_count = dirs ? xpc_array_get_count(dirs) : 0;
	context.directories = CFSetCreateMutable(kCFAllocatorDefault, dirs_count, &kCFTypeSetCallBacks);
	if (dirs) {
		xpc_array_apply(dirs, ^bool(size_t index, xpc_object_t value) {
			CFStringRef directory = CFStringCreateWithCString(kCFAllocatorDefault, xpc_string_get_string_ptr(value), kCFStringEncodingUTF8);
			CFSetAddValue(context.directories, directory);
			CFRelease(directory);
			return true;
		});
	}

	if (context.do_strip) {
		// check if /usr/bin/strip is present
		struct stat st;
		if (stat("/usr/bin/strip", &st))
			context.do_strip = 0;
	}
	
	context.file_blacklist = CFSetCreateMutable(kCFAllocatorDefault, 0, &kCFTypeSetCallBacks);
	
	// delete regular files
	size_t num_files = files ? xpc_array_get_count(files) : 0;
	for (size_t i=0; i<num_files && !context.should_exit; ++i)
		context.remove_func(xpc_array_get_string(files, i), &context);
	
	// recursively delete directories
	if (CFSetGetCount(context.directories)) {
		size_t num_roots = roots ? xpc_array_get_count(roots) : 0;
		for (size_t i=0; i<num_roots && !context.should_exit; ++i)
			process_directory(xpc_array_get_string(roots, i), 0, &context);
	}
	
	// thin fat binaries
	size_t num_archs = thin ? xpc_array_get_count(thin) : 0;
	if (num_archs) {
		const char **archs = malloc(num_archs * sizeof(char *));
		for (size_t i=0; i<num_archs; ++i) {
			archs[i] = xpc_array_get_string(thin, i);
		}
												
		if (setup_lipo(archs, num_archs)) {
			size_t num_roots = roots ? xpc_array_get_count(roots) : 0;
			for (size_t i=0; i<num_roots && !context.should_exit; ++i) {
				thin_recursively(xpc_array_get_string(roots, i), &context);
			}
			finish_lipo();
		}

		free(archs);
	}

	CFRelease(context.file_blacklist);
	CFRelease(context.bundle_blacklist);
	CFRelease(context.directories);
	
	xpc_dictionary_set_int64(reply, "exit_code", context.should_exit);

	if (context.connection) {
		xpc_connection_suspend(context.connection);
		//xpc_release(context.connection);
	}
}

static void peer_event_handler(xpc_connection_t peer, xpc_object_t event) {
	syslog(LOG_NOTICE, "Received event in helper");

	xpc_type_t type = xpc_get_type(event);

	if (type == XPC_TYPE_ERROR) {
		if (event == XPC_ERROR_CONNECTION_INVALID) {
			// The client process on the other end of the connection has either
			// crashed or cancelled the connection. After receiving this error,
			// the connection is in an invalid state, and you do not need to
			// call xpc_connection_cancel(). Just tear down any associated state
			// here.
			syslog(LOG_NOTICE, "peer(%d) received XPC_ERROR_CONNECTION_INVALID", xpc_connection_get_pid(peer));
		} else if (event == XPC_ERROR_TERMINATION_IMMINENT) {
			// Handle per-connection termination cleanup.
			syslog(LOG_NOTICE, "peer(%d) received XPC_ERROR_TERMINATION_IMMINENT", xpc_connection_get_pid(peer));
		} else if (XPC_ERROR_CONNECTION_INTERRUPTED == event) {
			syslog(LOG_NOTICE, "peer(%d) received XPC_ERROR_CONNECTION_INTERRUPTED", xpc_connection_get_pid(peer));
		}
	} else if (XPC_TYPE_DICTIONARY == type) {
		xpc_object_t requestMessage = event;
		char *messageDescription = xpc_copy_description(requestMessage);
		
		syslog(LOG_NOTICE, "received message from peer(%d)\n:%s", xpc_connection_get_pid(peer), messageDescription);
		free(messageDescription);
		
		if (xpc_dictionary_get_value(requestMessage, "exit_code")) {
			exit(xpc_dictionary_get_int64(requestMessage, "exit_code"));
		} else {
			xpc_object_t replyMessage = xpc_dictionary_create_reply(requestMessage);
			process_request(requestMessage, replyMessage);

			messageDescription = xpc_copy_description(replyMessage);
			syslog(LOG_NOTICE, "reply message to peer(%d)\n: %s", xpc_connection_get_pid(peer), messageDescription);
			free(messageDescription);

			xpc_connection_send_message(peer, replyMessage);
			xpc_release(replyMessage);
		}
	}
}

static void service_event_handler(xpc_connection_t connection)  {
	syslog(LOG_NOTICE, "Configuring message event handler for helper.");

	xpc_connection_set_event_handler(connection, ^(xpc_object_t event) {
		peer_event_handler(connection, event);
	});
	
	xpc_connection_resume(connection);
}

int main(int argc, const char *argv[])
{
	xpc_connection_t service = xpc_connection_create_mach_service("net.sourceforge.MonolingualHelper",
																  dispatch_get_main_queue(),
																  XPC_CONNECTION_MACH_SERVICE_LISTENER);

	if (!service) {
		syslog(LOG_NOTICE, "Failed to create service.");
		exit(EXIT_FAILURE);
	}

	syslog(LOG_NOTICE, "Configuring connection event handler for helper");
	xpc_connection_set_event_handler(service, ^(xpc_object_t connection) {
		service_event_handler(connection);
	});

	xpc_connection_resume(service);

	dispatch_main();

	// dead code:
	//xpc_release(service);

	//return EXIT_SUCCESS;
}
