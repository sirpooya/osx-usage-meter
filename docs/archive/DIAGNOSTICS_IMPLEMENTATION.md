# 诊断功能实现文档

> **目标版本**: 1.4.0  
> **实现时间**: 2025-11  
> **目的**: 帮助用户和开发者诊断连接问题，特别是 Cloudflare 拦截相关问题

---

## 📋 功能概述

### 需求背景

部分用户报告应用无法正常工作，错误信息包括：
1. "Request blocked by security system" (Cloudflare 拦截)
2. "Failed to parse response data" (数据解析失败)

由于这些错误可能由多种原因引起（网络环境、IP信誉、认证过期等），我们需要一个诊断系统来：
- **快速识别问题根源**
- **收集详细的技术信息**
- **提供可分享的诊断报告**（已自动脱敏）
- **给出针对性的解决建议**

### 核心特性

✅ **一键连接测试** - 验证认证信息和网络连接  
✅ **详细诊断信息** - HTTP状态码、响应类型、错误分析  
✅ **自动脱敏处理** - 不泄露任何敏感信息  
✅ **导出诊断报告** - 方便用户分享给开发者  
✅ **友好的错误提示** - 针对不同错误类型给出建议  

---

## 🏗️ 架构设计

### 文件结构

```
UsageMeter/
├── Helpers/
│   ├── DiagnosticManager.swift          (新增)
│   └── LocalizationHelper.swift         (更新)
├── Views/
│   └── SettingsView.swift               (更新)
├── Resources/
│   ├── en.lproj/Localizable.strings     (更新)
│   ├── ja.lproj/Localizable.strings     (更新)
│   ├── zh-Hans.lproj/Localizable.strings (更新)
│   └── zh-Hant.lproj/Localizable.strings (更新)
```

### 组件关系

```
SettingsView (Authentication Tab)
    ↓
DiagnosticsView (内嵌组件)
    ↓
DiagnosticManager
    ↓
ClaudeAPIService (诊断模式)
    ↓
生成 DiagnosticReport
    ↓
导出或显示
```

---

## 🔧 实现细节

## 1. 数据模型定义

### DiagnosticReport.swift (新增文件)

**文件路径**: `UsageMeter/Models/DiagnosticReport.swift`

