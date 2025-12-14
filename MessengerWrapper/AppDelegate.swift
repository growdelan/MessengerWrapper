import Cocoa
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private weak var mainWindow: NSWindow?
    private var unreadObserver: NSObjectProtocol?
    private let statusItemBaseTitle = "💬"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Aplikacja ma działać dalej po zamknięciu ostatniego okna
        // NSApp.setActivationPolicy(.accessory) // tylko menu bar, bez ikony w Docku
        // Jeśli chcesz ZOSTAWIĆ ikonę w Docku, zakomentuj linię wyżej.

        setupStatusItem()
        startUnreadObserver()
        hookMainWindowWhenReady()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // Przechwytujemy "zamknięcie" okna: zamiast zamknąć, chowamy
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    private func hookMainWindowWhenReady() {
        // Okno pojawia się chwilę po starcie — łapiemy je async
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let window = NSApp.windows.first {
                self.mainWindow = window
                window.delegate = self
            }
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.title = statusItemBaseTitle  // możesz podmienić na ikonę SF Symbols

        let menu = NSMenu()

        let show = NSMenuItem(title: "Pokaż Messenger", action: #selector(showApp), keyEquivalent: "")
        show.target = self
        menu.addItem(show)

        menu.addItem(NSMenuItem.separator())

        let quit = NSMenuItem(title: "Zakończ", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem?.menu = menu
    }

    private func startUnreadObserver() {
        unreadObserver = NotificationCenter.default.addObserver(
            forName: .messengerWrapperUnreadCountDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let unread = (notification.userInfo?["unread"] as? Int) ?? 0
            self.updateStatusItemTitle(unread: unread)
        }
    }

    private func updateStatusItemTitle(unread: Int) {
        statusItem?.button?.title = unread > 0 ? "\(statusItemBaseTitle) \(unread)" : statusItemBaseTitle
    }

    @objc private func showApp() {
        NSApp.setActivationPolicy(.regular) // żeby okno mogło się aktywować
        NSApp.activate(ignoringOtherApps: true)

        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
        } else {
            // fallback: jeśli nie mamy referencji, spróbujmy wziąć pierwsze okno
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
