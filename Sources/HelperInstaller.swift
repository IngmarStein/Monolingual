//
//  HelperInstaller.swift
//  Monolingual
//
//  Copyright © 2026 Ingmar Stein. All rights reserved.
//

import Foundation
import OSLog
import ServiceManagement
#if canImport(HelperShared)
import HelperShared
#endif

/// A reason why the privileged helper is not available.
enum HelperInstallationFailure: Error {
	/// The daemon is registered but an administrator has not allowed it in System Settings yet.
	case requiresApproval
	/// The launchd property list is missing from the app bundle.
	case plistNotFound
	/// A helper from a different version of Monolingual answered instead of the bundled one.
	case outdatedHelper(String)
	/// The registered helper did not answer at all.
	case helperUnreachable
	/// Registering the daemon failed.
	case registrationFailed(Error)

	var title: String {
		switch self {
		case .requiresApproval:
			NSLocalizedString("Monolingual needs your permission", comment: "")
		case .plistNotFound, .registrationFailed:
			NSLocalizedString("Failed to install helper utility.", comment: "")
		case .outdatedHelper:
			NSLocalizedString("An outdated helper utility is still installed.", comment: "")
		case .helperUnreachable:
			NSLocalizedString("Monolingual cannot reach its helper utility.", comment: "")
		}
	}

	var message: String {
		switch self {
		case .requiresApproval:
			NSLocalizedString("Allow Monolingual to use its helper tool in System Settings › General › Login Items & Extensions, then try again.", comment: "")
		case .plistNotFound:
			NSLocalizedString("The Monolingual application bundle is incomplete.", comment: "")
		case let .outdatedHelper(version):
			String(format: NSLocalizedString("Monolingual %@ is still installed. Remove it with util/uninstall.sh, then try again.", comment: ""), version)
		case .helperUnreachable:
			NSLocalizedString("A helper utility from an older version of Monolingual may still be registered. Restart your Mac and try again.", comment: "")
		case let .registrationFailed(error):
			error.localizedDescription
		}
	}

	var canOpenSystemSettings: Bool {
		if case .requiresApproval = self {
			return true
		}
		return false
	}
}

/// Registers the privileged helper with Service Management.
///
/// Older versions installed the helper with SMJobBless, which copied it to
/// `/Library/PrivilegedHelperTools` and asked for an administrator password on first use.
/// The helper now lives inside the app bundle and is registered as a launchd daemon with
/// `SMAppService`, so an administrator allows it in System Settings instead. A helper left
/// behind by the older versions is not touched: it serves a Mach service of its own name, so it
/// does not get in the way, and `util/uninstall.sh` removes it.
@MainActor
final class HelperInstaller {
	static let machServiceName = HelperService.machServiceName
	static let daemonPlistName = HelperService.daemonPlistName

	/// The app version whose helper was registered last. Service Management requires the
	/// daemon to be registered again after its executable or property list has changed.
	private static let registeredVersionKey = "RegisteredHelperVersion"

	private let logger = Logger()

	/// Registers the helper daemon and verifies that it is allowed to run.
	func installIfNeeded() async throws {
		let service = SMAppService.daemon(plistName: Self.daemonPlistName)
		var status = service.status

		if isRegistered(status), let registeredVersion = UserDefaults.standard.string(forKey: Self.registeredVersionKey), registeredVersion != Self.appVersion {
			// The helper that ships with this version of the app is a different executable,
			// so the registration has to be renewed.
			logger.notice("Helper was updated, registering it again")
			try? await service.unregister()
			status = service.status
		}

		if isRegistered(status) {
			// Another copy of the app may have registered the helper before.
			UserDefaults.standard.set(Self.appVersion, forKey: Self.registeredVersionKey)
		} else {
			do {
				try service.register()
			} catch {
				// A daemon stays unapproved until an administrator allows it in System Settings;
				// that is reported through the service status rather than as a registration error.
				guard isRegistered(service.status) else {
					logger.error("Failed to register helper: \(error.localizedDescription, privacy: .public)")
					throw HelperInstallationFailure.registrationFailed(error)
				}
			}
			UserDefaults.standard.set(Self.appVersion, forKey: Self.registeredVersionKey)
			status = service.status
		}

		switch status {
		case .enabled:
			return
		case .requiresApproval:
			throw HelperInstallationFailure.requiresApproval
		case .notRegistered, .notFound:
			throw HelperInstallationFailure.plistNotFound
		@unknown default:
			throw HelperInstallationFailure.plistNotFound
		}
	}

	/// Opens the System Settings pane where the helper daemon can be allowed.
	static func openSystemSettingsLoginItems() {
		SMAppService.openSystemSettingsLoginItems()
	}

	private func isRegistered(_ status: SMAppService.Status) -> Bool {
		status == .enabled || status == .requiresApproval
	}

	/// The version of the running app, which the bundled helper reports as its own because
	/// it lives inside the app bundle.
	static var appVersion: String {
		Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
	}
}
