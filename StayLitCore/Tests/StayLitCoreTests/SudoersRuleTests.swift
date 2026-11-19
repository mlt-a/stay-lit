import Testing
@testable import StayLitCore

struct SudoersRuleTests {
    @Test func ruleTextForUser501() {
        #expect(SudoersRule.text(forUserID: 501) == """
            # Added by Stay Lit. Lets user 501 run these two pmset commands without a password.
            #501 ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1

            """)
    }

    @Test func installScriptForUser501() {
        #expect(SudoersRule.installScript(forUserID: 501) == """
            /usr/bin/printf '%s\\n' \
            '# Added by Stay Lit. Lets user 501 run these two pmset commands without a password.' \
            '#501 ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1' \
            > /etc/sudoers.d/staylit-501.tmp \
            && /usr/sbin/visudo -cf /etc/sudoers.d/staylit-501.tmp \
            && /usr/sbin/chown root:wheel /etc/sudoers.d/staylit-501.tmp \
            && /bin/chmod 0440 /etc/sudoers.d/staylit-501.tmp \
            && /bin/mv -f /etc/sudoers.d/staylit-501.tmp /etc/sudoers.d/staylit-501 \
            || { /bin/rm -f /etc/sudoers.d/staylit-501.tmp; exit 1; }
            """)
    }

    @Test func removeScriptForUser501() {
        #expect(SudoersRule.removeScript(forUserID: 501)
            == "/usr/bin/pmset -a disablesleep 0; status=$?; /bin/rm -f /etc/sudoers.d/staylit-501; exit $status")
    }

    @Test func eachUserHasItsOwnFiles() {
        #expect(SudoersRule.path(forUserID: 501) == "/etc/sudoers.d/staylit-501")
        #expect(SudoersRule.path(forUserID: 502) == "/etc/sudoers.d/staylit-502")
        #expect(SudoersRule.temporaryPath(forUserID: 502) == "/etc/sudoers.d/staylit-502.tmp")
        #expect(SudoersRule.installScript(forUserID: 502).contains("/bin/mv -f /etc/sudoers.d/staylit-502.tmp /etc/sudoers.d/staylit-502"))
        #expect(!SudoersRule.installScript(forUserID: 502).contains("staylit-501"))
        #expect(SudoersRule.removeScript(forUserID: 502).contains("/bin/rm -f /etc/sudoers.d/staylit-502;"))
    }

    @Test func temporaryFileNameIsIgnoredBySudo() {
        // sudo skips names in sudoers.d that contain a dot or end in a tilde.
        let name = SudoersRule.temporaryPath(forUserID: 501).split(separator: "/").last ?? ""
        #expect(name.contains("."))
        let finalName = SudoersRule.path(forUserID: 501).split(separator: "/").last ?? ""
        #expect(!finalName.contains(".") && !finalName.hasSuffix("~"))
    }

    @Test(arguments: [
        ("plain", "'plain'"),
        ("it's", "'it'\\''s'"),
        ("$HOME `id` \\n", "'$HOME `id` \\n'"),
    ])
    func shellQuoting(value: String, quoted: String) {
        #expect(SudoersRule.shellQuoted(value) == quoted)
    }
}

struct AppleScriptTests {
    @Test(arguments: [
        ("plain", "\"plain\""),
        ("say \"hi\"", "\"say \\\"hi\\\"\""),
        ("a\\nb", "\"a\\\\nb\""),
        ("\\\"", "\"\\\\\\\"\""),
    ])
    func stringLiteral(value: String, literal: String) {
        #expect(AppleScript.stringLiteral(value) == literal)
    }

    @Test func runAsAdministrator() {
        #expect(AppleScript.runAsAdministrator("/usr/bin/printf '%s\\n' x", prompt: "Allow it")
            == "do shell script \"/usr/bin/printf '%s\\\\n' x\" with prompt \"Allow it\""
            + " with administrator privileges")
    }

    @Test func runAsAdministratorEscapesThePrompt() {
        #expect(AppleScript.runAsAdministrator("true", prompt: "Say \"hi\" \\ now")
            == "do shell script \"true\" with prompt \"Say \\\"hi\\\" \\\\ now\""
            + " with administrator privileges")
    }
}
