import SwiftUI

/// 웹 프로토타입과 같은 팔레트: 밤의 낚시터. 단일 다크 테마.
enum Theme {
    static let night = Color.black                                  // 플레이 화면 (OLED 절전)
    static let pond = Color(red: 0.020, green: 0.043, blue: 0.047)  // 시작 화면·시트 바탕
    static let mist = Color(red: 0.804, green: 0.843, blue: 0.831)  // 본문
    static let dim = Color(red: 0.455, green: 0.518, blue: 0.498)   // 보조 글자
    static let line = Color(red: 0.102, green: 0.145, blue: 0.149)  // 구분선
    static let reed = Color(red: 0.498, green: 0.659, blue: 0.561)  // 안전 장력, 강조
    static let warn = Color(red: 0.851, green: 0.643, blue: 0.255)  // 주의 장력
    static let bobber = Color(red: 1.0, green: 0.353, blue: 0.212)  // 찌 끝 형광 주황, 위험

    /// 제목·자막용 명조 (Gowun Batang, OFL). 시스템 글자 크기 설정을 따름.
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom("GowunBatang-Bold", size: size, relativeTo: style)
    }
}
