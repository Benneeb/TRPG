import SwiftUI

struct RootView: View {
    @EnvironmentObject private var game: GameController

    var body: some View {
        Group {
            if game.started {
                GameView()
            } else {
                StartView()
            }
        }
        .sheet(isPresented: $game.showingMenu, onDismiss: { game.menuDidClose() }) {
            RecordsView()
                .environmentObject(game)
        }
    }
}
