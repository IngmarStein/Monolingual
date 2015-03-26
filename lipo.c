/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 *
 * This file contains Original Code and/or Modifications of Original Code
 * as defined in and that are subject to the Apple Public Source License
 * Version 2.0 (the 'License'). You may not use this file except in
 * compliance with the License. Please obtain a copy of the License at
 * http://www.opensource.apple.com/apsl/ and read it before using this
 * file.
 *
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE, QUIET ENJOYMENT OR NON-INFRINGEMENT.
 * Please see the License for the specific language governing rights and
 * limitations under the License.
 *
 * @APPLE_LICENSE_HEADER_END@
 */
/*
 * The lipo(1) program.  This program creates, thins and operates on fat files.
 * This program takes the following options:
 *   <input_file>
 *   -output <filename>
 *   -thin <arch_type>
 *   -remove <arch_type>
 */
#include "lipo.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdarg.h>
#include <ar.h>
#include <errno.h>
#include <utime.h>
#include <sys/file.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <syslog.h>
#include <sys/mman.h>
#include <mach-o/swap.h>
#include <mach/machine.h>

#ifndef CPU_SUBTYPE_MASK
# define CPU_SUBTYPE_MASK	0xff000000  /* mask for feature flags */
#endif

/* The maximum section alignment allowed to be specified, as a power of two */
#define MAXSECTALIGN		15 /* 2**15 or 0x8000 */

/*
 * The structure describing an architecture flag with the string of the flag
 * name, and the cputype and cpusubtype.
 */
struct arch_flag {
	const char    *name;
	cpu_type_t    cputype;
	cpu_subtype_t cpusubtype;
};

