// macos/Tests/Tmux/TmuxParserTests.swift
import Testing
@testable import Ghostty

struct TmuxParserTests {

    // MARK: - parseSessions

    @Test func parseSessions_normalOutput() {
        let input = """
        my-project|1
        dotfiles|0
        """
        let sessions = TmuxParser.parseSessions(input)
        #expect(sessions.count == 2)
        #expect(sessions[0].id == "my-project")
        #expect(sessions[0].attached == true)
        #expect(sessions[1].id == "dotfiles")
        #expect(sessions[1].attached == false)
    }

    @Test func parseSessions_emptyOutput() {
        #expect(TmuxParser.parseSessions("").isEmpty)
        #expect(TmuxParser.parseSessions("\n\n").isEmpty)
    }

    @Test func parseSessions_sessionNameWithSpaces() {
        let input = "my project|1"
        let sessions = TmuxParser.parseSessions(input)
        #expect(sessions.count == 1)
        #expect(sessions[0].id == "my project")
    }

    // MARK: - parseWindows

    @Test func parseWindows_normalOutput() {
        let input = """
        0|vim|1
        1|server|0
        2|logs|0
        """
        let windows = TmuxParser.parseWindows(input, sessionName: "proj")
        #expect(windows.count == 3)
        #expect(windows[0].id == "proj:0")
        #expect(windows[0].sessionName == "proj")
        #expect(windows[0].windowIndex == 0)
        #expect(windows[0].name == "vim")
        #expect(windows[0].active == true)
        #expect(windows[1].active == false)
    }

    @Test func parseWindows_emptyOutput() {
        #expect(TmuxParser.parseWindows("", sessionName: "s").isEmpty)
    }

    @Test func parseWindows_idIsComposite() {
        // 不同 session 的 window 0 ID 不能相同
        let w1 = TmuxParser.parseWindows("0|vim|1", sessionName: "a")
        let w2 = TmuxParser.parseWindows("0|vim|1", sessionName: "b")
        #expect(w1[0].id != w2[0].id)
    }

    @Test func parseWindows_windowNameWithPipe() {
        let input = "0|my|project|1"
        let windows = TmuxParser.parseWindows(input, sessionName: "s")
        #expect(windows.count == 1)
        #expect(windows[0].name == "my|project")
        #expect(windows[0].active == true)
    }

}
