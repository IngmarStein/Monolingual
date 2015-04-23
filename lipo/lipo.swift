//
//  lipo.swift
//  Monolingual
//
//  Created by Ingmar Stein on 21.04.15.
//
//

import Foundation
import MachO.fat

private let CPU_SUBTYPE_MASK: cpu_subtype_t = 0xffffff  // mask for feature flags

// The maximum section alignment allowed to be specified, as a power of two
private let MAXSECTALIGN = 15 // 2**15 or 0x8000

// these defines are not (yet) visible to Swift
private let CPU_TYPE_ANY : cpu_type_t					= -1
private let CPU_TYPE_MC680x0: cpu_type_t				= 6
private let CPU_TYPE_X86 : cpu_type_t					= 7
private let CPU_TYPE_I386								= CPU_TYPE_X86		// compatibility
private let CPU_TYPE_X86_64 : cpu_type_t				= CPU_TYPE_X86 | CPU_ARCH_ABI64
private let CPU_TYPE_HPPA : cpu_type_t					= 11
private let CPU_TYPE_ARM : cpu_type_t					= 12
private let CPU_TYPE_ARM64 : cpu_type_t					= CPU_TYPE_ARM | CPU_ARCH_ABI64
private let CPU_TYPE_MC88000 : cpu_type_t				= 13
private let CPU_TYPE_SPARC : cpu_type_t					= 14
private let CPU_TYPE_I860 : cpu_type_t					= 15
private let CPU_TYPE_POWERPC : cpu_type_t				= 18
private let CPU_TYPE_POWERPC64 : cpu_type_t				= CPU_TYPE_POWERPC | CPU_ARCH_ABI64

private let CPU_SUBTYPE_MULTIPLE : cpu_subtype_t		= -1
private let CPU_SUBTYPE_LITTLE_ENDIAN : cpu_subtype_t	= 0
private let CPU_SUBTYPE_BIG_ENDIAN : cpu_subtype_t		= 1

private let CPU_SUBTYPE_ARM_ALL : cpu_subtype_t			= 0
private let CPU_SUBTYPE_ARM64_ALL : cpu_subtype_t		= 0
private let CPU_SUBTYPE_ARM_V4T : cpu_subtype_t			= 5
private let CPU_SUBTYPE_ARM_V6 : cpu_subtype_t			= 6
private let CPU_SUBTYPE_ARM_V5TEJ : cpu_subtype_t		= 7
private let CPU_SUBTYPE_ARM_XSCALE : cpu_subtype_t		= 8
private let CPU_SUBTYPE_ARM_V7 : cpu_subtype_t			= 9
private let CPU_SUBTYPE_ARM_V7F : cpu_subtype_t			= 10
private let CPU_SUBTYPE_ARM_V7S : cpu_subtype_t			= 11
private let CPU_SUBTYPE_ARM_V7K : cpu_subtype_t			= 12
private let CPU_SUBTYPE_ARM_V6M : cpu_subtype_t			= 14
private let CPU_SUBTYPE_ARM_V7M : cpu_subtype_t			= 15
private let CPU_SUBTYPE_ARM_V7EM : cpu_subtype_t		= 16

private let CPU_SUBTYPE_ARM64_V8 : cpu_subtype_t		= 1

private let CPU_SUBTYPE_POWERPC_ALL : cpu_subtype_t		= 0
private let CPU_SUBTYPE_POWERPC_601 : cpu_subtype_t		= 1
private let CPU_SUBTYPE_POWERPC_603 : cpu_subtype_t		= 3
private let CPU_SUBTYPE_POWERPC_603e : cpu_subtype_t	= 4
private let CPU_SUBTYPE_POWERPC_603ev : cpu_subtype_t	= 5
private let CPU_SUBTYPE_POWERPC_604 : cpu_subtype_t		= 6
private let CPU_SUBTYPE_POWERPC_604e : cpu_subtype_t	= 7
private let CPU_SUBTYPE_POWERPC_750 : cpu_subtype_t		= 9
private let CPU_SUBTYPE_POWERPC_7400 : cpu_subtype_t	= 10
private let CPU_SUBTYPE_POWERPC_7450 : cpu_subtype_t	= 11
private let CPU_SUBTYPE_POWERPC_970 : cpu_subtype_t		= 100
private let CPU_SUBTYPE_X86_ALL : cpu_subtype_t			= 3
private let CPU_SUBTYPE_X86_64_ALL : cpu_subtype_t		= 3
private let CPU_SUBTYPE_X86_64_H : cpu_subtype_t		= 8
private let CPU_SUBTYPE_MC680x0_ALL : cpu_subtype_t		= 1
private let CPU_SUBTYPE_HPPA_ALL : cpu_subtype_t		= 0
private let CPU_SUBTYPE_SPARC_ALL : cpu_subtype_t		= 0
private let CPU_SUBTYPE_MC88000_ALL : cpu_subtype_t		= 0
private let CPU_SUBTYPE_I860_ALL : cpu_subtype_t		= 0
private let CPU_SUBTYPE_MC68040 : cpu_subtype_t			= 2
private let CPU_SUBTYPE_MC68030_ONLY : cpu_subtype_t	= 3
private let CPU_SUBTYPE_HPPA_7100LC : cpu_subtype_t		= 1

