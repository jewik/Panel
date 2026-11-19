import AppKit

@MainActor
protocol PlaybackSourceOpening {
    @discardableResult
    func openPlaybackSource(_ source: PlaybackSource) -> Bool
}

@MainActor
struct WorkspacePlaybackSourceOpener: PlaybackSourceOpening {
    @discardableResult
    func openPlaybackSource(_ source: PlaybackSource) -> Bool {
        if let bundleIdentifier = source.preferredIdentifier {
            if let application = NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleIdentifier
            ).first {
                activate(application)
                return true
            }

            if let applicationURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleIdentifier
            ) {
                openApplication(at: applicationURL)
                return true
            }
        }

        guard let processIdentifier = source.processIdentifier,
              let application = NSRunningApplication(
                processIdentifier: processIdentifier
              ) else { return false }

        activate(application)
        return true
    }

    private func activate(_ application: NSRunningApplication) {
        application.unhide()

        if let applicationURL = application.bundleURL {
            openApplication(at: applicationURL)
        } else if #available(macOS 14.0, *) {
            application.activate()
        } else {
            application.activate(options: [
                .activateAllWindows,
                .activateIgnoringOtherApps,
            ])
        }
    }

    private func openApplication(at url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(
            at: url,
            configuration: configuration,
            completionHandler: nil
        )
    }
}
