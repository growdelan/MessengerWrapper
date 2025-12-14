# Repository Guidelines

## Projekt – struktura i moduły
Repozytorium to natywna aplikacja macOS w SwiftUI. Kod źródłowy znajduje się w `MessengerWrapper/` i obejmuje:
- `MessengerWrapperApp.swift` – punkt startowy oraz konfiguracja okna.
- `AppDelegate.swift` – logika paska menu, obsługa okna i zakończenia aplikacji.
- `ContentView.swift` i `MessengerWebView.swift` – widok główny oraz wrapper WebKit z obsługą badge i powiadomień.
- `Notifications.swift` – wspólne nazwy powiadomień (np. zmiana licznika nieprzeczytanych).
- `Assets.xcassets` – zasoby graficzne, w tym `MenuBarIcon.imageset` dla paska menu (template image + licznik tekstowy).  
Konfiguracja: `MessengerWrapper.xcodeproj`; testy w `MessengerWrapperTests/` (target XCTest).

## Budowa, testy i rozwój
- Xcode: `open MessengerWrapper.xcodeproj`, scheme `MessengerWrapper`, build/run (`⌘B`/`⌘R`).
- CLI: `xcodebuild -project MessengerWrapper.xcodeproj -scheme MessengerWrapper -configuration Debug -destination 'platform=macOS' -derivedDataPath ./_DerivedData build`.
- Testy (po dodaniu targetu): `xcodebuild -project MessengerWrapper.xcodeproj -scheme MessengerWrapper -destination 'platform=macOS' test`.

## Styl kodu i nazewnictwo
- Swift: wcięcia 4 spacje, unikanie siły unwrapowania.
- Typy w `UpperCamelCase`, właściwości/funkcje w `lowerCamelCase`; plik = typ wiodący.
- Komentarze zwięzłe, opisują „dlaczego”; język wg kontekstu.
- Brak lint/format; używaj Xcode „Re-Indent”/„Format” przed commitem.

## Wytyczne testów
- Dodawaj testy jednostkowe w XCTest dla nowej logiki (np. parsowanie licznika nieprzeczytanych, routing URLi). Pliki nazywaj `NazwaKlasTests.swift`.
- Testy asynchroniczne oznaczaj `async` i używaj oczekiwań (`XCTestExpectation`) dla operacji WebKit/Notification.
- Utrzymuj szybkie, hermetyczne testy; unikaj zależności od sieci zewnętrznej.

## Commit i pull requesty
- Historia używa krótkich tytułów (np. „add: git ignore”); preferuj tryb rozkazujący i prefiksy (`add:`, `fix:`, `chore:`) gdy to porządkuje zakres.
- PR: krótki opis, motywacja/problem, kroki weryfikacji (build/test), zrzuty ekranu przy zmianach UI.
- Linkuj zadania/issue; zaznacz znane ograniczenia/regresje.

## Uwagi platformowe i bezpieczeństwo
- Aplikacja korzysta z WebKit, powiadomień i badge Docka; pamiętaj o aktualizacji `allowedHosts` w `MessengerWebView.swift` przy zmianach routingu.
- Licznik nieprzeczytanych jest odświeżany natywnie (polling `document.title`) i rozsyłany przez `NotificationCenter` (`messengerWrapper.unreadCountDidChange`) do UI status bar oraz Dock badge.
- Ikona paska menu to template `MenuBarIcon` z asset catalogu; liczba nieprzeczytanych dodawana jest w tytule obok ikony (status item ma `variableLength`).
- WebKit może logować ostrzeżenia o braku entitlements dla “WebKit Media Playback” — zazwyczaj są nieszkodliwe, o ile nie używasz rozmów audio/wideo.
- Nie commituj prywatnych tokenów ani danych logowania; cookies i sesje są trzymane lokalnie w `WKWebsiteDataStore.default()`.
- Przy zmianach polityki powiadomień lub ikon status bar zadbaj o zachowanie dotychczasowego UX (status bar + okno możliwe do ukrycia).
