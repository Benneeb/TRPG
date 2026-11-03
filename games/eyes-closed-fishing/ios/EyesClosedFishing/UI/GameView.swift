import FishingCore
import SwiftUI

/// 플레이 화면: 완전한 검은 화면. 자막·연습용 표시·메뉴 버튼만 희미하게 겹칩니다.
struct GameView: View {
    @EnvironmentObject private var game: GameController

    var body: some View {
        ZStack {
            Theme.night.ignoresSafeArea()
            TouchSurface(
                onPress: { game.press() },
                onRelease: { game.release() },
                onMenu: { game.openMenu() }
            )
            .ignoresSafeArea()

            VStack {
                HStack(alignment: .top) {
                    if game.save.settings.assist { AssistPanel() }
                    Spacer()
                    Button("기록 · 설정") { game.openMenu() }
                        .font(.footnote)
                        .foregroundStyle(Theme.dim)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .overlay(Capsule().stroke(Theme.line))
                        .opacity(0.7)
                        .accessibilityHint("진행 중인 낚시는 취소됩니다")
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                Spacer()
                Text(game.caption)
                    .font(Theme.display(19, relativeTo: .title3))
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .foregroundStyle(Theme.mist)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                    .opacity(game.captionVisible ? 0.82 : 0)
                    .animation(.easeInOut(duration: 0.4), value: game.captionVisible)
                    .allowsHitTesting(false)
                    // 음성 안내가 같은 내용을 읽으므로 VoiceOver에는 숨김
                    .accessibilityHidden(true)
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }
}

/// 연습용 장력·거리 표시 (설정에서 켬)
struct AssistPanel: View {
    @EnvironmentObject private var game: GameController

    private var stateLabel: String {
        switch game.phase {
        case .boot: return ""
        case .intro: return "안내 중"
        case .idle: return "던질 준비"
        case .casting: return "던지는 중"
        case .waiting: return "입질 기다리는 중"
        case .bite: return "챔질!"
        case .reeling: return "릴링"
        case .caught: return "포획"
        case .failed: return "실패"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(stateLabel)
            Text("장력")
            Meter(value: min(100, game.assistTension) / 100, marks: [0.6, 0.85], color: tensionColor)
            Text("남은 거리")
            Meter(value: game.assistDistance / 100, marks: [], color: Theme.reed)
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(Theme.dim)
        .frame(width: 180)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var tensionColor: Color {
        let t = game.assistTension
        return t >= 85 ? Theme.bobber : (t >= 60 ? Theme.warn : Theme.reed)
    }
}

struct Meter: View {
    var value: Double
    var marks: [Double]
    var color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.line)
                Capsule().fill(color).frame(width: geo.size.width * max(0, min(1, value)))
                ForEach(marks, id: \.self) { m in
                    Rectangle().fill(Theme.dim).frame(width: 1).offset(x: geo.size.width * m)
                }
            }
        }
        .frame(height: 6)
    }
}
