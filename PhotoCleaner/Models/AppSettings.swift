import Foundation

struct AppSettings: Codable {
    var backupGraceDays: Int
    var generateContactSheet: Bool
    var keepAlbumName: String  // コンタクトシート保存先
    var protectedAlbumNames: [String]  // 保護するアルバム（削除対象外）

    static let `default` = AppSettings(
        backupGraceDays: 730,  // 2年
        generateContactSheet: true,
        keepAlbumName: "Keep",
        protectedAlbumNames: ["Keep"]  // デフォルトでKeepを保護
    )
}

@MainActor
final class AppSettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet {
            save()
        }
    }

    private static let key = "AppSettings"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = .default
        }
    }

    private func save() {
        if let encoded = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(encoded, forKey: Self.key)
        }
    }

    func reset() {
        settings = .default
    }
}
