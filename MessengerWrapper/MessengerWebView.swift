import SwiftUI
import WebKit
import UserNotifications
import AppKit

struct MessengerWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        // 1) Konfiguracja WebView
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default() // trzyma cookies/sesję

        // Kanał JS -> native (badge/unread)
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "unreadCount")

        // 2) JS: odczyt "unread" co 5s i wysłanie do native
        // Heurystyka: próba z document.title + fallback (możesz dopracować selektory DOM)
        let js = """
        (function() {
          function parseUnreadFromTitle() {
            // Czasem tytuł wygląda jak "(3) Messenger" albo "Messenger (3)" — zależy od wdrożeń
            const t = document.title || "";
            const m1 = t.match(/^\\((\\d+)\\)/);
            if (m1) return parseInt(m1[1], 10);
            const m2 = t.match(/\\((\\d+)\\)\\s*$/);
            if (m2) return parseInt(m2[1], 10);
            return 0;
          }

          function tick() {
            const unread = parseUnreadFromTitle();
            try {
              window.webkit.messageHandlers.unreadCount.postMessage({ unread });
            } catch (e) {}
          }

          // start
          tick();
          setInterval(tick, 5000);
        })();
        """

        let userScript = WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        contentController.addUserScript(userScript)
        config.userContentController = contentController

        // 3) WebView
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        // Opcjonalnie: sensowny UA (czasem pomaga, gdy serwis wykrywa "in-app browser")
        // webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

        // 4) Load
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
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

        // MARK: - WKNavigationDelegate
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            requestNotificationsIfNeeded()
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

        // MARK: - WKScriptMessageHandler (JS -> native)
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "unreadCount",
                  let dict = message.body as? [String: Any],
                  let unread = dict["unread"] as? Int else { return }

            updateDockBadge(unread)

            // Notyfikacja tylko, gdy licznik rośnie (prosta heurystyka)
            if unread > lastUnread {
                sendNotification(unread: unread)
            }
            lastUnread = unread
        }

        // MARK: - Dock badge
        private func updateDockBadge(_ unread: Int) {
            DispatchQueue.main.async {
                NSApp.dockTile.badgeLabel = unread > 0 ? "\(unread)" : nil
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
