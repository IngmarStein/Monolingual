//
//  helper.m
//  Monolingual
//
//  Created by Ingmar Stein on Tue Mar 23 2004.
//  Copyright (c) 2004-2008 Ingmar Stein. All rights reserved.
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
#include "lipo.h"

static int do_strip;
static void (*remove_func)(const char *path);
static unsigned num_directories;
static unsigned num_excludes;
static unsigned num_archs;
static unsigned num_blacklists;
static const char **directories;
static const char **excludes;
static const char **archs;
static const char **blacklist;

static int string_compare(const void *s1, const void *s2)
{
	return strcmp(*(const char **)s1, *(const char **)s2);
}

static int string_search(const void *s1, const void *s2)
{
	return strcmp((const char *)s1, *(const char **)s2);
}

static int should_exit(void)
{
	fd_set fdset;
	struct timeval timeout = {0, 0};
	
	FD_ZERO(&fdset);
	FD_SET(0, &fdset);
	return select(1, &fdset, NULL, NULL, &timeout) == 1;
}

static void thin_file(const char *path)
{
	size_t size_diff;
	if (!run_lipo(path, &size_diff)) {
		printf("%s%c%zu%c", path, '\0', size_diff, '\0');
		fflush(stdout);
	}
}

static int thin_has_code_signature(char *addr, size_t size)
{
	uint32_t i;
	size_t mh_size = 0;
	uint32_t ncmds = 0;

	if (size >= sizeof(struct mach_header) &&
#ifdef __BIG_ENDIAN__
		*((uint32_t *)addr) == MH_MAGIC)
#endif /* __BIG_ENDIAN__ */
#ifdef __LITTLE_ENDIAN__
		*((uint32_t *)addr) == MH_CIGAM)
#endif /* __LITTLE_ENDIAN__ */
	{
		struct mach_header *mh = (struct mach_header *)addr;
#ifdef __LITTLE_ENDIAN__
		swap_mach_header(mh, NX_BigEndian);
#endif
		mh_size = sizeof(*mh);
		ncmds = mh->ncmds;
	} else if (size >= sizeof(struct mach_header_64) &&
#ifdef __BIG_ENDIAN__
		*((uint32_t *)addr) == MH_MAGIC_64)
#endif /* __BIG_ENDIAN__ */
#ifdef __LITTLE_ENDIAN__
		*((uint32_t *)addr) == MH_CIGAM_64)
#endif /* __LITTLE_ENDIAN__ */
	{
		struct mach_header_64 *mh = (struct mach_header_64 *)addr;
#ifdef __LITTLE_ENDIAN__
		swap_mach_header_64(mh, NX_BigEndian);
#endif
		mh_size = sizeof(*mh);
		ncmds = mh->ncmds;
	}
	if (mh_size) {
		struct load_command *lc = (struct load_command *)(addr + mh_size);
		for (i=0; i<ncmds; ++i) {
#ifdef __LITTLE_ENDIAN__
			swap_load_command(&lc[i], NX_BigEndian);
#endif
			if (LC_CODE_SIGNATURE == lc[i].cmd)
				return 1;
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
		swap_fat_header(fat_header, NX_BigEndian);
#endif /* __LITTLE_ENDIAN__ */
		struct fat_arch *fat_arches = (struct fat_arch *)(addr + sizeof(struct fat_header));
#ifdef __LITTLE_ENDIAN__
		swap_fat_arch(fat_arches, fat_header->nfat_arch, NX_BigEndian);
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

static void strip_file(const char *path)
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
			size_t size_diff = (size_t)(old_size - st.st_size);
			if (size_diff) {
				printf("%s%c%zu%c", path, '\0', size_diff, '\0');
				fflush(stdout);
			}
		}
	}
}

