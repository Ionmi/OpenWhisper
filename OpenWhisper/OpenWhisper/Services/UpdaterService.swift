import Foundation
import Sparkle
import Combine

@Observable
final class UpdaterService {
    private var updaterController: SPUStandardUpdaterController?
    @ObservationIgnored private var cancellable: AnyCancellable?

    private(set) var canCheckForUpdates = false

    var isEnabled: Bool { updaterController != nil }

    init() {
        #if !DEBUG
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        updaterController = controller
        cancellable = controller.updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] value in
                self?.canCheckForUpdates = value
            }
        #endif
    }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }

    var automaticallyChecksForUpdates: Bool {
        get { updaterController?.updater.automaticallyChecksForUpdates ?? false }
        set { updaterController?.updater.automaticallyChecksForUpdates = newValue }
    }
}
