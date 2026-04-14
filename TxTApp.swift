import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class TxTDocumentController: NSDocumentController {
    override func runModalOpenPanel(_ openPanel: NSOpenPanel, forTypes types: [String]?) -> Int {
        openPanel.allowedContentTypes = []
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        openPanel.allowsMultipleSelection = false
        openPanel.title = "Open"
        openPanel.prompt = "Open"
        openPanel.message = "Select a text file. All file types can be opened."
        return super.runModalOpenPanel(openPanel, forTypes: types)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        _ = TxTDocumentController()
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        CommandLine.arguments.count <= 1
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        var openedFromCommandLine = false
        for arg in CommandLine.arguments.dropFirst() {
            let url = URL(fileURLWithPath: arg)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            guard !isDir.boolValue else { continue }
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
            openedFromCommandLine = true
        }

        if !openedFromCommandLine, CommandLine.arguments.count <= 1, NSDocumentController.shared.documents.isEmpty {
            NSDocumentController.shared.newDocument(nil)
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            if NSDocumentController.shared.documents.isEmpty {
                NSDocumentController.shared.newDocument(nil)
            } else {
                for doc in NSDocumentController.shared.documents {
                    for wc in doc.windowControllers {
                        wc.window?.makeKeyAndOrderFront(nil)
                    }
                }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        return true
    }
}

private struct RecentRefreshHost: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var recentModel: RecentDocumentsModel

    var body: some View {
        EmptyView()
            .onChange(of: scenePhase) { phase in
                if phase == .active {
                    recentModel.refresh()
                }
            }
    }
}

@main
struct TxTApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var recentModel = RecentDocumentsModel()

    var body: some Scene {
        Settings {
            RecentRefreshHost()
                .environmentObject(recentModel)
        }
        .commands {
            TxTCommands(recentModel: recentModel)
        }
    }
}
