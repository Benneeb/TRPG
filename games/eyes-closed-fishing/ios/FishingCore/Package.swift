// swift-tools-version:5.9
import PackageDescription

// 게임 규칙과 사운드 합성 레시피. UIKit/AVFoundation에 의존하지 않으므로
// macOS·Linux에서 `swift test`로 단독 검증할 수 있습니다.
let package = Package(
    name: "FishingCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "FishingCore", targets: ["FishingCore"]),
    ],
    targets: [
        .target(name: "FishingCore"),
        .testTarget(name: "FishingCoreTests", dependencies: ["FishingCore"]),
    ]
)
