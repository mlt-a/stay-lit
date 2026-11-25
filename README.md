# Stay Lit

**Close your MacBook. Your Claude Code agents keep working.**

You started a long Claude Code task and need to leave. Close the lid, and macOS puts the Mac to sleep and your agents stop. Stay Lit is a menu bar switch that keeps the Mac awake with the lid closed. It locks the screen, watches your sessions, and can put the Mac to sleep once Claude Code is done.

Under the hood it toggles `pmset -a disablesleep`. That needs root, so Stay Lit installs a narrow sudoers rule once. Read [Security](#security) before you install it.

## Features

- **One switch.** Blocks or allows sleep. "Close me. I stay lit." or "Close me and I sleep."
- **Agent lights.** One light per Claude Code session: green while it works, amber while it waits for you. A warning shows if agents are working and the lid would put them to sleep.
- **Lock on close.** Closing the lid while sleep is blocked locks the session. The Mac keeps running behind the lock screen.
- **Sleep when Claude is done** (off by default). Once every session is idle and the lid is closed, the Mac goes to sleep: after 1 minute, or 10 minutes if a session waits for your answer.
- **Timer.** Until turned off, 1 h, 2 h or 4 h.
- **Back on after sleep.** When Stay Lit allowed sleep by itself (Claude done, timer, battery, heat) and the Mac slept, it turns back on when you unlock the Mac. Low battery or heat: it waits until you plug in or the Mac cools down. Turning the switch off cancels it.
- **Guards.** Sleep comes back when the battery drops to 20% or when the Mac gets too hot. Both are on by default.
- **Report.** After a lid-closed run, the window shows how long it lasted and why it stopped.
- **Launch at login.**

The Claude Code integration reads the session files in `~/.claude/sessions`, which Claude Code does not document. It may break with a future version.

## Install

Requires macOS 26 and Xcode 26. There is no published binary yet.

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild build -scheme StayLit -configuration Release -destination 'platform=macOS' -derivedDataPath build
cp -R "build/Build/Products/Release/Stay Lit.app" /Applications/
open "/Applications/Stay Lit.app"
```

- No Apple developer account needed: the build signs ad hoc.
- Keep the app in `/Applications` for launch at login.
- On first launch, click "Install…" to add the sudoers rule.

## Security

Stay Lit writes one file, `/etc/sudoers.d/staylit-<uid>` (`root:wheel`, `0440`):

```
#<uid> ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
```

- Your user ID, and only yours, can run exactly these two commands as root without a password. Nothing else.
- Any program running as you can use them too, not only Stay Lit.
- The install script runs once through the macOS admin dialog. It validates the rule with `visudo -cf` before moving it into place. Your user ID is its only input.
- "Show the rule" in the window displays it before you install.
- The app is not sandboxed (it runs `sudo`), but uses the hardened runtime and calls every executable by absolute path.

Check it:

```bash
ls -l /etc/sudoers.d/staylit-$(id -u)
sudo -l
```

### Remove it

Click "Remove…" in the app. Or by hand:

```bash
sudo /usr/bin/pmset -a disablesleep 0
sudo rm /etc/sudoers.d/staylit-$(id -u)
```

## Things to know

- **Quit** turns sleep back on. A crash or force quit does not: run `sudo /usr/bin/pmset -a disablesleep 0` or relaunch the app.
- **The timer duration you pick is kept between launches.** The running timer and the report live in memory: quitting forgets them.
- **The state follows the system.** The app reads `pmset -g` every 10 seconds, so a change made in a terminal shows up. Lid detection has the same 10-second resolution.
- **Lock on close** uses `SACLockScreenImmediate`, a private API Apple may remove.
- **Back on after sleep** detects the unlock through an undocumented notification (`com.apple.screenIsUnlocked`) and an undocumented session key. Apple may change them.

## Development

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test --package-path StayLitCore
xcodebuild build -scheme StayLit -destination 'platform=macOS'
```

- `StayLitCore/` holds all the logic and its tests. It imports only Foundation, Observation and IOKit.
- `StayLit/` is the thin SwiftUI app target.
- No test runs `sudo`, `pmset` or `osascript`.
- To sign with your team, put `DEVELOPMENT_TEAM` in `Config/Local.xcconfig` (git ignores it).
- `scripts/release.sh` builds a signed, notarized DMG. It needs a Developer ID certificate and a `notarytool` profile named `staylit`.

Issues and pull requests are welcome.

## License

MIT. See [LICENSE](LICENSE).
