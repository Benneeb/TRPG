import SwiftUI

@main
struct EyesClosedFishingApp: App {
    @StateObject private var game = GameController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(game)
                .preferredColorScheme(.dark)
                .task { await game.prepare() }
        }
        .onChange(of: scenePhase) { newPhase in
            game.scenePhaseChanged(newPhase)
        }
    }
}