/* from arch.c */
static const struct arch_flag arch_flags[] = {
	{ "any",	CPU_TYPE_ANY,	  CPU_SUBTYPE_MULTIPLE },
	{ "little",	CPU_TYPE_ANY,	  CPU_SUBTYPE_LITTLE_ENDIAN },
	{ "big",	CPU_TYPE_ANY,	  CPU_SUBTYPE_BIG_ENDIAN },
	
	/* 64-bit Mach-O architectures */
	
	/* architecture families */
	{ "ppc64",     CPU_TYPE_POWERPC64, CPU_SUBTYPE_POWERPC_ALL },
	{ "x86_64",    CPU_TYPE_X86_64, CPU_SUBTYPE_X86_64_ALL },
	{ "x86_64h",   CPU_TYPE_X86_64, CPU_SUBTYPE_X86_64_H },
	{ "arm64",     CPU_TYPE_ARM64,     CPU_SUBTYPE_ARM64_ALL },
	/* specific architecture implementations */
	{ "ppc970-64", CPU_TYPE_POWERPC64, CPU_SUBTYPE_POWERPC_970 },
	
	/* 32-bit Mach-O architectures */
	
	/* architecture families */
	{ "ppc",    CPU_TYPE_POWERPC, CPU_SUBTYPE_POWERPC_ALL },
	{ "i386",   CPU_TYPE_I386,    CPU_SUBTYPE_I386_ALL },
	{ "m68k",   CPU_TYPE_MC680x0, CPU_SUBTYPE_MC680x0_ALL },
	{ "hppa",   CPU_TYPE_HPPA,    CPU_SUBTYPE_HPPA_ALL },
	{ "sparc",	CPU_TYPE_SPARC,   CPU_SUBTYPE_SPARC_ALL },
	{ "m88k",   CPU_TYPE_MC88000, CPU_SUBTYPE_MC88000_ALL },
	{ "i860",   CPU_TYPE_I860,    CPU_SUBTYPE_I860_ALL },
//	{ "veo",    CPU_TYPE_VEO,     CPU_SUBTYPE_VEO_ALL },
	{ "arm",    CPU_TYPE_ARM,     CPU_SUBTYPE_ARM_ALL },
	/* specific architecture implementations */
	{ "ppc601", CPU_TYPE_POWERPC, CPU_SUBTYPE_POWERPC_601 },
	{ "ppc603", CPU_TYPE_POWERPC, CPU_SUBTYPE_POWERPC_603 },
	{ "ppc603e",CPU_TYPE_POWERPC, CPU_SUBTYPE_POWERPC_603e },
	{ "ppc603ev",CPU_TYPE_POWERPC,CPU_SUBTYPE_POWERPC_603ev },
	{ "ppc604", CPU_TYPE_POWERPC, CPU_SUBTYPE_POWERPC_604 },
	{ "ppc604e",CPU_TYPE_POWERPC, CPU_SUBTYPE_POWERPC_604e },
	{ "ppc750", CPU_TYPE_POWERPC, CPU_SUBTYPE_POWERPC_750 },
	{ "ppc7400",CPU_TYPE_POWERPC, CPU_SUBTYPE_POWERPC_7400 },
	{ "ppc7450",CPU_TYPE_POWERPC, CPU_SUBTYPE_POWERPC_7450 },
	{ "ppc970", CPU_TYPE_POWERPC, CPU_SUBTYPE_POWERPC_970 },
	{ "i486",   CPU_TYPE_I386,    CPU_SUBTYPE_486 },
	{ "i486SX", CPU_TYPE_I386,    CPU_SUBTYPE_486SX },
	{ "pentium",CPU_TYPE_I386,    CPU_SUBTYPE_PENT }, /* same as i586 */
	{ "i586",   CPU_TYPE_I386,    CPU_SUBTYPE_586 },
	{ "pentpro", CPU_TYPE_I386, CPU_SUBTYPE_PENTPRO }, /* same as i686 */
	{ "i686",   CPU_TYPE_I386, CPU_SUBTYPE_PENTPRO },
	{ "pentIIm3",CPU_TYPE_I386, CPU_SUBTYPE_PENTII_M3 },
	{ "pentIIm5",CPU_TYPE_I386, CPU_SUBTYPE_PENTII_M5 },
	{ "pentium4",CPU_TYPE_I386, CPU_SUBTYPE_PENTIUM_4 },
	{ "m68030", CPU_TYPE_MC680x0, CPU_SUBTYPE_MC68030_ONLY },
	{ "m68040", CPU_TYPE_MC680x0, CPU_SUBTYPE_MC68040 },
	{ "hppa7100LC", CPU_TYPE_HPPA,  CPU_SUBTYPE_HPPA_7100LC },
//	{ "veo1",   CPU_TYPE_VEO,     CPU_SUBTYPE_VEO_1 },
//	{ "veo2",   CPU_TYPE_VEO,     CPU_SUBTYPE_VEO_2 },
//	{ "veo3",   CPU_TYPE_VEO,     CPU_SUBTYPE_VEO_3 },
//	{ "veo4",   CPU_TYPE_VEO,     CPU_SUBTYPE_VEO_4 },
	{ "armv4t", CPU_TYPE_ARM,     CPU_SUBTYPE_ARM_V4T},
	{ "armv5",  CPU_TYPE_ARM,     CPU_SUBTYPE_ARM_V5TEJ},
	{ "xscale", CPU_TYPE_ARM,     CPU_SUBTYPE_ARM_XSCALE},
	{ "armv6",  CPU_TYPE_ARM,     CPU_SUBTYPE_ARM_V6 },
	{ "armv6m", CPU_TYPE_ARM,     CPU_SUBTYPE_ARM_V6M },
	{ "armv7",  CPU_TYPE_ARM,     CPU_SUBTYPE_ARM_V7 },
	{ "armv7f", CPU_TYPE_ARM,     CPU_SUBTYPE_ARM_V7F },
	{ "armv7s", CPU_TYPE_ARM,     CPU_SUBTYPE_ARM_V7S },
	{ "armv7k", CPU_TYPE_ARM,     CPU_SUBTYPE_ARM_V7K },
	{ "armv7m", CPU_TYPE_ARM,     CPU_SUBTYPE_ARM_V7M },
	{ "armv7em", CPU_TYPE_ARM,    CPU_SUBTYPE_ARM_V7EM },
	{ "arm64v8",CPU_TYPE_ARM64,   CPU_SUBTYPE_ARM64_V8 },
	{ NULL,	0,		  0 }
};