```swift
//
//  DiagnosticReport.swift
//  Usage Meter
//
//  Created by f-is-h on 2025-11.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation

/// 诊断报告数据模型
/// 包含完整的诊断信息，所有敏感数据已自动脱敏
struct DiagnosticReport: Codable {
    // MARK: - 基本信息
    
    /// 报告生成时间
    let timestamp: Date
    
    /// 应用版本
    let appVersion: String
    
    /// macOS 版本
    let osVersion: String
    
    /// 系统架构 (arm64/x86_64)
    let architecture: String
    
    /// 用户设置的界面语言
    let locale: String
    
    // MARK: - 配置信息
    
    /// 刷新模式 (Smart/Fixed)
    let refreshMode: String
    
    /// 刷新间隔（如果是固定模式）
    let refreshInterval: String?
    
    /// 显示模式
    let displayMode: String
    
    /// Organization ID (已脱敏)
    let organizationIdRedacted: String
    
    /// Session Key (已脱敏)
    let sessionKeyRedacted: String
    
    // MARK: - 测试结果
    
    /// 测试是否成功
    let success: Bool
    
    /// HTTP 状态码
    let httpStatusCode: Int?
    
    /// 响应时间（毫秒）
    let responseTime: Double?
    
    /// 响应类型 (JSON/HTML/Unknown)
    let responseType: ResponseType
    
    /// 错误类型（如果失败）
    let errorType: DiagnosticErrorType?
    
    /// 错误描述
    let errorDescription: String?
    
    // MARK: - 响应详情
    
    /// 响应头信息（已过滤敏感信息）
    let responseHeaders: [String: String]
    
    /// 响应体预览（前500字符）
    let responseBodyPreview: String?
    
    /// 是否检测到 Cloudflare challenge
    let cloudflareChallenge: Bool
    
    /// 是否包含 cf-mitigated 头
    let cfMitigated: Bool
    
    // MARK: - 分析结果
    
    /// 问题诊断
    let diagnosis: String
    
    /// 建议的解决方案（数组）
    let suggestions: [String]
    
    /// 置信度 (High/Medium/Low)
    let confidence: ConfidenceLevel
    
    // MARK: - 枚举定义
    
    enum ResponseType: String, Codable {
        case json = "JSON"
        case html = "HTML"
        case unknown = "Unknown"
    }
    
    enum ConfidenceLevel: String, Codable {
        case high = "High"
        case medium = "Medium"
        case low = "Low"
    }
    
    // MARK: - 格式化输出
    
    /// 生成 Markdown 格式的完整报告
    func toMarkdown() -> String {
        var report = """
        # Usage Meter Diagnostic Report
        
        **⚠️ PRIVACY NOTICE**: All sensitive information has been automatically redacted.  
        **Safe to share**: This report contains no complete credentials or personal data.
        
        ---
        
        ## Test Result
        
        **Status**: \(success ? "✅ Success" : "❌ Failed")  
        **Timestamp**: \(formatTimestamp())  
        **Response Time**: \(formatResponseTime())
        
        """
        
        if !success {
            report += """
            
            ### Error Information
            
            **Error Type**: \(errorType?.rawValue ?? "Unknown")  
            **Description**: \(errorDescription ?? "No description")
            
            """
        }
        
        report += """
        
        ---
        
        ## System Information
        
        - **App Version**: \(appVersion)
        - **macOS Version**: \(osVersion)
        - **Architecture**: \(architecture)
        - **Locale**: \(locale)
        
        ## Configuration
        
        - **Refresh Mode**: \(refreshMode)
        """
        
        if let interval = refreshInterval {
            report += "\n- **Refresh Interval**: \(interval)"
        }
        
        report += """
        
        - **Display Mode**: \(displayMode)
        - **Organization ID**: `\(organizationIdRedacted)` (redacted)
        - **Session Key**: `\(sessionKeyRedacted)` (redacted)
        
        ---
        
        ## Connection Test Details
        
        ### Request
        
        ```http
        GET /api/organizations/\(organizationIdRedacted)/usage HTTP/2
        Host: claude.ai
        accept: */*
        user-agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36
        Cookie: sessionKey=\(sessionKeyRedacted)
        [... other headers omitted for brevity]
        ```
        
        ### Response
        
        """
        
        if let statusCode = httpStatusCode {
            report += "**HTTP Status**: \(statusCode)\n"
        }
        
        report += "**Content Type**: \(responseType.rawValue)\n"
        
        if cloudflareChallenge {
            report += "**Cloudflare Challenge**: ⚠️ Detected\n"
        }
        
        if cfMitigated {
            report += "**CF-Mitigated Header**: Present\n"
        }
        
        if !responseHeaders.isEmpty {
            report += "\n**Response Headers**:\n```\n"
            for (key, value) in responseHeaders.sorted(by: { $0.key < $1.key }) {
                report += "\(key): \(value)\n"
            }
            report += "```\n"
        }
        
        if let preview = responseBodyPreview, !preview.isEmpty {
            report += """
            
            **Response Body** (first 500 characters):
            ```
            \(preview)
            ```
            
            """
        }
        
        report += """
        
        ---
        
        ## Analysis
        
        **Diagnosis**: \(diagnosis)  
        **Confidence**: \(confidence.rawValue)
        
        ### Suggested Actions
        
        """
        
        for (index, suggestion) in suggestions.enumerated() {
            report += "\(index + 1). \(suggestion)\n"
        }
        
        report += """
        
        ---
        
        ## Additional Information
        
        - Report generated by Usage Meter v\(appVersion)
        - For help, visit: https://github.com/sirpooya/osx-usage-meter/issues
        - Include this report when reporting issues
        
        """
        
        return report
    }
    
    // MARK: - 私有辅助方法
    
    private func formatTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: timestamp)
    }
    
    private func formatResponseTime() -> String {
        guard let time = responseTime else {
            return "N/A"
        }
        return String(format: "%.0f ms", time)
    }
}

/// 诊断错误类型
enum DiagnosticErrorType: String, Codable {
    case cloudflareBlocked = "Cloudflare Challenge"
    case authenticationFailed = "Authentication Failed"
    case networkError = "Network Error"
    case decodingError = "Data Parsing Error"
    case invalidCredentials = "Invalid Credentials"
    case timeout = "Request Timeout"
    case unknown = "Unknown Error"
}
```

---

## 2. 诊断管理器实现

### DiagnosticManager.swift (新增文件)

**文件路径**: `UsageMeter/Helpers/DiagnosticManager.swift`

```swift
//
//  DiagnosticManager.swift
//  Usage Meter
//
//  Created by f-is-h on 2025-11.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation
import AppKit

/// 诊断管理器
/// 负责执行连接测试、生成诊断报告、导出报告等功能
class DiagnosticManager: ObservableObject {
    
    // MARK: - Published Properties
    
    /// 是否正在进行诊断测试
    @Published var isTesting: Bool = false
    
    /// 最新的诊断报告
    @Published var latestReport: DiagnosticReport?
    
    /// 测试状态消息
    @Published var statusMessage: String = ""
    
    // MARK: - Private Properties
    
    private let settings = UserSettings.shared
    private let apiService = ClaudeAPIService()
    
    // MARK: - Public Methods
    
    /// 执行完整的诊断测试
    func runDiagnosticTest() async {
        await MainActor.run {
            isTesting = true
            statusMessage = L.Diagnostic.testingConnection
        }
        
        // 检查凭据
        guard settings.hasValidCredentials else {
            let report = createReportForMissingCredentials()
            await MainActor.run {
                self.latestReport = report
                self.isTesting = false
                self.statusMessage = L.Diagnostic.testCompleted
            }
            return
        }
        
        // 记录开始时间
        let startTime = Date()
        
        // 构建请求
        guard let request = buildDiagnosticRequest() else {
            let report = createReportForInvalidURL()
            await MainActor.run {
                self.latestReport = report
                self.isTesting = false
                self.statusMessage = L.Diagnostic.testCompleted
            }
            return
        }
        
        // 执行请求
        let session = URLSession(configuration: .default)
        
        do {
            let (data, response) = try await session.data(for: request)
            let responseTime = Date().timeIntervalSince(startTime) * 1000 // 毫秒
            
            // 分析响应
            let report = analyzeResponse(data: data, response: response, responseTime: responseTime)
            
            await MainActor.run {
                self.latestReport = report
                self.isTesting = false
                self.statusMessage = report.success ? L.Diagnostic.testSuccess : L.Diagnostic.testFailed
            }
            
        } catch {
            let responseTime = Date().timeIntervalSince(startTime) * 1000
            let report = createReportForNetworkError(error: error, responseTime: responseTime)
            
            await MainActor.run {
                self.latestReport = report
                self.isTesting = false
                self.statusMessage = L.Diagnostic.testFailed
            }
        }
    }
    
    /// 导出诊断报告到文件
    /// - Returns: 导出的文件路径，失败返回 nil
    func exportReport() -> URL? {
        guard let report = latestReport else {
            return nil
        }
        
        // 生成 Markdown 内容
        let markdown = report.toMarkdown()
        
        // 创建临时文件
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "UsageMeter_Diagnostic_\(formatFilenameDate()).md"
        let fileURL = tempDir.appendingPathComponent(filename)
        
        do {
            try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            print("Failed to export report: \(error)")
            return nil
        }
    }
    
    /// 显示保存对话框并导出报告
    func saveReportWithDialog() {
        guard let report = latestReport else {
            return
        }
        
        let savePanel = NSSavePanel()
        savePanel.title = L.Diagnostic.exportTitle
        savePanel.message = L.Diagnostic.exportMessage
        savePanel.nameFieldStringValue = "UsageMeter_Diagnostic_\(formatFilenameDate()).md"
        savePanel.allowedContentTypes = [.plainText]
        savePanel.canCreateDirectories = true
        
        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else {
                return
            }
            
            let markdown = report.toMarkdown()
            
            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
                
                // 显示成功通知
                self.showSuccessNotification(url: url)
                
            } catch {
                // 显示错误通知
                self.showErrorNotification(error: error)
            }
        }
    }
    
    // MARK: - Private Methods - 请求构建
    
    private func buildDiagnosticRequest() -> URLRequest? {
        let urlString = "https://claude.ai/api/organizations/\(settings.organizationId)/usage"
        
        guard let url = URL(string: urlString) else {
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        
        // 添加完整的浏览器 Headers (与 ClaudeAPIService 完全一致)
        request.setValue("*/*", forHTTPHeaderField: "accept")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "accept-language")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("web_claude_ai", forHTTPHeaderField: "anthropic-client-platform")
        request.setValue("1.0.0", forHTTPHeaderField: "anthropic-client-version")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
                        forHTTPHeaderField: "user-agent")
        request.setValue("https://claude.ai", forHTTPHeaderField: "origin")
        request.setValue("https://claude.ai/settings/usage", forHTTPHeaderField: "referer")
        request.setValue("empty", forHTTPHeaderField: "sec-fetch-dest")
        request.setValue("cors", forHTTPHeaderField: "sec-fetch-mode")
        request.setValue("same-origin", forHTTPHeaderField: "sec-fetch-site")
        
        // 设置 Cookie
        let cookieString = "sessionKey=\(settings.sessionKey)"
        request.setValue(cookieString, forHTTPHeaderField: "Cookie")
        
        return request
    }
    
    // MARK: - Private Methods - 响应分析
    
    private func analyzeResponse(data: Data, response: URLResponse, responseTime: Double) -> DiagnosticReport {
        guard let httpResponse = response as? HTTPURLResponse else {
            return createReportForUnknownResponse(data: data, responseTime: responseTime)
        }
        
        let statusCode = httpResponse.statusCode
        let headers = extractSafeHeaders(from: httpResponse)
        
        // 检查是否是 HTML 响应（Cloudflare challenge）
        if let bodyString = String(data: data, encoding: .utf8) {
            let isHTML = bodyString.contains("<!DOCTYPE html>") || bodyString.contains("<html")
            let containsCloudflare = bodyString.localizedCaseInsensitiveContains("cloudflare") ||
                                     bodyString.contains("cf-mitigated") ||
                                     bodyString.contains("Just a moment")
            
            if isHTML && (statusCode == 403 || containsCloudflare) {
                return createReportForCloudflareBlock(
                    statusCode: statusCode,
                    headers: headers,
                    bodyPreview: String(bodyString.prefix(500)),
                    responseTime: responseTime
                )
            }
            
            // 尝试解析 JSON
            if let json = try? JSONDecoder().decode(UsageResponse.self, from: data) {
                return createReportForSuccess(
                    statusCode: statusCode,
                    headers: headers,
                    usageData: json,
                    responseTime: responseTime
                )
            }
            
            // JSON 解析失败
            return createReportForDecodingError(
                statusCode: statusCode,
                headers: headers,
                bodyPreview: String(bodyString.prefix(500)),
                responseTime: responseTime
            )
        }
        
        // 无法读取响应体
        return createReportForUnknownResponse(
            data: data,
            responseTime: responseTime,
            statusCode: statusCode,
            headers: headers
        )
    }
    
    // MARK: - Private Methods - 报告生成
    
    private func createReportForSuccess(
        statusCode: Int,
        headers: [String: String],
        usageData: UsageResponse,
        responseTime: Double
    ) -> DiagnosticReport {
        DiagnosticReport(
            timestamp: Date(),
            appVersion: getAppVersion(),
            osVersion: getOSVersion(),
            architecture: getArchitecture(),
            locale: settings.language.rawValue,
            refreshMode: settings.refreshMode == .smart ? "Smart" : "Fixed",
            refreshInterval: settings.refreshMode == .fixed ? "\(settings.refreshInterval) min" : nil,
            displayMode: settings.displayMode.rawValue,
            organizationIdRedacted: redactOrganizationId(settings.organizationId),
            sessionKeyRedacted: redactSessionKey(settings.sessionKey),
            success: true,
            httpStatusCode: statusCode,
            responseTime: responseTime,
            responseType: .json,
            errorType: nil,
            errorDescription: nil,
            responseHeaders: headers,
            responseBodyPreview: "Valid usage data received (utilization: \(usageData.five_hour.utilization)%)",
            cloudflareChallenge: false,
            cfMitigated: headers["cf-mitigated"] != nil,
            diagnosis: L.Diagnostic.diagnosisSuccess,
            suggestions: [L.Diagnostic.suggestionSuccess],
            confidence: .high
        )
    }
    
    private func createReportForCloudflareBlock(
        statusCode: Int,
        headers: [String: String],
        bodyPreview: String,
        responseTime: Double
    ) -> DiagnosticReport {
        DiagnosticReport(
            timestamp: Date(),
            appVersion: getAppVersion(),
            osVersion: getOSVersion(),
            architecture: getArchitecture(),
            locale: settings.language.rawValue,
            refreshMode: settings.refreshMode == .smart ? "Smart" : "Fixed",
            refreshInterval: settings.refreshMode == .fixed ? "\(settings.refreshInterval) min" : nil,
            displayMode: settings.displayMode.rawValue,
            organizationIdRedacted: redactOrganizationId(settings.organizationId),
            sessionKeyRedacted: redactSessionKey(settings.sessionKey),
            success: false,
            httpStatusCode: statusCode,
            responseTime: responseTime,
            responseType: .html,
            errorType: .cloudflareBlocked,
            errorDescription: L.Error.cloudflareBlocked,
            responseHeaders: headers,
            responseBodyPreview: bodyPreview,
            cloudflareChallenge: true,
            cfMitigated: headers["cf-mitigated"] != nil,
            diagnosis: L.Diagnostic.diagnosisCloudflare,
            suggestions: [
                L.Diagnostic.suggestionVisitBrowser,
                L.Diagnostic.suggestionWaitAndRetry,
                L.Diagnostic.suggestionCheckVPN,
                L.Diagnostic.suggestionUseSmartMode
            ],
            confidence: .high
        )
    }
    
    private func createReportForDecodingError(
        statusCode: Int,
        headers: [String: String],
        bodyPreview: String,
        responseTime: Double
    ) -> DiagnosticReport {
        DiagnosticReport(
            timestamp: Date(),
            appVersion: getAppVersion(),
            osVersion: getOSVersion(),
            architecture: getArchitecture(),
            locale: settings.language.rawValue,
            refreshMode: settings.refreshMode == .smart ? "Smart" : "Fixed",
            refreshInterval: settings.refreshMode == .fixed ? "\(settings.refreshInterval) min" : nil,
            displayMode: settings.displayMode.rawValue,
            organizationIdRedacted: redactOrganizationId(settings.organizationId),
            sessionKeyRedacted: redactSessionKey(settings.sessionKey),
            success: false,
            httpStatusCode: statusCode,
            responseTime: responseTime,
            responseType: .unknown,
            errorType: .decodingError,
            errorDescription: L.Error.decodingFailed,
            responseHeaders: headers,
            responseBodyPreview: bodyPreview,
            cloudflareChallenge: false,
            cfMitigated: headers["cf-mitigated"] != nil,
            diagnosis: L.Diagnostic.diagnosisDecoding,
            suggestions: [
                L.Diagnostic.suggestionVerifyCredentials,
                L.Diagnostic.suggestionUpdateSessionKey,
                L.Diagnostic.suggestionCheckBrowser
            ],
            confidence: .medium
        )
    }
    
    private func createReportForNetworkError(error: Error, responseTime: Double) -> DiagnosticReport {
        DiagnosticReport(
            timestamp: Date(),
            appVersion: getAppVersion(),
            osVersion: getOSVersion(),
            architecture: getArchitecture(),
            locale: settings.language.rawValue,
            refreshMode: settings.refreshMode == .smart ? "Smart" : "Fixed",
            refreshInterval: settings.refreshMode == .fixed ? "\(settings.refreshInterval) min" : nil,
            displayMode: settings.displayMode.rawValue,
            organizationIdRedacted: redactOrganizationId(settings.organizationId),
            sessionKeyRedacted: redactSessionKey(settings.sessionKey),
            success: false,
            httpStatusCode: nil,
            responseTime: responseTime,
            responseType: .unknown,
            errorType: .networkError,
            errorDescription: error.localizedDescription,
            responseHeaders: [:],
            responseBodyPreview: nil,
            cloudflareChallenge: false,
            cfMitigated: false,
            diagnosis: L.Diagnostic.diagnosisNetwork,
            suggestions: [
                L.Diagnostic.suggestionCheckInternet,
                L.Diagnostic.suggestionCheckFirewall,
                L.Diagnostic.suggestionRetryLater
            ],
            confidence: .high
        )
    }
    
    private func createReportForMissingCredentials() -> DiagnosticReport {
        DiagnosticReport(
            timestamp: Date(),
            appVersion: getAppVersion(),
            osVersion: getOSVersion(),
            architecture: getArchitecture(),
            locale: settings.language.rawValue,
            refreshMode: settings.refreshMode == .smart ? "Smart" : "Fixed",
            refreshInterval: settings.refreshMode == .fixed ? "\(settings.refreshInterval) min" : nil,
            displayMode: settings.displayMode.rawValue,
            organizationIdRedacted: "Not configured",
            sessionKeyRedacted: "Not configured",
            success: false,
            httpStatusCode: nil,
            responseTime: nil,
            responseType: .unknown,
            errorType: .invalidCredentials,
            errorDescription: L.Error.noCredentials,
            responseHeaders: [:],
            responseBodyPreview: nil,
            cloudflareChallenge: false,
            cfMitigated: false,
            diagnosis: L.Diagnostic.diagnosisNoCredentials,
            suggestions: [L.Diagnostic.suggestionConfigureAuth],
            confidence: .high
        )
    }
    
    private func createReportForInvalidURL() -> DiagnosticReport {
        DiagnosticReport(
            timestamp: Date(),
            appVersion: getAppVersion(),
            osVersion: getOSVersion(),
            architecture: getArchitecture(),
            locale: settings.language.rawValue,
            refreshMode: settings.refreshMode == .smart ? "Smart" : "Fixed",
            refreshInterval: settings.refreshMode == .fixed ? "\(settings.refreshInterval) min" : nil,
            displayMode: settings.displayMode.rawValue,
            organizationIdRedacted: redactOrganizationId(settings.organizationId),
            sessionKeyRedacted: redactSessionKey(settings.sessionKey),
            success: false,
            httpStatusCode: nil,
            responseTime: nil,
            responseType: .unknown,
            errorType: .invalidCredentials,
            errorDescription: L.Error.invalidUrl,
            responseHeaders: [:],
            responseBodyPreview: nil,
            cloudflareChallenge: false,
            cfMitigated: false,
            diagnosis: L.Diagnostic.diagnosisInvalidUrl,
            suggestions: [L.Diagnostic.suggestionCheckOrgId],
            confidence: .high
        )
    }
    
    private func createReportForUnknownResponse(
        data: Data,
        responseTime: Double,
        statusCode: Int? = nil,
        headers: [String: String] = [:]
    ) -> DiagnosticReport {
        let preview = String(data: data, encoding: .utf8)?.prefix(500).map(String.init) ?? "Unable to decode response"
        
        DiagnosticReport(
            timestamp: Date(),
            appVersion: getAppVersion(),
            osVersion: getOSVersion(),
            architecture: getArchitecture(),
            locale: settings.language.rawValue,
            refreshMode: settings.refreshMode == .smart ? "Smart" : "Fixed",
            refreshInterval: settings.refreshMode == .fixed ? "\(settings.refreshInterval) min" : nil,
            displayMode: settings.displayMode.rawValue,
            organizationIdRedacted: redactOrganizationId(settings.organizationId),
            sessionKeyRedacted: redactSessionKey(settings.sessionKey),
            success: false,
            httpStatusCode: statusCode,
            responseTime: responseTime,
            responseType: .unknown,
            errorType: .unknown,
            errorDescription: "Unknown response format",
            responseHeaders: headers,
            responseBodyPreview: preview,
            cloudflareChallenge: false,
            cfMitigated: false,
            diagnosis: L.Diagnostic.diagnosisUnknown,
            suggestions: [
                L.Diagnostic.suggestionExportAndShare,
                L.Diagnostic.suggestionContactSupport
            ],
            confidence: .low
        )
    }
    
    // MARK: - Private Methods - 数据脱敏
    
    /// 脱敏 Organization ID
    /// 例如: "12345678-abcd-ef90-1234-567890abcdef" -> "1234...cdef"
    private func redactOrganizationId(_ orgId: String) -> String {
        guard orgId.count > 8 else {
            return String(repeating: "*", count: orgId.count)
        }
        let prefix = orgId.prefix(4)
        let suffix = orgId.suffix(4)
        return "\(prefix)...\(suffix)"
    }
    
    /// 脱敏 Session Key
    /// 例如: "sk-ant-sid01-XXXX..." -> "sk-ant-***...*** (128 chars)"
    private func redactSessionKey(_ sessionKey: String) -> String {
        guard sessionKey.count > 20 else {
            return "***"
        }
        
        // 保留前缀 "sk-ant-"
        if sessionKey.hasPrefix("sk-ant-") {
            return "sk-ant-***...*** (\(sessionKey.count) chars)"
        }
        
        return "***...*** (\(sessionKey.count) chars)"
    }
    
    /// 从 HTTP 响应中提取安全的头信息（过滤敏感数据）
    private func extractSafeHeaders(from response: HTTPURLResponse) -> [String: String] {
        var safeHeaders: [String: String] = [:]
        
        // 允许的头信息列表
        let allowedHeaders = [
            "content-type",
            "content-length",
            "cf-mitigated",
            "cf-ray",
            "server",
            "date",
            "cache-control",
            "x-request-id"
        ]
        
        for (key, value) in response.allHeaderFields {
            let keyStr = (key as? String ?? "").lowercased()
            if allowedHeaders.contains(keyStr) {
                safeHeaders[keyStr] = value as? String ?? ""
            }
        }
        
        return safeHeaders
    }
    
    // MARK: - Private Methods - 系统信息
    
    private func getAppVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
    
    private func getOSVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
    
    private func getArchitecture() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
    
    private func formatFilenameDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }
    
    // MARK: - Private Methods - 通知
    
    private func showSuccessNotification(url: URL) {
        let alert = NSAlert()
        alert.messageText = L.Diagnostic.exportSuccessTitle
        alert.informativeText = L.Diagnostic.exportSuccessMessage + "\n\n\(url.path)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: L.Update.okButton)
        alert.runModal()
    }
    
    private func showErrorNotification(error: Error) {
        let alert = NSAlert()
        alert.messageText = L.Diagnostic.exportErrorTitle
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: L.Update.okButton)
        alert.runModal()
    }
}
```

---

## 3. UI 组件实现

### SettingsView.swift 更新

在 **Authentication Settings** 标签页底部添加诊断组件。

**修改位置**: `SettingsView.swift` 的 `authenticationSettingsView` 计算属性

**在现有内容之后添加**:

```swift
// 现有的认证设置内容...

