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
		return NSURL(fileURLWithPath: NSFileManager.defaultManager().currentDirectoryPath, isDirectory: true).URLByAppendingPathComponent("testdata")
	}

	private var utilDir: NSURL {
		return NSBundle(forClass: self.dynamicType).resourceURL!
	}

	private func createTestApp(name: String, bundleIdentifier: String) {
		let appDir = testDir.URLByAppendingPathComponent("\(name).app")
		let localizableStringsData = NSData(base64EncodedString: "dGVzdA==", options: [])!
		let infoPlist = [ "CFBundleIdentifier" : bundleIdentifier ] as NSDictionary
		let fileManager = NSFileManager.defaultManager()

		do {
			try fileManager.createDirectoryAtURL(appDir.URLByAppendingPathComponent("Contents/Resources/en.lproj"), withIntermediateDirectories: true, attributes: nil)
			try fileManager.createDirectoryAtURL(appDir.URLByAppendingPathComponent("Contents/Resources/de.lproj"), withIntermediateDirectories: true, attributes: nil)
			try fileManager.createDirectoryAtURL(appDir.URLByAppendingPathComponent("Contents/Resources/fr.lproj"), withIntermediateDirectories: true, attributes: nil)
			fileManager.createFileAtPath(appDir.URLByAppendingPathComponent("Contents/Resources/en.lproj/Localizable.strings").path!, contents: localizableStringsData, attributes: nil)
			fileManager.createFileAtPath(appDir.URLByAppendingPathComponent("Contents/Resources/de.lproj/Localizable.strings").path!, contents: localizableStringsData, attributes: nil)
			fileManager.createFileAtPath(appDir.URLByAppendingPathComponent("Contents/Resources/fr.lproj/Localizable.strings").path!, contents: localizableStringsData, attributes: nil)
			infoPlist.writeToURL(appDir.URLByAppendingPathComponent("Contents/Info.plist"), atomically: false)
		} catch let error as NSError {
			XCTAssert(false, "Could not create test app: \(error)")
		}
	}

    override func setUp() {
        super.setUp()

		createTestApp("test", bundleIdentifier:"com.test.test")
		createTestApp("excluded", bundleIdentifier:"com.test.excluded")
		createTestApp("blacklisted", bundleIdentifier:"com.test.blacklisted")

		let fileManager = NSFileManager.defaultManager()
		do {
			try fileManager.copyItemAtURL(utilDir.URLByAppendingPathComponent("hello1"), toURL: testDir.URLByAppendingPathComponent("hello1"))
			try fileManager.copyItemAtURL(utilDir.URLByAppendingPathComponent("hello2"), toURL: testDir.URLByAppendingPathComponent("hello2"))
			try fileManager.copyItemAtURL(utilDir.URLByAppendingPathComponent("hello3"), toURL: testDir.URLByAppendingPathComponent("hello3"))
		} catch let error as NSError {
			XCTAssert(false, "Could not copy test data: \(error)")
		}
	}

    override func tearDown() {
        super.tearDown()

		let fileManager = NSFileManager.defaultManager()
		try! fileManager.removeItemAtPath("testdata")
    }

    func testRemoveLocalizations() {
		let request = HelperRequest()
		request.dryRun = false
		request.uid = getuid()
		request.trash = false
		request.includes = [ testDir.path! ]
		request.excludes = [ testDir.URLByAppendingPathComponent("excluded.app").path! ]
		request.directories = [ "fr.lproj" ]
		request.bundleBlacklist = [ "com.test.blacklisted" ]

		let expectation = expectationWithDescription("Asynchronous helper processing")

		let helper = Helper()
		helper.processRequest(request, progress: nil) { (exitCode) -> Void in
			XCTAssert(exitCode == 0, "Helper should return with exit code 0")

			let fileManager = NSFileManager.defaultManager()
			XCTAssert(fileManager.fileExistsAtPath(self.testDir.URLByAppendingPathComponent("test.app/Contents/Resources/en.lproj/Localizable.strings").path!), "English localization should be untouched")
			XCTAssert(fileManager.fileExistsAtPath(self.testDir.URLByAppendingPathComponent("test.app/Contents/Resources/de.lproj/Localizable.strings").path!), "German localization app should be untouched")
			XCTAssert(!fileManager.fileExistsAtPath(self.testDir.URLByAppendingPathComponent("test.app/Contents/Resources/fr.lproj/Localizable.strings").path!), "French localization should have been removed")
			XCTAssert(fileManager.fileExistsAtPath(self.testDir.URLByAppendingPathComponent("excluded.app/Contents/Resources/en.lproj/Localizable.strings").path!), "excluded app should be untouched")
			XCTAssert(fileManager.fileExistsAtPath(self.testDir.URLByAppendingPathComponent("excluded.app/Contents/Resources/de.lproj/Localizable.strings").path!), "excluded app should be untouched")
			XCTAssert(fileManager.fileExistsAtPath(self.testDir.URLByAppendingPathComponent("excluded.app/Contents/Resources/fr.lproj/Localizable.strings").path!), "excluded app should be untouched")
			XCTAssert(fileManager.fileExistsAtPath(self.testDir.URLByAppendingPathComponent("blacklisted.app/Contents/Resources/en.lproj/Localizable.strings").path!), "excluded app should be untouched")
			XCTAssert(fileManager.fileExistsAtPath(self.testDir.URLByAppendingPathComponent("blacklisted.app/Contents/Resources/de.lproj/Localizable.strings").path!), "excluded app should be untouched")
			XCTAssert(fileManager.fileExistsAtPath(self.testDir.URLByAppendingPathComponent("blacklisted.app/Contents/Resources/fr.lproj/Localizable.strings").path!), "excluded app should be untouched")

			expectation.fulfill()
		}

		waitForExpectationsWithTimeout(NSTimeInterval(5.0)) { (error) -> Void in
			if let error = error {
				XCTFail("Expectation failed with error: \(error)")
			}
		}
    }

	private func assertFileSize(path: NSURL, expectedSize: Int, message: String) {
		do {
			let attributes = try NSFileManager.defaultManager().attributesOfItemAtPath(path.path!)
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
		request.excludes = [ testDir.URLByAppendingPathComponent("excluded.app").path! ]
		request.thin = [ "i386" ]
		request.bundleBlacklist = [ "com.test.blacklisted" ]

		let hello1Path = testDir.URLByAppendingPathComponent("hello1")
		let hello2Path = testDir.URLByAppendingPathComponent("hello2")
		let hello3Path = testDir.URLByAppendingPathComponent("hello3")
		assertFileSize(hello1Path, expectedSize: 4312, message: "non-fat file size mismatch")
		assertFileSize(hello2Path, expectedSize: 16600, message: "2-arch fat file size mismatch")
		assertFileSize(hello3Path, expectedSize: 24792, message: "3-arch fat file size mismatch")

		let expectation = expectationWithDescription("Asynchronous helper processing")

		let helper = Helper()
		helper.processRequest(request, progress: nil) { (exitCode) -> Void in
			XCTAssert(exitCode == 0, "Helper should return with exit code 0")

			let fileManager = NSFileManager.defaultManager()
			XCTAssert(fileManager.fileExistsAtPath(self.testDir.URLByAppendingPathComponent("hello1").path!), "non-fat file should be present")
			XCTAssert(fileManager.fileExistsAtPath(self.testDir.URLByAppendingPathComponent("hello2").path!), "2-arch fat file should be present")
			XCTAssert(fileManager.fileExistsAtPath(self.testDir.URLByAppendingPathComponent("hello3").path!), "3-arch fat file should be present")

			// should remain untouched
			self.assertFileSize(hello1Path, expectedSize: 4312, message: "non-fat file size mismatch after lipo")
			// should now be a thin (non-fat) file containing a single architecture
			self.assertFileSize(hello2Path, expectedSize: 4312, message: "2-arch fat file size mismatch after lipo")
			// should be a fat file containing two remaining architectures
			self.assertFileSize(hello3Path, expectedSize: 16600, message: "3-arch fat file size mismatch after lipo")

			expectation.fulfill()
		}

		waitForExpectationsWithTimeout(NSTimeInterval(5.0)) { (error) -> Void in
			if let error = error {
				XCTFail("Expectation failed with error: \(error)")
			}
		}
	}
}