/* name of input file */
struct input_file {
	const char        *name;
	size_t            size;
	struct fat_header *fat_header;
	struct fat_arch   *fat_arches;
};
static struct input_file input_file;

/* Thin files from the input files to operate on */
struct thin_file {
	const char      *name;
	char            *addr;
	struct fat_arch fat_arch;
};
static struct thin_file *thin_files = NULL;
static uint32_t nthin_files = 0U;

/* The specified output file */
static const char *output_file = NULL;
static mode_t output_filemode = 0;
static uid_t output_uid;
static gid_t output_gid;
static struct utimbuf output_timep;

static struct arch_flag *remove_arch_flags = NULL;
static uint32_t nremove_arch_flags = 0U;

static struct fat_arch *arm64_fat_arch = NULL;

/* from arch.c */
/*
 * get_arch_from_flag() is passed a name of an architecture flag and returns
 * zero if that flag is not known and non-zero if the flag is known.
 * If the pointer to the arch_flag is not NULL it is filled in with the
 * arch_flag struct that matches the name.
 */
static
int
get_arch_from_flag(
				   char const *name,
				   struct arch_flag *arch_flag)
{
	uint32_t i;
	
	for(i = 0; arch_flags[i].name != NULL; i++){
		if(strcmp(arch_flags[i].name, name) == 0){
			if(arch_flag != NULL)
				*arch_flag = arch_flags[i];
			return(1);
		}
	}
	if(arch_flag != NULL)
		memset(arch_flag, '\0', sizeof(struct arch_flag));
	return(0);
}

/*
 * Function for qsort for comparing thin file's alignment
 */
static int cmp_qsort(const struct thin_file *thin1, const struct thin_file *thin2)
{
	return thin1->fat_arch.align - thin2->fat_arch.align;
}

/*
 * rnd() rounds v to a multiple of r.
 */
static uint32_t rnd(uint32_t v, uint32_t r)
{
	--r;
	v += r;
	v &= ~(int32_t)r;
	return v;
}

/*
 * allocate() is just a wrapper around malloc that prints an error message and
 * exits if the malloc fails.
 */
static
void *
allocate(
		 size_t size)
{
    void *p;
	
	if(size == 0)
	    return(NULL);
	if((p = malloc(size)) == NULL)
	    syslog(LOG_ERR, "virtual memory exhausted (malloc failed)");
	return(p);
}

/*
 * Makestr() creates a string that is the concatenation of a variable number of
 * strings.  It is pass a variable number of pointers to strings and the last
 * pointer is NULL.  It returns the pointer to the string it created.  The
 * storage for the string is malloc()'ed can be free()'ed when nolonger needed.
 */
static
char *
makestr(
		const char *args,
		...)
{
    va_list ap;
    char *s, *p;
    long size;
	
	size = 0;
	if(args != NULL){
	    size += strlen(args);
	    va_start(ap, args);
	    p = (char *)va_arg(ap, char *);
	    while(p != NULL){
			size += strlen(p);
			p = (char *)va_arg(ap, char *);
	    }
	}
	s = allocate(size + 1);
	*s = '\0';
	
	if(args != NULL){
	    (void)strcat(s, args);
	    va_start(ap, args);
	    p = (char *)va_arg(ap, char *);
	    while(p != NULL){
			(void)strcat(s, p);
			p = (char *)va_arg(ap, char *);
	    }
	    va_end(ap);
	}
	return(s);
}

