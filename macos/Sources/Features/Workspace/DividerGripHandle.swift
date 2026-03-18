// macos/Sources/Features/Workspace/DividerGripHandle.swift
import SwiftUI

/// 分割线中央的三点抓手，提示用户可拖拽调整大小。
struct DividerGripHandle: View {
    var body: some View {
        VStack(spacing: 3) {
            Spacer()
            Circle().fill(Color.white.opacity(0.5)).frame(width: 4, height: 4)
            Circle().fill(Color.white.opacity(0.5)).frame(width: 4, height: 4)
            Circle().fill(Color.white.opacity(0.5)).frame(width: 4, height: 4)
            Spacer()
        }
        .allowsHitTesting(false)
    }
}
