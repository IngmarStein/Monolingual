//
//  helper.m
//  Monolingual
//
//  Created by Ingmar Stein on Tue Mar 23 2004.
//  Copyright (c) 2004-2006 Ingmar Stein. All rights reserved.
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
#include "lipo.h"

#ifndef FAT_MAGIC
#define FAT_MAGIC	0xcafebabe
#endif
#ifndef FAT_CIGAM
#define FAT_CIGAM	0xbebafeca
#endif

static int trash;
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
	off_t size_diff;
	if (!run_lipo(path, archs, num_archs, &size_diff)) {
		printf("%s%c%llu%c", path, '\0', size_diff, '\0');
		fflush(stdout);
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

static int delete_recursively(const char *path)
{
	struct stat st;
	int result;

	if (should_exit())
		return 0;

	if (lstat(path, &st) == -1)
		return 1;

	switch (st.st_mode & S_IFMT) {
		case S_IFDIR: {
			DIR *dir;
			struct dirent *ent;
			dir = opendir(path);
			if (dir) {
				size_t pathlen = strlen(path);
				while ((ent = readdir(dir))) {
					if (strcmp(ent->d_name, ".") && strcmp(ent->d_name, "..")) {
						char *subdir = malloc(pathlen + ent->d_namlen + 2);
						strcpy(subdir, path);
						if (path[pathlen-1] != '/') {
							subdir[pathlen] = '/';
							subdir[pathlen+1] = '\0';
						}
						strcat(subdir, ent->d_name);
						delete_recursively(subdir);
						free(subdir);
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
			return 1;
	}
	if (!result) {
		printf("%s%c%llu%c", path, '\0', st.st_size, '\0');
		fflush(stdout);
	}

	return result;
}

static void remove_file(const char *path)
{
	if (trash) {
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
	} else {
		delete_recursively(path);
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
			remove_file(path);
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

				char *subdir = malloc(pathlen + ent->d_namlen + 2);
				strcpy(subdir, path);
				if (path[pathlen-1] != '/') {
					subdir[pathlen] = '/';
					subdir[pathlen+1] = '\0';
				}
				strcat(subdir, ent->d_name);

				if (lstat(subdir, &st) != -1 && ((st.st_mode & S_IFMT) == S_IFDIR))
					process_directory(subdir);

				free(subdir);
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
							char *subdir = malloc(pathlen + ent->d_namlen + 2);
							strcpy(subdir, path);
							if (path[pathlen-1] != '/') {
								subdir[pathlen] = '/';
								subdir[pathlen+1] = '\0';
							}
							strcat(subdir, ent->d_name);
							thin_recursively(subdir);
							free(subdir);
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
					num = read(fd, &magic, sizeof(magic));
					close(fd);

					if (num == sizeof(magic) && (magic == FAT_MAGIC || magic == FAT_CIGAM))
						thin_file(path);
				}
			}
			break;
		default:
			break;
	}

	return;
}

int main(int argc, const char *argv[])
{
	const char **roots;
	const char **files;
	unsigned   num_roots;
	unsigned   num_files;

	if (argc <= 2)
		return EXIT_FAILURE;

	trash = 0;
	num_roots = 0U;
	num_files = 0U;
	num_archs = 0U;
	num_blacklists = 0U;

	roots       = (const char **)malloc((argc-1) * sizeof(char *));
	files       = (const char **)malloc((argc-1) * sizeof(char *));
	directories = (const char **)malloc((argc-1) * sizeof(char *));
	excludes    = (const char **)malloc((argc-1) * sizeof(char *));
	archs       = (const char **)malloc((argc-1) * sizeof(char *));
	blacklist   = (const char **)malloc((argc-1) * sizeof(char *));

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
			trash = 1;
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
		} else {
			directories[num_directories++] = arg;
		}
	}

	if (num_directories)
		qsort(directories, num_directories, sizeof(char *), string_compare);

	if (num_blacklists)
		qsort(blacklist, num_blacklists, sizeof(char *), string_compare);

	// delete regular files
	for (unsigned i=0U; i<num_files && !should_exit(); ++i)
		remove_file(files[i]);

	// recursively delete directories
	if (num_directories)
		for (unsigned i=0U; i<num_roots && !should_exit(); ++i)
			process_directory(roots[i]);

	// thin fat binaries
	if (num_archs)
		for (unsigned i=0U; i<num_roots && !should_exit(); ++i)
			thin_recursively(roots[i]);

	free(directories);
	free(roots);
	free(excludes);
	free(files);
	free(archs);

	return EXIT_SUCCESS;
}