private func CPU_SUBTYPE_INTEL(f: Int, m: Int) -> cpu_subtype_t { return cpu_subtype_t(f + (m << 4)) }

private let CPU_SUBTYPE_I386_ALL =			CPU_SUBTYPE_INTEL(3, 0)
private let CPU_SUBTYPE_486 =				CPU_SUBTYPE_INTEL(4, 0)
private let CPU_SUBTYPE_486SX =				CPU_SUBTYPE_INTEL(4, 8)	// 8 << 4 = 128
private let CPU_SUBTYPE_586 =				CPU_SUBTYPE_INTEL(5, 0)
private let CPU_SUBTYPE_PENT =				CPU_SUBTYPE_INTEL(5, 0)
private let CPU_SUBTYPE_PENTPRO =			CPU_SUBTYPE_INTEL(6, 1)
private let CPU_SUBTYPE_PENTII_M3 =			CPU_SUBTYPE_INTEL(6, 3)
private let CPU_SUBTYPE_PENTII_M5 =			CPU_SUBTYPE_INTEL(6, 5)
private let CPU_SUBTYPE_PENTIUM_3 =			CPU_SUBTYPE_INTEL(8, 0)
private let CPU_SUBTYPE_PENTIUM_4 =			CPU_SUBTYPE_INTEL(10, 0)

/*
 * The structure describing an architecture flag with the string of the flag
 * name, and the cputype and cpusubtype.
 */
private struct ArchFlag : Equatable, Hashable {
	var name: String
	var cputype: cpu_type_t
	var cpusubtype: cpu_subtype_t

	var hashValue: Int {
		return cputype.hashValue ^ cpusubtype.hashValue
	}
}

extension fat_arch : Hashable {
	public var hashValue: Int {
		return cputype.hashValue ^ cpusubtype.hashValue
	}
}

private func ==(lhs: ArchFlag, rhs: ArchFlag) -> Bool {
	return lhs.cputype == rhs.cputype && cpuSubtypeWithMask(lhs.cpusubtype) == cpuSubtypeWithMask(rhs.cpusubtype)
}

public func ==(lhs: fat_arch, rhs: fat_arch) -> Bool {
	return lhs.cputype == rhs.cputype && cpuSubtypeWithMask(lhs.cpusubtype) == cpuSubtypeWithMask(rhs.cpusubtype)
}

