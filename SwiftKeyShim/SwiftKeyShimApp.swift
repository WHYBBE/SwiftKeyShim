import SwiftUI

@main
struct SwiftKeyShimApp: App {
    @StateObject private var settings: RemapSettings
    @StateObject private var remapper: KeyboardRemapper

    init() {
        let settings = RemapSettings()
        _settings = StateObject(wrappedValue: settings)
        _remapper = StateObject(wrappedValue: KeyboardRemapper(settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(remapper)
        }
        .windowResizability(.contentSize)
    }
}
