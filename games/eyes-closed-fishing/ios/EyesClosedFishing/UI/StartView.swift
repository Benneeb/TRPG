import SwiftUI

/// 시작 화면: 찌와 물결 위에 게임 소개와 조작법
struct StartView: View {
    @EnvironmentObject private var game: GameController

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Theme.pond.ignoresSafeArea()
            RippleView()
                .ignoresSafeArea()
                .accessibilityHidden(true)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Spacer(minLength: 220)
                    Text("이어폰 권장 · 소리만으로 플레이")
                        .font(.caption)
                        .tracking(1.6)
                        .foregroundStyle(Theme.reed)
                    Text("눈 감고 낚시")
                        .font(Theme.display(52, relativeTo: .largeTitle))
                        .foregroundStyle(Theme.mist)
                        .accessibilityAddTraits(.isHeader)
                    Text("화면에는 아무것도 없습니다. 물소리와 입질 소리, 낚싯줄이 우는 소리만 듣고 손가락 하나로 낚시하세요.")
                        .font(.body)
                        .lineSpacing(6)
                        .foregroundStyle(Theme.mist.opacity(0.86))
                        .fixedSize(horizontal: false, vertical: true)
                    controls
                    startButton
                    Text("무음 모드에서도 소리가 납니다. 다른 앱의 음악은 잠시 멈춥니다.")
                        .font(.footnote)
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 560, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().overlay(Theme.line)
            controlRow("짧게 터치", Text("낚싯줄 던지기 · ") + Text("촤박!").foregroundColor(Theme.bobber) + Text(" 소리에 챔질"))
            controlRow("길게 누르기", Text("릴 감기 (드르륵)"))
            controlRow("손 떼기", Text("끼이익").foregroundColor(Theme.bobber) + Text(" 소리가 높아지면 바로"))
        }
    }

    private func controlRow(_ label: String, _ value: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.dim)
                .frame(width: 96, alignment: .leading)
            value
                .font(.body)
                .foregroundStyle(Theme.mist)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var startButton: some View {
        Button {
            game.startGame()
        } label: {
            HStack(spacing: 10) {
                if !game.audioReady { ProgressView().tint(Theme.night) }
                Text(game.audioReady ? "시작하기" : "소리 준비 중")
                    .font(.headline)
            }
            .foregroundStyle(Theme.night)
            .padding(.horizontal, 30)
            .padding(.vertical, 15)
            .background(Capsule().fill(Theme.mist))
        }
        .disabled(!game.audioReady)
        .accessibilityHint("소리만으로 진행되는 낚시를 시작합니다")
    }
}

/// 찌 하나와 천천히 퍼지는 물결
struct RippleView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            Canvas { ctx, size in
                let t = context.date.timeIntervalSinceReferenceDate
                let cx = size.width * 0.7
                let cy = size.height * (size.height < 700 ? 0.22 : 0.3)
                let maxR = max(size.width, size.height) * 0.55
                let rings = 5
                for i in 0..<rings {
                    let p = reduceMotion ? (Double(i) + 0.5) / Double(rings)
                                         : (t / 5.2 + Double(i) / Double(rings)).truncatingRemainder(dividingBy: 1)
                    let r = 14 + p * maxR
                    let rect = CGRect(x: cx - r, y: cy - r * 0.32, width: r * 2, height: r * 0.64)
                    ctx.stroke(Path(ellipseIn: rect), with: .color(Theme.mist.opacity(0.22 * (1 - p))), lineWidth: 1)
                }
                let bob = reduceMotion ? 0 : sin(t / 0.9) * 1.5
                ctx.fill(Path(ellipseIn: CGRect(x: cx - 3.2, y: cy - 19 + bob, width: 6.4, height: 18)), with: .color(Theme.bobber))
                ctx.fill(Path(ellipseIn: CGRect(x: cx - 3.2, y: cy - 2 + bob, width: 6.4, height: 6)), with: .color(Theme.mist.opacity(0.9)))
            }
        }
    }
}
