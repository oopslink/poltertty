// macos/Sources/Features/Workspace/Browser/BrowserTabOverflowMenu.swift
import SwiftUI

/// 当 tab 数量超出可见区域时，显示「+N ▾」下拉按钮，列出所有溢出 tab。
struct BrowserTabOverflowMenu: View {
    let overflowTabs: [BrowserTab]
    let activeTabId: UUID?
    let onSelect: (UUID) -> Void

    var body: some View {
        Menu {
            ForEach(overflowTabs) { tab in
                Button {
                    onSelect(tab.id)
                } label: {
                    HStack {
                        if tab.id == activeTabId {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9))
                        }
                        Text(tab.title.isEmpty ? "New Tab" : tab.title)
                        Spacer()
                        if let url = tab.url {
                            Text(url.host ?? "")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 10))
                        }
                    }
                }
            }
        } label: {
            Text("+\(overflowTabs.count) ▾")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
                .cornerRadius(3)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
