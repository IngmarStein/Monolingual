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

static int trash;
static unsigned num_directories;
static unsigned num_excludes;
static unsigned num_archs;
static const char **directories;
static const char **excludes;
static const char **archs;

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
	struct stat st;
	if (stat(path, &st) != -1) {
		int status = EXIT_FAILURE;
		int child_status;
		off_t old_size = st.st_size;
		for (unsigned i=0U; i<num_archs; ++i) {
			switch (fork()) {
				case 0: // child
				{
					char *const env[1] = { NULL };
					char *argv[7];
					argv[0] = "lipo";
					argv[1] = "-remove";
					argv[2] = (char *)archs[i];
					argv[3] = (char *)path;
					argv[4] = "-o";
					argv[5] = (char *)path;
					argv[6] = NULL;
					int nulldev = open("/dev/null", O_WRONLY, 0);
					dup2(nulldev, 1);
					dup2(nulldev, 2);
					if (execve("/usr/bin/lipo", (char * const *)argv, env) == -1)
						exit(EXIT_FAILURE);
					break;
				}
				case -1: // error
					status = EXIT_FAILURE;
					fprintf(stderr, "could not fork()\n");
					break;
				default: // parent
					wait(&child_status);
					if (child_status == EXIT_SUCCESS)
						status = EXIT_SUCCESS;
					break;
			}
		}
		if (status == EXIT_SUCCESS) {
			// restore the original owner and permissions
			chown(path, st.st_uid, st.st_gid);
			chmod(path, st.st_mode & ~S_IFMT);
			if (stat(path, &st) != -1) {
				printf("%s%c%llu%c", path, '\0', old_size - st.st_size, '\0');
				fflush(stdout);
			}
		}
	}
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
				while ((ent = readdir(dir))) {
					if (strcmp(ent->d_name, ".") && strcmp(ent->d_name, "..")) {
						char *subdir = malloc(strlen(path) + ent->d_namlen + 2);
						strcpy(subdir, path);
						strcat(subdir, "/");
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
					struct stat sb;
					filename = strdup(filename);
					char *extension = strrchr(filename, '.');
					strncpy(destination, userTrash, sizeof(destination));
					strncat(destination, filename, sizeof(destination));
					while (1) {
						if (stat(destination, &sb)) {
							if (!rename(path, destination)) {
								printf("%s%c0%c", path, '\0', '\0');
								fflush(stdout);
								break;
							}
						}
						if (extension)
							*extension = '\0';
						time_t now = time(NULL);
						struct tm *lt = localtime(&now);
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
	DIR *dir;

	if (should_exit())
		return;

	for (unsigned i=0U; i<num_excludes; ++i)
		if (!strncmp(path, excludes[i], strlen(excludes[i])))
			return;

	char *last_component = strrchr(path, '/');
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
		while ((ent = readdir(dir))) {
			if (strcmp(ent->d_name, ".") && strcmp(ent->d_name, "..")) {
				struct stat st;

				char *subdir = malloc(strlen(path) + ent->d_namlen + 2);
				strcpy(subdir, path);
				strcat(subdir, "/");
				strcat(subdir, ent->d_name);

				if (lstat(subdir, &st) != -1 && ((st.st_mode & S_IFMT) == S_IFDIR))
					process_directory(subdir);

				free(subdir);
			}
		}
		closedir(dir);
	}
}

static int thin_recursively(const char *path)
{
	struct stat st;
	int type;

	if (should_exit())
		return 0;

	for (unsigned i=0U; i<num_excludes; ++i)
		if (!strncmp(path, excludes[i], strlen(excludes[i])))
			return 0;

	if (lstat(path, &st) == -1)
		return 1;

	type = st.st_mode & S_IFMT;
	switch (type) {
		case S_IFDIR: {
			DIR *dir;
			struct dirent *ent;
			dir = opendir(path);
			if (dir) {
				while ((ent = readdir(dir))) {
					if (strcmp(ent->d_name, ".") && strcmp(ent->d_name, "..")) {
						char *subdir = malloc(strlen(path) + ent->d_namlen + 2);
						strcpy(subdir, path);
						strcat(subdir, "/");
						strcat(subdir, ent->d_name);
						thin_recursively(subdir);
						free(subdir);
					}
				}
				closedir(dir);
			}
			break;
		}
		case S_IFREG:
			if (st.st_mode & S_IXUSR) {
				FILE *fp = fopen(path, "r");
				if (fp) {
					unsigned char magic[4];
					size_t num;
					num = fread(magic, 1, sizeof(magic), fp);
					fclose(fp);

					if (num == 4
						&& ((magic[0] == 0xca && magic[1] == 0xfe && magic[2] == 0xba && magic[3] == 0xbe)
							|| (magic[0] == 0xbe && magic[1] == 0xba && magic[2] == 0xfe && magic[3] == 0xca))) {
						thin_file(path);
					}
				}
			}
			break;
		default:
			break;
	}

	return 0;
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

	roots       = (const char **)malloc((argc-1) * sizeof(char *));
	files       = (const char **)malloc((argc-1) * sizeof(char *));
	directories = (const char **)malloc((argc-1) * sizeof(char *));
	excludes    = (const char **)malloc((argc-1) * sizeof(char *));
	archs       = (const char **)malloc((argc-1) * sizeof(char *));

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
		} else {
			directories[num_directories++] = arg;
		}
	}

	if (num_directories)
		qsort(directories, num_directories, sizeof(char *), string_compare);

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