private let archFlags : [ArchFlag] = [
	ArchFlag(name: "any",	    cputype: CPU_TYPE_ANY,	  cpusubtype:CPU_SUBTYPE_MULTIPLE),
	ArchFlag(name: "little",	cputype: CPU_TYPE_ANY,	  cpusubtype:CPU_SUBTYPE_LITTLE_ENDIAN),
	ArchFlag(name: "big",	    cputype: CPU_TYPE_ANY,	  cpusubtype:CPU_SUBTYPE_BIG_ENDIAN),

	// 64-bit Mach-O architectures
	
	// architecture families
	ArchFlag(name: "ppc64",     cputype: CPU_TYPE_POWERPC64, cpusubtype:CPU_SUBTYPE_POWERPC_ALL),
	ArchFlag(name: "x86_64",    cputype: CPU_TYPE_X86_64, cpusubtype:CPU_SUBTYPE_X86_64_ALL),
	ArchFlag(name: "x86_64h",   cputype: CPU_TYPE_X86_64, cpusubtype:CPU_SUBTYPE_X86_64_H),
	ArchFlag(name: "arm64",     cputype: CPU_TYPE_ARM64,     cpusubtype:CPU_SUBTYPE_ARM64_ALL),
	/* specific architecture implementations */
	ArchFlag(name: "ppc970-64", cputype: CPU_TYPE_POWERPC64, cpusubtype:CPU_SUBTYPE_POWERPC_970),

	// 32-bit Mach-O architectures
	
	// architecture families
	ArchFlag(name: "ppc",      cputype: CPU_TYPE_POWERPC, cpusubtype:CPU_SUBTYPE_POWERPC_ALL),
	ArchFlag(name: "x86",      cputype: CPU_TYPE_X86,     cpusubtype:CPU_SUBTYPE_X86_ALL),
	ArchFlag(name: "i386",     cputype: CPU_TYPE_I386,    cpusubtype:CPU_SUBTYPE_I386_ALL),
	ArchFlag(name: "m68k",     cputype: CPU_TYPE_MC680x0, cpusubtype:CPU_SUBTYPE_MC680x0_ALL),
	ArchFlag(name: "hppa",     cputype: CPU_TYPE_HPPA,    cpusubtype:CPU_SUBTYPE_HPPA_ALL),
	ArchFlag(name: "sparc",    cputype: CPU_TYPE_SPARC,   cpusubtype:CPU_SUBTYPE_SPARC_ALL),
	ArchFlag(name: "m88k",     cputype: CPU_TYPE_MC88000, cpusubtype:CPU_SUBTYPE_MC88000_ALL),
	ArchFlag(name: "i860",     cputype: CPU_TYPE_I860,    cpusubtype:CPU_SUBTYPE_I860_ALL),
//	ArchFlag(name: "veo",      cputype: CPU_TYPE_VEO,     cpusubtype:CPU_SUBTYPE_VEO_ALL),
	ArchFlag(name: "arm",      cputype: CPU_TYPE_ARM,     cpusubtype:CPU_SUBTYPE_ARM_ALL),
	// specific architecture implementations
	ArchFlag(name: "ppc601",   cputype: CPU_TYPE_POWERPC, cpusubtype:CPU_SUBTYPE_POWERPC_601),
	ArchFlag(name: "ppc603",   cputype: CPU_TYPE_POWERPC, cpusubtype:CPU_SUBTYPE_POWERPC_603),
	ArchFlag(name: "ppc603e",  cputype: CPU_TYPE_POWERPC, cpusubtype:CPU_SUBTYPE_POWERPC_603e),
	ArchFlag(name: "ppc603ev", cputype: CPU_TYPE_POWERPC, cpusubtype:CPU_SUBTYPE_POWERPC_603ev),
	ArchFlag(name: "ppc604",   cputype: CPU_TYPE_POWERPC, cpusubtype:CPU_SUBTYPE_POWERPC_604),
	ArchFlag(name: "ppc604e",  cputype: CPU_TYPE_POWERPC, cpusubtype:CPU_SUBTYPE_POWERPC_604e),
	ArchFlag(name: "ppc750",   cputype: CPU_TYPE_POWERPC, cpusubtype:CPU_SUBTYPE_POWERPC_750),
	ArchFlag(name: "ppc7400",  cputype: CPU_TYPE_POWERPC, cpusubtype:CPU_SUBTYPE_POWERPC_7400),
	ArchFlag(name: "ppc7450",  cputype: CPU_TYPE_POWERPC, cpusubtype:CPU_SUBTYPE_POWERPC_7450),
	ArchFlag(name: "ppc970",   cputype: CPU_TYPE_POWERPC, cpusubtype:CPU_SUBTYPE_POWERPC_970),
	ArchFlag(name: "i486",     cputype: CPU_TYPE_I386,    cpusubtype:CPU_SUBTYPE_486),
	ArchFlag(name: "i486SX",   cputype: CPU_TYPE_I386,    cpusubtype:CPU_SUBTYPE_486SX),
	ArchFlag(name: "pentium",  cputype: CPU_TYPE_I386,    cpusubtype:CPU_SUBTYPE_PENT), /* same as i586 */
	ArchFlag(name: "i586",     cputype: CPU_TYPE_I386,    cpusubtype:CPU_SUBTYPE_586),
	ArchFlag(name: "pentpro",  cputype: CPU_TYPE_I386,    cpusubtype:CPU_SUBTYPE_PENTPRO), /* same as i686 */
	ArchFlag(name: "i686",     cputype: CPU_TYPE_I386,    cpusubtype:CPU_SUBTYPE_PENTPRO),
	ArchFlag(name: "pentIIm3", cputype: CPU_TYPE_I386,    cpusubtype:CPU_SUBTYPE_PENTII_M3),
	ArchFlag(name: "pentIIm5", cputype: CPU_TYPE_I386,    cpusubtype:CPU_SUBTYPE_PENTII_M5),
	ArchFlag(name: "pentium4", cputype: CPU_TYPE_I386,    cpusubtype:CPU_SUBTYPE_PENTIUM_4),
	ArchFlag(name: "m68030",   cputype: CPU_TYPE_MC680x0, cpusubtype:CPU_SUBTYPE_MC68030_ONLY),
	ArchFlag(name: "m68040",   cputype: CPU_TYPE_MC680x0, cpusubtype:CPU_SUBTYPE_MC68040),
	ArchFlag(name: "hppa7100LC", cputype: CPU_TYPE_HPPA,  cpusubtype:CPU_SUBTYPE_HPPA_7100LC),
//	ArchFlag(name: "veo1",     cputype: CPU_TYPE_VEO,     cpusubtype:CPU_SUBTYPE_VEO_1),
//	ArchFlag(name: "veo2",     cputype: CPU_TYPE_VEO,     cpusubtype:CPU_SUBTYPE_VEO_2),
//	ArchFlag(name: "veo3",     cputype: CPU_TYPE_VEO,     cpusubtype:CPU_SUBTYPE_VEO_3),
//	ArchFlag(name: "veo4",     cputype: CPU_TYPE_VEO,     cpusubtype:CPU_SUBTYPE_VEO_4),
	ArchFlag(name: "armv4t",   cputype: CPU_TYPE_ARM,     cpusubtype:CPU_SUBTYPE_ARM_V4T),
	ArchFlag(name: "armv5",    cputype: CPU_TYPE_ARM,     cpusubtype:CPU_SUBTYPE_ARM_V5TEJ),
	ArchFlag(name: "xscale",   cputype: CPU_TYPE_ARM,     cpusubtype:CPU_SUBTYPE_ARM_XSCALE),
	ArchFlag(name: "armv6",    cputype: CPU_TYPE_ARM,     cpusubtype:CPU_SUBTYPE_ARM_V6),
	ArchFlag(name: "armv6m",   cputype: CPU_TYPE_ARM,     cpusubtype:CPU_SUBTYPE_ARM_V6M),
	ArchFlag(name: "armv7",    cputype: CPU_TYPE_ARM,     cpusubtype:CPU_SUBTYPE_ARM_V7),
	ArchFlag(name: "armv7f",   cputype: CPU_TYPE_ARM,     cpusubtype:CPU_SUBTYPE_ARM_V7F),
	ArchFlag(name: "armv7s",   cputype: CPU_TYPE_ARM,     cpusubtype:CPU_SUBTYPE_ARM_V7S),
	ArchFlag(name: "armv7k",   cputype: CPU_TYPE_ARM,     cpusubtype:CPU_SUBTYPE_ARM_V7K),
	ArchFlag(name: "armv7m",   cputype: CPU_TYPE_ARM,     cpusubtype:CPU_SUBTYPE_ARM_V7M),
	ArchFlag(name: "armv7em",  cputype: CPU_TYPE_ARM,     cpusubtype:CPU_SUBTYPE_ARM_V7EM),
	ArchFlag(name: "arm64v8",  cputype: CPU_TYPE_ARM64,   cpusubtype:CPU_SUBTYPE_ARM64_V8)
]

