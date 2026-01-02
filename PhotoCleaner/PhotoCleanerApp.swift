import SwiftUI

@main
struct PhotoCleanerApp: App {
    @StateObject private var settingsStore = AppSettingsStore()

    var body: some Scene {
        WindowGroup {
            MainView(settingsStore: settingsStore)
        }
    }
}
