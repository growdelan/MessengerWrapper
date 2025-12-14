import SwiftUI
import WebKit
import UserNotifications
import AppKit

struct MessengerWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default() // trzyma cookies/sesję

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.attach(webView: webView)

        // Opcjonalnie: sensowny UA (czasem pomaga, gdy serwis wykrywa "in-app browser")
        // webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private weak var webView: WKWebView?
        private var pollTimer: Timer?
        private var lastUnread: Int = 0
        private var notificationPermissionAsked = false
        private let allowedHosts: Set<String> = [
            "www.messenger.com",
            "messenger.com",
            "www.facebook.com",
            "facebook.com",
            "static.xx.fbcdn.net",   // czasem zasoby
            "scontent.xx.fbcdn.net"  // czasem zasoby
        ]

        deinit {
            pollTimer?.invalidate()
        }

        func attach(webView: WKWebView) {
            self.webView = webView
        }

        // MARK: - WKNavigationDelegate
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            requestNotificationsIfNeeded()
            startUnreadPollingIfNeeded()
        }

        // MARK: - WKUIDelegate (otwieranie nowych okienek jako nowe karty/okna)
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {

            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            // Pozwól na wewnętrzne/techniczne schematy
            let scheme = url.scheme?.lowercased() ?? ""
            if scheme == "about" || scheme == "blob" || scheme == "data" {
                decisionHandler(.allow)
                return
            }

            // Jeśli to NIE jest kliknięcie w link, nie wypychaj do Safari
            // (redirecty, window.open, przeładowania, nawigacje aplikacji)
            if navigationAction.navigationType != .linkActivated {
                decisionHandler(.allow)
                return
            }

            // Tylko dla klikniętych linków decyduj "zewnętrzne -> Safari"
            guard let host = url.host?.lowercased() else {
                decisionHandler(.allow)
                return
            }

            if !allowedHosts.contains(host) {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        // MARK: - Unread polling (native)
        private func startUnreadPollingIfNeeded() {
            guard pollTimer == nil else { return }
            guard let webView else { return }

            let timer = Timer(timeInterval: 5.0, repeats: true) { [weak self, weak webView] _ in
                guard let self, let webView else { return }
                self.pollUnreadCount(using: webView)
            }
            pollTimer = timer
            RunLoop.main.add(timer, forMode: .common)

            pollUnreadCount(using: webView)
        }

        private func pollUnreadCount(using webView: WKWebView) {
            webView.evaluateJavaScript("document.title") { [weak self] result, _ in
                guard let self else { return }
                guard let title = result as? String else { return }
                let unread = self.parseUnreadFromTitle(title)
                self.handleUnreadUpdate(unread)
            }
        }

        private func parseUnreadFromTitle(_ title: String) -> Int {
            let nsRange = NSRange(title.startIndex..<title.endIndex, in: title)

            if let match = Self.leadingUnreadRegex.firstMatch(in: title, range: nsRange),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: title) {
                return Int(title[range]) ?? 0
            }

            if let match = Self.trailingUnreadRegex.firstMatch(in: title, range: nsRange),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: title) {
                return Int(title[range]) ?? 0
            }

            return 0
        }

        private func handleUnreadUpdate(_ unread: Int) {
            updateDockBadge(unread)
            NotificationCenter.default.post(
                name: .messengerWrapperUnreadCountDidChange,
                object: nil,
                userInfo: ["unread": unread]
            )

            if unread > lastUnread {
                sendNotification(unread: unread)
            }
            lastUnread = unread
        }

        private static let leadingUnreadRegex = try! NSRegularExpression(pattern: #"^\((\d+)\)"#)
        private static let trailingUnreadRegex = try! NSRegularExpression(pattern: #"\((\d+)\)\s*$"#)

        // MARK: - Dock badge
        private func updateDockBadge(_ unread: Int) {
            DispatchQueue.main.async {
                NSApp.dockTile.badgeLabel = unread > 0 ? "\(unread)" : nil
                NSApp.dockTile.display()
            }
        }

        // MARK: - Notifications
        private func requestNotificationsIfNeeded() {
            guard !notificationPermissionAsked else { return }
            notificationPermissionAsked = true

            let center = UNUserNotificationCenter.current()
            center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
                // nic - użytkownik zdecyduje w System Settings
            }
        }

        private func sendNotification(unread: Int) {
            let content = UNMutableNotificationContent()
            content.title = "Messenger"
            content.body = "Masz \(unread) nieprzeczytane wiadomości."
            content.sound = .default

            // Bez triggera = praktycznie od razu
            let request = UNNotificationRequest(identifier: UUID().uuidString,
                                                content: content,
                                                trigger: nil)
            UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        }
    }
}
