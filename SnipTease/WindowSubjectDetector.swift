import AppKit
import CoreGraphics

// MARK: - Window Subject Detection
// Finds the frontmost app window on the current screen so the initial guide
// frame can compose around real content instead of arbitrary empty space.

enum WindowSubjectDetector {

    static func frontmostWindowRect(
        on screen: NSScreen,
        excludingBundleID: String?
    ) -> CGRect? {
        guard let windowList = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
              ) as? [[String: Any]] else {
            return nil
        }

        let currentPID = ProcessInfo.processInfo.processIdentifier

        for windowInfo in windowList {
            guard let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID != currentPID,
                  let layer = windowInfo[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let alpha = windowInfo[kCGWindowAlpha as String] as? Double,
                  alpha > 0.01,
                  let boundsDictionary = windowInfo[kCGWindowBounds as String] as? NSDictionary,
                  let globalBounds = CGRect(dictionaryRepresentation: boundsDictionary),
                  globalBounds.width > 80,
                  globalBounds.height > 80 else {
                continue
            }

            if let bundleID = excludingBundleID,
               let ownerName = windowInfo[kCGWindowOwnerName as String] as? String,
               ownerName.localizedCaseInsensitiveContains(bundleID) {
                continue
            }

            let screenBounds = screen.frame
            let visibleBounds = globalBounds.intersection(screenBounds)
            guard !visibleBounds.isNull, visibleBounds.width > 80, visibleBounds.height > 80 else {
                continue
            }

            return CGRect(
                x: visibleBounds.minX - screenBounds.minX,
                y: screenBounds.maxY - visibleBounds.maxY,
                width: visibleBounds.width,
                height: visibleBounds.height
            )
        }

        return nil
    }
}
