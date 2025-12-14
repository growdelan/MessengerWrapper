import SwiftUI

struct ContentView: View {
    var body: some View {
        MessengerWebView(url: URL(string: "https://www.messenger.com")!)
            .ignoresSafeArea()
    }
}
