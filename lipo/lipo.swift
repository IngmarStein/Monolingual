//
//  lipo.swift
//  Monolingual
//
//  Created by Ingmar Stein on 21.04.15.
//
//

import Foundation
import MachO.fat
import OSLog

private let cpuSubtypeMask: cpu_subtype_t = 0xffffff  // mask for feature flags

// The maximum section alignment allowed to be specified, as a power of two
private let maxSectionAlign = 15 // 2**15 or 0x8000

/*
 * The structure describing an architecture flag with the string of the flag
 * name, and the cputype and cpusubtype.
 */
private struct ArchFlag: Equatable, Hashable {
	var name: String
	var cputype: cpu_type_t
	var cpusubtype: cpu_subtype_t

	func hash(into hasher: inout Hasher) {
		hasher.combine(cputype)
		hasher.combine(cpusubtype)
	}
}

extension fat_arch: Hashable {
	public func hash(into hasher: inout Hasher) {
		hasher.combine(cputype.hashValue)
		hasher.combine(cpusubtype.hashValue)
	}
}

extension fat_arch_64: Hashable {
	public func hash(into hasher: inout Hasher) {
		hasher.combine(cputype.hashValue)
		hasher.combine(cpusubtype.hashValue)
	}
}

private func == (lhs: ArchFlag, rhs: ArchFlag) -> Bool {
	return lhs.cputype == rhs.cputype && cpuSubtypeWithMask(lhs.cpusubtype) == cpuSubtypeWithMask(rhs.cpusubtype)
}

public func == (lhs: fat_arch, rhs: fat_arch) -> Bool {
	return lhs.cputype == rhs.cputype && cpuSubtypeWithMask(lhs.cpusubtype) == cpuSubtypeWithMask(rhs.cpusubtype)
}

public func == (lhs: fat_arch_64, rhs: fat_arch_64) -> Bool {
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
	for flag in archFlags where flag.name == name {
		return flag
	}
	return nil
}

/*
 * rnd() rounds v to a multiple of r.
 */
#if swift(>=4.0)
private func rnd<T: BinaryInteger>(v: T, r: T) -> T {
	let r2 = r - 1
	let v2 = v + r2
	return v2 & (~r2)
}
#else
private func rnd<T: Integer>(v: T, r: T) -> T {
	let r2 = r - 1
	let v2 = v + r2
	return v2 & (~r2)
}
#endif

private func cpuSubtypeWithMask(_ subtype: cpu_subtype_t) -> cpu_subtype_t {
	return subtype & cpuSubtypeMask
}

class Lipo {
	// Thin files from the input file to operate on
	private struct ThinFile {
		var data: Data
		var cputype: cpu_type_t
		var cpusubtype: cpu_subtype_t
		var offset: UInt64
		var size: UInt64
		var align: UInt32
	}

	private var fileName: String!
	private var inputData: Data!
	private var fatHeader: fat_header!
	private var thinFiles: [ThinFile]!
	private var removeArchFlags: [ArchFlag]!
	private var fat64Flag: Bool
	private let logger = Logger()

