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

    // MARK: - parsePanes

    @Test func parsePanes_normalOutput() {
        let input = """
        %0|nvim|1|220|50
        %1|zsh|0|220|50
        """
        let panes = TmuxParser.parsePanes(input)
        #expect(panes.count == 2)
        #expect(panes[0].id == 0)
        #expect(panes[0].title == "nvim")
        #expect(panes[0].active == true)
        #expect(panes[0].width == 220)
        #expect(panes[0].height == 50)
        #expect(panes[1].id == 1)
        #expect(panes[1].active == false)
    }

    @Test func parsePanes_emptyOutput() {
        #expect(TmuxParser.parsePanes("").isEmpty)
    }

    @Test func parsePanes_stripsPercentPrefix() {
        let panes = TmuxParser.parsePanes("%42|bash|0|80|24")
        #expect(panes[0].id == 42)
    }

    @Test func parsePanes_invalidLineSkipped() {
        let input = """
        %0|nvim|1|220|50
        invalid_line
        %1|zsh|0|80|24
        """
        let panes = TmuxParser.parsePanes(input)
        #expect(panes.count == 2)
    }

    @Test func parsePanes_titleWithPipe() {
        let panes = TmuxParser.parsePanes("%0|my|title|1|220|50")
        #expect(panes.count == 1)
        #expect(panes[0].title == "my|title")
        #expect(panes[0].active == true)
        #expect(panes[0].width == 220)
        #expect(panes[0].height == 50)
    }
}
