//
//  Helper_Tests.swift
//  Helper Tests
//
//  Created by Ingmar Stein on 21.04.15.
//
//

import Cocoa
import XCTest

class HelperTests: XCTestCase {

	private var testDir: URL {
		return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true).appendingPathComponent("testdata")
	}

	private var utilDir: URL {
		return Bundle(for: self.dynamicType).resourceURL!
	}

	private func createTestApp(name: String, bundleIdentifier: String) {
		do {
			let appDir = testDir.appendingPathComponent("\(name).app")
			let localizableStringsData = Data(base64Encoded: "dGVzdA==", options: [])!
			let infoPlist = [ "CFBundleIdentifier": bundleIdentifier ] as NSDictionary
			let fileManager = FileManager.default

			try fileManager.createDirectory(at: (appDir.appendingPathComponent("Contents/Resources/en.lproj")), withIntermediateDirectories: true, attributes: nil)
			try fileManager.createDirectory(at: (appDir.appendingPathComponent("Contents/Resources/de.lproj")), withIntermediateDirectories: true, attributes: nil)
			try fileManager.createDirectory(at: (appDir.appendingPathComponent("Contents/Resources/fr.lproj")), withIntermediateDirectories: true, attributes: nil)
			XCTAssert(fileManager.createFile(atPath: (appDir.appendingPathComponent("Contents/Resources/en.lproj/Localizable.strings").path), contents: localizableStringsData, attributes: nil))
			XCTAssert(fileManager.createFile(atPath: (appDir.appendingPathComponent("Contents/Resources/de.lproj/Localizable.strings").path), contents: localizableStringsData, attributes: nil))
			XCTAssert(fileManager.createFile(atPath: (appDir.appendingPathComponent("Contents/Resources/fr.lproj/Localizable.strings").path), contents: localizableStringsData, attributes: nil))
			XCTAssert(infoPlist.write(to: (appDir.appendingPathComponent("Contents/Info.plist")), atomically: false))
		} catch let error {
			XCTFail("Could not create test app: \(error)")
		}
	}

    override func setUp() {
        super.setUp()

		createTestApp(name: "test", bundleIdentifier: "com.test.test")
		createTestApp(name: "excluded", bundleIdentifier: "com.test.excluded")
		createTestApp(name: "blacklisted", bundleIdentifier: "com.test.blacklisted")

		let testHello1 = testDir.appendingPathComponent("hello1")
		let testHello2 = testDir.appendingPathComponent("hello2")
		let testHello3 = testDir.appendingPathComponent("hello3")
		let fileManager = FileManager.default
		do {
			try fileManager.removeItem(at: testHello1)
			try fileManager.removeItem(at: testHello2)
			try fileManager.removeItem(at: testHello3)
		} catch {
			// ignore
		}
		do {
			try fileManager.copyItem(at: utilDir.appendingPathComponent("hello1"), to: testHello1)
			try fileManager.copyItem(at: utilDir.appendingPathComponent("hello2"), to: testHello2)
			try fileManager.copyItem(at: utilDir.appendingPathComponent("hello3"), to: testHello3)
		} catch let error {
			XCTFail("Could not copy test data: \(error)")
		}
	}

    override func tearDown() {
        super.tearDown()

		let fileManager = FileManager.default
		do {
			try fileManager.removeItem(atPath: "testdata")
		} catch _ {
			// ignore
		}
    }

    func testRemoveLocalizations() {
		let request = HelperRequest()
		request.dryRun = false
		request.uid = getuid()
		request.trash = false
		request.includes = [ testDir.path ]
		request.excludes = [ (testDir.appendingPathComponent("excluded.app").path) ]
		request.directories = [ "fr.lproj" ]
		request.bundleBlacklist = [ "com.test.blacklisted" ]

		let helperExpectation = expectation(description: "Asynchronous helper processing")

		let helper = Helper()
		helper.processRequest(request, progress: nil) { (exitCode) -> Void in
			XCTAssert(exitCode == 0, "Helper should return with exit code 0")

			let fileManager = FileManager.default

			XCTAssert(fileManager.fileExists(atPath: (self.testDir.appendingPathComponent("test.app/Contents/Resources/en.lproj/Localizable.strings").path)), "English localization should be untouched")
			XCTAssert(fileManager.fileExists(atPath: (self.testDir.appendingPathComponent("test.app/Contents/Resources/de.lproj/Localizable.strings").path)), "German localization app should be untouched")
			XCTAssert(!fileManager.fileExists(atPath: (self.testDir.appendingPathComponent("test.app/Contents/Resources/fr.lproj/Localizable.strings").path)), "French localization should have been removed")
			XCTAssert(fileManager.fileExists(atPath: (self.testDir.appendingPathComponent("excluded.app/Contents/Resources/en.lproj/Localizable.strings").path)), "excluded app should be untouched")
			XCTAssert(fileManager.fileExists(atPath: (self.testDir.appendingPathComponent("excluded.app/Contents/Resources/de.lproj/Localizable.strings").path)), "excluded app should be untouched")
			XCTAssert(fileManager.fileExists(atPath: (self.testDir.appendingPathComponent("excluded.app/Contents/Resources/fr.lproj/Localizable.strings").path)), "excluded app should be untouched")
			XCTAssert(fileManager.fileExists(atPath: (self.testDir.appendingPathComponent("blacklisted.app/Contents/Resources/en.lproj/Localizable.strings").path)), "excluded app should be untouched")
			XCTAssert(fileManager.fileExists(atPath: (self.testDir.appendingPathComponent("blacklisted.app/Contents/Resources/de.lproj/Localizable.strings").path)), "excluded app should be untouched")
			XCTAssert(fileManager.fileExists(atPath: (self.testDir.appendingPathComponent("blacklisted.app/Contents/Resources/fr.lproj/Localizable.strings").path)), "excluded app should be untouched")

			helperExpectation.fulfill()
		}

		waitForExpectations(timeout: TimeInterval(5.0)) { (error) -> Void in
			if let error = error {
				XCTFail("Expectation failed with error: \(error)")
			}
		}
    }

	private func assertFileSize(path: URL, expectedSize: Int, message: String) {
		do {
			let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
			let size = attributes[FileAttributeKey.size] as? Int
			XCTAssertEqual(size, expectedSize, message)
		} catch _ {
			XCTFail("Could not file size of '\(path)'")
		}
	}

	func testRemoveArchitectures() {
		let request = HelperRequest()
		request.dryRun = false
		request.uid = getuid()
		request.trash = false
		request.includes = [ testDir.path ]
		request.excludes = [ (testDir.appendingPathComponent("excluded.app").path) ]
		request.thin = [ "i386" ]
		request.bundleBlacklist = [ "com.test.blacklisted" ]

		let hello1Path = testDir.appendingPathComponent("hello1")
		let hello2Path = testDir.appendingPathComponent("hello2")
		let hello3Path = testDir.appendingPathComponent("hello3")
		assertFileSize(path: hello1Path, expectedSize: 4312, message: "non-fat file size mismatch")
		assertFileSize(path: hello2Path, expectedSize: 16600, message: "2-arch fat file size mismatch")
		assertFileSize(path: hello3Path, expectedSize: 24792, message: "3-arch fat file size mismatch")

		let helperExpectation = expectation(description: "Asynchronous helper processing")

		let helper = Helper()
		helper.processRequest(request, progress: nil) { (exitCode) -> Void in
			XCTAssert(exitCode == 0, "Helper should return with exit code 0")

			let fileManager = FileManager.default

			XCTAssert(fileManager.fileExists(atPath: (self.testDir.appendingPathComponent("hello1").path)), "non-fat file should be present")
			XCTAssert(fileManager.fileExists(atPath: (self.testDir.appendingPathComponent("hello2").path)), "2-arch fat file should be present")
			XCTAssert(fileManager.fileExists(atPath: (self.testDir.appendingPathComponent("hello3").path)), "3-arch fat file should be present")

			// should remain untouched
			self.assertFileSize(path: hello1Path, expectedSize: 4312, message: "non-fat file size mismatch after lipo")
			// should now be a thin (non-fat) file containing a single architecture
			self.assertFileSize(path: hello2Path, expectedSize: 4312, message: "2-arch fat file size mismatch after lipo")
			// should be a fat file containing two remaining architectures
			self.assertFileSize(path: hello3Path, expectedSize: 16600, message: "3-arch fat file size mismatch after lipo")

			helperExpectation.fulfill()
		}

		waitForExpectations(timeout: TimeInterval(5.0)) { (error) -> Void in
			if let error = error {
				XCTFail("Expectation failed with error: \(error)")
			}
		}
	}

}
