//
//  lipo.swift
//  Monolingual
//
//  Created by Ingmar Stein on 21.04.15.
//
//

import Foundation
import MachO.fat

private let cpuSubtypeMask: cpu_subtype_t = 0xffffff  // mask for feature flags

// The maximum section alignment allowed to be specified, as a power of two
private let maxSectionAlign = 15 // 2**15 or 0x8000

// TODO: these defines are not (yet) visible to Swift
// swiftlint:disable variable_name
private let CPU_TYPE_X86_64: cpu_type_t				    = CPU_TYPE_X86 | CPU_ARCH_ABI64
private let CPU_TYPE_ARM64: cpu_type_t					= CPU_TYPE_ARM | CPU_ARCH_ABI64
private let CPU_TYPE_POWERPC64: cpu_type_t				= CPU_TYPE_POWERPC | CPU_ARCH_ABI64
// swiftlint:enable variable_name

/*
 * The structure describing an architecture flag with the string of the flag
 * name, and the cputype and cpusubtype.
 */
private struct ArchFlag: Equatable, Hashable {
	var name: String
	var cputype: cpu_type_t
	var cpusubtype: cpu_subtype_t

	var hashValue: Int {
		return cputype.hashValue ^ cpusubtype.hashValue
	}
}

extension fat_arch: Hashable {
	public var hashValue: Int {
		return cputype.hashValue ^ cpusubtype.hashValue
	}
}

private func == (lhs: ArchFlag, rhs: ArchFlag) -> Bool {
	return lhs.cputype == rhs.cputype && cpuSubtypeWithMask(lhs.cpusubtype) == cpuSubtypeWithMask(rhs.cpusubtype)
}

public func == (lhs: fat_arch, rhs: fat_arch) -> Bool {
	return lhs.cputype == rhs.cputype && cpuSubtypeWithMask(lhs.cpusubtype) == cpuSubtypeWithMask(rhs.cpusubtype)
}

