// macos/Sources/Features/Workspace/WorkspaceStartupMode.swift
import Foundation

/// Defines what PolterttyRootView should display on startup.
/// Defined at file scope because it must be referenced from TerminalController,
/// and Swift does not allow referencing types nested inside a generic struct.
enum WorkspaceStartupMode {
    case terminal       // Normal workspace with terminal
    case onboarding     // First launch, no workspaces
    case restore        // Cold start with existing workspaces
}
