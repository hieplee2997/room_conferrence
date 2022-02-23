import Cocoa
import Sparkle
import FlutterMacOS

@NSApplicationMain
class AppDelegate: FlutterAppDelegate, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    var updateController: SPUStandardUpdaterController?
    
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }
    override func applicationDidFinishLaunching(_ notification: Notification) {
        updateController = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        updateController?.startUpdater()
    }
    
    @IBAction func checkForUpdate(_ sender: Any) {
        updateController?.checkForUpdates(self)
    }
}