// swiftlint:disable comma
private let archFlags: [ArchFlag] = [
	ArchFlag(name: "any",	     cputype: CPU_TYPE_ANY,	      cpusubtype: CPU_SUBTYPE_MULTIPLE),
	ArchFlag(name: "little",	 cputype: CPU_TYPE_ANY,	      cpusubtype: CPU_SUBTYPE_LITTLE_ENDIAN),
	ArchFlag(name: "big",	     cputype: CPU_TYPE_ANY,	      cpusubtype: CPU_SUBTYPE_BIG_ENDIAN),

	// 64-bit Mach-O architectures

	// architecture families
	ArchFlag(name: "ppc64",      cputype: CPU_TYPE_POWERPC64, cpusubtype: CPU_SUBTYPE_POWERPC_ALL),
	ArchFlag(name: "x86_64",     cputype: CPU_TYPE_X86_64,    cpusubtype: CPU_SUBTYPE_X86_64_ALL),
	ArchFlag(name: "x86_64h",    cputype: CPU_TYPE_X86_64,    cpusubtype: CPU_SUBTYPE_X86_64_H),
	ArchFlag(name: "arm64",      cputype: CPU_TYPE_ARM64,     cpusubtype: CPU_SUBTYPE_ARM64_ALL),
	/* specific architecture implementations */
	ArchFlag(name: "ppc970-64",  cputype: CPU_TYPE_POWERPC64, cpusubtype: CPU_SUBTYPE_POWERPC_970),

	// 32-bit Mach-O architectures

	// architecture families
	ArchFlag(name: "ppc",        cputype: CPU_TYPE_POWERPC,   cpusubtype: CPU_SUBTYPE_POWERPC_ALL),
	ArchFlag(name: "x86",        cputype: CPU_TYPE_X86,       cpusubtype: CPU_SUBTYPE_X86_ALL),
	ArchFlag(name: "i386",       cputype: CPU_TYPE_I386,      cpusubtype: CPU_SUBTYPE_X86_ALL),
	ArchFlag(name: "m68k",       cputype: CPU_TYPE_MC680x0,   cpusubtype: CPU_SUBTYPE_MC680x0_ALL),
	ArchFlag(name: "hppa",       cputype: CPU_TYPE_HPPA,      cpusubtype: CPU_SUBTYPE_HPPA_ALL),
	ArchFlag(name: "sparc",      cputype: CPU_TYPE_SPARC,     cpusubtype: CPU_SUBTYPE_SPARC_ALL),
	ArchFlag(name: "m88k",       cputype: CPU_TYPE_MC88000,   cpusubtype: CPU_SUBTYPE_MC88000_ALL),
	ArchFlag(name: "i860",       cputype: CPU_TYPE_I860,      cpusubtype: CPU_SUBTYPE_I860_ALL),
//	ArchFlag(name: "veo",        cputype: CPU_TYPE_VEO,       cpusubtype: CPU_SUBTYPE_VEO_ALL),
	ArchFlag(name: "arm",        cputype: CPU_TYPE_ARM,       cpusubtype: CPU_SUBTYPE_ARM_ALL),
	// specific architecture implementations
	ArchFlag(name: "ppc601",     cputype: CPU_TYPE_POWERPC,   cpusubtype: CPU_SUBTYPE_POWERPC_601),
	ArchFlag(name: "ppc603",     cputype: CPU_TYPE_POWERPC,   cpusubtype: CPU_SUBTYPE_POWERPC_603),
	ArchFlag(name: "ppc603e",    cputype: CPU_TYPE_POWERPC,   cpusubtype: CPU_SUBTYPE_POWERPC_603e),
	ArchFlag(name: "ppc603ev",   cputype: CPU_TYPE_POWERPC,   cpusubtype: CPU_SUBTYPE_POWERPC_603ev),
	ArchFlag(name: "ppc604",     cputype: CPU_TYPE_POWERPC,   cpusubtype: CPU_SUBTYPE_POWERPC_604),
	ArchFlag(name: "ppc604e",    cputype: CPU_TYPE_POWERPC,   cpusubtype: CPU_SUBTYPE_POWERPC_604e),
	ArchFlag(name: "ppc750",     cputype: CPU_TYPE_POWERPC,   cpusubtype: CPU_SUBTYPE_POWERPC_750),
	ArchFlag(name: "ppc7400",    cputype: CPU_TYPE_POWERPC,   cpusubtype: CPU_SUBTYPE_POWERPC_7400),
	ArchFlag(name: "ppc7450",    cputype: CPU_TYPE_POWERPC,   cpusubtype: CPU_SUBTYPE_POWERPC_7450),
	ArchFlag(name: "ppc970",     cputype: CPU_TYPE_POWERPC,   cpusubtype: CPU_SUBTYPE_POWERPC_970),
	ArchFlag(name: "m68030",     cputype: CPU_TYPE_MC680x0,   cpusubtype: CPU_SUBTYPE_MC68030_ONLY),
	ArchFlag(name: "m68040",     cputype: CPU_TYPE_MC680x0,   cpusubtype: CPU_SUBTYPE_MC68040),
	ArchFlag(name: "hppa7100LC", cputype: CPU_TYPE_HPPA,      cpusubtype: CPU_SUBTYPE_HPPA_7100LC),
//	ArchFlag(name: "veo1",       cputype: CPU_TYPE_VEO,       cpusubtype: CPU_SUBTYPE_VEO_1),
//	ArchFlag(name: "veo2",       cputype: CPU_TYPE_VEO,       cpusubtype: CPU_SUBTYPE_VEO_2),
//	ArchFlag(name: "veo3",       cputype: CPU_TYPE_VEO,       cpusubtype: CPU_SUBTYPE_VEO_3),
//	ArchFlag(name: "veo4",       cputype: CPU_TYPE_VEO,       cpusubtype: CPU_SUBTYPE_VEO_4),
	ArchFlag(name: "armv4t",     cputype: CPU_TYPE_ARM,       cpusubtype: CPU_SUBTYPE_ARM_V4T),
	ArchFlag(name: "armv5",      cputype: CPU_TYPE_ARM,       cpusubtype: CPU_SUBTYPE_ARM_V5TEJ),
	ArchFlag(name: "xscale",     cputype: CPU_TYPE_ARM,       cpusubtype: CPU_SUBTYPE_ARM_XSCALE),
	ArchFlag(name: "armv6",      cputype: CPU_TYPE_ARM,       cpusubtype: CPU_SUBTYPE_ARM_V6),
	ArchFlag(name: "armv6m",     cputype: CPU_TYPE_ARM,       cpusubtype: CPU_SUBTYPE_ARM_V6M),
	ArchFlag(name: "armv7",      cputype: CPU_TYPE_ARM,       cpusubtype: CPU_SUBTYPE_ARM_V7),
	ArchFlag(name: "armv7f",     cputype: CPU_TYPE_ARM,       cpusubtype: CPU_SUBTYPE_ARM_V7F),
	ArchFlag(name: "armv7s",     cputype: CPU_TYPE_ARM,       cpusubtype: CPU_SUBTYPE_ARM_V7S),
	ArchFlag(name: "armv7k",     cputype: CPU_TYPE_ARM,       cpusubtype: CPU_SUBTYPE_ARM_V7K),
	ArchFlag(name: "armv7m",     cputype: CPU_TYPE_ARM,       cpusubtype: CPU_SUBTYPE_ARM_V7M),
	ArchFlag(name: "armv7em",    cputype: CPU_TYPE_ARM,       cpusubtype: CPU_SUBTYPE_ARM_V7EM),
	ArchFlag(name: "arm64v8",    cputype: CPU_TYPE_ARM64,     cpusubtype: CPU_SUBTYPE_ARM64_V8)
]
// swiftlint:enable comma

