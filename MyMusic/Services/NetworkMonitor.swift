import Foundation
import Network
import Observation

/// Следит, есть ли интернет: без сети доступны только скачанные треки.
@MainActor
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var isOnline = true
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            Task { @MainActor in NetworkMonitor.shared.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "network.monitor"))
    }
}
