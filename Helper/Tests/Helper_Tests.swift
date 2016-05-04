//
//  Helper_Tests.swift
//  Helper Tests
//
//  Created by Ingmar Stein on 21.04.15.
//
//

import Cocoa
import XCTest

class Helper_Tests: XCTestCase {

	private var testDir: NSURL {
		return NSURL(fileURLWithPath: NSFileManager.default().currentDirectoryPath, isDirectory: true).appendingPathComponent("testdata")
	}

	private var utilDir: NSURL {
		return NSBundle(for: self.dynamicType).resourceURL!
	}

	private func createTestApp(name: String, bundleIdentifier: String) {
		let appDir = testDir.appendingPathComponent("\(name).app")
		let localizableStringsData = NSData(base64Encoded: "dGVzdA==", options: [])!
		let infoPlist = [ "CFBundleIdentifier" : bundleIdentifier ] as NSDictionary
		let fileManager = NSFileManager.default()

		do {
			try fileManager.createDirectory(at: appDir.appendingPathComponent("Contents/Resources/en.lproj"), withIntermediateDirectories: true, attributes: nil)
			try fileManager.createDirectory(at: appDir.appendingPathComponent("Contents/Resources/de.lproj"), withIntermediateDirectories: true, attributes: nil)
			try fileManager.createDirectory(at: appDir.appendingPathComponent("Contents/Resources/fr.lproj"), withIntermediateDirectories: true, attributes: nil)
			fileManager.createFile(atPath: appDir.appendingPathComponent("Contents/Resources/en.lproj/Localizable.strings").path!, contents: localizableStringsData, attributes: nil)
			fileManager.createFile(atPath: appDir.appendingPathComponent("Contents/Resources/de.lproj/Localizable.strings").path!, contents: localizableStringsData, attributes: nil)
			fileManager.createFile(atPath: appDir.appendingPathComponent("Contents/Resources/fr.lproj/Localizable.strings").path!, contents: localizableStringsData, attributes: nil)
			infoPlist.write(to: appDir.appendingPathComponent("Contents/Info.plist"), atomically: false)
		} catch let error as NSError {
			XCTAssert(false, "Could not create test app: \(error)")
		}
	}

    override func setUp() {
        super.setUp()

		createTestApp(name: "test", bundleIdentifier:"com.test.test")
		createTestApp(name: "excluded", bundleIdentifier:"com.test.excluded")
		createTestApp(name: "blacklisted", bundleIdentifier:"com.test.blacklisted")

		let fileManager = NSFileManager.default()
		do {
			try fileManager.copyItem(at: utilDir.appendingPathComponent("hello1"), to: testDir.appendingPathComponent("hello1"))
			try fileManager.copyItem(at: utilDir.appendingPathComponent("hello2"), to: testDir.appendingPathComponent("hello2"))
			try fileManager.copyItem(at: utilDir.appendingPathComponent("hello3"), to: testDir.appendingPathComponent("hello3"))
		} catch let error as NSError {
			XCTAssert(false, "Could not copy test data: \(error)")
		}
	}

    override func tearDown() {
        super.tearDown()

		let fileManager = NSFileManager.default()
		try! fileManager.removeItem(atPath: "testdata")
    }

