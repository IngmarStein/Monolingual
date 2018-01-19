protocol ScanfileProtocol: class {
  var workspace: String? { get }
  var project: String? { get }
  var device: String? { get }
  var toolchain: String? { get }
  var devices: [String]? { get }
  var scheme: String? { get }
  var clean: Bool { get }
  var codeCoverage: Bool? { get }
  var addressSanitizer: Bool? { get }
  var threadSanitizer: Bool? { get }
  var skipBuild: Bool { get }
  var outputDirectory: String { get }
  var outputStyle: String? { get }
  var outputTypes: String { get }
  var outputFiles: String? { get }
  var buildlogPath: String { get }
  var includeSimulatorLogs: Bool { get }
  var formatter: String? { get }
  var testWithoutBuilding: Bool? { get }
  var buildForTesting: Bool? { get }
  var xctestrun: String? { get }
  var derivedDataPath: String? { get }
  var resultBundle: String? { get }
  var sdk: String? { get }
  var openReport: Bool { get }
  var configuration: String? { get }
  var destination: String? { get }
  var xcargs: String? { get }
  var xcconfig: String? { get }
  var onlyTesting: String? { get }
  var skipTesting: String? { get }
  var slackUrl: String? { get }
  var slackChannel: String? { get }
  var slackMessage: String? { get }
  var skipSlack: Bool { get }
  var slackOnlyOnFailure: Bool { get }
  var useClangReportName: Bool { get }
  var customReportFileName: String? { get }
  var failBuild: Bool { get }
}

extension ScanfileProtocol {
  var workspace: String? { return nil }
  var project: String? { return nil }
  var device: String? { return nil }
  var toolchain: String? { return nil }
  var devices: [String]? { return nil }
  var scheme: String? { return nil }
  var clean: Bool { return false }
  var codeCoverage: Bool? { return nil }
  var addressSanitizer: Bool? { return nil }
  var threadSanitizer: Bool? { return nil }
  var skipBuild: Bool { return false }
  var outputDirectory: String { return "./test_output" }
  var outputStyle: String? { return nil }
  var outputTypes: String { return "html,junit" }
  var outputFiles: String? { return nil }
  var buildlogPath: String { return "~/Library/Logs/scan" }
  var includeSimulatorLogs: Bool { return false }
  var formatter: String? { return nil }
  var testWithoutBuilding: Bool? { return nil }
  var buildForTesting: Bool? { return nil }
  var xctestrun: String? { return nil }
  var derivedDataPath: String? { return nil }
  var resultBundle: String? { return nil }
  var sdk: String? { return nil }
  var openReport: Bool { return false }
  var configuration: String? { return nil }
  var destination: String? { return nil }
  var xcargs: String? { return nil }
  var xcconfig: String? { return nil }
  var onlyTesting: String? { return nil }
  var skipTesting: String? { return nil }
  var slackUrl: String? { return nil }
  var slackChannel: String? { return nil }
  var slackMessage: String? { return nil }
  var skipSlack: Bool { return false }
  var slackOnlyOnFailure: Bool { return false }
  var useClangReportName: Bool { return false }
  var customReportFileName: String? { return nil }
  var failBuild: Bool { return true }
}


// Please don't remove the lines below
// They are used to detect outdated files
// FastlaneRunnerAPIVersion [0.9.1]
