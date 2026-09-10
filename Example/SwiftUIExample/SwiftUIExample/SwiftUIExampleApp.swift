import SwiftUI
import CheqEnforce

@main
struct SwiftUIExampleApp: App {
    /// App-lifetime model: performs the initial Enforce.configure(), registers
    /// the onConsent handlers, and holds the state the UI renders (consent,
    /// log, inline results).
    @State private var model = SampleAppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
        }
    }
}
