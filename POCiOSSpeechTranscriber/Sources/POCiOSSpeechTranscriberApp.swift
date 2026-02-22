import SwiftUI

@main
struct POCiOSSpeechTranscriberApp: App {
    var body: some Scene {
        WindowGroup {
            EntryView()
                .preferredColorScheme(.light)
        }
    }
}