private func getArchFromFlag(name: String) -> ArchFlag? {
	for flag in archFlags {
		if flag.name == name {
			return flag
		}
	}
	return nil
}

/*
 * rnd() rounds v to a multiple of r.
 */
private func rnd(v: UInt32, r: UInt32) -> UInt32 {
	let r2 = r - 1
	let v2 = v + r2
	return v2 & (~r2)
}

private func cpuSubtypeWithMask(subtype: cpu_subtype_t) -> cpu_subtype_t {
	return subtype & CPU_SUBTYPE_MASK
}

class Lipo {
	// Thin files from the input file to operate on
	private struct ThinFile {
		var data: UnsafePointer<Void>
		var fatArch: fat_arch
	}

	private var fileName: String!
	private var inputData: NSData!
	private var fatHeader: fat_header!
	private var thinFiles: [ThinFile]!
	private var removeArchFlags : [ArchFlag]!

	init?(archs: [String]) {

		removeArchFlags = []
		removeArchFlags.reserveCapacity(archs.count)

		for flag in archs {
			if let arch = getArchFromFlag(flag) {
				removeArchFlags.append(arch)
			} else {
				NSLog("unknown architecture specification flag: %@", flag)
				return nil
			}
		}

		var flagSet = Set<ArchFlag>()
		for flag in removeArchFlags {
			if flagSet.contains(flag) {
				NSLog("-remove %@ specified multiple times", flag.name)
			}
			flagSet.insert(flag)
		}
	}