	init?(archs: [String]) {

		fat64Flag = false
		removeArchFlags = []
		removeArchFlags.reserveCapacity(archs.count)

		for flag in archs {
			if let arch = getArchFromFlag(flag) {
				removeArchFlags.append(arch)
			} else {
				logger.error("unknown architecture specification flag: \(flag, privacy: .public)")
				return nil
			}
		}

		var flagSet = Set<ArchFlag>()
		for flag in removeArchFlags {
			if flagSet.contains(flag) {
				self.logger.error("-remove \(flag.name, privacy: .public) specified multiple times")
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
		fat64Flag = false

		// Determine the types of the input files.
		if !processInputFile() {
			inputData = nil
			return false
		}

		// remove those thin files
		thinFiles = thinFiles.filter { thinFile in
			for flag in self.removeArchFlags {
				if flag.cputype == thinFile.cputype && cpuSubtypeWithMask(flag.cpusubtype) == cpuSubtypeWithMask(thinFile.cpusubtype) {
					return false
				}
			}
			return true
		}

		// write output file
		if thinFiles.isEmpty {
			logger.error("-remove's specified would result in an empty fat file")
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

	private func fatArch64FromFile(_ fatArch: fat_arch_64) -> fat_arch_64 {
		return fat_arch_64(
			cputype: cpu_type_t(bigEndian: fatArch.cputype),
			cpusubtype: cpu_subtype_t(bigEndian: fatArch.cpusubtype),
			offset: UInt64(bigEndian: fatArch.offset),
			size: UInt64(bigEndian: fatArch.size),
			align: UInt32(bigEndian: fatArch.align),
			reserved: UInt32(bigEndian: fatArch.reserved))
	}

	private func fatArchToFile(_ fatArch: fat_arch) -> fat_arch {
		return fat_arch(
			cputype: fatArch.cputype.bigEndian,
			cpusubtype: fatArch.cpusubtype.bigEndian,
			offset: fatArch.offset.bigEndian,
			size: fatArch.size.bigEndian,
			align: fatArch.align.bigEndian)
	}

	private func fatArch64ToFile(_ fatArch: fat_arch_64) -> fat_arch_64 {
		return fat_arch_64(
			cputype: fatArch.cputype.bigEndian,
			cpusubtype: fatArch.cpusubtype.bigEndian,
			offset: fatArch.offset.bigEndian,
			size: fatArch.size.bigEndian,
			align: fatArch.align.bigEndian,
			reserved: fatArch.reserved.bigEndian)
	}

	/*
	 * processInputFile() checks input file and breaks it down into thin files
	 * for later operations.
	 */
	private func processInputFile() -> Bool {
		do {
			try FileManager.default.attributesOfItem(atPath: fileName)
		} catch let error {
			logger.error("can't stat input file '\(self.fileName, privacy: .public)': \(error.localizedDescription, privacy: .public)")
			return false
		}

		let data: Data
		do {
			data = try Data(contentsOf: URL(fileURLWithPath: fileName, isDirectory: false), options: [.alwaysMapped, .uncached])
		} catch let error {
			logger.error("can't map input file '\(self.fileName, privacy: .public)': \(error.localizedDescription, privacy: .public)")
			return false
		}
		inputData = data
		let size = inputData.count

		// check if this file is a fat file
		if size < MemoryLayout<fat_header>.size {
			// not a fat file
			return false
		}

		return inputData.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Bool in
			let magic = buffer.load(as: UInt32.self)
			if magic == FAT_MAGIC || magic == FAT_CIGAM {
				// this file is a 32-bit fat file
				fatHeader = fatHeaderFromFile(buffer.load(as: fat_header.self))
				let bigSize = Int(fatHeader.nfat_arch) * MemoryLayout<fat_arch>.size + MemoryLayout<fat_header>.size
				if bigSize > size {
					logger.error("truncated or malformed fat file (fat_arch structs would extend past the end of the file) \(self.fileName, privacy: .public)")
					inputData = nil
					return false
				}
				let fatArchsRawPointer = UnsafeRawBufferPointer(rebasing: buffer.dropFirst(MemoryLayout<fat_header>.size))
				let fatArchsPointer = fatArchsRawPointer.bindMemory(to: fat_arch.self)
				let fatArchsCount = Int(fatHeader.nfat_arch)
				let fatArchs = Array(UnsafeBufferPointer<fat_arch>(start: fatArchsPointer.baseAddress!, count: fatArchsCount)).map { self.fatArchFromFile($0) }
				var fatArchSet = Set<fat_arch>()
				for fatArch in fatArchs {
					if Int(fatArch.offset + fatArch.size) > size {
						logger.error("truncated or malformed fat file (offset plus size of cputype (\(fatArch.cputype, privacy: .public) cpusubtype (\(cpuSubtypeWithMask(fatArch.cpusubtype), privacy: .public) extends past the end of the file) \(self.fileName, privacy: .public)")
						return false
					}
					if fatArch.align > UInt32(maxSectionAlign) {
						logger.error("align (2^\(fatArch.align, privacy: .public) too large of fat file \(self.fileName, privacy: .public) (cputype (\(fatArch.cputype, privacy: .public) cpusubtype (\(cpuSubtypeWithMask(fatArch.cpusubtype), privacy: .public))) (maximum 2^\(maxSectionAlign, privacy: .public)")
						return false
					}
					if (fatArch.offset % (1 << fatArch.align)) != 0 {
						logger.error("offset \(fatArch.offset, privacy: .public) of fat file \(self.fileName, privacy: .public) (cputype (\(fatArch.cputype, privacy: .public)) cpusubtype (\(cpuSubtypeWithMask(fatArch.cpusubtype), privacy: .public))) not aligned on its alignment (2^\(fatArch.align, privacy: .public)")
						return false
					}
					if fatArchSet.contains(fatArch) {
						logger.error("fat file \(self.fileName, privacy: .public) contains two of the same architecture (cputype (\(fatArch.cputype, privacy: .public)) cpusubtype (\(cpuSubtypeWithMask(fatArch.cpusubtype), privacy: .public)))")
						return false
					}
					fatArchSet.insert(fatArch)
				}

				if fatArchs.isEmpty {
					logger.error("fat file contains no architectures \(self.fileName, privacy: .public)")
					return false
				} else {
					// create a thin file struct for each arch in the fat file
					thinFiles = fatArchs.map { fatArch in
						let data = self.inputData.subdata(in: Int(fatArch.offset)..<Int(fatArch.offset + fatArch.size))
						return ThinFile(data: data, cputype: fatArch.cputype, cpusubtype: fatArch.cpusubtype, offset: UInt64(fatArch.offset), size: UInt64(fatArch.size), align: fatArch.align)
					}
				}
				return true
			} else if magic == FAT_MAGIC_64 || magic == FAT_CIGAM_64 {
				// this file is a 64-bit fat file
				fat64Flag = true
				fatHeader = fatHeaderFromFile(buffer.load(as: fat_header.self))
				let bigSize = Int(fatHeader.nfat_arch) * MemoryLayout<fat_arch_64>.size + MemoryLayout<fat_header>.size
				if bigSize > size {
					logger.error("truncated or malformed fat file (fat_arch structs would extend past the end of the file) \(self.fileName, privacy: .public)")
					inputData = nil
					return false
				}
				let fatArchsRawPointer = UnsafeRawBufferPointer(rebasing: buffer.dropFirst(MemoryLayout<fat_header>.size))
				let fatArchsPointer = fatArchsRawPointer.bindMemory(to: fat_arch_64.self)
				let fatArchsCount = Int(fatHeader.nfat_arch)
				let fatArchs = Array(UnsafeBufferPointer<fat_arch_64>(start: fatArchsPointer.baseAddress!, count: fatArchsCount)).map { self.fatArch64FromFile($0) }
				var fatArchSet = Set<fat_arch_64>()
				for fatArch in fatArchs {
					if Int(fatArch.offset + fatArch.size) > size {
						logger.error("truncated or malformed fat file (offset plus size of cputype (\(fatArch.cputype, privacy: .public)) cpusubtype (\(cpuSubtypeWithMask(fatArch.cpusubtype), privacy: .public)) extends past the end of the file) \(self.fileName, privacy: .public)")
						return false
					}
					if fatArch.align > UInt32(maxSectionAlign) {
						logger.error("align (2^\(fatArch.align, privacy: .public) too large of fat file \(self.fileName, privacy: .public) (cputype (\(fatArch.cputype, privacy: .public)) cpusubtype (\(cpuSubtypeWithMask(fatArch.cpusubtype), privacy: .public))) (maximum 2^\(maxSectionAlign, privacy: .public)")
						return false
					}
					if (fatArch.offset % UInt64((1 << fatArch.align))) != 0 {
						logger.error("offset \(fatArch.offset, privacy: .public) of fat file \(self.fileName, privacy: .public) (cputype (\(fatArch.cputype, privacy: .public)) cpusubtype (\(cpuSubtypeWithMask(fatArch.cpusubtype), privacy: .public))) not aligned on its alignment (2^\(fatArch.align, privacy: .public)")
						return false
					}
					if fatArchSet.contains(fatArch) {
						logger.error("fat file \(self.fileName, privacy: .public) contains two of the same architecture (cputype (\(fatArch.cputype, privacy: .public)) cpusubtype (\(cpuSubtypeWithMask(fatArch.cpusubtype), privacy: .public)))")
						return false
					}
					fatArchSet.insert(fatArch)
				}

				if fatArchs.isEmpty {
					logger.error("fat file contains no architectures \(self.fileName, privacy: .public)")
					return false
				} else {
					// create a thin file struct for each arch in the fat file
					thinFiles = fatArchs.map { fatArch in
						let data = self.inputData.subdata(in: Int(fatArch.offset)..<Int(fatArch.offset + fatArch.size))
						return ThinFile(data: data, cputype: fatArch.cputype, cpusubtype: fatArch.cpusubtype, offset: fatArch.offset, size: fatArch.size, align: fatArch.align)
					}
				}
				return true
			}
			return false
		}
	}

	/*
	 * createFat() creates a fat output file from the thin files.
	 */
	private func createFat(newsize: inout Int) -> Bool {
		let temporaryFile = "\(fileName!).lipo"

		let fd = open(temporaryFile, O_WRONLY | O_CREAT | O_TRUNC, 0o700)
		if fd == -1 {
			logger.error("can't create temporary output file: \(temporaryFile, privacy: .public)")
			return false
		}
		let fileHandle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)

		// sort the files by alignment to save space in the output file
		if thinFiles.count > 1 {
			thinFiles.sort { (thin1: ThinFile, thin2: ThinFile) in
				return thin1.align < thin2.align
			}
		}

		var arm64Arch: Int?
		var x8664hArch: Int?

		// Create a fat file only if there is more than one thin file on the list.
		let nthinFiles = thinFiles.count
		if nthinFiles > 1 {
			// We will order the ARM64 slice last.
			arm64Arch = getArm64Arch()

			// We will order the x86_64h slice last too.
			x8664hArch = getX8664hArch()

			// Fill in the fat header and the fat_arch's offsets.
			let magic = fat64Flag ? FAT_MAGIC_64 : FAT_MAGIC
			var fatHeader = fatHeaderToFile(fat_header(magic: magic, nfat_arch: UInt32(nthinFiles)))
			var offset = UInt64(MemoryLayout<fat_header>.size)
			if fat64Flag {
				offset += UInt64(nthinFiles * MemoryLayout<fat_arch_64>.size)
			} else {
				offset += UInt64(nthinFiles * MemoryLayout<fat_arch>.size)
			}
			thinFiles = thinFiles.map { (thinFile: ThinFile) in
				offset = rnd(v: offset, r: UInt64(1 << thinFile.align))
				let result = ThinFile(data: thinFile.data, cputype: thinFile.cputype, cpusubtype: thinFile.cpusubtype, offset: UInt64(offset), size: thinFile.size, align: thinFile.align)
				offset += thinFile.size
				return result
			}

			do {
				try withUnsafePointer(to: &fatHeader) { (pointer) in
					let data = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: pointer), count: MemoryLayout<fat_header>.size, deallocator: .none)
					try fileHandle.write(contentsOf: data)
				}
			} catch {
				logger.error("can't write fat header to output file: \(temporaryFile, privacy: .public)")
				return false
			}
			let thinFilesEnumerator = thinFiles.enumerated()
			for (i, thinFile) in thinFilesEnumerator {
				/*
				 * If we are ordering the ARM64 slice last of the fat_arch
				 * structs, so skip it in this loop.
				 */
				if i == arm64Arch {
					continue
				}
				/*
				 * If we are ordering the x86_64h slice last too of the fat_arch
				 * structs, so skip it in this loop.
				 */
				if i == x8664hArch {
					continue
				}

				if fat64Flag {
					var fatArch = fatArch64ToFile(fat_arch_64(cputype: thinFile.cputype, cpusubtype: thinFile.cpusubtype, offset: thinFile.offset, size: thinFile.size, align: thinFile.align, reserved: 0))
					do {
						try withUnsafePointer(to: &fatArch) { (pointer) in
							let data = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: pointer), count: MemoryLayout<fat_arch_64>.size, deallocator: .none)
							try fileHandle.write(contentsOf: data)
						}
					} catch {
						logger.error("can't write fat arch to output file: \(temporaryFile, privacy: .public)")
						return false
					}
				} else {
					var fatArch = fatArchToFile(fat_arch(cputype: thinFile.cputype, cpusubtype: thinFile.cpusubtype, offset: UInt32(thinFile.offset), size: UInt32(thinFile.size), align: thinFile.align))
					do {
						try withUnsafePointer(to: &fatArch) { (pointer) in
							let data = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: pointer), count: MemoryLayout<fat_arch>.size, deallocator: .none)
							try fileHandle.write(contentsOf: data)
						}
					} catch {
						logger.error("can't write fat arch to output file: \(temporaryFile, privacy: .public)")
						return false
					}
				}
			}
		}

		/*
		 * We are ordering the ARM64 slice so it gets written last of the
		 * fat_arch structs, so write it out here as it was skipped above.
		 */
		if let arm64Arch = arm64Arch {
			let thinFile = thinFiles[arm64Arch]
			if fat64Flag {
				var fatArch = fatArch64ToFile(fat_arch_64(cputype: thinFile.cputype, cpusubtype: thinFile.cpusubtype, offset: thinFile.offset, size: thinFile.size, align: thinFile.align, reserved: 0))
				do {
					try withUnsafePointer(to: &fatArch) { (pointer) in
						let data = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: pointer), count: MemoryLayout<fat_arch_64>.size, deallocator: .none)
						try fileHandle.write(contentsOf: data)
					}
				} catch {
					logger.error("can't write fat arch to output file: \(temporaryFile, privacy: .public)")
					return false
				}
			} else {
				var fatArch = fatArchToFile(fat_arch(cputype: thinFile.cputype, cpusubtype: thinFile.cpusubtype, offset: UInt32(thinFile.offset), size: UInt32(thinFile.size), align: thinFile.align))
				do {
					try withUnsafePointer(to: &fatArch) { (pointer) in
						let data = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: pointer), count: MemoryLayout<fat_arch>.size, deallocator: .none)
						try fileHandle.write(contentsOf: data)
					}
				} catch {
					logger.error("can't write fat arch to output file: \(temporaryFile, privacy: .public)")
					return false
				}
			}
		}

		/*
		 * We are ordering the x86_64h slice so it gets written last too of the
		 * fat arch structs, so write it out here as it was skipped above.
		 */
		if let x8664hArch = x8664hArch {
			let thinFile = thinFiles[x8664hArch]
			if fat64Flag {
				var fatArch = fatArch64ToFile(fat_arch_64(cputype: thinFile.cputype, cpusubtype: thinFile.cpusubtype, offset: thinFile.offset, size: thinFile.size, align: thinFile.align, reserved: 0))
				do {
					try withUnsafePointer(to: &fatArch) { (pointer) in
						let data = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: pointer), count: MemoryLayout<fat_arch_64>.size, deallocator: .none)
						try fileHandle.write(contentsOf: data)
					}
				} catch {
					logger.error("can't write fat arch to output file: \(temporaryFile, privacy: .public)")
					return false
				}
			} else {
				var fatArch = fatArchToFile(fat_arch(cputype: thinFile.cputype, cpusubtype: thinFile.cpusubtype, offset: UInt32(thinFile.offset), size: UInt32(thinFile.size), align: thinFile.align))
				do {
					try withUnsafePointer(to: &fatArch) { (pointer) in
						let data = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: pointer), count: MemoryLayout<fat_arch>.size, deallocator: .none)
						try fileHandle.write(contentsOf: data)
					}
				} catch {
					logger.error("can't write fat arch to output file: \(temporaryFile, privacy: .public)")
					return false
				}
			}
		}
		for thinFile in thinFiles {
			if nthinFiles != 1 {
				do {
					try fileHandle.seek(toOffset: thinFile.offset)
				} catch {
					logger.error("can't seek in output file: \(temporaryFile, privacy: .public)")
					return false
				}
			}
			do {
				try fileHandle.write(contentsOf: thinFile.data)
			} catch {
				logger.error("can't write to output file: \(temporaryFile, privacy: .public)")
				return false
			}
		}

		do {
			newsize = Int(try fileHandle.seekToEnd())
		} catch {
			logger.error("can't seek in output file: \(temporaryFile, privacy: .public)")
			return false
		}

		do {
			try fileHandle.close()
		} catch {
			logger.warning("can't close output file: \(temporaryFile, privacy: .public)")
		}

		let temporaryURL = URL(fileURLWithPath: temporaryFile, isDirectory: false)
		let inputURL = URL(fileURLWithPath: fileName, isDirectory: false)
		do {
			try FileManager.default.replaceItem(at: inputURL, withItemAt: temporaryURL, backupItemName: nil, options: [], resultingItemURL: nil)
		} catch let error {
			logger.error("can't move temporary file: '\(temporaryFile, privacy: .public)' to file '\(self.fileName, privacy: .public)': \(error.localizedDescription)")
			try? FileManager.default.removeItem(at: temporaryURL)
			return false
		}

		return true
	}

	/*
	 * getArm64Arch() will return a pointer to the fat_arch struct for the
	 * 64-bit arm slice in the thin_files[i] if it is present.  Else it returns
	 * NULL.
	 */
	private func getArm64Arch() -> Int? {
		// Look for a 64-bit arm slice.
		for (i, thinFile) in thinFiles.enumerated() where thinFile.cputype == CPU_TYPE_ARM64 {
			return i
		}
		return nil
	}

	/*
	 * getX8664hArch() will return a pointer to the fat_arch struct for the
	 * x86_64h slice in the thin_files[i] if it is present.  Else it returns
	 * NULL.
	 */
	private func getX8664hArch() -> Int? {
		// Look for a x86_64h slice.
		for (i, thinFile) in thinFiles.enumerated() where thinFile.cputype == CPU_TYPE_X86_64 && cpuSubtypeWithMask(thinFile.cpusubtype) == CPU_SUBTYPE_X86_64_H {
			return i
		}
		return nil
	}

}