static int is_blacklisted(const char *path)
{
	int result = 0;
	CFStringRef infoPlistPath = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%s/Contents/Info.plist"), path);
	CFURLRef infoPlistURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, infoPlistPath, kCFURLPOSIXPathStyle, false);
	CFRelease(infoPlistPath);
	CFReadStreamRef stream = CFReadStreamCreateWithFile(kCFAllocatorDefault, infoPlistURL);
	CFRelease(infoPlistURL);
	if (stream) {
		if (CFReadStreamOpen(stream)) {
			CFPropertyListFormat format;
			CFPropertyListRef plist = CFPropertyListCreateFromStream(kCFAllocatorDefault,
																	 stream,
																	 /*streamLength*/ 0,
																	 kCFPropertyListImmutable,
																	 &format,
																	 /*errorString*/ NULL);
			if (plist) {
				CFStringRef bundleId = CFDictionaryGetValue(plist, kCFBundleIdentifierKey);
				if (bundleId) {
					char buffer[256];
					if (CFStringGetCString(bundleId, buffer, sizeof(buffer), kCFStringEncodingUTF8))
						result = bsearch(buffer, blacklist, num_blacklists, sizeof(char *), string_search) != NULL;
				}
				CFRelease(plist);
			}
			
			CFReadStreamClose(stream);
		}
		
		CFRelease(stream);
	}

	return result;
}

static void delete_recursively(const char *path)
{
	struct stat st;
	int result;

	if (should_exit())
		return;

	if (lstat(path, &st) == -1)
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
						strncat(subdir, ent->d_name, sizeof(subdir));
						delete_recursively(subdir);
					}
				}
				closedir(dir);
			}
			result = rmdir(path);
			break;
		}
		case S_IFREG:
		case S_IFLNK:
			result = unlink(path);
			break;
		default:
			return;
	}
	if (!result) {
		printf("%s%c%llu%c", path, '\0', st.st_size, '\0');
		fflush(stdout);
	}
}

