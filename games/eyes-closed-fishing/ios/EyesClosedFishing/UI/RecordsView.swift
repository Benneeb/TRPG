import FishingCore
import SwiftUI

/// 기록·도감·설정 시트 (기획서 7.2, 9.2)
struct RecordsView: View {
    @EnvironmentObject private var game: GameController
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingReset = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                totals
                dex
                HStack(spacing: 10) {
                    Button("기록 듣기") { game.speakRecords() }
                        .buttonStyle(GhostButtonStyle())
                    Button("튜토리얼 다시 하기") { game.replayTutorial() }
                        .buttonStyle(GhostButtonStyle())
                }
                settings
                Button("기록 초기화") { confirmingReset = true }
                    .buttonStyle(GhostButtonStyle(tint: Theme.bobber))
                    .confirmationDialog("모든 포획 기록이 지워집니다.", isPresented: $confirmingReset, titleVisibility: .visible) {
                        Button("기록 지우기", role: .destructive) { game.resetRecords() }
                        Button("취소", role: .cancel) {}
                    }
                licenses
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 22)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.pond.ignoresSafeArea())
        .foregroundStyle(Theme.mist)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack {
            Text("낚시 기록")
                .font(Theme.display(26, relativeTo: .title))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button("닫고 계속하기") { dismiss() }
                .buttonStyle(GhostButtonStyle())
        }
    }

    private var totals: some View {
        let st = game.save.stats
        let rate = st.totalCasts > 0 ? "\(Int((Double(st.totalCatches) / Double(st.totalCasts) * 100).rounded()))%" : "–"
        return HStack(alignment: .top, spacing: 8) {
            stat("던진 횟수", "\(st.totalCasts)")
            stat("잡은 물고기", "\(st.totalCatches)")
            stat("성공률", rate)
            stat("퍼펙트 챔질", "\(st.perfectHooks)")
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(Theme.dim)
            Text(value).font(Theme.display(22, relativeTo: .title2)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var dex: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("도감")
            ForEach(Species.all, id: \.id) { sp in
                let rec = game.save.record(for: sp.id)
                let known = rec.count > 0
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(known ? sp.name : "???")
                            .font(Theme.display(17, relativeTo: .body))
                            .foregroundStyle(known ? Theme.mist : Theme.dim)
                        Text(sp.grade)
                            .font(.caption2)
                            .foregroundStyle(sp.isGold ? Theme.warn : Theme.dim)
                    }
                    Spacer()
                    Text(known ? "\(rec.count)마리" : "–")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.dim)
                    Text(known ? "최대 \(rec.maxSize)cm" : "")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.dim)
                        .frame(minWidth: 76, alignment: .trailing)
                }
                .padding(.vertical, 11)
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(known ? "\(sp.name), \(sp.grade), \(rec.count)마리, 최대 \(rec.maxSize)센티미터" : "아직 발견하지 못한 \(sp.grade) 물고기")
            }
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel("설정")
            SliderRow(title: "물소리 · 자연음", value: game.binding(\.bgmVolume))
            SliderRow(title: "효과음", value: game.binding(\.sfxVolume))
            SliderRow(title: "음성 안내", value: game.binding(\.voiceVolume)) { editing in
                if !editing { game.previewVoiceVolume() }
            }
            ToggleRow(title: "실패 음성 힌트", detail: "왜 놓쳤는지 말로 알려줍니다", isOn: game.binding(\.failHint))
            ToggleRow(title: "진동", detail: nil, isOn: game.binding(\.haptics))
            ToggleRow(title: "두 번 탭해서 던지기", detail: "주머니 속 오작동 방지", isOn: game.binding(\.doubleTapCast))
            ToggleRow(title: "음성 자막", detail: nil, isOn: game.binding(\.captions))
            ToggleRow(title: "연습용 장력 표시", detail: "화면에 장력과 거리를 보여줍니다", isOn: game.binding(\.assist))
        }
    }

    private var licenses: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("정보")
            Text("모든 효과음은 기기에서 실시간으로 합성됩니다. 기록은 이 기기에만 저장되며 어디에도 전송되지 않습니다.")
            Text("글꼴: 고운바탕 (Gowun Batang) · SIL Open Font License 1.1")
            if let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                Text("버전 \(v)")
            }
        }
        .font(.footnote)
        .foregroundStyle(Theme.dim)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .tracking(1.6)
            .foregroundStyle(Theme.reed)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Float
    var onEditingChanged: (Bool) -> Void = { _ in }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Slider(value: $value, in: 0...1, onEditingChanged: onEditingChanged)
                .frame(width: 150)
                .tint(Theme.reed)
                .accessibilityLabel(title)
        }
    }
}

private struct ToggleRow: View {
    let title: String
    let detail: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(Theme.dim)
                }
            }
        }
        .tint(Theme.reed)
    }
}

struct GhostButtonStyle: ButtonStyle {
    var tint: Color = Theme.mist

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .foregroundStyle(tint)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .overlay(Capsule().stroke(tint == Theme.mist ? Theme.line : tint))
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Capsule())
    }
}