    func testRemoveLocalizations() {
		let request = HelperRequest()
		request.dryRun = false
		request.uid = getuid()
		request.trash = false
		request.includes = [ testDir.path! ]
		request.excludes = [ testDir.appendingPathComponent("excluded.app").path! ]
		request.directories = [ "fr.lproj" ]
		request.bundleBlacklist = [ "com.test.blacklisted" ]

		let helperExpectation = expectation(withDescription: "Asynchronous helper processing")

		let helper = Helper()
		helper.processRequest(request, progress: nil) { (exitCode) -> Void in
			XCTAssert(exitCode == 0, "Helper should return with exit code 0")

			let fileManager = NSFileManager.default()
			XCTAssert(fileManager.fileExists(atPath: self.testDir.appendingPathComponent("test.app/Contents/Resources/en.lproj/Localizable.strings").path!), "English localization should be untouched")
			XCTAssert(fileManager.fileExists(atPath: self.testDir.appendingPathComponent("test.app/Contents/Resources/de.lproj/Localizable.strings").path!), "German localization app should be untouched")
			XCTAssert(!fileManager.fileExists(atPath: self.testDir.appendingPathComponent("test.app/Contents/Resources/fr.lproj/Localizable.strings").path!), "French localization should have been removed")
			XCTAssert(fileManager.fileExists(atPath: self.testDir.appendingPathComponent("excluded.app/Contents/Resources/en.lproj/Localizable.strings").path!), "excluded app should be untouched")
			XCTAssert(fileManager.fileExists(atPath: self.testDir.appendingPathComponent("excluded.app/Contents/Resources/de.lproj/Localizable.strings").path!), "excluded app should be untouched")
			XCTAssert(fileManager.fileExists(atPath: self.testDir.appendingPathComponent("excluded.app/Contents/Resources/fr.lproj/Localizable.strings").path!), "excluded app should be untouched")
			XCTAssert(fileManager.fileExists(atPath: self.testDir.appendingPathComponent("blacklisted.app/Contents/Resources/en.lproj/Localizable.strings").path!), "excluded app should be untouched")
			XCTAssert(fileManager.fileExists(atPath: self.testDir.appendingPathComponent("blacklisted.app/Contents/Resources/de.lproj/Localizable.strings").path!), "excluded app should be untouched")
			XCTAssert(fileManager.fileExists(atPath: self.testDir.appendingPathComponent("blacklisted.app/Contents/Resources/fr.lproj/Localizable.strings").path!), "excluded app should be untouched")

			helperExpectation.fulfill()
		}

		waitForExpectations(withTimeout: NSTimeInterval(5.0)) { (error) -> Void in
			if let error = error {
				XCTFail("Expectation failed with error: \(error)")
			}
		}
    }

	private func assertFileSize(path: NSURL, expectedSize: Int, message: String) {
		do {
			let attributes = try NSFileManager.default().attributesOfItem(atPath: path.path!)
			let size = attributes[NSFileSize] as? Int
			XCTAssertEqual(size, expectedSize, message)
		} catch _ {
			XCTAssert(false, "Could not file size of '\(path)'")
		}
	}

	func testRemoveArchitectures() {
		let request = HelperRequest()
		request.dryRun = false
		request.uid = getuid()
		request.trash = false
		request.includes = [ testDir.path! ]
		request.excludes = [ testDir.appendingPathComponent("excluded.app").path! ]
		request.thin = [ "i386" ]
		request.bundleBlacklist = [ "com.test.blacklisted" ]

		let hello1Path = testDir.appendingPathComponent("hello1")
		let hello2Path = testDir.appendingPathComponent("hello2")
		let hello3Path = testDir.appendingPathComponent("hello3")
		assertFileSize(path: hello1Path, expectedSize: 4312, message: "non-fat file size mismatch")
		assertFileSize(path: hello2Path, expectedSize: 16600, message: "2-arch fat file size mismatch")
		assertFileSize(path: hello3Path, expectedSize: 24792, message: "3-arch fat file size mismatch")

		let helperExpectation = expectation(withDescription: "Asynchronous helper processing")

		let helper = Helper()
		helper.processRequest(request, progress: nil) { (exitCode) -> Void in
			XCTAssert(exitCode == 0, "Helper should return with exit code 0")

			let fileManager = NSFileManager.default()
			XCTAssert(fileManager.fileExists(atPath: self.testDir.appendingPathComponent("hello1").path!), "non-fat file should be present")
			XCTAssert(fileManager.fileExists(atPath: self.testDir.appendingPathComponent("hello2").path!), "2-arch fat file should be present")
			XCTAssert(fileManager.fileExists(atPath: self.testDir.appendingPathComponent("hello3").path!), "3-arch fat file should be present")

			// should remain untouched
			self.assertFileSize(path: hello1Path, expectedSize: 4312, message: "non-fat file size mismatch after lipo")
			// should now be a thin (non-fat) file containing a single architecture
			self.assertFileSize(path: hello2Path, expectedSize: 4312, message: "2-arch fat file size mismatch after lipo")
			// should be a fat file containing two remaining architectures
			self.assertFileSize(path: hello3Path, expectedSize: 16600, message: "3-arch fat file size mismatch after lipo")

			helperExpectation.fulfill()
		}

		waitForExpectations(withTimeout: NSTimeInterval(5.0)) { (error) -> Void in
			if let error = error {
				XCTFail("Expectation failed with error: \(error)")
			}
		}
	}
}
