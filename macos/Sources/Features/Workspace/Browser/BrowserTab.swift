// macos/Sources/Features/Workspace/Browser/BrowserTab.swift
import Foundation
import WebKit

/// 一个 browser tab 实例。WKWebView 由 BrowserTabManager 在创建时注入。
@MainActor
struct BrowserTab: Identifiable {
    let id: UUID
    var title: String
    var url: URL?
    let webView: WKWebView

    init(id: UUID = UUID(), title: String = "New Tab", url: URL? = nil, webView: WKWebView) {
        self.id = id
        self.title = title
        self.url = url
        self.webView = webView
    }
}

/// 用于持久化的轻量快照，不含 WKWebView。
struct BrowserTabSnapshot: Codable, Equatable {
    let id: UUID
    let url: URL?
    let title: String
}

extension BrowserTabSnapshot {
    @MainActor
    init(from tab: BrowserTab) {
        self.id = tab.id
        self.url = tab.url
        self.title = tab.title
    }
}