	func run(path: String, inout sizeDiff: Int) -> Bool {
		var success = true
		var newsize = 0

		// reset context and process the arguments.
		fileName = path
		inputData = nil
		fatHeader = nil
		thinFiles = nil

		// Determine the types of the input files.
		if !processInputFile() {
			inputData = nil
			return false
		}

		// remove those thin files
		thinFiles = thinFiles.filter { thinFile in
			for flag in self.removeArchFlags {
				if flag.cputype == thinFile.fatArch.cputype && cpuSubtypeWithMask(flag.cpusubtype) == cpuSubtypeWithMask(thinFile.fatArch.cpusubtype) {
					return false
				}
			}
			return true
		}

		// write output file
		if thinFiles.isEmpty {
			NSLog("-remove's specified would result in an empty fat file")
			success = false
		} else {
			success = createFat(&newsize)
			if success {
				sizeDiff = inputData.length - newsize
			}
		}

		inputData = nil

		return success
	}

	private func fatHeaderFromFile(fatHeader: fat_header) -> fat_header {
		return fat_header(magic: UInt32(bigEndian: fatHeader.magic), nfat_arch: UInt32(bigEndian: fatHeader.nfat_arch))
	}

	private func fatHeaderToFile(fatHeader: fat_header) -> fat_header {
		return fat_header(magic: fatHeader.magic.bigEndian, nfat_arch: fatHeader.nfat_arch.bigEndian)
	}

	private func fatArchFromFile(fatArch: fat_arch) -> fat_arch {
		return fat_arch(
			cputype: cpu_type_t(bigEndian: fatArch.cputype),
			cpusubtype: cpu_subtype_t(bigEndian: fatArch.cpusubtype),
			offset: UInt32(bigEndian: fatArch.offset),
			size: UInt32(bigEndian: fatArch.size),
			align: UInt32(bigEndian: fatArch.align))
	}

	private func fatArchToFile(fatArch: fat_arch) -> fat_arch {
		return fat_arch(
			cputype: fatArch.cputype.bigEndian,
			cpusubtype: fatArch.cpusubtype.bigEndian,
			offset: fatArch.offset.bigEndian,
			size: fatArch.size.bigEndian,
			align: fatArch.align.bigEndian)
	}
	
