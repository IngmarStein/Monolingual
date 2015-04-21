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

	private var testDir: String {
		return NSFileManager.defaultManager().currentDirectoryPath.stringByAppendingPathComponent("testdata")
	}
    
    override func setUp() {
        super.setUp()

		let localizableStringsData = NSData(base64EncodedString: "dGVzdA==", options: .allZeros)!
		let fileManager = NSFileManager.defaultManager()

		fileManager.createDirectoryAtPath(testDir.stringByAppendingPathComponent("test.app/Contents/Resources/en.lproj"), withIntermediateDirectories: true, attributes: nil, error: nil)
		fileManager.createDirectoryAtPath(testDir.stringByAppendingPathComponent("test.app/Contents/Resources/de.lproj"), withIntermediateDirectories: true, attributes: nil, error: nil)
		fileManager.createDirectoryAtPath(testDir.stringByAppendingPathComponent("test.app/Contents/Resources/fr.lproj"), withIntermediateDirectories: true, attributes: nil, error: nil)
		fileManager.createFileAtPath(testDir.stringByAppendingPathComponent("test.app/Contents/Resources/en.lproj/Localizable.strings"), contents: localizableStringsData, attributes: nil)
		fileManager.createFileAtPath(testDir.stringByAppendingPathComponent("test.app/Contents/Resources/de.lproj/Localizable.strings"), contents: localizableStringsData, attributes: nil)
		fileManager.createFileAtPath(testDir.stringByAppendingPathComponent("test.app/Contents/Resources/fr.lproj/Localizable.strings"), contents: localizableStringsData, attributes: nil)

		fileManager.createDirectoryAtPath(testDir.stringByAppendingPathComponent("excluded.app/Contents/Resources/en.lproj"), withIntermediateDirectories: true, attributes: nil, error: nil)
		fileManager.createDirectoryAtPath(testDir.stringByAppendingPathComponent("excluded.app/Contents/Resources/de.lproj"), withIntermediateDirectories: true, attributes: nil, error: nil)
		fileManager.createDirectoryAtPath(testDir.stringByAppendingPathComponent("excluded.app/Contents/Resources/fr.lproj"), withIntermediateDirectories: true, attributes: nil, error: nil)
		fileManager.createFileAtPath(testDir.stringByAppendingPathComponent("excluded.app/Contents/Resources/en.lproj/Localizable.strings"), contents: localizableStringsData, attributes: nil)
		fileManager.createFileAtPath(testDir.stringByAppendingPathComponent("excluded.app/Contents/Resources/de.lproj/Localizable.strings"), contents: localizableStringsData, attributes: nil)
		fileManager.createFileAtPath(testDir.stringByAppendingPathComponent("excluded.app/Contents/Resources/fr.lproj/Localizable.strings"), contents: localizableStringsData, attributes: nil)
	}

    override func tearDown() {
        super.tearDown()

		let fileManager = NSFileManager.defaultManager()
		fileManager.removeItemAtPath("testdata", error: nil)
    }

    func testRemoveLocalizations() {
		let request = HelperRequest()
		request.dryRun = false
		request.uid = getuid()
		request.trash = false
		request.includes = [ testDir ]
		request.excludes = [ testDir.stringByAppendingPathComponent("excluded.app") ]
		request.directories = [ "fr.lproj" ]

		let expectation = expectationWithDescription("Asynchronous helper processing")

		let helper = Helper()
		helper.processRequest(request, progress: nil) { (exitCode) -> Void in
			XCTAssert(exitCode == 0, "Helper should return with exit code 0")

			let fileManager = NSFileManager.defaultManager()
			XCTAssert(fileManager.fileExistsAtPath(self.testDir.stringByAppendingPathComponent("test.app/Contents/Resources/en.lproj/Localizable.strings")), "English localization should be untouched")
			XCTAssert(fileManager.fileExistsAtPath(self.testDir.stringByAppendingPathComponent("test.app/Contents/Resources/de.lproj/Localizable.strings")), "German localization app should be untouched")
			XCTAssert(!fileManager.fileExistsAtPath(self.testDir.stringByAppendingPathComponent("test.app/Contents/Resources/fr.lproj/Localizable.strings")), "French localization should have been removed")
			XCTAssert(fileManager.fileExistsAtPath(self.testDir.stringByAppendingPathComponent("excluded.app/Contents/Resources/en.lproj/Localizable.strings")), "excluded app should be untouched")
			XCTAssert(fileManager.fileExistsAtPath(self.testDir.stringByAppendingPathComponent("excluded.app/Contents/Resources/de.lproj/Localizable.strings")), "excluded app should be untouched")
			XCTAssert(fileManager.fileExistsAtPath(self.testDir.stringByAppendingPathComponent("excluded.app/Contents/Resources/fr.lproj/Localizable.strings")), "excluded app should be untouched")

			expectation.fulfill()
		}

		waitForExpectationsWithTimeout(NSTimeInterval(5.0)) { (error) -> Void in
			if let error = error {
				XCTFail("Expectation failed with error: \(error)")
			}
		}
    }
}
