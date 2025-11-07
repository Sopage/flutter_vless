import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    GeneratedPluginRegistrant.register(with: self)
    super.applicationDidFinishLaunching(notification)
  }
  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
  return true
}
}

