import SwiftUI
import UIKit

/// 화면 전체가 하나의 버튼. 터치 시작/끝을 지연 없이 전달하고,
/// 두 손가락 1.5초 길게 누르기로 메뉴를 엽니다.
/// VoiceOver를 켠 사용자도 바로 플레이할 수 있도록 직접 조작(allowsDirectInteraction)을 허용합니다.
struct TouchSurface: UIViewRepresentable {
    var onPress: () -> Void
    var onRelease: () -> Void
    var onMenu: () -> Void

    func makeUIView(context: Context) -> TouchSurfaceView {
        let view = TouchSurfaceView()
        update(view)
        return view
    }

    func updateUIView(_ view: TouchSurfaceView, context: Context) {
        update(view)
    }

    private func update(_ view: TouchSurfaceView) {
        view.onPress = onPress
        view.onRelease = onRelease
        view.onMenu = onMenu
    }
}

final class TouchSurfaceView: UIView {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onMenu: (() -> Void)?

    private var down = false
    private var holdTask: Task<Void, Never>?
    private var keyDown = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .black
        isAccessibilityElement = true
        accessibilityLabel = "낚시터"
        accessibilityHint = "화면 아무 곳이나 터치해 낚싯줄을 던지고, 큰 물소리에 터치해 챔질하고, 길게 눌러 릴을 감습니다. 두 손가락으로 길게 누르면 기록과 설정이 열립니다."
        accessibilityTraits = [.allowsDirectInteraction]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func activeTouchCount(_ event: UIEvent?) -> Int {
        event?.allTouches?.filter { $0.phase != .ended && $0.phase != .cancelled }.count ?? 0
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if !down {
            down = true
            onPress?()
        }
        if activeTouchCount(event) >= 2 {
            holdTask?.cancel()
            holdTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled, let self else { return }
                self.down = false
                self.onRelease?()
                self.onMenu?()
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesFinished(event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesFinished(event)
    }

    private func touchesFinished(_ event: UIEvent?) {
        let remaining = activeTouchCount(event)
        if remaining < 2 {
            holdTask?.cancel()
            holdTask = nil
        }
        if remaining == 0 && down {
            down = false
            onRelease?()
        }
    }

    // MARK: 하드웨어 키보드 (iPad·Mac에서 스페이스바, M 키)

    override var canBecomeFirstResponder: Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { becomeFirstResponder() }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            switch press.key?.keyCode {
            case .keyboardSpacebar?:
                handled = true
                if !keyDown {
                    keyDown = true
                    onPress?()
                }
            case .keyboardM?:
                handled = true
                onMenu?()
            default:
                break
            }
        }
        if !handled { super.pressesBegan(presses, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { $0.key?.keyCode == .keyboardSpacebar }) {
            keyDown = false
            onRelease?()
        } else {
            super.pressesEnded(presses, with: event)
        }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if keyDown {
            keyDown = false
            onRelease?()
        }
        super.pressesCancelled(presses, with: event)
    }
}