static void trash_file(const char *path)
{
	char resolved_path[PATH_MAX];
	if (realpath(path, resolved_path)) {
		char userTrash[PATH_MAX];
		int validTrash = 0;
		if (!strncmp(path, "/Volumes/", 9)) {
			strncpy(userTrash, path, sizeof(userTrash));
			char *sep_pos = strchr(&userTrash[9], '/');
			if (sep_pos) {
				sep_pos[1] = '\0';
				strncat(userTrash, ".Trashes", sizeof(userTrash));
				mkdir(userTrash, 0700);
				snprintf(sep_pos+9, sizeof(userTrash)-(sep_pos+9-userTrash), "/%d", getuid());
				validTrash = 1;
			}
		} else {
			struct passwd *pwd = getpwuid(getuid());
			if (pwd) {
				strncpy(userTrash, pwd->pw_dir, sizeof(userTrash));
				strncat(userTrash, "/.Trash", sizeof(userTrash));
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
				strncat(destination, filename, sizeof(destination));
				while (1) {
					struct stat sb;
					struct tm *lt;
					time_t now;

					if (stat(destination, &sb)) {
						if (rename(path, destination)) {
							syslog(LOG_WARNING, "Failed to rename %s to %s: %m", path, destination);
						} else {
							printf("%s%c0%c", path, '\0', '\0');
							fflush(stdout);
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

static void process_directory(const char *path)
{
	DIR  *dir;
	char *last_component;

	if (should_exit())
		return;

	if (!strcmp(path, "/dev"))
		return;

	for (unsigned i=0U; i<num_excludes; ++i)
		if (!strncmp(path, excludes[i], strlen(excludes[i])))
			return;

	last_component = strrchr(path, '/');
	if (last_component) {
		++last_component;
		if (bsearch(last_component, directories, num_directories, sizeof(char *), string_search)) {
			remove_func(path);
			return;
		}
	}

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
				strncat(subdir, ent->d_name, sizeof(subdir));

				if (lstat(subdir, &st) != -1 && ((st.st_mode & S_IFMT) == S_IFDIR))
					process_directory(subdir);
			}
		}
		closedir(dir);
	}
}

static void thin_recursively(const char *path)
{
	struct stat st;

	if (should_exit())
		return;

	if (!strcmp(path, "/dev"))
		return;

	for (unsigned i=0U; i<num_excludes; ++i)
		if (!strncmp(path, excludes[i], strlen(excludes[i])))
			return;

	if (lstat(path, &st) == -1)
		return;

	switch (st.st_mode & S_IFMT) {
		case S_IFDIR: {
			DIR *dir;
			if (!is_blacklisted(path)) {
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
							strncat(subdir, ent->d_name, sizeof(subdir));
							thin_recursively(subdir);
						}
					}
					closedir(dir);
				}
			}
			break;
		}
		case S_IFREG:
			if (st.st_mode & (S_IXUSR|S_IXGRP|S_IXOTH)) {
				int fd = open(path, O_RDONLY, 0);
				if (fd >= 0) {
					unsigned int magic;
					ssize_t num;
					fcntl(fd, F_NOCACHE, 1);
					num = read(fd, &magic, sizeof(magic));
					close(fd);

					if (num == sizeof(magic)) {
						if (magic == FAT_MAGIC || magic == FAT_CIGAM)
							thin_file(path);
						if (do_strip && (magic == FAT_MAGIC || magic == FAT_CIGAM || magic == MH_MAGIC || magic == MH_CIGAM || magic == MH_MAGIC_64 || magic == MH_CIGAM_64))
							strip_file(path);
					}
				}
			}
			break;
		default:
			break;
	}
}

int main(int argc, const char *argv[])
{
	const char **roots;
	const char **files;
	unsigned   num_roots;
	unsigned   num_files;
	size_t     maxsize;
	const char **buf;
	const char **bufptr;

	if (argc <= 2)
		return EXIT_FAILURE;

	num_roots = 0U;
	num_files = 0U;
	num_archs = 0U;
	num_blacklists = 0U;
	remove_func = delete_recursively;

	maxsize     = argc-1;
	buf         = (const char **)malloc(6 * maxsize * sizeof(char *));
	bufptr      = buf;
	roots       = bufptr;
	bufptr     += maxsize;
	files       = bufptr;
	bufptr     += maxsize;
	directories = bufptr;
	bufptr     += maxsize;
	excludes    = bufptr;
	bufptr     += maxsize;
	archs       = bufptr;
	bufptr     += maxsize;
	blacklist   = bufptr;

	for (int i=1; i<argc; ++i) {
		const char *arg = argv[i];
		if (!strcmp(arg, "-r") || !strcmp(arg, "--root")) {
			++i;
			if (i == argc) {
				fprintf(stderr, "Argument expected for -r/--root\n");
				return EXIT_FAILURE;
			} else {
				roots[num_roots++] = argv[i];
			}
		} else if (!strcmp(arg, "-x") || !strcmp(arg, "--exclude")) {
			++i;
			if (i == argc) {
				fprintf(stderr, "Argument expected for -x/--exclude\n");
				return EXIT_FAILURE;
			} else {
				excludes[num_excludes++] = argv[i];
			}
		} else if (!strcmp(arg, "-t") || !strcmp(arg, "--trash")) {
			remove_func = trash_file;
		} else if (!strcmp(arg, "--thin")) {
			++i;
			if (i == argc) {
				fprintf(stderr, "Argument expected for --thin\n");
				return EXIT_FAILURE;
			} else {
				archs[num_archs++] = argv[i];
			}
		} else if (!strcmp(arg, "-f") || !strcmp(arg, "--file")) {
			++i;
			if (i == argc) {
				fprintf(stderr, "Argument expected for -f/--file\n");
				return EXIT_FAILURE;
			} else {
				files[num_files++] = argv[i];
			}
		} else if (!strcmp(arg, "-b") || !strcmp(arg, "--blacklist")) {
			++i;
			if (i == argc) {
				fprintf(stderr, "Argument expected for -b/--blacklist\n");
				return EXIT_FAILURE;
			} else {
				blacklist[num_blacklists++] = argv[i];
			}
		} else if (!strcmp(arg, "-s") || !strcmp(arg, "--strip")) {
			do_strip = 1;
		} else {
			directories[num_directories++] = arg;
		}
	}

	if (num_directories)
		qsort(directories, num_directories, sizeof(char *), string_compare);

	if (num_blacklists)
		qsort(blacklist, num_blacklists, sizeof(char *), string_compare);
	
	if (do_strip) {
		// check if /usr/bin/strip is present
		struct stat st;
		if (stat("/usr/bin/strip", &st))
			do_strip = 0;
	}

	// delete regular files
	for (unsigned i=0U; i<num_files && !should_exit(); ++i)
		remove_func(files[i]);

	// recursively delete directories
	if (num_directories)
		for (unsigned i=0U; i<num_roots && !should_exit(); ++i)
			process_directory(roots[i]);

	// thin fat binaries
	if (num_archs && setup_lipo(archs, num_archs)) {
		for (unsigned i=0U; i<num_roots && !should_exit(); ++i)
			thin_recursively(roots[i]);
		finish_lipo();
	}

	free(buf);

	return EXIT_SUCCESS;
}
