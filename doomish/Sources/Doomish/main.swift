import AppKit

// Entry point. A plain executable (rather than NSApplicationMain) lets the
// simulation-only paths run without a window server round trip; --input is the
// one headless path that does build a real window, to test the event chain.
if CommandLine.arguments.contains("--armyprobe") { _probe(); fflush(stdout); exit(0) }
let headless = ["--selftest", "--probe", "--ascii", "--stress", "--logic"].contains { CommandLine.arguments.contains($0) }
if headless {
    SelfTest.run()
    exit(0)
} else if CommandLine.arguments.contains("--input") {
    SelfTest.runInputTest()
} else {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.regular)
    application.run()
}