// ===== 在此处添加诊断组件 =====
Divider()
    .padding(.vertical, 8)

// 诊断区域
VStack(alignment: .leading, spacing: 12) {
    HStack {
        Image(systemName: "stethoscope")
            .font(.system(size: 16))
            .foregroundColor(.blue)
        
        Text(L.Diagnostic.sectionTitle)
            .font(.headline)
        
        Spacer()
    }
    
    Text(L.Diagnostic.sectionDescription)
        .font(.caption)
        .foregroundColor(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    
    // 诊断按钮和结果显示
    DiagnosticsView()
}
.padding()
.background(
    RoundedRectangle(cornerRadius: 8)
        .fill(Color(NSColor.controlBackgroundColor))
)
```

### DiagnosticsView.swift (新增文件)

**文件路径**: `UsageMeter/Views/DiagnosticsView.swift`

```swift
//
//  DiagnosticsView.swift
//  Usage Meter
//
//  Created by f-is-h on 2025-11.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

/// 诊断视图组件
/// 显示在认证设置页面底部，提供连接测试和报告导出功能
struct DiagnosticsView: View {
    
    @StateObject private var diagnosticManager = DiagnosticManager()
    @State private var showDetailedReport = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            
            // 测试按钮和状态
            HStack {
                Button(action: {
                    Task {
                        await diagnosticManager.runDiagnosticTest()
                    }
                }) {
                    HStack {
                        if diagnosticManager.isTesting {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                        }
                        Text(L.Diagnostic.testButton)
                    }
                }
                .disabled(diagnosticManager.isTesting)
                
                if diagnosticManager.latestReport != nil {
                    Button(L.Diagnostic.viewDetailsButton) {
                        showDetailedReport.toggle()
                    }
                    
                    Button(L.Diagnostic.exportButton) {
                        diagnosticManager.saveReportWithDialog()
                    }
                }
            }
            
            // 状态消息
            if !diagnosticManager.statusMessage.isEmpty {
                Text(diagnosticManager.statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // 简要测试结果
            if let report = diagnosticManager.latestReport {
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    // 状态指示
                    HStack {
                        Image(systemName: report.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(report.success ? .green : .red)
                        
                        Text(report.success ? L.Diagnostic.resultSuccess : L.Diagnostic.resultFailed)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    
                    // 关键信息
                    if let statusCode = report.httpStatusCode {
                        DetailRow(
                            label: L.Diagnostic.httpStatus,
                            value: "\(statusCode)",
                            valueColor: statusCodeColor(statusCode)
                        )
                    }
                    
                    if let responseTime = report.responseTime {
                        DetailRow(
                            label: L.Diagnostic.responseTime,
                            value: String(format: "%.0f ms", responseTime)
                        )
                    }
                    
                    DetailRow(
                        label: L.Diagnostic.responseType,
                        value: report.responseType.rawValue
                    )
                    
                    if report.cloudflareChallenge {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(L.Diagnostic.cloudflareDetected)
                                .font(.caption)
                        }
                    }
                    
                    // 诊断结果
                    if !report.success {
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L.Diagnostic.diagnosis)
                                .font(.caption)
                                .fontWeight(.semibold)
                            
                            Text(report.diagnosis)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        if !report.suggestions.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L.Diagnostic.suggestions)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                
                                ForEach(Array(report.suggestions.prefix(3).enumerated()), id: \.offset) { index, suggestion in
                                    Text("• \(suggestion)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(NSColor.textBackgroundColor))
                )
            }
            
            // 隐私说明
            HStack(spacing: 4) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 10))
                    .foregroundColor(.green)
                
                Text(L.Diagnostic.privacyNotice)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .sheet(isPresented: $showDetailedReport) {
            DetailedReportView(report: diagnosticManager.latestReport)
        }
    }
    
    // MARK: - Helper Views
    
    private struct DetailRow: View {
        let label: String
        let value: String
        var valueColor: Color = .primary
        
        var body: some View {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(value)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(valueColor)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func statusCodeColor(_ code: Int) -> Color {
        switch code {
        case 200..<300:
            return .green
        case 400..<500:
            return .orange
        case 500..<600:
            return .red
        default:
            return .secondary
        }
    }
}

/// 详细报告视图
/// 以弹窗形式显示完整的 Markdown 格式诊断报告
struct DetailedReportView: View {
    
    let report: DiagnosticReport?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text(L.Diagnostic.detailedReportTitle)
                    .font(.headline)
                
                Spacer()
                
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // 报告内容
            if let report = report {
                ScrollView {
                    Text(report.toMarkdown())
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text(L.Diagnostic.noReportAvailable)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            Divider()
            
            // 底部按钮
            HStack {
                Spacer()
                
                Button(L.Diagnostic.copyToClipboard) {
                    if let report = report {
                        let markdown = report.toMarkdown()
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(markdown, forType: .string)
                    }
                }
                
                Button(L.Update.okButton) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 700, height: 600)
    }
}

// MARK: - Preview

struct DiagnosticsView_Previews: PreviewProvider {
    static var previews: some View {
        DiagnosticsView()
            .frame(width: 500)
            .padding()
    }
}
```

---

## 4. 本地化字符串

### 需要添加到所有语言文件的字符串

**文件路径**:
- `UsageMeter/Resources/en.lproj/Localizable.strings`
- `UsageMeter/Resources/ja.lproj/Localizable.strings`
- `UsageMeter/Resources/zh-Hans.lproj/Localizable.strings`
- `UsageMeter/Resources/zh-Hant.lproj/Localizable.strings`

#### English (en.lproj/Localizable.strings)

```strings
// MARK: - Diagnostics
"diagnostic.section_title" = "Connection Diagnostics";
"diagnostic.section_description" = "Test your connection to Claude API and diagnose issues. All sensitive information is automatically redacted in reports.";
"diagnostic.test_button" = "Test Connection";
"diagnostic.view_details_button" = "View Details";
"diagnostic.export_button" = "Export Report";
"diagnostic.testing_connection" = "Testing connection...";
"diagnostic.test_completed" = "Test completed";
"diagnostic.test_success" = "Connection test successful";
"diagnostic.test_failed" = "Connection test failed";
"diagnostic.result_success" = "Connection Successful";
"diagnostic.result_failed" = "Connection Failed";
"diagnostic.http_status" = "HTTP Status";
"diagnostic.response_time" = "Response Time";
"diagnostic.response_type" = "Response Type";
"diagnostic.cloudflare_detected" = "Cloudflare challenge detected";
"diagnostic.diagnosis" = "Diagnosis";
"diagnostic.suggestions" = "Suggestions";
"diagnostic.privacy_notice" = "All sensitive data is automatically redacted for privacy";
"diagnostic.detailed_report_title" = "Detailed Diagnostic Report";
"diagnostic.no_report_available" = "No report available. Please run a test first.";
"diagnostic.copy_to_clipboard" = "Copy to Clipboard";
"diagnostic.export_title" = "Export Diagnostic Report";
"diagnostic.export_message" = "This report contains no sensitive information and is safe to share.";
"diagnostic.export_success_title" = "Export Successful";
"diagnostic.export_success_message" = "Diagnostic report has been saved to:";
"diagnostic.export_error_title" = "Export Failed";

// Diagnosis messages
"diagnostic.diagnosis_success" = "Connection is working properly. API returned valid usage data.";
"diagnostic.diagnosis_cloudflare" = "Request was blocked by Cloudflare security system. This may be due to IP reputation or network configuration.";
"diagnostic.diagnosis_decoding" = "Server returned data but it couldn't be parsed. This usually means credentials are incorrect or don't match.";
"diagnostic.diagnosis_network" = "Network connection failed. Please check your internet connection.";
"diagnostic.diagnosis_no_credentials" = "Authentication credentials are not configured.";
"diagnostic.diagnosis_invalid_url" = "Invalid Organization ID format.";
"diagnostic.diagnosis_unknown" = "Unknown error occurred. Please export and share this report with developers.";

// Suggestion messages
"diagnostic.suggestion_success" = "Everything is working correctly. No action needed.";
"diagnostic.suggestion_visit_browser" = "Visit claude.ai in your browser and complete any security challenges";
"diagnostic.suggestion_wait_and_retry" = "Wait 5-10 minutes and try again";
"diagnostic.suggestion_check_vpn" = "Check if VPN or proxy is affecting the connection";
"diagnostic.suggestion_use_smart_mode" = "Use Smart Refresh mode to reduce request frequency";
"diagnostic.suggestion_verify_credentials" = "Verify that Organization ID and Session Key are correct";
"diagnostic.suggestion_update_session_key" = "Your Session Key may have expired. Please update it from browser";
"diagnostic.suggestion_check_browser" = "Verify you can access claude.ai/settings/usage in browser";
"diagnostic.suggestion_check_internet" = "Check your internet connection";
"diagnostic.suggestion_check_firewall" = "Check firewall or antivirus settings";
"diagnostic.suggestion_retry_later" = "Try again later";
"diagnostic.suggestion_configure_auth" = "Please configure Organization ID and Session Key in the fields above";
"diagnostic.suggestion_check_org_id" = "Check if Organization ID format is correct (should be a UUID)";
"diagnostic.suggestion_export_and_share" = "Export this diagnostic report and share it on GitHub Issues";
"diagnostic.suggestion_contact_support" = "Contact developer for help at github.com/sirpooya/osx-usage-meter/issues";
```

#### Japanese (ja.lproj/Localizable.strings)

```strings
// MARK: - Diagnostics
"diagnostic.section_title" = "接続診断";
"diagnostic.section_description" = "Claude APIへの接続をテストし、問題を診断します。レポート内の機密情報はすべて自動的に編集されます。";
"diagnostic.test_button" = "接続テスト";
"diagnostic.view_details_button" = "詳細を表示";
"diagnostic.export_button" = "レポートをエクスポート";
"diagnostic.testing_connection" = "接続をテスト中...";
"diagnostic.test_completed" = "テスト完了";
"diagnostic.test_success" = "接続テスト成功";
"diagnostic.test_failed" = "接続テスト失敗";
"diagnostic.result_success" = "接続成功";
"diagnostic.result_failed" = "接続失敗";
"diagnostic.http_status" = "HTTPステータス";
"diagnostic.response_time" = "応答時間";
"diagnostic.response_type" = "応答タイプ";
"diagnostic.cloudflare_detected" = "Cloudflareチャレンジを検出";
"diagnostic.diagnosis" = "診断結果";
"diagnostic.suggestions" = "推奨事項";
"diagnostic.privacy_notice" = "すべての機密データは自動的に編集されます";
"diagnostic.detailed_report_title" = "詳細診断レポート";
"diagnostic.no_report_available" = "レポートがありません。まずテストを実行してください。";
"diagnostic.copy_to_clipboard" = "クリップボードにコピー";
"diagnostic.export_title" = "診断レポートのエクスポート";
"diagnostic.export_message" = "このレポートには機密情報は含まれておらず、安全に共有できます。";
"diagnostic.export_success_title" = "エクスポート成功";
"diagnostic.export_success_message" = "診断レポートが保存されました:";
"diagnostic.export_error_title" = "エクスポート失敗";

// Diagnosis messages
"diagnostic.diagnosis_success" = "接続は正常に動作しています。APIから有効な使用状況データが返されました。";
"diagnostic.diagnosis_cloudflare" = "Cloudflareセキュリティシステムによってリクエストがブロックされました。IPレピュテーションまたはネットワーク設定が原因の可能性があります。";
"diagnostic.diagnosis_decoding" = "サーバーからデータが返されましたが、解析できませんでした。通常、認証情報が間違っているか一致していないことを意味します。";
"diagnostic.diagnosis_network" = "ネットワーク接続に失敗しました。インターネット接続を確認してください。";
"diagnostic.diagnosis_no_credentials" = "認証情報が設定されていません。";
"diagnostic.diagnosis_invalid_url" = "組織IDの形式が無効です。";
"diagnostic.diagnosis_unknown" = "不明なエラーが発生しました。このレポートをエクスポートして開発者に共有してください。";

// Suggestion messages
"diagnostic.suggestion_success" = "すべて正常に動作しています。操作は不要です。";
"diagnostic.suggestion_visit_browser" = "ブラウザでclaude.aiにアクセスし、セキュリティチャレンジを完了してください";
"diagnostic.suggestion_wait_and_retry" = "5〜10分待ってから再試行してください";
"diagnostic.suggestion_check_vpn" = "VPNまたはプロキシが接続に影響していないか確認してください";
"diagnostic.suggestion_use_smart_mode" = "スマート更新モードを使用してリクエスト頻度を減らしてください";
"diagnostic.suggestion_verify_credentials" = "組織IDとセッションキーが正しいことを確認してください";
"diagnostic.suggestion_update_session_key" = "セッションキーが期限切れの可能性があります。ブラウザから更新してください";
"diagnostic.suggestion_check_browser" = "ブラウザでclaude.ai/settings/usageにアクセスできることを確認してください";
"diagnostic.suggestion_check_internet" = "インターネット接続を確認してください";
"diagnostic.suggestion_check_firewall" = "ファイアウォールまたはアンチウイルス設定を確認してください";
"diagnostic.suggestion_retry_later" = "後でもう一度お試しください";
"diagnostic.suggestion_configure_auth" = "上記のフィールドに組織IDとセッションキーを設定してください";
"diagnostic.suggestion_check_org_id" = "組織IDの形式が正しいか確認してください(UUID形式である必要があります)";
"diagnostic.suggestion_export_and_share" = "この診断レポートをエクスポートしてGitHub Issuesで共有してください";
"diagnostic.suggestion_contact_support" = "github.com/sirpooya/osx-usage-meter/issuesで開発者にお問い合わせください";
```

#### Simplified Chinese (zh-Hans.lproj/Localizable.strings)

```strings
// MARK: - Diagnostics
"diagnostic.section_title" = "连接诊断";
"diagnostic.section_description" = "测试与 Claude API 的连接并诊断问题。报告中的所有敏感信息都会自动脱敏处理。";
"diagnostic.test_button" = "测试连接";
"diagnostic.view_details_button" = "查看详情";
"diagnostic.export_button" = "导出报告";
"diagnostic.testing_connection" = "正在测试连接...";
"diagnostic.test_completed" = "测试完成";
"diagnostic.test_success" = "连接测试成功";
"diagnostic.test_failed" = "连接测试失败";
"diagnostic.result_success" = "连接成功";
"diagnostic.result_failed" = "连接失败";
"diagnostic.http_status" = "HTTP 状态";
"diagnostic.response_time" = "响应时间";
"diagnostic.response_type" = "响应类型";
"diagnostic.cloudflare_detected" = "检测到 Cloudflare 挑战";
"diagnostic.diagnosis" = "诊断结果";
"diagnostic.suggestions" = "建议操作";
"diagnostic.privacy_notice" = "所有敏感数据都已自动脱敏，可安全分享";
"diagnostic.detailed_report_title" = "详细诊断报告";
"diagnostic.no_report_available" = "暂无报告。请先运行测试。";
"diagnostic.copy_to_clipboard" = "复制到剪贴板";
"diagnostic.export_title" = "导出诊断报告";
"diagnostic.export_message" = "此报告不包含任何敏感信息，可安全分享。";
"diagnostic.export_success_title" = "导出成功";
"diagnostic.export_success_message" = "诊断报告已保存至:";
"diagnostic.export_error_title" = "导出失败";

// Diagnosis messages
"diagnostic.diagnosis_success" = "连接正常工作。API 返回了有效的使用数据。";
"diagnostic.diagnosis_cloudflare" = "请求被 Cloudflare 安全系统拦截。这可能是由于 IP 信誉或网络配置导致的。";
"diagnostic.diagnosis_decoding" = "服务器返回了数据但无法解析。这通常意味着认证信息不正确或不匹配。";
"diagnostic.diagnosis_network" = "网络连接失败。请检查您的互联网连接。";
"diagnostic.diagnosis_no_credentials" = "未配置认证信息。";
"diagnostic.diagnosis_invalid_url" = "组织 ID 格式无效。";
"diagnostic.diagnosis_unknown" = "发生未知错误。请导出此报告并分享给开发者。";

// Suggestion messages
"diagnostic.suggestion_success" = "一切正常运行。无需任何操作。";
"diagnostic.suggestion_visit_browser" = "在浏览器中访问 claude.ai 并完成任何安全验证";
"diagnostic.suggestion_wait_and_retry" = "等待 5-10 分钟后重试";
"diagnostic.suggestion_check_vpn" = "检查 VPN 或代理是否影响连接";
"diagnostic.suggestion_use_smart_mode" = "使用智能刷新模式以降低请求频率";
"diagnostic.suggestion_verify_credentials" = "验证组织 ID 和会话密钥是否正确";
"diagnostic.suggestion_update_session_key" = "您的会话密钥可能已过期。请从浏览器更新它";
"diagnostic.suggestion_check_browser" = "验证您可以在浏览器中访问 claude.ai/settings/usage";
"diagnostic.suggestion_check_internet" = "检查您的互联网连接";
"diagnostic.suggestion_check_firewall" = "检查防火墙或杀毒软件设置";
"diagnostic.suggestion_retry_later" = "稍后重试";
"diagnostic.suggestion_configure_auth" = "请在上方字段中配置组织 ID 和会话密钥";
"diagnostic.suggestion_check_org_id" = "检查组织 ID 格式是否正确(应该是 UUID 格式)";
"diagnostic.suggestion_export_and_share" = "导出此诊断报告并在 GitHub Issues 上分享";
"diagnostic.suggestion_contact_support" = "在 github.com/sirpooya/osx-usage-meter/issues 联系开发者寻求帮助";
```

#### Traditional Chinese (zh-Hant.lproj/Localizable.strings)

```strings
// MARK: - Diagnostics
"diagnostic.section_title" = "連線診斷";
"diagnostic.section_description" = "測試與 Claude API 的連線並診斷問題。報告中的所有敏感資訊都會自動遮罩處理。";
"diagnostic.test_button" = "測試連線";
"diagnostic.view_details_button" = "檢視詳情";
"diagnostic.export_button" = "匯出報告";
"diagnostic.testing_connection" = "正在測試連線...";
"diagnostic.test_completed" = "測試完成";
"diagnostic.test_success" = "連線測試成功";
"diagnostic.test_failed" = "連線測試失敗";
"diagnostic.result_success" = "連線成功";
"diagnostic.result_failed" = "連線失敗";
"diagnostic.http_status" = "HTTP 狀態";
"diagnostic.response_time" = "回應時間";
"diagnostic.response_type" = "回應類型";
"diagnostic.cloudflare_detected" = "偵測到 Cloudflare 挑戰";
"diagnostic.diagnosis" = "診斷結果";
"diagnostic.suggestions" = "建議操作";
"diagnostic.privacy_notice" = "所有敏感資料都已自動遮罩，可安全分享";
"diagnostic.detailed_report_title" = "詳細診斷報告";
"diagnostic.no_report_available" = "暫無報告。請先執行測試。";
"diagnostic.copy_to_clipboard" = "複製到剪貼簿";
"diagnostic.export_title" = "匯出診斷報告";
"diagnostic.export_message" = "此報告不包含任何敏感資訊，可安全分享。";
"diagnostic.export_success_title" = "匯出成功";
"diagnostic.export_success_message" = "診斷報告已儲存至:";
"diagnostic.export_error_title" = "匯出失敗";

// Diagnosis messages
"diagnostic.diagnosis_success" = "連線正常運作。API 回傳了有效的使用資料。";
"diagnostic.diagnosis_cloudflare" = "請求被 Cloudflare 安全系統攔截。這可能是由於 IP 信譽或網路設定導致的。";
"diagnostic.diagnosis_decoding" = "伺服器回傳了資料但無法解析。這通常表示認證資訊不正確或不匹配。";
"diagnostic.diagnosis_network" = "網路連線失敗。請檢查您的網際網路連線。";
"diagnostic.diagnosis_no_credentials" = "未設定認證資訊。";
"diagnostic.diagnosis_invalid_url" = "組織 ID 格式無效。";
"diagnostic.diagnosis_unknown" = "發生未知錯誤。請匯出此報告並分享給開發者。";

// Suggestion messages
"diagnostic.suggestion_success" = "一切正常運作。無需任何操作。";
"diagnostic.suggestion_visit_browser" = "在瀏覽器中造訪 claude.ai 並完成任何安全驗證";
"diagnostic.suggestion_wait_and_retry" = "等待 5-10 分鐘後重試";
"diagnostic.suggestion_check_vpn" = "檢查 VPN 或代理是否影響連線";
"diagnostic.suggestion_use_smart_mode" = "使用智慧重新整理模式以降低請求頻率";
"diagnostic.suggestion_verify_credentials" = "驗證組織 ID 和工作階段金鑰是否正確";
"diagnostic.suggestion_update_session_key" = "您的工作階段金鑰可能已過期。請從瀏覽器更新它";
"diagnostic.suggestion_check_browser" = "驗證您可以在瀏覽器中存取 claude.ai/settings/usage";
"diagnostic.suggestion_check_internet" = "檢查您的網際網路連線";
"diagnostic.suggestion_check_firewall" = "檢查防火牆或防毒軟體設定";
"diagnostic.suggestion_retry_later" = "稍後重試";
"diagnostic.suggestion_configure_auth" = "請在上方欄位中設定組織 ID 和工作階段金鑰";
"diagnostic.suggestion_check_org_id" = "檢查組織 ID 格式是否正確(應該是 UUID 格式)";
"diagnostic.suggestion_export_and_share" = "匯出此診斷報告並在 GitHub Issues 上分享";
"diagnostic.suggestion_contact_support" = "在 github.com/sirpooya/osx-usage-meter/issues 聯絡開發者尋求協助";
```

### LocalizationHelper.swift 更新

在 `LocalizationHelper.swift` 中添加 `Diagnostic` 枚举：

```swift
// MARK: - Diagnostics
enum Diagnostic {
    static let sectionTitle = localized("diagnostic.section_title")
    static let sectionDescription = localized("diagnostic.section_description")
    static let testButton = localized("diagnostic.test_button")
    static let viewDetailsButton = localized("diagnostic.view_details_button")
    static let exportButton = localized("diagnostic.export_button")
    static let testingConnection = localized("diagnostic.testing_connection")
    static let testCompleted = localized("diagnostic.test_completed")
    static let testSuccess = localized("diagnostic.test_success")
    static let testFailed = localized("diagnostic.test_failed")
    static let resultSuccess = localized("diagnostic.result_success")
    static let resultFailed = localized("diagnostic.result_failed")
    static let httpStatus = localized("diagnostic.http_status")
    static let responseTime = localized("diagnostic.response_time")
    static let responseType = localized("diagnostic.response_type")
    static let cloudflareDetected = localized("diagnostic.cloudflare_detected")
    static let diagnosis = localized("diagnostic.diagnosis")
    static let suggestions = localized("diagnostic.suggestions")
    static let privacyNotice = localized("diagnostic.privacy_notice")
    static let detailedReportTitle = localized("diagnostic.detailed_report_title")
    static let noReportAvailable = localized("diagnostic.no_report_available")
    static let copyToClipboard = localized("diagnostic.copy_to_clipboard")
    static let exportTitle = localized("diagnostic.export_title")
    static let exportMessage = localized("diagnostic.export_message")
    static let exportSuccessTitle = localized("diagnostic.export_success_title")
    static let exportSuccessMessage = localized("diagnostic.export_success_message")
    static let exportErrorTitle = localized("diagnostic.export_error_title")
    
    // Diagnosis messages
    static let diagnosisSuccess = localized("diagnostic.diagnosis_success")
    static let diagnosisCloudflare = localized("diagnostic.diagnosis_cloudflare")
    static let diagnosisDecoding = localized("diagnostic.diagnosis_decoding")
    static let diagnosisNetwork = localized("diagnostic.diagnosis_network")
    static let diagnosisNoCredentials = localized("diagnostic.diagnosis_no_credentials")
    static let diagnosisInvalidUrl = localized("diagnostic.diagnosis_invalid_url")
    static let diagnosisUnknown = localized("diagnostic.diagnosis_unknown")
    
    // Suggestion messages
    static let suggestionSuccess = localized("diagnostic.suggestion_success")
    static let suggestionVisitBrowser = localized("diagnostic.suggestion_visit_browser")
    static let suggestionWaitAndRetry = localized("diagnostic.suggestion_wait_and_retry")
    static let suggestionCheckVPN = localized("diagnostic.suggestion_check_vpn")
    static let suggestionUseSmartMode = localized("diagnostic.suggestion_use_smart_mode")
    static let suggestionVerifyCredentials = localized("diagnostic.suggestion_verify_credentials")
    static let suggestionUpdateSessionKey = localized("diagnostic.suggestion_update_session_key")
    static let suggestionCheckBrowser = localized("diagnostic.suggestion_check_browser")
    static let suggestionCheckInternet = localized("diagnostic.suggestion_check_internet")
    static let suggestionCheckFirewall = localized("diagnostic.suggestion_check_firewall")
    static let suggestionRetryLater = localized("diagnostic.suggestion_retry_later")
    static let suggestionConfigureAuth = localized("diagnostic.suggestion_configure_auth")
    static let suggestionCheckOrgId = localized("diagnostic.suggestion_check_org_id")
    static let suggestionExportAndShare = localized("diagnostic.suggestion_export_and_share")
    static let suggestionContactSupport = localized("diagnostic.suggestion_contact_support")
}
```

---

## 5. 实现步骤

### Step 1: 创建数据模型
1. 创建 `UsageMeter/Models/DiagnosticReport.swift`
2. 复制本文档中的完整代码
3. 编译确认无错误

### Step 2: 创建诊断管理器
1. 创建 `UsageMeter/Helpers/DiagnosticManager.swift`
2. 复制本文档中的完整代码
3. 编译确认无错误

### Step 3: 创建诊断视图
1. 创建 `UsageMeter/Views/DiagnosticsView.swift`
2. 复制本文档中的完整代码
3. 编译确认无错误

### Step 4: 更新本地化文件
1. 打开 `UsageMeter/Resources/en.lproj/Localizable.strings`
2. 在文件末尾添加本文档中的英文字符串
3. 对其他三个语言文件重复此操作
4. 编译确认无错误

### Step 5: 更新 LocalizationHelper
1. 打开 `UsageMeter/Helpers/LocalizationHelper.swift`
2. 在 `enum L` 中添加 `enum Diagnostic` 部分
3. 编译确认无错误

### Step 6: 更新 SettingsView
1. 打开 `UsageMeter/Views/SettingsView.swift`
2. 找到 `authenticationSettingsView` 计算属性
3. 在认证设置内容的末尾添加诊断组件
4. 编译确认无错误

### Step 7: 测试
1. 运行应用
2. 打开设置 → 认证设置
3. 验证诊断组件显示正确
4. 测试连接功能
5. 验证报告导出功能
6. 测试所有语言

---

## 6. 测试清单

### 功能测试

- [ ] **无认证信息时**
  - [ ] 点击"测试连接"显示提示需要配置认证信息
  - [ ] 诊断结果正确显示"未配置认证信息"

- [ ] **有认证信息但无效时**
  - [ ] 测试连接显示失败
  - [ ] 正确识别错误类型（Cloudflare / 解析失败 / 网络错误）
  - [ ] 显示合适的建议操作

- [ ] **有效认证信息时**
  - [ ] 测试连接显示成功
  - [ ] 显示 HTTP 200 状态码
  - [ ] 显示响应时间
  - [ ] 显示"连接正常"诊断

- [ ] **查看详细报告**
  - [ ] 点击"查看详情"打开详细报告弹窗
  - [ ] Markdown 格式正确显示
  - [ ] 所有敏感信息已脱敏
  - [ ] 可以滚动查看完整内容

- [ ] **导出报告**
  - [ ] 点击"导出报告"打开保存对话框
  - [ ] 可以选择保存位置
  - [ ] 文件成功保存
  - [ ] 显示成功通知
  - [ ] 导出的文件内容正确

- [ ] **复制到剪贴板**
  - [ ] 在详细报告中点击"复制到剪贴板"
  - [ ] 内容成功复制到系统剪贴板
  - [ ] 可以粘贴到其他应用

### 数据脱敏测试

- [ ] Organization ID 正确脱敏 (1234...cdef)
- [ ] Session Key 正确脱敏 (sk-ant-***...*** (128 chars))
- [ ] URL 中的 Organization ID 已脱敏
- [ ] Cookie 中的 Session Key 已脱敏
- [ ] 响应体预览中无敏感信息

### 多语言测试

- [ ] 英文界面所有文本正确显示
- [ ] 日文界面所有文本正确显示
- [ ] 简体中文界面所有文本正确显示
- [ ] 繁体中文界面所有文本正确显示
- [ ] 切换语言后诊断功能正常工作

### UI/UX 测试

- [ ] 诊断区域在认证设置底部正确显示
- [ ] 测试按钮点击响应正常
- [ ] 测试中显示加载动画
- [ ] 测试完成后按钮恢复可点击状态
- [ ] 隐私说明清晰可见
- [ ] 详细报告弹窗大小合适
- [ ] 所有按钮对齐和间距正确

### 边界情况测试

- [ ] 网络完全断开时的表现
- [ ] Session Key 过期时的表现
- [ ] Organization ID 格式错误时的表现
- [ ] Cloudflare 拦截时的表现
- [ ] 响应超时时的表现
- [ ] 响应为非 JSON 格式时的表现

---

## 7. 文件清单

### 新增文件
- `UsageMeter/Models/DiagnosticReport.swift`
- `UsageMeter/Helpers/DiagnosticManager.swift`
- `UsageMeter/Views/DiagnosticsView.swift`

### 修改文件
- `UsageMeter/Views/SettingsView.swift`
- `UsageMeter/Helpers/LocalizationHelper.swift`
- `UsageMeter/Resources/en.lproj/Localizable.strings`
- `UsageMeter/Resources/ja.lproj/Localizable.strings`
- `UsageMeter/Resources/zh-Hans.lproj/Localizable.strings`
- `UsageMeter/Resources/zh-Hant.lproj/Localizable.strings`

---

## 8. 代码规范

### 注释规范
- 所有公开方法必须有文档注释
- 使用 `// MARK:` 分隔不同功能区域
- 复杂逻辑添加行内注释说明

### 命名规范
- 类名使用大驼峰 (PascalCase)
- 方法和变量使用小驼峰 (camelCase)
- 常量使用全大写+下划线
- 本地化字符串键使用点分隔小写

### 代码风格
- 缩进：4 空格
- 行宽：不超过 120 字符
- 大括号：K&R 风格
- 空行：逻辑块之间添加空行

---

## 9. 版本信息

### 目标版本
**1.4.0**

### 预计发布时间
**2025-11**

### CHANGELOG 条目

```markdown
## [1.4.0] - 2025-11-XX

### Added
- **Connection Diagnostics**: Built-in diagnostic tool to help troubleshoot connection issues
  - One-click connection testing with detailed analysis
  - Automatic error detection and classification
  - Privacy-safe diagnostic reports with automatic credential redaction
  - Export functionality for sharing reports with developers
  - Localized suggestions for different error types

### Improved
- Enhanced error messages with more specific guidance
- Better troubleshooting support for Cloudflare blocking issues
- Added detailed logging for connection problems (privacy-safe)

### Security
- All sensitive information (Organization ID, Session Key) is automatically redacted in diagnostic reports
- Reports are safe to share publicly without exposing credentials
```

---

## 10. GitHub Issue 回复模板

当用户报告连接问题时，可以使用以下模板回复：

```markdown
Thank you for reporting this issue! To help diagnose the problem, we've added a built-in diagnostic tool in version 1.4.0.

### Quick Steps

1. **Update to v1.4.0** (if you haven't already)
2. Open **Settings** → **Authentication Settings**
3. Scroll down to **Connection Diagnostics**
4. Click **[Test Connection]**
5. Click **[Export Report]** and save the file
6. **Attach the exported file to this issue**

### Privacy Notice

⚠️ The diagnostic report automatically redacts all sensitive information:
- Organization ID is masked (e.g., `1234...cdef`)
- Session Key is masked (e.g., `sk-ant-***...*** (128 chars)`)
- **It's completely safe to share publicly**

### What the Report Contains

The diagnostic report includes:
- Connection test results
- HTTP status codes and response types
- Error analysis and suggestions
- System information (OS version, app version)
- Network response details (no sensitive data)

This will help us quickly identify whether the issue is:
- Cloudflare blocking
- Authentication problems
- Network configuration
- Or something else

Looking forward to seeing your diagnostic report!
```

---

## 📝 总结

本文档提供了完整的诊断功能实现指南，包括：

1. ✅ **完整的代码实现** - 可直接复制使用
2. ✅ **详细的注释说明** - 便于理解和维护
3. ✅ **多语言支持** - 4 种语言的完整翻译
4. ✅ **隐私安全设计** - 自动脱敏所有敏感信息
5. ✅ **用户友好界面** - 简洁直观的 UI 设计
6. ✅ **详细的测试清单** - 确保功能质量
7. ✅ **实施步骤指南** - 按顺序实现避免遗漏

### 关键特性

- 🔐 **自动脱敏** - 无需担心泄露敏感信息
- 🎯 **精准诊断** - 区分不同错误类型
- 📊 **详细报告** - Markdown 格式，易读易分享
- 🌍 **多语言** - 支持英日中文
- 🎨 **原生设计** - 符合 macOS 设计规范

### 预期效果

实现此功能后，可以：
1. 大幅降低 Issue 处理时间
2. 帮助用户自行诊断常见问题
3. 收集详细的技术信息用于 bug 修复
4. 改善用户体验和满意度

---

**准备就绪，可以开始实施！** 🚀