	/*
	 * processInputFile() checks input file and breaks it down into thin files
	 * for later operations.
	 */
	private func processInputFile() -> Bool {
		var error: NSError?
		let fileAttributes = NSFileManager.defaultManager().attributesOfItemAtPath(fileName, error: &error)
		if fileAttributes == nil {
			NSLog("can't stat input file '%@'", fileName)
			return false
		}

		let data = NSData(contentsOfFile:fileName, options:(.DataReadingMappedAlways | .DataReadingUncached), error:&error)
		if data == nil {
			NSLog("can't map input file '%@'", fileName)
			return false
		}
		inputData = data
		let addr = inputData.bytes
		let size = inputData.length

		// check if this file is a fat file
		if size >= sizeof(fat_header) {
			let magic = UnsafePointer<UInt32>(addr).memory
			if magic == FAT_MAGIC || magic == FAT_CIGAM {
				let headerPointer = UnsafePointer<fat_header>(addr)
				fatHeader = fatHeaderFromFile(headerPointer.memory)
				let big_size = Int(fatHeader.nfat_arch) * sizeof(fat_arch) + sizeof(fat_header)
				if big_size > size {
					NSLog("truncated or malformed fat file (fat_arch structs would extend past the end of the file) %@", fileName)
					inputData = nil
					return false
				}
				let fatArchsPointer = UnsafePointer<fat_arch>(addr + sizeof(fat_header))
				let fatArchs = Array(UnsafeBufferPointer<fat_arch>(start: fatArchsPointer, count:Int(fatHeader.nfat_arch))).map { self.fatArchFromFile($0) }
				var fatArchSet = Set<fat_arch>()
				for fatArch in fatArchs {
					if Int(fatArch.offset + fatArch.size) > size {
						NSLog("truncated or malformed fat file (offset plus size of cputype (%d) cpusubtype (%d) extends past the end of the file) %@",
							fatArch.cputype, cpuSubtypeWithMask(fatArch.cpusubtype), fileName)
						return false
					}
					if fatArch.align > UInt32(MAXSECTALIGN) {
						NSLog("align (2^%u) too large of fat file %@ (cputype (%d) cpusubtype (%d)) (maximum 2^%d)",
							fatArch.align, fileName, fatArch.cputype, cpuSubtypeWithMask(fatArch.cpusubtype), MAXSECTALIGN)
						return false
					}
					if (fatArch.offset % (1 << fatArch.align)) != 0 {
						NSLog("offset %u of fat file %@ (cputype (%d) cpusubtype (%d)) not aligned on its alignment (2^%u)",
							fatArch.offset, fileName, fatArch.cputype, cpuSubtypeWithMask(fatArch.cpusubtype), fatArch.align)
						return false
					}
					if fatArchSet.contains(fatArch) {
						NSLog("fat file %@ contains two of the same architecture (cputype (%d) cpusubtype (%d))",
							fileName, fatArch.cputype, cpuSubtypeWithMask(fatArch.cpusubtype))
						return false
					}
					fatArchSet.insert(fatArch)
				}

				if fatArchs.isEmpty {
					NSLog("fat file contains no architectures %@", fileName)
					return false
				} else {
					// create a thin file struct for each arch in the fat file
					thinFiles = fatArchs.map { fatArch in
						let data = addr + Int(fatArch.offset)
						return ThinFile(data: data, fatArch: fatArch)
					}
				}
				return true
			}
		}

		// not a fat file
		return false
	}