/*
 * get_arm64_fat_arch() will return a pointer to the fat_arch struct for the
 * 64-bit arm slice in the thin_files[i] if it is present.  Else it returns
 * NULL.
 */
static
struct fat_arch *
get_arm64_fat_arch(
				   void)
{
	uint32_t i;
	struct fat_arch *arm64_fat_arch;
	
	/*
	 * Look for a 64-bit arm slice.
	 */
	arm64_fat_arch = NULL;
	for(i = 0; i < nthin_files; i++){
		if(thin_files[i].fat_arch.cputype == CPU_TYPE_ARM64){
			arm64_fat_arch = &(thin_files[i].fat_arch);
			return(arm64_fat_arch);
		}
	}
	return(NULL);
}

/*
 * create_fat() creates a fat output file from the thin files.
 */
static int create_fat(size_t *newsize)
{
	uint32_t i;
	char *rename_file;
	int fd;

	/*
	 * Create the output file.  The unlink() is done to handle the
	 * problem when the outputfile is not writable but the directory
	 * allows the file to be removed and thus created (since the file
	 * may not be there the return code of the unlink() is ignored).
	 */
	rename_file = makestr(output_file, ".lipo", NULL);
	if((fd = open(rename_file, O_WRONLY | O_CREAT | O_TRUNC,
				  output_filemode)) == -1) {
		syslog(LOG_ERR, "can't create temporary output file: %s", rename_file);
		return 1;
	}

	/* sort the files by alignment to save space in the output file */
	if (nthin_files > 1U)
		qsort(thin_files, nthin_files, sizeof(struct thin_file),
			  (int (*)(const void *, const void *))cmp_qsort);

	/*
	 * Create a fat file only if there is more than one thin file on the list.
	 */
	if (nthin_files != 1) {
		struct fat_header fat_header;
		uint32_t offset;

		/* We will order the ARM64 slice last. */
		arm64_fat_arch = get_arm64_fat_arch();
		
		/* Fill in the fat header and the fat_arch's offsets. */
		fat_header.magic = FAT_MAGIC;
		fat_header.nfat_arch = nthin_files;
		offset = (uint32_t)(sizeof(struct fat_header) + nthin_files * sizeof(struct fat_arch));
		for (i = 0; i < nthin_files; ++i) {
			offset = rnd(offset, 1 << thin_files[i].fat_arch.align);
			thin_files[i].fat_arch.offset = offset;
			offset += thin_files[i].fat_arch.size;
		}
		
#ifdef __LITTLE_ENDIAN__
		swap_fat_header(&fat_header, NX_BigEndian);
#endif /* __LITTLE_ENDIAN__ */
		if (write(fd, &fat_header, sizeof(struct fat_header)) != sizeof(struct fat_header)) {
			syslog(LOG_ERR, "can't write fat header to output file: %s", rename_file);
			close(fd);
			return 1;
		}
		for (i = 0; i < nthin_files; ++i) {
			/*
			 * If we are ordering the ARM64 slice last of the fat_arch
			 * structs, so skip it in this loop.
			 */
			if(arm64_fat_arch == &(thin_files[i].fat_arch))
				continue;
#ifdef __LITTLE_ENDIAN__
			swap_fat_arch(&(thin_files[i].fat_arch), 1, NX_BigEndian);
#endif /* __LITTLE_ENDIAN__ */
			if (write(fd, &(thin_files[i].fat_arch), sizeof(struct fat_arch)) != sizeof(struct fat_arch)) {
				syslog(LOG_ERR, "can't write fat arch to output file: %s", rename_file);
				close(fd);
				return 1;
			}
#ifdef __LITTLE_ENDIAN__
			swap_fat_arch(&(thin_files[i].fat_arch), 1, NX_LittleEndian);
#endif /* __LITTLE_ENDIAN__ */
		}
	}
	/*
	 * We are ordering the ARM64 slice so it gets written last of the
	 * fat_arch structs, so write it out here as it was skipped above.
	 */
	if(arm64_fat_arch){
#ifdef __LITTLE_ENDIAN__
		swap_fat_arch(arm64_fat_arch, 1, NX_BigEndian);
#endif /* __LITTLE_ENDIAN__ */
		if(write(fd, arm64_fat_arch,
				 sizeof(struct fat_arch)) != sizeof(struct fat_arch)) {
			syslog(LOG_ERR, "can't write fat arch to output file: %s",
						 rename_file);
			close(fd);
			return 1;
		}
#ifdef __LITTLE_ENDIAN__
		swap_fat_arch(arm64_fat_arch, 1, NX_LittleEndian);
#endif /* __LITTLE_ENDIAN__ */
	}
	for (i = 0; i < nthin_files; ++i) {
		if (nthin_files != 1)
			if (lseek(fd, thin_files[i].fat_arch.offset, L_SET) == -1) {
				syslog(LOG_ERR, "can't lseek in output file: %s", rename_file);
				close(fd);
				return 1;
			}
		if (write(fd, thin_files[i].addr, thin_files[i].fat_arch.size) != (int)(thin_files[i].fat_arch.size)) {
			syslog(LOG_ERR, "can't write to output file: %s", rename_file);
			close(fd);
			return 1;
		}
	}
	if (nthin_files != 1)
		*newsize = thin_files[nthin_files-1].fat_arch.offset + thin_files[nthin_files-1].fat_arch.size;
	else
		*newsize = thin_files[0].fat_arch.size;

	// restore the original owner and permissions
	fchown(fd, output_uid, output_gid);	
	fchmod(fd, output_filemode);
	
	if(rename(rename_file, output_file) == -1)
	    syslog(LOG_WARNING, "can't move temporary file: %s to file: %s",
					 rename_file, output_file);
	free(rename_file);

	return 0;
}

