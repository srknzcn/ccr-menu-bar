import SwiftUI

@main
struct CCRMenuBarApp: App {
    var body: some Scene {
        MenuBarExtra("CCR", systemImage: "arrow.triangle.branch") {
            Text("CCR Menu Bar")
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
