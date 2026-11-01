//
//  SymlinkOwnershipTests.swift
//  Helper Tests
//
//  GHSA-9gmw-jhrw-g8wf: on the way to the trash the helper hands a localization directory and
//  everything below it to the user the app runs as. It did that with `FileManager.setAttributes`,
//  which follows a symbolic link, so a link sitting inside the directory changed the ownership of
//  its target — a root-owned file outside the tree, and with it the user's way to root.
//

import Darwin
import Foundation
import XCTest
#if canImport(HelperShared)
import HelperShared
#endif

final class SymlinkOwnershipTests: XCTestCase {
	/// What `lstat` reports, which is the entry itself and never what a link points at.
	private func status(of path: String) throws -> stat {
		var value = stat()
		guard lstat(path, &value) == 0 else {
			throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
		}
		return value
	}

	private func mode(of path: String) throws -> mode_t {
		try status(of: path).st_mode & 0o7777
	}

	private func statusChangeTime(of path: String) throws -> timespec {
		try status(of: path).st_ctimespec
	}

	/// A directory outside the localization directory is not handed to the user through a link
	/// that sits inside it.
	func testDescendantLinkToDirectoryLeavesItsTargetAlone() throws {
		try assertDescendantLinkLeavesItsTargetAlone { root in
			let target = root.appendingPathComponent("outside")
			try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
			return target
		}
	}

	/// The same for a file, which is what a root-owned configuration file or executable is.
	func testDescendantLinkToFileLeavesItsTargetAlone() throws {
		try assertDescendantLinkLeavesItsTargetAlone { root in
			let target = root.appendingPathComponent("outside")
			try Data("root-owned".utf8).write(to: target)
			return target
		}
	}

	private func assertDescendantLinkLeavesItsTargetAlone(
		linkTo makeTarget: (URL) throws -> URL,
		file: StaticString = #filePath,
		line: UInt = #line
	) throws {
		let fileManager = FileManager.default
		let (root, localization) = try makeScanRoot()
		defer { remove(root) }

		let target = try makeTarget(root)
		try fileManager.createSymbolicLink(at: localization.appendingPathComponent("pivot"), withDestinationURL: target)

		let modeBefore = try mode(of: target.path)
		let timeBefore = try statusChangeTime(of: target.path)
		// The change this guards against lands well inside the second, and a time that does not
		// move is only told apart from one that did by its nanoseconds.
		usleep(20_000)

		try keepInPlace(root)
		removeLanguages(in: root)

		XCTAssertTrue(fileManager.fileExists(atPath: localization.path),
		              "the scan root should have kept the localization directory", file: file, line: line)
		let timeAfter = try statusChangeTime(of: target.path)
		XCTAssertEqual(timeAfter.tv_sec, timeBefore.tv_sec,
		               "the status change time of the link's target moved", file: file, line: line)
		XCTAssertEqual(timeAfter.tv_nsec, timeBefore.tv_nsec,
		               "the status change time of the link's target moved", file: file, line: line)
		XCTAssertEqual(try mode(of: target.path), modeBefore,
		               "the permissions of the link's target changed", file: file, line: line)
	}

	/// What is really inside the directory is still handed over: the user has to be able to empty
	/// the trash afterwards, which is what the ownership change is for.
	func testRealContentsAreStillHandedOver() throws {
		let fileManager = FileManager.default
		let (root, localization) = try makeScanRoot()
		defer { remove(root) }

		let nested = localization.appendingPathComponent("nested")
		let contents = nested.appendingPathComponent("Localizable.strings")
		try fileManager.createDirectory(at: nested, withIntermediateDirectories: true)
		try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: nested.path)
		try Data("key = value;".utf8).write(to: contents)

		try keepInPlace(root)
		removeLanguages(in: root)

		XCTAssertTrue(fileManager.fileExists(atPath: localization.path),
		              "the scan root should have kept the localization directory")
		XCTAssertEqual(try mode(of: nested.path), 0o700,
		               "a directory below the localization directory should have been handed to the user")
		XCTAssertTrue(fileManager.fileExists(atPath: contents.path),
		              "the contents should be left where they are")
	}

	/// A scan root with a real `fr.lproj` in it, for a test to fill.
	private func makeScanRoot() throws -> (root: URL, localization: URL) {
		let fileManager = FileManager.default
		let root = fileManager.temporaryDirectory.appendingPathComponent("monolingual-\(UUID().uuidString)")
		let localization = root.appendingPathComponent("fr.lproj")
		try fileManager.createDirectory(at: localization, withIntermediateDirectories: true)
		return (root, localization)
	}

	/// Marks a filled scan root user-immutable, once the test is done building it.
	///
	/// The flag is what keeps the helper from moving the localization directory into the trash: the
	/// ownership it changes on the way there is what these tests look at, and a directory that stays
	/// where it is can be looked at. It also keeps them out of the trash the machine's user actually
	/// uses, which is not where `FileManager.urls(for: .trashDirectory, in: .userDomainMask)` points
	/// when Xcode runs the bundle.
	private func keepInPlace(_ root: URL) throws {
		guard chflags(root.path, UInt32(UF_IMMUTABLE)) == 0 else {
			throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
		}
	}

	private func remove(_ root: URL) {
		// The flag would outlive the test, and a temporary directory that cannot be cleaned up is
		// worse than the one it protects.
		_ = chflags(root.path, 0)
		try? FileManager.default.removeItem(at: root)
	}

	/// Runs the removal the way the app does, with the trash enabled.
	private func removeLanguages(in root: URL) {
		var request = HelperRequest()
		request.uid = getuid()
		request.trash = true
		request.includes = [root.path]
		request.directories = ["fr.lproj"]

		let finished = expectation(description: "the helper finished")
		Helper().process(request: request, report: nil) { code in
			XCTAssertEqual(code, Int(EXIT_SUCCESS), "the helper should have finished successfully")
			finished.fulfill()
		}
		wait(for: [finished], timeout: TimeInterval(5.0))
	}
}