/*
 * process_input_file() checks input file and breaks it down into thin files
 * for later operations.
 */
static void process_input_file(struct input_file *input)
{
	int fd;
	struct stat stat_buf, stat_buf2;
	off_t size;
	unsigned long i, j;
	char *addr;
	struct thin_file *thin;

	/* Open the input file and map it in */
	if ((fd = open(input->name, O_RDONLY)) == -1) {
		syslog(LOG_ERR, "can't open input file: %s", input->name);
		return;
	}
	if (fstat(fd, &stat_buf) == -1) {
		close(fd);
		syslog(LOG_ERR, "can't stat input file: %s", input->name);
		return;
	}
	size = (size_t)stat_buf.st_size;
	input->size = size;
	/* pick up set uid, set gid and sticky text bits */
	output_filemode = stat_buf.st_mode & 07777;
	output_uid = stat_buf.st_uid;
	output_gid = stat_buf.st_gid;
	/*
	 * Select the earliest modify time so that if the output file
	 * contains archives with table of contents lipo will not make them
	 * out of date. This logic however could make an out of date table of
	 * contents appear up to date if another file is combined with it that
	 * has a date early enough.
	 */
	if (output_timep.modtime == 0 || output_timep.modtime > stat_buf.st_mtime) {
		output_timep.actime = stat_buf.st_atime;
		output_timep.modtime = stat_buf.st_mtime;
	}
	addr = mmap(NULL, size, PROT_READ|PROT_WRITE, MAP_PRIVATE, fd, 0);
	if (MAP_FAILED == addr) {
		syslog(LOG_ERR, "can't map input file: %s", input->name);
		close(fd);
		return;
	}

	/*
	 * Because of rdar://8087586 we do a second stat to see if the file
	 * is still there and the same file.
	 */
	if(fstat(fd, &stat_buf2) == -1) {
	    syslog(LOG_ERR, "can't stat input file: %s", input->name);
		close(fd);
		return;
	}
	if(stat_buf2.st_size != size ||
	   stat_buf2.st_mtime != stat_buf.st_mtime) {
	    syslog(LOG_ERR, "Input file: %s changed since opened", input->name);
		close(fd);
		return;
	}

	close(fd);

	/* Try to figure out what kind of file this is */

	/* see if this file is a fat file */
	if ((size_t)size >= sizeof(struct fat_header) &&
#ifdef __BIG_ENDIAN__
	   *((uint32_t *)addr) == FAT_MAGIC)
#endif /* __BIG_ENDIAN__ */
#ifdef __LITTLE_ENDIAN__
	   *((uint32_t *)addr) == FAT_CIGAM)
