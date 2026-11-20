# Stay Lit

A macOS menu bar app that turns `pmset -a disablesleep` on and off, so your Mac stays awake when you need it to.

It is for people who already run `sudo pmset -a disablesleep 1` in a terminal and want a switch instead. The window shows the front edge of a closed MacBook with its lights, one switch, a sentence that says what happens when you close the lid, and a few settings.

Changing this setting needs root. Stay Lit asks for an administrator password once, to install a narrow sudoers rule. Read [Security model](#security-model) before you install it.

## Features

- **Main switch.** Turns `disablesleep` on and off. The sentence beside it says "Close me. I stay lit." while sleep is blocked and "Close me and I sleep." while it is allowed. While sleep is blocked, the line below says the session locks on close and how long the block lasts ("Locks on close. Until you turn it off." or "Locks on close. Sleeps again in ...").
- **Lid lights.** The top of the window draws the front edge of a closed MacBook. Its lights are off while the Mac would sleep. While sleep is blocked, each working Claude Code session has a green light that breathes, and each session waiting for you has an amber one. With no session, a single white light stays on. Six lights at most. With Reduce Motion, the lights stay still.
- **Agents line.** Under the switch, the count of Claude Code sessions: "2 agents working", "1 agent working, 1 waiting for you", "No agent working". While sleep is allowed and a session works, the line turns amber and warns that closing the lid pauses it.
- **Status in the menu bar.** The icon is an almost closed laptop with two Zs above it (`laptop.closed.zzz`) while sleep is allowed, and the same laptop with a bolt (`laptop.closed.bolt`) while it is blocked. Both are custom symbols. There is no Dock icon.
- **Duration.** The "Time is up" row, under "Let me sleep when", has a segmented control: an infinity symbol ("Until turned off"), `1 h`, `2 h` and `4 h`. When the time is up, the app turns sleep back on. The line under the switch counts down the time left ("Sleeps again in ..."). Changing the duration while sleep is blocked restarts the countdown from now.
- **Battery guard.** The "Battery at 20% or less" row. On by default. When the Mac runs on battery at 20% or less, the app turns sleep back on, posts a notification (if you allowed notifications) and shows "Battery low, so I can sleep again." in the window. While the Mac runs on battery at 20% or less and sleep is allowed, the switch is disabled, and the row's caption turns amber to say why. Plugging in or turning the guard off enables it again. The setting is hidden on a Mac without a battery. The 20% threshold is fixed.
- **Temperature guard.** The "I get too hot" row. On by default. macOS reports the Mac's thermal state, not degrees. When the state is serious or critical, the app turns sleep back on, posts a notification (if you allowed notifications) and shows "I got too hot, so I can sleep again." in the window. While the Mac is that hot and the guard is on, the switch is disabled, and the row's caption turns amber to say why. Cooling down or turning the guard off enables it again. The threshold is fixed. The setting is shown on every Mac, with or without a battery.
- **Claude guard.** The "Claude Code is done" row. Off by default, because it puts the Mac to sleep. Once Claude Code has finished working and the lid is closed, the app turns sleep back on, posts a notification (if you allowed notifications), shows "Claude Code finished, so I can sleep again." in the window and puts the Mac to sleep. It acts after 1 minute without work, or after 10 minutes if a session waits for a permission or an answer. It only acts if a session was seen working since you blocked sleep, so blocking sleep for something else triggers nothing. With the lid open, it does nothing. The delays are fixed.
- **Lid-closed report.** When the Mac ran with the lid closed and sleep blocked for at least 1 minute, the window shows how long it ran and why it stopped: the timer ended, the battery guard, the temperature guard or the Claude guard acted, the lid was opened while sleep was still blocked, sleep was allowed outside Stay Lit, or the Mac went to sleep anyway. It shows under "Last time I stayed lit", and stays until a newer report replaces it or an automatic restore leaves no report. You turning sleep back on yourself leaves no report.
- **Lock on lid close.** Always on. When the lid closes while sleep is blocked, the app locks the session, so the Mac keeps running behind the lock screen. It acts when a status check sees the lid go from open to closed, so up to 10 seconds late. Closing the lid with an external display connected locks too. A lid already closed when sleep was blocked, or when the app started, locks nothing. If the system function is missing, the window shows an error. It uses `SACLockScreenImmediate` from the private `login.framework`, which Apple does not document and may remove.
- **Launch at login.** A switch that registers the app as a login item (`SMAppService`). If macOS wants your approval, the window says to allow Stay Lit in System Settings, under Login Items.
- **About.** The bottom of the window shows the version and "Made by mlt-a", next to "Quit".

## Security model

### Why root is needed

`pmset -a disablesleep` changes a system-wide power setting, and only root can do that. The app could ask for a password at every toggle, or install a sudoers rule once. Stay Lit installs a rule.

### The rule

The rule is one file per user:

```
/etc/sudoers.d/staylit-<uid>
```

`<uid>` is your numeric user ID. The name has no dot, because sudo skips files in `sudoers.d` whose name contains one. Each user on the Mac gets their own file, so one account never overwrites or removes another's rule.

The file is owned by `root:wheel`, with mode `0440`. This is its content, as the app generates it:

```
# Added by Stay Lit. Lets user <uid> run these two pmset commands without a password.
#<uid> ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
```

In sudoers, `#` followed by digits is a user ID, not a comment. So the second line is a rule for the user with that ID.

### What it allows

- It lets your user (and only your user ID) run exactly two commands as root, without a password: `/usr/bin/pmset -a disablesleep 0` and `/usr/bin/pmset -a disablesleep 1`.
- sudo matches the full command line. Other `pmset` arguments, and any other command, still need the usual authentication.
- Consequence: once the rule is installed, any program that runs under your account can switch this setting on or off without a password. It is not limited to Stay Lit. It cannot do anything else as root through this rule.

### How it is installed

- One click on "Install…". macOS shows its own administrator password dialog, once.
- The app runs one script as root through `/usr/bin/osascript` (`do shell script ... with administrator privileges`). The only value that varies in the script is your user ID, an integer. No other input reaches it.
- The script writes the rule to `/etc/sudoers.d/staylit-<uid>.tmp`. The dot makes sudo ignore the file while it is being written, and the file belongs to root from the start.
- It checks the file with `/usr/sbin/visudo -cf`, sets the owner with `chown root:wheel` and the mode with `chmod 0440`, then renames it into place with `mv`. If any step fails, it deletes the `.tmp` file and installs nothing.
- Cancelling the password dialog changes nothing and shows no error.
- Before you install, the window can show the exact rule ("Show the rule").

### Not sandboxed

The app does not run in the App Sandbox (`ENABLE_APP_SANDBOX = NO`), because it launches `sudo` and `pmset`. It does use the hardened runtime (`ENABLE_HARDENED_RUNTIME = YES`). Every executable it runs is called by absolute path (`/usr/bin/pmset`, `/usr/bin/sudo`, `/usr/sbin/visudo`, `/usr/bin/osascript`), never looked up in `PATH`.

### Check it yourself

```bash
# Owner, group and mode: expect -r--r-----, root, wheel
ls -l /etc/sudoers.d/staylit-$(id -u)

# Content
sudo cat /etc/sudoers.d/staylit-$(id -u)

# What sudo lets you run without a password
sudo -l
```

The app reads its authorization status the same way: the rule file must exist, and `sudo -n -l` must accept both `pmset -a disablesleep 1` and `pmset -a disablesleep 0`. If an install succeeds but sudo does not accept the rule, the window says so and suggests checking that `/etc/sudoers` includes `/etc/sudoers.d`. The window then keeps offering "Install…", because the rule is not usable.

## Removing the authorization

**From the app.** Click "Remove…" on the "Password-free rule" row (shown only while the rule is usable). macOS asks for an administrator password. The root script then:

1. runs `/usr/bin/pmset -a disablesleep 0`, so sleep is allowed again;
2. deletes `/etc/sudoers.d/staylit-<uid>`.

The rule is deleted even if `pmset` fails, because removing it is what you asked for. The failure is then reported, and sleep may still be blocked.

**By hand, if the app is gone.** In a terminal:

```bash
sudo /usr/bin/pmset -a disablesleep 0
sudo rm /etc/sudoers.d/staylit-$(id -u)
```

## Things to know

- **Quitting.** "Quit" (or Command-Q, while the window is open) turns sleep back on before the app exits. It waits for any operation already running, and does it whether or not Stay Lit turned sleep off. This needs a usable rule: without one, the reset fails silently and sleep stays as it was.
- **Crash or kill.** Nothing turns sleep back on. If the app crashes or you force quit it, sleep may stay blocked. Restore it by hand:

  ```bash
  sudo /usr/bin/pmset -a disablesleep 0
  ```

  Or relaunch the app and turn the switch off (this needs the rule).
- **The timer lives in memory.** It is not saved. Quitting, or a crash, forgets it. The timer also stops if the status refresh sees that sleep was allowed by something else, or that the rule is no longer usable.
- **The displayed state follows the system.** It comes from the `SleepDisabled` line of `pmset -g`, not from what the app last asked for. The app reads it at launch, each time the window opens, after each action, and every 10 seconds, so a change made in a terminal shows up. Check it yourself with `pmset -g | grep SleepDisabled`. `pmset -g` prints no such line while the setting is off.
- **The lid-closed report is approximate and lives in memory.** The app reads the lid with each status check, every 10 seconds, so the duration is accurate to about 10 seconds and shown in hours and minutes. A run shorter than 1 minute leaves no report. Quitting, or a crash, forgets the report.
- **A timer ending does not notify.** You chose the duration. The battery guard, the temperature guard and the Claude guard do post a notification. macOS asks to allow notifications the first time the window opens with a guard on, or when you turn one on.
- **The Claude guard reads an undocumented file.** It reads the session files in `~/.claude/sessions`, which Claude Code does not document (seen in 2.1.328). A status the app does not know counts as work, so the Mac stays awake. An idle session that waits for a scheduled wake-up or a long background task looks finished, and the guard acts after 1 minute. To sleep, the app runs `/usr/bin/pmset sleepnow`, which needs no root rights.

## Requirements

- macOS 26.0 or later.
- Xcode 26 or later (the package uses Swift tools 6.2 and Swift 6 language mode).
- An administrator account, to install the rule.

## Install

There is no published binary yet. Build the app and copy it to Applications:

```bash
# From the repository root
# Only if xcode-select points at the command line tools
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

xcodebuild build -scheme StayLit -configuration Release -destination 'platform=macOS' -derivedDataPath build
cp -R "build/Build/Products/Release/Stay Lit.app" /Applications/
open "/Applications/Stay Lit.app"
```

- No Apple developer account is needed. A free or ad hoc signature runs fine on the Mac that built the app.
- Keep the app in `/Applications`: launch at login points to the app's location.
- Stay Lit lives in the menu bar, with no Dock icon. On first launch, click "Install…" to add the sudoers rule.
- To update, quit Stay Lit, pull, then run the build and copy commands again.

## Build from source

```bash
# From the repository root
# Only if xcode-select points at the command line tools
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

xcodebuild build -scheme StayLit -destination 'platform=macOS'
```

You can also open `StayLit.xcodeproj` in Xcode and run the `StayLit` scheme.

### Signing

The committed project has no team. `Config/Base.xcconfig` signs ad hoc ("Sign to Run Locally"), so a fresh clone builds without an Apple developer account.

To sign with your own team, create `Config/Local.xcconfig`. Git ignores it, and `Base.xcconfig` includes it when it exists:

```
CODE_SIGN_STYLE = Automatic
CODE_SIGN_IDENTITY = Apple Development
DEVELOPMENT_TEAM = ABCDE12345
```

Replace `ABCDE12345` with your own team ID.

### Release

`scripts/release.sh` archives the app, signs it with Developer ID, builds a DMG, notarizes and staples it. The result lands in `build/release/StayLit-<version>.dmg`.

One-time setup:

- A paid Apple Developer Program membership.
- A "Developer ID Application" certificate: Xcode > Settings > Accounts > Manage Certificates > +.
- A notarytool profile in the keychain, with an app-specific password from account.apple.com:

```bash
xcrun notarytool store-credentials staylit --apple-id <apple-id> --team-id <team-id>
```

Each release:

```bash
# Bump MARKETING_VERSION and CURRENT_PROJECT_VERSION first
scripts/release.sh
gh release create v<version> build/release/StayLit-<version>.dmg
```

The script reads the team ID from `Config/Local.xcconfig`. `TEAM_ID` and `NOTARY_PROFILE` override it and the profile name.

## Tests

```bash
# Only if xcode-select points at the command line tools
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test --package-path StayLitCore
```

No test ever runs `sudo`, `pmset` or `osascript`. The core talks to the system through protocols, and the tests use doubles. The tests do not launch the app, so quitting never touches your real power settings.

## Project structure

- `StayLitCore/` is a local Swift package with all the logic and its tests: reading and setting the sleep state, the sudoers rule and its scripts, the app model, the timer, the battery guard, the temperature guard, the Claude guard and the lid-closed report (`LidReport`). It imports only Foundation, Observation and IOKit, never SwiftUI or AppKit.
- `StayLit/` is the thin app target: entry point, views, the login item and notifications.
- `Config/` holds the build settings shared by the project.
- `scripts/release.sh` builds the notarized DMG.

## Contributing

Issues and pull requests are welcome.

- Run `swift test --package-path StayLitCore` before you open a pull request.
- Code, comments, commits, this README and the interface are in English.
- Keep the core free of SwiftUI and AppKit, and keep tests away from `sudo`, `pmset` and `osascript`.
- Keep the user ID the only variable in anything that runs as root.

## License

MIT. See [LICENSE](LICENSE).
