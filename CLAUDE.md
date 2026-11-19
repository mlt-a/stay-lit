# Stay Lit

macOS menu bar app (SwiftUI, `MenuBarExtra`) that toggles `pmset -a disablesleep`.

- Code, comments, README and commits are in English. The UI is English only.
- Swift 6 language mode, strict concurrency. macOS 26.0 minimum.
- `StayLitCore/` is a local Swift package: all logic and its tests.
  - It imports only Foundation, Observation and IOKit. Never SwiftUI or AppKit.
  - Check: `grep -rh '^import ' StayLitCore/Sources | sort -u`
- `StayLit/` is the thin app target: entry point, views, composition.
- Xcode synchronized folders: adding a `.swift` file on disk is enough, no `project.pbxproj` edit.
- No test runs `sudo`, `pmset` or `osascript`. Go through protocols and test doubles.
- Call every executable by absolute path (`/usr/bin/pmset`, `/usr/bin/sudo`, `/usr/sbin/visudo`, `/usr/bin/osascript`).
- No em dash in UI text.
- The committed project has no `DEVELOPMENT_TEAM`. Put it in `Config/Local.xcconfig` (git ignores it).
- Commands:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test --package-path StayLitCore
xcodebuild build -scheme StayLit -destination 'platform=macOS'
```
