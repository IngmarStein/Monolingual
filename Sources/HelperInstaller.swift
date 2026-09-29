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
	static let daemonPlistName = HelperService.daemonPlistName

	/// The app version whose helper was registered last. Service Management requires the
	/// daemon to be registered again after its executable or property list has changed.
	private static let registeredVersionKey = "RegisteredHelperVersion"

	private let logger = Logger()

	/// Registers the helper daemon and verifies that it is allowed to run.
	func installIfNeeded() async throws {
		let service = SMAppService.daemon(plistName: Self.daemonPlistName)
		var status = service.status

		if isRegistered(status), UserDefaults.standard.string(forKey: Self.registeredVersionKey) != Self.appVersion {
			// The helper that ships with this version of the app is a different executable,
			// so the registration has to be renewed. A version that was never recorded counts
			// as a different one: the registration may be older, and it is only by registering
			// again that this app can be sure the daemon runs the helper from its bundle.
			logger.notice("Helper was updated, registering it again")
			try? await service.unregister()
			status = service.status
		}

		if !isRegistered(status) {
			do {
				try await register(service)
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

	/// How long to wait after a refused registration before trying it again.
	///
	/// The waits follow the one attempt that is made right away and add up to under four seconds,
	/// which is the order of time the helper that was unregistered takes to be gone.
	private static let registrationRetryDelays: [Duration] = [.milliseconds(250), .milliseconds(500), .seconds(1), .seconds(2)]

	/// Registers the daemon, trying again while the system refuses it.
	///
	/// Renewing a registration means unregistering the daemon first, and Service Management does
	/// not wait for the helper that was running to be reaped. Registering the daemon again right
	/// away is therefore refused — with `Operation not permitted`, because the job being replaced
	/// is still on its way out — while the very same call goes through a moment later, which is
	/// why the refusal is retried here instead of reported. The error the caller is left with is
	/// the one the last attempt ran into.
	private func register(_ service: SMAppService) async throws {
		for delay in Self.registrationRetryDelays {
			// A registration that went through all the same is not one to try again: a daemon
			// that is waiting for an administrator to allow it reports the error and the status
			// together, and the status is what the caller goes by.
			guard !isRegistered(service.status) else {
				return
			}

			do {
				try service.register()
				return
			} catch {
				logger.notice("Registering the helper was refused: \(error.localizedDescription, privacy: .public)")
				try? await Task.sleep(for: delay)
			}
		}

		try service.register()
	}

	/// Opens the System Settings pane where the helper daemon can be allowed.
	static func openSystemSettingsLoginItems() {
		SMAppService.openSystemSettingsLoginItems()
	}

	/// Forgets which app version registered the helper.
	///
	/// Called when the daemon turns out to be running a helper other than the one in this app
	/// bundle: the recorded version says the registration is this version's, which is exactly
	/// what keeps it from being renewed. Dropping the record makes the next attempt register
	/// the daemon again, which is the only way to get the bundled helper answering.
	static func forgetRegisteredVersion() {
		UserDefaults.standard.removeObject(forKey: registeredVersionKey)
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
