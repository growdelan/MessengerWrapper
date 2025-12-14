# Repository Guidelines

## Projekt – struktura i moduły
Repozytorium to natywna aplikacja macOS w SwiftUI. Kod źródłowy znajduje się w `MessengerWrapper/` i obejmuje:
- `MessengerWrapperApp.swift` – punkt startowy oraz konfiguracja okna.
- `AppDelegate.swift` – logika paska menu, obsługa okna i zakończenia aplikacji.
- `ContentView.swift` i `MessengerWebView.swift` – widok główny oraz wrapper WebKit z obsługą badge i powiadomień.
- `Assets.xcassets` – zasoby graficzne.  
Konfiguracja projektu jest w `MessengerWrapper.xcodeproj`. Brak obecnie katalogu testów; nowe testy umieszczaj w `MessengerWrapperTests/` tworząc osobny target XCTest.

## Budowa, testy i rozwój
- Uruchomienie w Xcode: `open MessengerWrapper.xcodeproj`, wybierz scheme `MessengerWrapper`, Build (`⌘B`) lub Run (`⌘R`) na platformie macOS.
- Build z CLI: `xcodebuild -project MessengerWrapper.xcodeproj -scheme MessengerWrapper -configuration Debug -destination 'platform=macOS' build`.
- Testy (po dodaniu targetu testowego): `xcodebuild -project MessengerWrapper.xcodeproj -scheme MessengerWrapper -destination 'platform=macOS' test`.
- Szybkie podglądy SwiftUI: preferuj Xcode Previews tam, gdzie to możliwe.

## Styl kodu i nazewnictwo
- Swift styl domyślny: wcięcia 4 spacje, linie zwięzłe, unikanie siły unwrapowania.
- Nazwy typów w `UpperCamelCase`, właściwości i funkcje w `lowerCamelCase`; pliki nazwij jak typ wiodący.
- Komentarze krótkie, opisują „dlaczego”. Zachowuj istniejący język komentarzy (PL/EN) według kontekstu pliku.
- Brak skonfigurowanego lint/format; używaj Xcode „Re-Indent”/„Format” przed commitem.

## Wytyczne testów
- Dodawaj testy jednostkowe w XCTest dla nowej logiki (np. parsowanie licznika nieprzeczytanych, routing URLi). Pliki nazywaj `NazwaKlasTests.swift`.
- Testy asynchroniczne oznaczaj `async` i używaj oczekiwań (`XCTestExpectation`) dla operacji WebKit/Notification.
- Utrzymuj szybkie, hermetyczne testy; unikaj zależności od sieci zewnętrznej.

## Commit i pull requesty
- Obecna historia używa zwięzłych tytułów (np. „add: git ignore”, „Initial Commit”). Preferuj tryb rozkazujący i krótkie prefiksy zakresu (`add:`, `fix:`, `chore:`) gdy pomaga.
- Każdy PR powinien zawierać: krótki opis zmiany, motywację/problem, kroki weryfikacji (komenda build/test), oraz zrzuty ekranu UI jeśli zmieniasz interfejs.
- Linkuj do powiązanych zadań/issue i wspomnij o ewentualnych regresjach lub ograniczeniach.

## Uwagi platformowe i bezpieczeństwo
- Aplikacja korzysta z WebKit, powiadomień i badge Docka; pamiętaj o aktualizacji `allowedHosts` w `MessengerWebView.swift` przy zmianach routingu.
- Nie commituj prywatnych tokenów ani danych logowania; cookies i sesje są trzymane lokalnie w `WKWebsiteDataStore.default()`.
- Przy zmianach polityki powiadomień lub ikon status bar zadbaj o zachowanie dotychczasowego UX (status bar + okno możliwe do ukrycia).
