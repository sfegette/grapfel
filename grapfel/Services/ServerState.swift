import Foundation

@Observable
@MainActor
final class ServerState {
    static let shared = ServerState()

    enum Status: Equatable {
        case starting
        case running
        case binaryNotFound
        case startFailed(String)
    }

    var status: Status = .starting
    var apfelVersion: String? = nil
    var isUpdateBannerDismissed = false

    var isApfelOutdated: Bool {
        guard let version = apfelVersion else { return false }
        return !ServerState.meetsMinimumVersion(version, minimum: "1.3.3")
    }

    private init() {}

    // MARK: - Server lifecycle

    func retry() async {
        status = .starting
        do {
            try await ApfelServerManager.shared.start()
            apfelVersion = await ApfelServerManager.shared.serverVersion
            status = .running
        } catch ApfelError.binaryNotFound {
            status = .binaryNotFound
        } catch {
            status = .startFailed(error.localizedDescription)
        }
    }

    func restart() async {
        status = .starting
        isUpdateBannerDismissed = false
        await ApfelServerManager.shared.stop()
        try? await Task.sleep(for: .milliseconds(200))
        await retry()
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
