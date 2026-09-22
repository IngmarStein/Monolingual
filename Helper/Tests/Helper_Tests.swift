//
//  Helper_Tests.swift
//  Helper Tests
//
//  Created by Ingmar Stein on 21.04.15.
//
//

import Cocoa
import XCTest
#if canImport(HelperShared)
import HelperShared
#endif

@MainActor class HelperTests: XCTestCase {
	nonisolated private var testDir: URL {
		URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true).appendingPathComponent("testdata")
	}

	nonisolated private var utilDir: URL {
		#if SWIFT_PACKAGE
		return Bundle.module.resourceURL!
		#else
		return Bundle(for: type(of: self)).resourceURL!
		#endif
	}

	nonisolated private func createTestApp(name: String, bundleIdentifier: String) {
		do {
			let appDir = testDir.appendingPathComponent("\(name).app")
			let localizableStringsData = Data(base64Encoded: "dGVzdA==", options: [])!
			let infoPlist = ["CFBundleIdentifier": bundleIdentifier] as NSDictionary
			let fileManager = FileManager.default

			try fileManager.createDirectory(at: appDir.appendingPathComponent("Contents/Resources/en.lproj"), withIntermediateDirectories: true, attributes: nil)
			try fileManager.createDirectory(at: appDir.appendingPathComponent("Contents/Resources/de.lproj"), withIntermediateDirectories: true, attributes: nil)
			try fileManager.createDirectory(at: appDir.appendingPathComponent("Contents/Resources/fr.lproj"), withIntermediateDirectories: true, attributes: nil)
			XCTAssert(fileManager.createFile(atPath: appDir.appendingPathComponent("Contents/Resources/en.lproj/Localizable.strings").path, contents: localizableStringsData, attributes: nil))
			XCTAssert(fileManager.createFile(atPath: appDir.appendingPathComponent("Contents/Resources/de.lproj/Localizable.strings").path, contents: localizableStringsData, attributes: nil))
			XCTAssert(fileManager.createFile(atPath: appDir.appendingPathComponent("Contents/Resources/fr.lproj/Localizable.strings").path, contents: localizableStringsData, attributes: nil))
			XCTAssert(infoPlist.write(to: appDir.appendingPathComponent("Contents/Info.plist"), atomically: false))
		} catch {
			XCTFail("Could not create test app: \(error)")
		}
	}

	override func setUp() {
		super.setUp()

		createTestApp(name: "test", bundleIdentifier: "com.test.test")
		createTestApp(name: "excluded", bundleIdentifier: "com.test.excluded")
		createTestApp(name: "blocklisted", bundleIdentifier: "com.test.blocklisted")

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
		} catch {
			XCTFail("Could not copy test data: \(error)")
		}
	}

	override func tearDown() {
		super.tearDown()

		let fileManager = FileManager.default
		do {
			try fileManager.removeItem(atPath: "testdata")
		} catch {
			// ignore
		}
	}

	func testRemoveLocalizations() {
		var request = HelperRequest()
		request.dryRun = false
		request.uid = getuid()
		request.trash = false
		request.includes = [testDir.path]
		request.excludes = [testDir.appendingPathComponent("excluded.app").path]
		request.directories = ["fr.lproj"]
		request.bundleBlocklist = ["com.test.blocklisted"]

		let helperExpectation = expectation(description: "Asynchronous helper processing")

		let helper = Helper()
		let progress = helper.process(request: request, report: nil) { exitCode -> Void in
			XCTAssert(exitCode == 0, "Helper should return with exit code 0")

			let fileManager = FileManager.default

			XCTAssert(fileManager.fileExists(atPath: self.testDir.appendingPathComponent("test.app/Contents/Resources/en.lproj/Localizable.strings").path), "English localization should be untouched")
			XCTAssert(fileManager.fileExists(atPath: self.testDir.appendingPathComponent("test.app/Contents/Resources/de.lproj/Localizable.strings").path), "German localization app should be untouched")
			XCTAssert(!fileManager.fileExists(atPath: self.testDir.appendingPathComponent("test.app/Contents/Resources/fr.lproj/Localizable.strings").path), "French localization should have been removed")
			XCTAssert(fileManager.fileExists(atPath: self.testDir.appendingPathComponent("excluded.app/Contents/Resources/en.lproj/Localizable.strings").path), "excluded app should be untouched")
			XCTAssert(fileManager.fileExists(atPath: self.testDir.appendingPathComponent("excluded.app/Contents/Resources/de.lproj/Localizable.strings").path), "excluded app should be untouched")
			XCTAssert(fileManager.fileExists(atPath: self.testDir.appendingPathComponent("excluded.app/Contents/Resources/fr.lproj/Localizable.strings").path), "excluded app should be untouched")
			XCTAssert(fileManager.fileExists(atPath: self.testDir.appendingPathComponent("blocklisted.app/Contents/Resources/en.lproj/Localizable.strings").path), "excluded app should be untouched")
			XCTAssert(fileManager.fileExists(atPath: self.testDir.appendingPathComponent("blocklisted.app/Contents/Resources/de.lproj/Localizable.strings").path), "excluded app should be untouched")
			XCTAssert(fileManager.fileExists(atPath: self.testDir.appendingPathComponent("blocklisted.app/Contents/Resources/fr.lproj/Localizable.strings").path), "excluded app should be untouched")

			helperExpectation.fulfill()
		}

		waitForExpectations(timeout: TimeInterval(5.0)) { error -> Void in
			if let error = error {
				XCTFail("Expectation failed with error: \(error)")
			}
		}

		XCTAssert(progress.fileCompletedCount == 1, "should have processed 1 file")
		XCTAssert(progress.totalUnitCount == Int64(4097), "totalUnitCount should be 4097")
		XCTAssert(progress.completedUnitCount == Int64(4096), "completedUnitCount should be 4096")
		XCTAssert(progress.userInfo[ProgressUserInfoKey.appName] as! String == "test", "app name should be 'test'")
		XCTAssert(progress.userInfo[ProgressUserInfoKey.sizeDifference] as! Int == 4096, "last process file should have changed by 4k bytes")
	}

	nonisolated private func assertFileSize(path: URL, expectedSize: Int, message: String) {
		do {
			let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
			let size = attributes[FileAttributeKey.size] as? Int
			XCTAssertEqual(size, expectedSize, message)
		} catch {
			XCTFail("Could not file size of '\(path)'")
		}
	}

	func testRemoveArchitectures() {
		var request = HelperRequest()
		request.dryRun = false
		request.uid = getuid()
		request.trash = false
		request.includes = [testDir.path]
		request.excludes = [testDir.appendingPathComponent("excluded.app").path]
		request.thin = ["i386"]
		request.bundleBlocklist = ["com.test.blocklisted"]

		let hello1Path = testDir.appendingPathComponent("hello1")
		let hello2Path = testDir.appendingPathComponent("hello2")
		let hello3Path = testDir.appendingPathComponent("hello3")
		assertFileSize(path: hello1Path, expectedSize: 4312, message: "non-fat file size mismatch")
		assertFileSize(path: hello2Path, expectedSize: 16600, message: "2-arch fat file size mismatch")
		assertFileSize(path: hello3Path, expectedSize: 24792, message: "3-arch fat file size mismatch")

		let helperExpectation = expectation(description: "Asynchronous helper processing")

		let helper = Helper()
		let progress = helper.process(request: request, report: nil) { exitCode -> Void in
			XCTAssert(exitCode == 0, "Helper should return with exit code 0")

			let fileManager = FileManager.default

			XCTAssert(fileManager.fileExists(atPath: self.testDir.appendingPathComponent("hello1").path), "non-fat file should be present")
			XCTAssert(fileManager.fileExists(atPath: self.testDir.appendingPathComponent("hello2").path), "2-arch fat file should be present")
			XCTAssert(fileManager.fileExists(atPath: self.testDir.appendingPathComponent("hello3").path), "3-arch fat file should be present")

			// should remain untouched
			self.assertFileSize(path: hello1Path, expectedSize: 4312, message: "non-fat file size mismatch after lipo")
			// should now be a thin (non-fat) file containing a single architecture
			self.assertFileSize(path: hello2Path, expectedSize: 4312, message: "2-arch fat file size mismatch after lipo")
			// should be a fat file containing two remaining architectures
			self.assertFileSize(path: hello3Path, expectedSize: 16600, message: "3-arch fat file size mismatch after lipo")

			helperExpectation.fulfill()
		}

		waitForExpectations(timeout: TimeInterval(5.0)) { error -> Void in
			if let error = error {
				XCTFail("Expectation failed with error: \(error)")
			}
		}

		XCTAssert(progress.fileCompletedCount == 2, "should have processed 2 files")
		XCTAssert(progress.totalUnitCount == Int64(20481), "totalUnitCount should be the size difference plus 1")
		XCTAssert(progress.completedUnitCount == Int64(20480), "should have removed 20480 bytes")
		XCTAssert(progress.userInfo[ProgressUserInfoKey.appName] == nil, "should not have an app name")
		XCTAssert(progress.userInfo[ProgressUserInfoKey.sizeDifference] as! Int == 8192, "should have removed 8k bytes")
	}

	/// The app and the helper exchange messages as JSON payloads in an XPC dictionary, and the
	/// helper reports progress and the result on an endpoint the app sends it. Reaching a
	/// running daemon takes an administrator's approval, but the transport itself can be
	/// exercised here, with a listener standing in for the app.
	func testWireRoundTrip() throws {
		var request = HelperRequest()
		request.dryRun = true
		request.trash = true
		request.uid = 501
		request.includes = ["/Applications", "/Library"]
		request.excludes = ["/Library/Logs"]
		request.directories = ["fr.lproj", "de.lproj"]
		request.bundleBlocklist = ["com.test.blocked"]
		request.thin = ["i386"]

		let replies: NSLock = NSLock()
		var received: [HelperReply] = []
		var requests: [HelperMessage] = []
		let reports = expectation(description: "progress, result and the request arrived")
		reports.expectedFulfillmentCount = 5

		let listener = XPCListener { incoming in
			incoming.accept { (dictionary: XPCDictionary) -> XPCDictionary? in
				if let reply = try? HelperWire.message(HelperReply.self, in: dictionary) {
					replies.lock()
					received.append(reply)
					replies.unlock()
					reports.fulfill()
					return nil
				}
				if let message = try? HelperWire.message(HelperMessage.self, in: dictionary) {
					replies.lock()
					requests.append(message)
					replies.unlock()
					reports.fulfill()
					return try? HelperWire.dictionary(for: HelperReply.accepted)
				}
				// An endpoint, which carries no message of its own.
				reports.fulfill()
				return nil
			}
		}

		// What the helper does with the endpoint the app sends it.
		let session = try XPCSession(endpoint: listener.endpoint)
		defer { session.cancel(reason: "test finished") }

		try session.send(message: HelperWire.dictionary(carrying: listener.endpoint))
		try session.send(message: HelperWire.dictionary(for: HelperMessage.version))
		try session.send(message: HelperWire.dictionary(for: HelperMessage.exit(0)))
		try session.send(message: HelperWire.dictionary(for: HelperReply.progress(file: "/Applications/Foo.app/Contents/Resources/fr.lproj", size: 4096, appName: "Foo")))
		try session.send(message: HelperWire.dictionary(for: HelperReply.finished(exitCode: 0)))

		// The request is what the helper is asked to do, so it has to survive the trip whole.
		let carried = try HelperWire.dictionary(for: HelperMessage.process(request))
		let decoded = try HelperWire.message(HelperMessage.self, in: carried)
		XCTAssertEqual(decoded, .process(request))

		waitForExpectations(timeout: TimeInterval(5.0)) { error in
			if let error = error {
				XCTFail("Expectation failed with error: \(error)")
			}
		}

		replies.lock()
		let gotReplies = received
		let gotRequests = requests
		replies.unlock()

		XCTAssertEqual(gotRequests, [.version, .exit(0)], "the messages the app sends should arrive")
		XCTAssertEqual(gotReplies, [
			.progress(file: "/Applications/Foo.app/Contents/Resources/fr.lproj", size: 4096, appName: "Foo"),
			.finished(exitCode: 0)
		], "the replies the helper sends should arrive")
	}
}
