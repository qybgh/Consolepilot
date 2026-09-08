import AppKit
import Foundation

@main
@MainActor
struct ConsolepilotMain {
    private static let appDelegate = AppDelegate()

    static func main() {
        let application = NSApplication.shared
        application.delegate = appDelegate
        application.setActivationPolicy(.regular)
        ApplicationMenu.install()
        application.activate(ignoringOtherApps: true)
        application.run()
    }
}
