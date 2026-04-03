// macos/Sources/Features/Workspace/Browser/BrowserPanelToolbar.swift
import SwiftUI
import WebKit

struct BrowserPanelToolbar: View {
    let webView: WKWebView
    var canGoBack: Bool
    var canGoForward: Bool
    @Binding var currentURL: URL?
    var onClose: () -> Void

    @State private var addressInput: String = ""
    @FocusState private var isEditingAddress: Bool

    var body: some View {
        HStack(spacing: 0) {
            // Globe icon
            Image(systemName: "globe")
                .font(.system(size: 13))
                .foregroundStyle(Color(nsColor: .controlAccentColor))
                .frame(width: 28, height: 28)
                .background(Color(nsColor: .controlAccentColor).opacity(0.15))
                .cornerRadius(5)

            // Back button
            Button {
                webView.goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(canGoBack ? Color.primary : Color.secondary.opacity(0.4))
                    .frame(width: 24, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(!canGoBack)
            .help("Back")

            // Forward button
            Button {
                webView.goForward()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(canGoForward ? Color.primary : Color.secondary.opacity(0.4))
                    .frame(width: 24, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(!canGoForward)
            .help("Forward")

            // Reload button
            Button {
                webView.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
                    .frame(width: 24, height: 28)
            }
            .buttonStyle(.plain)
            .help("Reload")

            // Address bar
            TextField("Enter URL", text: $addressInput)
                .onSubmit {
                    navigate(to: addressInput)
                }
                .focused($isEditingAddress)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isEditingAddress ? Color.accentColor : Color.clear, lineWidth: 1)
                )
                .frame(maxWidth: .infinity)
                .onChange(of: currentURL) { newURL in
                    if !isEditingAddress {
                        addressInput = newURL?.absoluteString ?? ""
                    }
                }
                .onChange(of: isEditingAddress) { editing in
                    if editing {
                        addressInput = currentURL?.absoluteString ?? ""
                    }
                }
                .onAppear {
                    addressInput = currentURL?.absoluteString ?? ""
                }

            // Close button
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("Close Panel")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func navigate(to input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let urlString = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: urlString) else { return }
        webView.load(URLRequest(url: url))
    }
}
