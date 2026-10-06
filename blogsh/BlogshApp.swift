import SwiftUI

@main
struct BlogshApp: App {
    init() {
        // Before the first screen is drawn: the faces it is set in.
        Typeface.register()
        // On a Mac the bars light up under the mouse with a ground and a
        // rule of their own, over paper that has neither: they stay bare.
        if ProcessInfo.processInfo.isiOSAppOnMac {
            let bare = UINavigationBarAppearance()
            bare.configureWithTransparentBackground()
            let bars = UINavigationBar.appearance()
            bars.standardAppearance = bare
            bars.compactAppearance = bare
            bars.scrollEdgeAppearance = bare
            bars.compactScrollEdgeAppearance = bare
        }
    }

    var body: some Scene {
        WindowGroup {
            // Under its tests the app is only a host: no screen, and so no
            // connection to anybody's blog.
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
                Color.clear
            } else {
                ContentView().modifier(TextSized())
                    .scrollEdgeEffectHidden(ProcessInfo.processInfo.isiOSAppOnMac, for: .top)
            }
        }
    }
}
