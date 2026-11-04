# CurbLens — rules for Claude Code

## What this is
iOS app (SwiftUI) that reads Boston parking signs with the camera and tells
the user whether they can park now and when they must move. Fully on-device.

## Hard constraints
- $0 project: no paid services, no API keys, no network calls in the app.
- Apple frameworks only: Vision, AVFoundation, CoreImage, ImageIO,
  CoreMotion, CoreLocation, MapKit, SwiftData, UserNotifications, SwiftUI.
  Only third-party dependency allowed: swift-argument-parser (CLI only).
- iOS 17.0 deployment target; macOS 14 for the package and CLI.
- Swift 5 language mode.
- NEVER edit CurbLens.xcodeproj by hand. Edit project.yml, then run
  'xcodegen generate'. The .xcodeproj is git-ignored.
- CurbCore must not import UIKit or SwiftUI. Use CGImage at boundaries.
- All date logic takes an injected Calendar (time zone America/New_York).
  Never call Date() inside CurbCore logic; pass the time in.
- Git: never add Claude / AI co-author or attribution lines to commits or PRs.

## Commands
- Package tests:     swift test --package-path CurbCore
  (Tests use Swift Testing, not XCTest. With only Command Line Tools and no
  Xcode, add: -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing)
- Generate project:  xcodegen generate
- Simulator build:   xcodebuild -project CurbLens.xcodeproj -scheme CurbLens \
                       -destination 'platform=iOS Simulator,name=<NAME>' build
  (get <NAME> from: xcrun simctl list devices available)
- Read one image:    swift run --package-path CurbCore curbeval read <path>
                       [--fast] [--no-crop] [--no-lang-correction] [--no-fallback]
                       [--at 2026-11-10T09:00] [--save-crop /tmp/crop.png] [--neural-engine]
  (On macOS Vision runs on the CPU by default: a cold Neural Engine fails with
  "e5rtError ... 13" after every rebuild. iOS uses the Neural Engine with CPU fallback.)
- Skip photo tests:  SKIP_VISION=1 swift test --package-path CurbCore
- Run eval:          swift run --package-path CurbCore curbeval eval \
                       --dataset Dataset --out Reports

## Workflow
- Work only on the phase I give you. Write tests first for CurbCore logic.
- After every change run package tests AND the simulator build. Fix all
  failures before you stop.
- Each parser pattern gets a comment with an example sign string.
- Small, well-named types and functions. No force unwraps outside tests.
- Do not say a phase is done until every acceptance item passes; show me
  the test output.
