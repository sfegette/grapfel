import Foundation

@Observable
@MainActor
final class ServerState {
    static let shared = ServerState()

    enum Status: Equatable {
        case starting
        case running
        case homebrewNotFound
        case binaryNotFound
        case binaryInvalid(String)
        case startFailed(String)
    }

    var status: Status = .starting
    var apfelVersion: String? = nil
    var availableApfelVersion: String? = nil
    var isUpdateBannerDismissed = false
    var hotKeyRegistrationMessage: String? = nil
    var isPrewarmed: Bool = false

    var isApfelOutdated: Bool {
        guard let version = apfelVersion else { return false }
        return !ServerState.meetsMinimumVersion(version, minimum: "1.3.3")
    }

    var isApfelUpdateAvailable: Bool {
        guard let installed = apfelVersion, let available = availableApfelVersion else { return false }
        return ServerState.meetsMinimumVersion(available, minimum: installed) && available != installed
    }

    var needsApfelUpdate: Bool { isApfelOutdated || isApfelUpdateAvailable }

    private init() {}

    // MARK: - Server lifecycle

    func retry() async {
        status = .starting
        isPrewarmed = false
        do {
            try await ApfelServerManager.shared.start()
            apfelVersion = await ApfelServerManager.shared.serverVersion
            isPrewarmed = await ApfelServerManager.shared.isPrewarmed
            status = .running
            availableApfelVersion = await HomebrewInstaller.latestAvailableVersion()
            if !isPrewarmed { startPrewarmPoller() }
        } catch ApfelError.binaryNotFound {
            status = SetupChecker.isHomebrewInstalled() ? .binaryNotFound : .homebrewNotFound
        } catch ApfelError.binaryInvalid(let reason) {
            status = .binaryInvalid(reason)
        } catch {
            status = .startFailed(error.localizedDescription)
        }
    }

    func restart() async {
        status = .starting
        isPrewarmed = false
        isUpdateBannerDismissed = false
        await ApfelServerManager.shared.stop()
        try? await Task.sleep(for: .milliseconds(200))
        await retry()
    }

    private func startPrewarmPoller() {
        Task { @MainActor [weak self] in
            while let self, !self.isPrewarmed {
                try? await Task.sleep(for: .milliseconds(750))
                if await ApfelServerManager.shared.healthCheck() {
                    self.isPrewarmed = await ApfelServerManager.shared.isPrewarmed
                }
            }
        }
    }

    func upgradeApfel() async {
        do {
            try await HomebrewInstaller.upgrade { _ in }
            await restart()
        } catch {
            // Upgrade failed — leave state unchanged so the banner stays visible.
        }
    }

    // MARK: - Version comparison

    private static func meetsMinimumVersion(_ version: String, minimum: String) -> Bool {
        let parts: (String) -> [Int] = {
            $0.split(separator: ".").compactMap { Int($0) }
        }
        let v = parts(version)
        let m = parts(minimum)
        for i in 0..<max(v.count, m.count) {
            let vi = i < v.count ? v[i] : 0
            let mi = i < m.count ? m[i] : 0
            if vi != mi { return vi > mi }
        }
        return true
    }
}
