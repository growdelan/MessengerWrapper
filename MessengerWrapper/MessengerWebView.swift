import SwiftUI
import WebKit
import UserNotifications
import AppKit

struct MessengerWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default() // trzyma cookies/sesję

        // Event-driven unread count: JS -> native (WKScriptMessageHandler)
        let ucc = WKUserContentController()
        ucc.add(context.coordinator, name: Coordinator.unreadMessageHandlerName)

        let script = WKUserScript(
            source: Coordinator.unreadObserverUserScriptSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: .page
        )
        ucc.addUserScript(script)
        config.userContentController = ucc

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

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        private weak var webView: WKWebView?
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

        static let unreadMessageHandlerName = "mwUnreadCount"

        deinit {
            // Bezpiecznie usuń handler (WKUserContentController trzyma strong ref do handlera)
            webView?.configuration.userContentController.removeScriptMessageHandler(forName: Self.unreadMessageHandlerName)
        }

        func attach(webView: WKWebView) {
            self.webView = webView
        }

        // MARK: - WKNavigationDelegate
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            requestNotificationsIfNeeded()
            // Zamiast pollingu: unread przychodzi event-driven z WKUserScript.
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

        // MARK: - WKScriptMessageHandler (event-driven unread)
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == Self.unreadMessageHandlerName else { return }

            var unread: Int?
            var titleFallback: String?

            if let dict = message.body as? [String: Any] {
                if let v = dict["unread"] as? Int {
                    unread = v
                } else if let v = dict["unread"] as? Double {
                    unread = Int(v)
                } else if let v = dict["unread"] as? String {
                    unread = Int(v)
                }

                if let t = dict["title"] as? String {
                    titleFallback = t
                }
            } else if let v = message.body as? Int {
                unread = v
            } else if let v = message.body as? Double {
                unread = Int(v)
            } else if let v = message.body as? String {
                unread = Int(v)
            }

            let finalUnread: Int
            if let unread {
                finalUnread = max(0, unread)
            } else if let titleFallback {
                finalUnread = parseUnreadFromTitle(titleFallback)
            } else {
                return
            }

            handleUnreadUpdate(finalUnread)
        }

        // MARK: - Unread parsing (fallback / compatibility)
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
            // Unikaj zbędnych cykli/odświeżeń gdy nic się nie zmieniło
            guard unread != lastUnread else { return }

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

        // MARK: - Injected JS (MutationObserver -> postMessage)
        static let unreadObserverUserScriptSource: String = """
        (function () {
          'use strict';

          const HANDLER = '\(Coordinator.unreadMessageHandlerName)';

          function parseUnread(title) {
            if (!title) return 0;

            // "(3) Messenger"
            let m = title.match(/^\\((\\d+)\\)/);
            if (m && m[1]) return parseInt(m[1], 10) || 0;

            // "Messenger (3)"
            m = title.match(/\\((\\d+)\\)\\s*$/);
            if (m && m[1]) return parseInt(m[1], 10) || 0;

            return 0;
          }

          let lastSent = null;
          let titleObserver = null;
          let observedTitleEl = null;
          let headObserver = null;

          function post(unread, title) {
            try {
              const mh = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers[HANDLER];
              if (!mh || !mh.postMessage) return;

              // prosta deduplikacja po stronie JS
              if (lastSent === unread) return;
              lastSent = unread;

              mh.postMessage({ unread: unread, title: title });
            } catch (_) {}
          }

          function emitFromDocumentTitle() {
            try {
              const title = document.title || '';
              const unread = parseUnread(title);
              post(unread, title);
            } catch (_) {}
          }

          function attachToTitleEl() {
            const titleEl = document.querySelector('title');
            if (!titleEl) return false;

            if (titleEl === observedTitleEl) return true;

            observedTitleEl = titleEl;

            if (titleObserver) {
              try { titleObserver.disconnect(); } catch (_) {}
            }

            titleObserver = new MutationObserver(function () {
              emitFromDocumentTitle();
            });

            try {
              titleObserver.observe(titleEl, { childList: true, subtree: true, characterData: true });
            } catch (_) {}

            return true;
          }

          function ensureHeadObserver() {
            if (headObserver) return;

            const target = document.head || document.documentElement;
            if (!target) return;

            headObserver = new MutationObserver(function () {
              // jeśli <title> zostało podmienione — podepnij obserwator ponownie
              attachToTitleEl();
            });

            try {
              headObserver.observe(target, { childList: true, subtree: true });
            } catch (_) {}
          }

          function start() {
            // pierwsza emisja (żeby badge od razu się ustawił)
            emitFromDocumentTitle();

            // obserwuj zmiany tytułu
            attachToTitleEl();
            ensureHeadObserver();

            // fallback: jeśli <title> jeszcze nie ma, spróbuj po załadowaniu DOM
            if (!observedTitleEl) {
              document.addEventListener('DOMContentLoaded', function () {
                attachToTitleEl();
                ensureHeadObserver();
                emitFromDocumentTitle();
              }, { once: true });
            }
          }

          start();
        })();
        """
    }
}

