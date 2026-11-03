# 《눈 감고 낚시》 iOS 앱

App Store 출시용 네이티브 iOS 앱입니다 (Swift · SwiftUI · AVAudioEngine · Core Haptics).
웹 프로토타입(`../web`)과 같은 규칙과 사운드 레시피를 Swift로 옮겼습니다.

## 빌드 방법 (Mac)

필요한 것: Xcode 15 이상, iOS 16 이상 기기, [XcodeGen](https://github.com/yonaskolb/XcodeGen)

```bash
brew install xcodegen
```

```bash
cd games/eyes-closed-fishing/ios && xcodegen generate && open EyesClosedFishing.xcodeproj
```

처음 한 번 `project.yml`의 `TODO` 세 곳을 바꾼 뒤 다시 `xcodegen generate` 하세요.

- `bundleIdPrefix`, `PRODUCT_BUNDLE_IDENTIFIER`: 본인 역도메인 (예: `kr.yourname.eyesclosedfishing`)
- `DEVELOPMENT_TEAM`: Apple Developer 팀 ID

게임 규칙·사운드 합성 테스트는 Xcode 없이도 돌릴 수 있습니다.

```bash
cd games/eyes-closed-fishing/ios/FishingCore && swift test
```

> 이 코드는 Swift 컴파일러가 없는 리눅스 환경에서 작성되어 아직 한 번도 빌드되지 않았습니다.
> 첫 빌드에서 사소한 컴파일 오류가 나올 수 있으니, 오류 메시지를 알려주시면 고치겠습니다.

## 구조

```
ios/
├── project.yml                    XcodeGen 프로젝트 정의 (Info.plist 포함)
├── FishingCore/                   UIKit 의존 없는 순수 Swift 패키지 → swift test 가능
│   ├── GameEngine.swift           상태 머신: 캐스팅·대기·챔질·릴링·결과, 튜토리얼 스크립트
│   ├── Species.swift              어종 5종 파라미터 (기획서 5.2)
│   ├── SaveData.swift             기록·설정 (Codable, 누락 키 기본값 처리)
│   ├── Synth.swift                바이쿼드 필터·PolyBLEP 오실레이터·오프라인 합성 버퍼
│   ├── SoundRecipes.swift         효과음 18종 레시피 (웹 버전과 동일)
│   └── RNG.swift                  시드 고정 가능한 난수 (테스트 재현용)
├── EyesClosedFishing/
│   ├── App/                       @main, 화면 상태(scenePhase) 처리
│   ├── Game/GameController.swift  엔진 ↔ 오디오·진동·음성·저장·화면 연결, 120Hz 프레임 루프
│   ├── Audio/AudioEngine.swift    AVAudioEngine 그래프, 효과음 뱅크, 덕킹, 리미터
│   ├── Audio/RealtimeSynths.swift 실시간 합성: 릴 래칫, 장력 마찰음, 느슨한 줄, 배경 물소리
│   ├── Services/                  음성 안내(AVSpeechSynthesizer), 진동(Core Haptics), 저장(UserDefaults)
│   ├── UI/                        시작 화면, 검은 플레이 화면, 터치 영역, 기록·설정 시트
│   └── Resources/                 앱 아이콘, 색상, 개인정보 매니페스트, 고운바탕 글꼴(OFL)
└── AppStore/metadata.md           스토어 등록 문구, 심사 메모, 개인정보·접근성 답변
```

## 웹 버전 대비 달라진 점 (앱이라서 가능한 것)

| 항목 | 내용 |
| --- | --- |
| 무음 스위치 | 오디오 세션 `.playback`으로 무음 모드에서도 소리가 남 (소리가 곧 화면인 게임) |
| 진동 | 아이폰에서도 동작. Core Haptics로 장력에 따라 세기가 연속으로 변하는 진동 |
| 지연 | IO 버퍼 5ms 요청, 입력 시각 기준 판정 (`press(at:)`) |
| 음성 | 기기의 한국어 음성 중 최고 품질(향상된 음성 설치 시 자동 사용) |
| VoiceOver | 게임 영역에 직접 조작(`allowsDirectInteraction`) 지정 → VoiceOver 사용자도 바로 플레이 |
| 중단 처리 | 전화·알람(오디오 인터럽션), 이어폰 분리, 백그라운드 전환 시 판을 조용히 취소 |
| 화면 | 플레이 중 자동 잠금 해제 방지, 상태 표시줄·홈 인디케이터 숨김 |
| 키보드 | iPad·Mac 키보드의 스페이스바(플레이), M(메뉴) |

## 출시 체크리스트

코드에 반영된 것

- [x] 개인정보 매니페스트 `PrivacyInfo.xcprivacy` (추적 없음, 수집 없음, UserDefaults 사유 CA92.1)
- [x] 수출 규정: `ITSAppUsesNonExemptEncryption = NO` (암호화 미사용)
- [x] 1024px 앱 아이콘 (알파 채널 없음), 런치 화면 색상
- [x] 세로 고정, iPhone 전용, 전체 화면
- [x] 서드파티 SDK·네트워크·계정 없음 → 개인정보 "데이터 수집 안 함"
- [x] 사용 글꼴 라이선스(OFL) 동봉 및 앱 내 표기

직접 해야 하는 것

- [ ] Apple Developer Program 가입, 번들 ID·팀 ID 입력
- [ ] 실제 기기에서 소리·진동 확인 후 어종 수치 튜닝 (`Species.swift`)
- [ ] App Store Connect에 앱 생성, `AppStore/metadata.md` 문구 입력
- [ ] 스크린샷 (6.9인치 필수): 시작 화면, 기록 시트, 연습용 장력 표시를 켠 플레이 화면
- [ ] TestFlight 내부 테스트 → 심사 제출