#endif /* __LITTLE_ENDIAN__ */
	{
		off_t big_size;

		input->fat_header = (struct fat_header *)addr;
#ifdef __LITTLE_ENDIAN__
		swap_fat_header(input->fat_header, NX_LittleEndian);
#endif /* __LITTLE_ENDIAN__ */
	    big_size = input->fat_header->nfat_arch;
	    big_size *= sizeof(struct fat_arch);
	    big_size += sizeof(struct fat_header);
		if (big_size > size) {
			syslog(LOG_ERR, "truncated or malformed fat file (fat_arch structs would "
					"extend past the end of the file) %s", input->name);
			munmap(addr, size);
			input->fat_header = NULL;
			return;
		}
		input->fat_arches = (struct fat_arch *)(addr + sizeof(struct fat_header));
#ifdef __LITTLE_ENDIAN__
		swap_fat_arch(input->fat_arches, input->fat_header->nfat_arch, NX_LittleEndian);
#endif /* __LITTLE_ENDIAN__ */
		for (i = 0; i < input->fat_header->nfat_arch; ++i) {
			if (input->fat_arches[i].offset + input->fat_arches[i].size > size) {
				syslog(LOG_ERR, "truncated or malformed fat file (offset plus size "
						"of cputype (%d) cpusubtype (%d) extends past the "
						"end of the file) %s", input->fat_arches[i].cputype,
						input->fat_arches[i].cpusubtype & ~CPU_SUBTYPE_MASK, input->name);
				munmap(addr, size);
				input->fat_header = NULL;
				return;
			}
			if (input->fat_arches[i].align > MAXSECTALIGN) {
				syslog(LOG_ERR, "align (2^%u) too large of fat file %s (cputype (%d)"
						" cpusubtype (%d)) (maximum 2^%d)",
						input->fat_arches[i].align, input->name,
						input->fat_arches[i].cputype,
						input->fat_arches[i].cpusubtype & ~CPU_SUBTYPE_MASK, MAXSECTALIGN);
				munmap(addr, size);
				input->fat_header = NULL;
				return;
			}
			if (input->fat_arches[i].offset % (1 << input->fat_arches[i].align) != 0) {
				syslog(LOG_ERR, "offset %u of fat file %s (cputype (%d) cpusubtype "
						"(%d)) not aligned on its alignment (2^%u)",
						input->fat_arches[i].offset, input->name,
						input->fat_arches[i].cputype,
						input->fat_arches[i].cpusubtype & ~CPU_SUBTYPE_MASK,
						input->fat_arches[i].align);
				munmap(addr, size);
				input->fat_header = NULL;
				return;
			}
		}
		for (i = 0; i < input->fat_header->nfat_arch; ++i) {
			for (j = i + 1; j < input->fat_header->nfat_arch; ++j) {
				if (input->fat_arches[i].cputype == input->fat_arches[j].cputype &&
				   (input->fat_arches[i].cpusubtype & ~CPU_SUBTYPE_MASK) == (input->fat_arches[j].cpusubtype & ~CPU_SUBTYPE_MASK)) {
					syslog(LOG_ERR, "fat file %s contains two of the same architecture "
							"(cputype (%d) cpusubtype (%d))", input->name,
							input->fat_arches[i].cputype,
							input->fat_arches[i].cpusubtype & ~CPU_SUBTYPE_MASK);
					munmap(addr, size);
					input->fat_header = NULL;
					return;
				}
			}
		}

		nthin_files = input->fat_header->nfat_arch;
		if (!nthin_files) {
			syslog(LOG_ERR, "fat file contains no architectures %s", input->name);
			munmap(addr, size);
			input->fat_header = NULL;
			return;
		} else {
			thin_files = malloc(nthin_files * sizeof(struct thin_file));
			/* create a thin file struct for each arch in the fat file */
			for (i = 0, thin = thin_files; i < nthin_files; ++i, ++thin) {
				thin->name = input->name;
				thin->addr = addr + input->fat_arches[i].offset;
				thin->fat_arch = input->fat_arches[i];
			}
		}
	} else {
		if (munmap(addr, size))
			syslog(LOG_ERR, "munmap: %s", strerror(errno));
	}
}