	/*
	 * createFat() creates a fat output file from the thin files.
	 */
	private func createFat(inout newsize: Int) -> Bool {
		let temporaryFile = "\(fileName).lipo"
		let fd = open(temporaryFile, O_WRONLY | O_CREAT | O_TRUNC, 0o700)
		if fd == -1 {
			NSLog("can't create temporary output file: %s", temporaryFile);
			return false
		}
		let fileHandle = NSFileHandle(fileDescriptor: fd, closeOnDealloc: true)

		// sort the files by alignment to save space in the output file
		if thinFiles.count > 1 {
			thinFiles.sort { (thin1: ThinFile, thin2: ThinFile) in
				return thin1.fatArch.align < thin2.fatArch.align
			}
		}

		var arm64FatArch: Int?
		var x8664hFatArch: Int?

		// Create a fat file only if there is more than one thin file on the list.
		let nthinFiles = thinFiles.count
		if nthinFiles > 1 {
			// We will order the ARM64 slice last.
			arm64FatArch = getArm64FatArch()

			// We will order the x86_64h slice last too.
			x8664hFatArch = getX8664hFatArch()

			// Fill in the fat header and the fat_arch's offsets.
			var fatHeader = fatHeaderToFile(fat_header(magic: FAT_MAGIC, nfat_arch: UInt32(nthinFiles)))
			var offset = UInt32(sizeof(fat_header) + nthinFiles * sizeof(fat_arch))
			for (i, thinFile) in enumerate(thinFiles) {
				offset = rnd(offset, 1 << thinFile.fatArch.align)
				let fatArch = thinFile.fatArch
				thinFiles[i] = ThinFile(data: thinFile.data, fatArch: fat_arch(cputype: fatArch.cputype, cpusubtype: fatArch.cpusubtype, offset: offset, size: fatArch.size, align: fatArch.align))
				offset += thinFile.fatArch.size
			}

			if write(fileHandle.fileDescriptor, &fatHeader, sizeof(fat_header)) != sizeof(fat_header) {
				NSLog("can't write fat header to output file: %@", temporaryFile)
				return false
			}
			for (i, thinFile) in enumerate(thinFiles) {
				/*
				 * If we are ordering the ARM64 slice last of the fat_arch
				 * structs, so skip it in this loop.
				 */
				if i == arm64FatArch {
					continue
				}
				/*
				 * If we are ordering the x86_64h slice last too of the fat_arch
				 * structs, so skip it in this loop.
				 */
				if i == x8664hFatArch {
					continue
				}

				var fatArch = fatArchToFile(thinFile.fatArch)
				if write(fileHandle.fileDescriptor, &fatArch, sizeof(fat_arch)) != sizeof(fat_arch) {
					NSLog("can't write fat arch to output file: %@", temporaryFile)
					return false
				}
			}
		}

		/*
		 * We are ordering the ARM64 slice so it gets written last of the
		 * fat_arch structs, so write it out here as it was skipped above.
		 */
		if let arm64FatArch = arm64FatArch {
			var fatArch = fatArchToFile(thinFiles[arm64FatArch].fatArch)
			if write(fileHandle.fileDescriptor, &fatArch, sizeof(fat_arch)) != sizeof(fat_arch) {
				NSLog("can't write fat arch to output file: %@", temporaryFile)
				return false
			}
		}

		/*
		 * We are ordering the x86_64h slice so it gets written last too of the
		 * fat arch structs, so write it out here as it was skipped above.
		 */
		if let x8664hFatArch = x8664hFatArch {
			var fatArch = fatArchToFile(thinFiles[x8664hFatArch].fatArch)
			if write(fileHandle.fileDescriptor, &fatArch, sizeof(fat_arch)) != sizeof(fat_arch) {
				NSLog("can't write fat arch to output file: %@", temporaryFile)
				return false
			}
		}
		for thinFile in thinFiles {
			if nthinFiles != 1 {
				if lseek(fileHandle.fileDescriptor, off_t(thinFile.fatArch.offset), L_SET) == -1 {
					NSLog("can't lseek in output file: %@", temporaryFile)
					return false
				}
			}
			if write(fileHandle.fileDescriptor, thinFile.data, Int(thinFile.fatArch.size)) != Int(thinFile.fatArch.size) {
				NSLog("can't write to output file: %@", temporaryFile)
				return false
			}
		}
		if nthinFiles != 1 {
			newsize = Int(thinFiles.last!.fatArch.offset + thinFiles.last!.fatArch.size)
		} else {
			newsize = Int(thinFiles.first!.fatArch.size)
		}

		fileHandle.closeFile()

		if let temporaryURL = NSURL(fileURLWithPath: temporaryFile), inputURL = NSURL(fileURLWithPath: fileName) {
			var error: NSError?
			if !NSFileManager.defaultManager().replaceItemAtURL(inputURL, withItemAtURL: temporaryURL, backupItemName: nil, options: .allZeros, resultingItemURL: nil, error: &error) {
				NSLog("can't move temporary file: '%@' to file '%@': %@", temporaryFile, fileName, error!)
			}
		}
		
		return true
	}
	
	/*
	 * getArm64FatArch() will return a pointer to the fat_arch struct for the
	 * 64-bit arm slice in the thin_files[i] if it is present.  Else it returns
	 * NULL.
	 */
	private func getArm64FatArch() -> Int? {
		/*
		 * Look for a 64-bit arm slice.
		 */
		for (i, thinFile) in enumerate(thinFiles) {
			if thinFile.fatArch.cputype == CPU_TYPE_ARM64 {
				return i
			}
		}
		return nil
	}

	/*
	 * getX8664hFatArch() will return a pointer to the fat_arch struct for the
	 * x86_64h slice in the thin_files[i] if it is present.  Else it returns
	 * NULL.
	 */
	private func getX8664hFatArch() -> Int? {
		/*
		 * Look for a x86_64h slice.
		 */
		for (i, thinFile) in enumerate(thinFiles) {
			if thinFile.fatArch.cputype == CPU_TYPE_X86_64 && cpuSubtypeWithMask(thinFile.fatArch.cpusubtype) == CPU_SUBTYPE_X86_64_H {
				return i
			}
		}
		return nil
	}
}
