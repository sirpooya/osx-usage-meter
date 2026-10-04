//
//  OAuthCallbackServer.swift
//  UsageMeter
//
//  Created by f-is-h on 2026-06-18.
//  Copyright © 2026 f-is-h. All rights reserved.
//

import Foundation
import Network
import OSLog

/// Local OAuth callback server (built on Network.framework, no third party dependency)
///
/// Listens on a localhost port, catches the
/// `/auth/callback?code=...&state=...` the system browser redirects back, returns a success page to the browser
/// and hands the query parameters up through onCallback.
final class OAuthCallbackServer {

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "in.pooya.usagemeter.oauth.callback")
    private(set) var port: UInt16 = 0
    private var onCallback: (([String: String]) -> Void)?
    private var didDeliver = false

    /// Tries the port list in order, binding the first one available
    /// - Returns: the port it bound, or nil when they all fail
    func start(ports: [UInt16], onCallback: @escaping ([String: String]) -> Void) -> UInt16? {
        self.onCallback = onCallback
        // Reset the deliver once flag: the coordinator reuses the same server instance for a retried login,
        // and without the reset a retry after a first failure would silently drop the callback even when the browser really did get a code.
        self.didDeliver = false
        for p in ports where startListener(on: p) {
            self.port = p
            return p
        }
        return nil
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func startListener(on port: UInt16) -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return false }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        // requiredLocalEndpoint is deliberately not forced: listening on both the IPv4 and IPv6 loopback
        // avoids the blank connection you get when the browser resolves localhost to ::1 while the server only bound 127.0.0.1.
        // The OAuth code is protected by PKCE and state, single use and short lived, so listening on loopback is acceptable.

        let listener: NWListener
        do {
            listener = try NWListener(using: params, on: nwPort)
        } catch {
            Logger.settings.error("OAuthCallbackServer: could not create a listener on port \(port) - \(error.localizedDescription, privacy: .public)")
            return false
        }

        let sema = DispatchSemaphore(value: 0)
        var ready = false
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                ready = true
                sema.signal()
            case .waiting(let error):
                // When the port is taken, NWListener goes to waiting (retrying indefinitely) rather than failed.
                // Signal immediately so the next port can be tried quickly, and record the real reason.
                Logger.settings.error("OAuthCallbackServer: port \(port) is unavailable (\(error.localizedDescription, privacy: .public)), trying the next one")
                sema.signal()
            case .failed(let error):
                Logger.settings.error("OAuthCallbackServer: listening on port \(port) failed - \(error.localizedDescription, privacy: .public)")
                sema.signal()
            case .cancelled:
                sema.signal()
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] conn in
            self?.handle(conn)
        }
        listener.start(queue: queue)

        // Wait up to 2 seconds for the bind result
        _ = sema.wait(timeout: .now() + 2)
        if ready {
            self.listener = listener
            Logger.settings.info("OAuthCallbackServer: listening on localhost:\(port)")
            return true
        }
        listener.cancel()
        Logger.settings.error("OAuthCallbackServer: port \(port) did not become ready before the timeout")
        return false
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            guard let self = self,
                  let data = data,
                  let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }

            let query = self.parseQuery(fromRequestLine: request)
            // Only a request carrying code or error is a real OAuth callback; anything else (a stray favicon
            // request from the browser, say) should semantically be a 404 rather than a success or failure page.
            let isOAuthCallback = query["code"] != nil || query["error"] != nil

            let response: String
            if isOAuthCallback {
                let body = Self.responseHTML(success: query["code"] != nil)
                response = """
                HTTP/1.1 200 OK\r
                Content-Type: text/html; charset=utf-8\r
                Content-Length: \(body.utf8.count)\r
                Connection: close\r
                \r
                \(body)
                """
            } else {
                let body = Self.notFoundHTML()
                response = """
                HTTP/1.1 404 Not Found\r
                Content-Type: text/html; charset=utf-8\r
                Content-Length: \(body.utf8.count)\r
                Connection: close\r
                \r
                \(body)
                """
            }
            connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })

            // Deliver only the first valid callback (code or error)
            if !self.didDeliver, isOAuthCallback {
                self.didDeliver = true
                DispatchQueue.main.async { self.onCallback?(query) }
            }
        }
    }

    /// Parse the query parameters out of an HTTP request line
    /// For example: `GET /auth/callback?code=...&state=... HTTP/1.1`
    private func parseQuery(fromRequestLine request: String) -> [String: String] {
        guard let firstLine = request.split(separator: "\r\n").first else { return [:] }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return [:] }
        let path = String(parts[1])
        guard let qIndex = path.firstIndex(of: "?") else { return [:] }

        let queryString = String(path[path.index(after: qIndex)...])
        var result: [String: String] = [:]
        for pair in queryString.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            guard let k = kv.first else { continue }
            let key = String(k).removingPercentEncoding ?? String(k)
            let rawValue = kv.count > 1 ? String(kv[1]) : ""
            result[key] = rawValue.removingPercentEncoding ?? rawValue
        }
        return result
    }

    private static func responseHTML(success: Bool) -> String {
        let title = success ? "Signed in" : "Sign-in failed"
        let heading = success ? "✅ Signed in successfully" : "⚠️ Sign-in failed"
        let message = success
            ? "You can close this tab and return to Usage Meter."
            : "Something went wrong. Please return to Usage Meter and try again."
        return """
        <!DOCTYPE html><html><head><meta charset="utf-8"><title>\(title)</title></head>
        <body style="font-family:-apple-system,BlinkMacSystemFont,sans-serif;text-align:center;padding-top:80px;color:#1d1d1f;background:#f5f5f7">
        <h2>\(heading)</h2>
        <p>\(message)</p>
        </body></html>
        """
    }

    private static func notFoundHTML() -> String {
        """
        <!DOCTYPE html><html><head><meta charset="utf-8"><title>Not Found</title></head>
        <body style="font-family:-apple-system,BlinkMacSystemFont,sans-serif;text-align:center;padding-top:80px;color:#1d1d1f;background:#f5f5f7">
        <h2>404 Not Found</h2>
        </body></html>
        """
    }
}
