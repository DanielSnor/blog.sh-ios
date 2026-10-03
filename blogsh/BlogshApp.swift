import SwiftUI

@main
struct BlogshApp: App {
    init() {
        // Before the first screen is drawn: the faces it is set in.
        Typeface.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
