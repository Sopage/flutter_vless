import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // ВАЖНО: Мы намеренно НЕ переопределяем applicationDidFinishLaunching и не вызываем
  // super.applicationDidFinishLaunching(notification). В новых версиях FlutterMacOS
  // этот метод может отсутствовать в Objective-C реализации FlutterAppDelegate,
  // что приводило к крашу приложения "unrecognized selector sent to instance" при старте.
  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}