int setup_lipo(const char *archs[], unsigned num_archs)
{
	nremove_arch_flags = num_archs;
	remove_arch_flags = malloc(num_archs * sizeof(struct arch_flag));
	if (!remove_arch_flags)
		return 0;
	
	for (unsigned i = 0U; i < num_archs; ++i) {
		if (!get_arch_from_flag(archs[i], &remove_arch_flags[i])) {
			syslog(LOG_ERR, "unknown architecture specification flag: %s", archs[i]);
			free(remove_arch_flags);
			return 0;
		}
	}

	for (uint32_t i = 0U; i < nremove_arch_flags; ++i) {
		for (uint32_t j = i + 1; j < nremove_arch_flags; ++j) {
			if (remove_arch_flags[i].cputype == remove_arch_flags[j].cputype
				&& (remove_arch_flags[i].cpusubtype & ~CPU_SUBTYPE_MASK) == (remove_arch_flags[j].cpusubtype & ~CPU_SUBTYPE_MASK))
				syslog(LOG_ERR, "-remove %s specified multiple times", remove_arch_flags[i].name);
		}
	}

	return 1;
}

void finish_lipo(void)
{
	if (remove_arch_flags)
		free(remove_arch_flags);
}

int run_lipo(const char *path, size_t *size_diff)
{
	int    err;
	size_t newsize;

	/*
	 * Check to see the specified arguments are valid.
	 */
	if (!path)
		return 1;

	/* reset static variables */
	thin_files = NULL;
	nthin_files = 0U;
	memset(&output_timep, 0, sizeof(output_timep));

	/*
	 * Process the arguments.
	 */
	output_file = path;
	input_file.name = path;
	input_file.size = 0;
	input_file.fat_header = NULL;
	input_file.fat_arches = NULL;

	/*
	 * Determine the types of the input files.
	 */
	process_input_file(&input_file);

	/*
	 * Do the specified operation.
	 */

	if (!input_file.fat_header)
		return 1;

	/* remove those thin files */
	for (uint32_t i = 0; i < nremove_arch_flags; ++i) {
		for (uint32_t j = 0; j < nthin_files; ++j) {
			if (remove_arch_flags[i].cputype == thin_files[j].fat_arch.cputype
				&& (remove_arch_flags[i].cpusubtype & ~CPU_SUBTYPE_MASK) == (thin_files[j].fat_arch.cpusubtype & ~CPU_SUBTYPE_MASK)) {
				--nthin_files;
				for (unsigned long k = j; k < nthin_files; ++k)
					thin_files[k] = thin_files[k + 1];
				break;
			}
		}
	}

	/* write output file */
	if (nthin_files) {
		err = create_fat(&newsize);
		if (!err)
			*size_diff = input_file.size - newsize;
	} else {
		syslog(LOG_WARNING, "-remove's specified would result in an empty fat file");
		err = 1;
	}

	if (munmap(input_file.fat_header, input_file.size))
		syslog(LOG_ERR, "munmap: %s", strerror(errno));

	if (thin_files)
		free(thin_files);

	return err;
}
