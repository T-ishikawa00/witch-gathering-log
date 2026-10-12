import AppKit

@main
struct StoreKitLocalQAHost {
    static func main() {
        // XCTest host only. No production UI or network activity.
        NSApplication.shared.run()
    }
}
