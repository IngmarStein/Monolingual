//
//  StripTests.swift
//  Helper Tests
//
//  `stripFile` rewrites an executable in place as root. It used the path for everything: `strip`
//  looks a path up and follows a link at the end of it, and so did the `setAttributes` that put the
//  ownership back afterwards. The walk refuses a link, but the entry can be replaced by one before
//  either of those runs, which is the state these tests put the path in.
//

import Darwin
import Foundation
import XCTest
@testable import HelperShared

final class StripTests: XCTestCase {
	private var directory: URL!

	override func setUpWithError() throws {
		directory = FileManager.default.temporaryDirectory.appendingPathComponent("monolingual-strip-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
	}

	override func tearDownWithError() throws {
		try? FileManager.default.removeItem(at: directory)
	}

	private var resources: URL {
		#if SWIFT_PACKAGE
		return Bundle.module.resourceURL!
		#else
		return Bundle(for: type(of: self)).resourceURL!
		#endif
	}

	/// A copy of the two-architecture fixture, which `strip` rewrites and does not leave alone.
	private func fixture(named name: String) throws -> URL {
		let destination = directory.appendingPathComponent(name)
		try FileManager.default.copyItem(at: resources.appendingPathComponent("hello2"), to: destination)
		return destination
	}

	private func context() -> HelperContext {
		var request = HelperRequest()
		request.uid = getuid()
		return HelperContext(request, rootless: true)
	}

	private func mode(of url: URL) throws -> NSNumber? {
		try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
	}

	func testStripDoesNotFollowSymbolicLink() throws {
		let target = try fixture(named: "victim")
		let link = directory.appendingPathComponent("link")
		try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

		let contentsBefore = try Data(contentsOf: target)
		let modeBefore = try mode(of: target)

		Helper().stripFile(link, context: context())

		XCTAssertEqual(try Data(contentsOf: target), contentsBefore, "the target of the link was rewritten")
		XCTAssertEqual(try mode(of: target), modeBefore, "the permissions of the link's target changed")
	}

	func testStripRewritesTheFileAndKeepsItsMode() throws {
		let file = try fixture(named: "binary")
		try FileManager.default.setAttributes([.posixPermissions: 0o751], ofItemAtPath: file.path)

		let contentsBefore = try Data(contentsOf: file)

		Helper().stripFile(file, context: context())

		XCTAssertNotEqual(try Data(contentsOf: file), contentsBefore, "the file should have been stripped")
		XCTAssertEqual(try mode(of: file), NSNumber(value: 0o751), "the mode should have been put back")
		XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "the file should still be where it was")
	}
}
