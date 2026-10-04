//
//  WebLoginWindowManager.swift
//  UsageMeter
//
//  Created by Claude Code on 2026-02-06.
//  Copyright © 2026 f-is-h. All rights reserved.
//

import AppKit
import SwiftUI

/// Web login window manager singleton
/// Creates, shows and closes the login window
/// The login WebView uses nonPersistent storage, so adding several accounts cannot auto SSO through an existing session
final class WebLoginWindowManager {
    static let shared = WebLoginWindowManager()

    private var loginWindow: NSWindow?
    private var codexLoginWindow: NSWindow?

    private init() {}

    // MARK: - Claude Login

    func showLoginWindow(onAccountCreated: ((Account) -> Void)? = nil) {
        if let window = loginWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Switched to OAuth in the system browser instead of an embedded WKWebView,
        // which supports Google, Microsoft, enterprise SSO, passkeys and the other methods an embedded WebView limits (Issue #49)
        let loginView = ClaudeOAuthLoginView(onAccountCreated: onAccountCreated)
        let window = makeCompactWindow(title: L.WebLogin.windowTitle, content: loginView, width: 440, height: 380)
        self.loginWindow = window

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in self?.loginWindow = nil }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeLoginWindow() {
        loginWindow?.close()
        loginWindow = nil
    }

    // MARK: - Codex Login

    func showCodexLoginWindow(onAccountCreated: ((Account) -> Void)? = nil) {
        if let window = codexLoginWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Switched to OAuth in the system browser instead of an embedded WKWebView,
        // which supports Google, Microsoft, enterprise SSO, passkeys and the other methods an embedded WebView limits
        let loginView = CodexOAuthLoginView(onAccountCreated: onAccountCreated)
        let window = makeCompactWindow(title: L.WebLogin.codexWindowTitle, content: loginView, width: 440, height: 300)
        self.codexLoginWindow = window

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in self?.codexLoginWindow = nil }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeCodexLoginWindow() {
        codexLoginWindow?.close()
        codexLoginWindow = nil
    }

    // MARK: - Private

    private func makeWindow<V: View>(title: String, content: V) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 700),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: content)
        window.title = title
        window.minSize = NSSize(width: 600, height: 500)
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        return window
    }

    /// A small fixed size window (for showing OAuth progress, not resizable)
    private func makeCompactWindow<V: View>(title: String, content: V, width: CGFloat, height: CGFloat) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: content)
        window.title = title
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        return window
    }
}
