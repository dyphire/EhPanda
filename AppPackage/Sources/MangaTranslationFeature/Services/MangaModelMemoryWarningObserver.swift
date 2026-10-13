import UIKit

@MainActor
public final class MangaModelMemoryWarningObserver {
    public static let shared = MangaModelMemoryWarningObserver()

    private init() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task {
                await MangaTranslationService.shared.releaseModels()
            }
        }
    }
}