private func getArchFromFlag(_ name: String) -> ArchFlag? {
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

private func cpuSubtypeWithMask(_ subtype: cpu_subtype_t) -> cpu_subtype_t {
	return subtype & cpuSubtypeMask
}

class Lipo {
	// Thin files from the input file to operate on
	private struct ThinFile {
		var data: Data
		var fatArch: fat_arch
	}

	private var fileName: String!
	private var inputData: Data!
	private var fatHeader: fat_header!
	private var thinFiles: [ThinFile]!
	private var removeArchFlags: [ArchFlag]!

	init?(archs: [String]) {

		removeArchFlags = []
		removeArchFlags.reserveCapacity(archs.count)

		for flag in archs {
			if let arch = getArchFromFlag(flag) {
				removeArchFlags.append(arch)
			} else {
				os_log_error(OS_LOG_DEFAULT, "unknown architecture specification flag: %@", flag as NSString)
				return nil
			}
		}

		var flagSet = Set<ArchFlag>()
		for flag in removeArchFlags {
			if flagSet.contains(flag) {
				os_log_error(OS_LOG_DEFAULT, "-remove %@ specified multiple times", flag.name as NSString)
			}
			flagSet.insert(flag)
		}
	}

	func run(path: String, sizeDiff: inout Int) -> Bool {
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
			os_log_error(OS_LOG_DEFAULT, "-remove's specified would result in an empty fat file")
			success = false
		} else {
			success = createFat(newsize: &newsize)
			if success {
				sizeDiff = inputData.count - newsize
			}
		}

		inputData = nil

		return success
	}

	private func fatHeaderFromFile(_ fatHeader: fat_header) -> fat_header {
		return fat_header(magic: UInt32(bigEndian: fatHeader.magic), nfat_arch: UInt32(bigEndian: fatHeader.nfat_arch))
	}

	private func fatHeaderToFile(_ fatHeader: fat_header) -> fat_header {
		return fat_header(magic: fatHeader.magic.bigEndian, nfat_arch: fatHeader.nfat_arch.bigEndian)
	}

	private func fatArchFromFile(_ fatArch: fat_arch) -> fat_arch {
		return fat_arch(
			cputype: cpu_type_t(bigEndian: fatArch.cputype),
			cpusubtype: cpu_subtype_t(bigEndian: fatArch.cpusubtype),
			offset: UInt32(bigEndian: fatArch.offset),
			size: UInt32(bigEndian: fatArch.size),
			align: UInt32(bigEndian: fatArch.align))
	}

	private func fatArchToFile(_ fatArch: fat_arch) -> fat_arch {
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
		do {
			try FileManager.default.attributesOfItem(atPath: fileName)
		} catch let error as NSError {
			os_log_error(OS_LOG_DEFAULT, "can't stat input file '%@': %@", fileName, error)
			return false
		}

		let data: Data
		do {
			data = try Data(contentsOf: URL(fileURLWithPath: fileName), options: [.alwaysMapped, .uncached])
		} catch let error as NSError {
			os_log_error(OS_LOG_DEFAULT, "can't map input file '%@': %@", fileName, error)
			return false
		}
		inputData = data
		let size = inputData.count

		// check if this file is a fat file
		if size < sizeof(fat_header.self) {
			// not a fat file
			return false
		}

		return inputData.withUnsafeBytes { (addr: UnsafePointer<Void>) -> Bool in
			let magic = UnsafePointer<UInt32>(addr).pointee
			if magic == FAT_MAGIC || magic == FAT_CIGAM {
				let headerPointer = UnsafePointer<fat_header>(addr)
				fatHeader = fatHeaderFromFile(headerPointer.pointee)
				let big_size = Int(fatHeader.nfat_arch) * sizeof(fat_arch.self) + sizeof(fat_header.self)
				if big_size > size {
					os_log_error(OS_LOG_DEFAULT, "truncated or malformed fat file (fat_arch structs would extend past the end of the file) %@", fileName as NSString)
					inputData = nil
					return false
				}
				let fatArchsPointer = UnsafePointer<fat_arch>(addr + sizeof(fat_header.self))
				let fatArchs = Array(UnsafeBufferPointer<fat_arch>(start: fatArchsPointer, count: Int(fatHeader.nfat_arch))).map { self.fatArchFromFile($0) }
				var fatArchSet = Set<fat_arch>()
				for fatArch in fatArchs {
					if Int(fatArch.offset + fatArch.size) > size {
						os_log_error(OS_LOG_DEFAULT, "truncated or malformed fat file (offset plus size of cputype (%d) cpusubtype (%d) extends past the end of the file) %@",
							fatArch.cputype, cpuSubtypeWithMask(fatArch.cpusubtype), fileName as NSString)
						return false
					}
					if fatArch.align > UInt32(maxSectionAlign) {
						os_log_error(OS_LOG_DEFAULT, "align (2^%u) too large of fat file %@ (cputype (%d) cpusubtype (%d)) (maximum 2^%d)",
							fatArch.align, fileName as NSString, fatArch.cputype, cpuSubtypeWithMask(fatArch.cpusubtype), maxSectionAlign)
						return false
					}
					if (fatArch.offset % (1 << fatArch.align)) != 0 {
						os_log_error(OS_LOG_DEFAULT, "offset %u of fat file %@ (cputype (%d) cpusubtype (%d)) not aligned on its alignment (2^%u)",
							fatArch.offset, fileName as NSString, fatArch.cputype, cpuSubtypeWithMask(fatArch.cpusubtype), fatArch.align)
						return false
					}
					if fatArchSet.contains(fatArch) {
						os_log_error(OS_LOG_DEFAULT, "fat file %@ contains two of the same architecture (cputype (%d) cpusubtype (%d))",
							fileName as NSString, fatArch.cputype, cpuSubtypeWithMask(fatArch.cpusubtype))
						return false
					}
					fatArchSet.insert(fatArch)
				}

				if fatArchs.isEmpty {
					os_log_error(OS_LOG_DEFAULT, "fat file contains no architectures %@", fileName as NSString)
					return false
				} else {
					// create a thin file struct for each arch in the fat file
					thinFiles = fatArchs.map { fatArch in
						let data = self.inputData.subdata(in: Int(fatArch.offset)..<Int(fatArch.offset + fatArch.size))
						return ThinFile(data: data, fatArch: fatArch)
					}
				}
				return true
			}
			return false
		}
	}

	/*
	 * createFat() creates a fat output file from the thin files.
	 * TODO: The FileHandle API doesn't support error handling, yet (see https://bugs.swift.org/browse/SR-2138).
	 */
	private func createFat(newsize: inout Int) -> Bool {
		let temporaryFile = "\(fileName!).lipo"
		guard let fileHandle = FileHandle(forWritingAtPath: temporaryFile) else {
			os_log_error(OS_LOG_DEFAULT, "can't create temporary output file: %@", temporaryFile);
			return false
		}

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
			var offset = UInt32(sizeof(fat_header.self) + nthinFiles * sizeof(fat_arch.self))
			thinFiles = thinFiles.map { thinFile in
				offset = rnd(v: offset, r: 1 << thinFile.fatArch.align)
				let fatArch = thinFile.fatArch
				let result = ThinFile(data: thinFile.data, fatArch: fat_arch(cputype: fatArch.cputype, cpusubtype: fatArch.cpusubtype, offset: offset, size: fatArch.size, align: fatArch.align))
				offset += thinFile.fatArch.size
				return result
			}

			withUnsafePointer(&fatHeader) { (pointer) in
				fileHandle.write(Data(bytesNoCopy: UnsafeMutablePointer<UInt8>(pointer), count: sizeof(fat_header.self), deallocator: .none))
				//os_log_error(OS_LOG_DEFAULT, "can't write fat header to output file: %@", temporaryFile as NSString)
				//return false
			}
			let thinFilesEnumerator = thinFiles.enumerated()
			for (i, thinFile) in thinFilesEnumerator {
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
				withUnsafePointer(&fatArch) { (pointer) in
					fileHandle.write(Data(bytesNoCopy: UnsafeMutablePointer<UInt8>(pointer), count: sizeof(fat_arch.self), deallocator: .none))
					//os_log_error(OS_LOG_DEFAULT, "can't write fat arch to output file: %@", temporaryFile as NSString)
					//return false
				}
			}
		}

		/*
		 * We are ordering the ARM64 slice so it gets written last of the
		 * fat_arch structs, so write it out here as it was skipped above.
		 */
		if let arm64FatArch = arm64FatArch {
			var fatArch = fatArchToFile(thinFiles[arm64FatArch].fatArch)
			withUnsafePointer(&fatArch) { (pointer) in
				fileHandle.write(Data(bytesNoCopy: UnsafeMutablePointer<UInt8>(pointer), count: sizeof(fat_arch.self), deallocator: .none))
				//os_log_error(OS_LOG_DEFAULT, "can't write fat arch to output file: %@", temporaryFile as NSString)
				//return false
			}
		}

		/*
		 * We are ordering the x86_64h slice so it gets written last too of the
		 * fat arch structs, so write it out here as it was skipped above.
		 */
		if let x8664hFatArch = x8664hFatArch {
			var fatArch = fatArchToFile(thinFiles[x8664hFatArch].fatArch)
			withUnsafePointer(&fatArch) { (pointer) in
				fileHandle.write(Data(bytesNoCopy: UnsafeMutablePointer<UInt8>(pointer), count: sizeof(fat_arch.self), deallocator: .none))
				//os_log_error(OS_LOG_DEFAULT, "can't write fat arch to output file: %@", temporaryFile as NSString)
				//return false
			}
		}
		for thinFile in thinFiles {
			if nthinFiles != 1 {
				fileHandle.seek(toFileOffset: UInt64(thinFile.fatArch.offset))
				//os_log_error(OS_LOG_DEFAULT, "can't lseek in output file: %@", temporaryFile as NSString)
				//return false
			}
			fileHandle.write(thinFile.data)
			//os_log_error(OS_LOG_DEFAULT, "can't write to output file: %@", temporaryFile as NSString)
			//return false
		}
		if nthinFiles != 1 {
			newsize = Int(thinFiles.last!.fatArch.offset + thinFiles.last!.fatArch.size)
		} else {
			newsize = Int(thinFiles.first!.fatArch.size)
		}

		fileHandle.closeFile()

		let temporaryURL = URL(fileURLWithPath: temporaryFile)
		let inputURL = URL(fileURLWithPath: fileName)
		do {
			try FileManager.default.replaceItem(at: inputURL as URL, withItemAt: temporaryURL as URL, backupItemName: nil, options: [], resultingItemURL: nil)
		} catch let error as NSError {
			os_log_error(OS_LOG_DEFAULT, "can't move temporary file: '%@' to file '%@': %@", temporaryFile as NSString, fileName as NSString, error)
		}

		return true
	}

	/*
	 * getArm64FatArch() will return a pointer to the fat_arch struct for the
	 * 64-bit arm slice in the thin_files[i] if it is present.  Else it returns
	 * NULL.
	 */
	private func getArm64FatArch() -> Int? {
		// Look for a 64-bit arm slice.
		for (i, thinFile) in thinFiles.enumerated() {
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
		// Look for a x86_64h slice.
		for (i, thinFile) in thinFiles.enumerated() {
			if thinFile.fatArch.cputype == CPU_TYPE_X86_64 && cpuSubtypeWithMask(thinFile.fatArch.cpusubtype) == CPU_SUBTYPE_X86_64_H {
				return i
			}
		}
		return nil
	}
}
