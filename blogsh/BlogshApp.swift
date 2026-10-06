import SwiftUI

@main
struct BlogshApp: App {
    init() {
        // Before the first screen is drawn: the faces it is set in.
        Typeface.register()
    }

    var body: some Scene {
        WindowGroup {
            // Under its tests the app is only a host: no screen, and so no
            // connection to anybody's blog.
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
                Color.clear
            } else {
                ContentView().modifier(TextSized())
            }
        }
    }
}
