import Foundation
import Security
import CryptoKit
import Observation

enum KeychainVault {
    static func identifier(_ endpoint: String) -> String { SHA256.hash(data: Data(endpoint.utf8)).map { String(format: "%02x", $0) }.joined() }
    static func read(endpoint: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "ASCEND.gateway", kSecAttrAccount as String: identifier(endpoint), kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ token: String, endpoint: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "ASCEND.gateway", kSecAttrAccount as String: identifier(endpoint)]
        SecItemDelete(query as CFDictionary)
        if token.isEmpty { return }
        var item = query; item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let result = SecItemAdd(item as CFDictionary, nil)
        guard result == errSecSuccess else { throw DataError.invalid("Could not save gateway authentication in Keychain (\(result))") }
    }
}
struct GatewayConfiguration: Decodable { var providers: [String: [String]]; var usage: GatewayUsage; var providerTested: Bool }
struct GatewayUsage: Decodable { var used: Int; var limit: Int; var day: String }
struct SessionResponse: Decodable { var questions: [Question] }
struct GradeResponse: Decodable { var correct: Bool; var feedback: String; var reviewTopic: String }
struct TestResponse: Decodable { var ok: Bool }
struct GatewayFailure: Decodable { struct Detail: Decodable { var code: String; var message: String }; var error: Detail }

@MainActor @Observable final class AIClient {
    var endpoint: String { didSet { if oldValue != endpoint { chat.clear() }; UserDefaults.standard.set(endpoint, forKey: "ai.endpoint"); status = "Connection not tested" } }
    var provider: String { didSet { if oldValue != provider { chat.clear() }; UserDefaults.standard.set(provider, forKey: "ai.provider"); status = "Connection not tested" } }
    var model: String { didSet { if oldValue != model { chat.clear() }; UserDefaults.standard.set(model, forKey: "ai.model"); status = "Connection not tested" } }
    var dailyLimit: Int { didSet { UserDefaults.standard.set(dailyLimit, forKey: "ai.dailyLimit") } }
    let chat = ChatSession()
    var status = "AI unconfigured"
    var providers: [String: [String]] = [:]
    var testing = false
    var usage: GatewayUsage?
    var configured: Bool { validURL != nil && KeychainVault.read(endpoint: endpoint) != nil && !model.isEmpty }
    var validURL: URL? {
        guard let url = URL(string: endpoint), url.host != nil, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { return nil }
        if url.scheme == "https" { return url }
        #if DEBUG
        if url.scheme == "http", ["localhost", "127.0.0.1", "::1"].contains(url.host!) { return url }
        #endif
        return nil
    }
    init() {
        endpoint = UserDefaults.standard.string(forKey: "ai.endpoint") ?? ""
        provider = UserDefaults.standard.string(forKey: "ai.provider") ?? "openai"
        model = UserDefaults.standard.string(forKey: "ai.model") ?? ""
        dailyLimit = UserDefaults.standard.object(forKey: "ai.dailyLimit") as? Int ?? 20
        status = endpoint.isEmpty ? "AI unconfigured" : "Connection not tested"
    }
    func saveToken(_ token: String) throws {
        guard validURL != nil else { throw DataError.invalid("Enter an HTTPS gateway URL first. Debug builds also accept localhost HTTP.") }
        try KeychainVault.save(token, endpoint: endpoint); chat.clear(); status = "Token saved securely · connection not tested"
    }
    private func request<T: Decodable>(_ path: String, body: [String: Any]? = nil) async throws -> T {
        guard let url = validURL, let token = KeychainVault.read(endpoint: endpoint) else { throw DataError.invalid("Configure your private AI gateway and authentication token in Settings") }
        var request = URLRequest(url: url.appendingPathComponent(path), timeoutInterval: 45)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            let day = Planning(zone: "UTC").day(Date())
            let previous = UserDefaults.standard.string(forKey: "ai.usageDay")
            let used = previous == day ? UserDefaults.standard.integer(forKey: "ai.usageCount") : 0
            guard used < dailyLimit else { throw DataError.invalid("This device’s daily AI request limit is reached. You can change it in Settings.") }
            let data = try JSONSerialization.data(withJSONObject: body)
            guard data.count <= 65536 else { throw DataError.invalid("This request is too large. Shorten the answer or session settings.") }
            request.httpBody = data; UserDefaults.standard.set(day, forKey: "ai.usageDay"); UserDefaults.standard.set(used + 1, forKey: "ai.usageCount")
        }
        // Ephemeral networking avoids caching authentication or learning context on disk.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 45; configuration.timeoutIntervalForResource = 50
        let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        var data = Data()
        for try await byte in bytes { data.append(byte); if data.count > 262144 { throw DataError.invalid("Gateway response exceeds the size limit") } }
        guard let response = response as? HTTPURLResponse else { throw DataError.invalid("Invalid gateway response") }
        guard (200..<300).contains(response.statusCode) else {
            let failure = try? JSONDecoder().decode(GatewayFailure.self, from: data)
            if response.statusCode == 404, path == "v1/plan" { throw DataError.invalid("Update and restart your ASCEND gateway to enable app planning.") }
            if response.statusCode == 404, path == "v1/chat" { throw DataError.invalid("Update your ASCEND gateway to version 1.5 or later and restart it to enable chat.") }
            throw DataError.invalid(failure?.error.message ?? "Gateway returned HTTP \(response.statusCode)")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
    func refreshConfiguration() async throws {
        let config: GatewayConfiguration = try await request("v1/config")
        providers = config.providers; usage = config.usage
        if !providers.keys.contains(provider), let first = providers.keys.sorted().first { provider = first }
        if !(providers[provider] ?? []).contains(model) { model = providers[provider]?.first ?? "" }
        status = providers.isEmpty ? "Gateway reachable · no providers configured" : "Gateway reachable · provider not tested"
    }
    func testConnection() async {
        testing = true; defer { testing = false }
        do {
            try await refreshConfiguration()
            guard !model.isEmpty else { return }
            let result: TestResponse = try await request("v1/test", body: ["requestID": UUID().uuidString, "provider": provider, "model": model])
            status = result.ok ? "Provider connection verified just now" : "Provider test did not succeed"
        } catch { status = "Connection failed · \(error.localizedDescription)" }
    }
    func generatePlan(messages: [[String: String]], context: Data) async throws -> AIPlan {
        let value = try JSONSerialization.jsonObject(with: context)
        return try await request("v1/plan", body: ["requestID": UUID().uuidString, "provider": provider, "model": model, "messages": messages, "context": value])
    }
    func chatReply(to messages: [[String: String]]) async throws -> String {
        struct Reply: Decodable { let reply: String }
        let response: Reply = try await request("v1/chat", body: ["requestID": UUID().uuidString, "provider": provider, "model": model, "messages": messages])
        let reply = response.reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reply.isEmpty, reply.utf16.count <= 8000 else { throw DataError.invalid("The provider returned an invalid chat reply.") }
        return reply
    }
    func generate(_ config: LearningConfig, day: String) async throws -> LearningSession {
        let value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(config))
        let result: SessionResponse = try await request("v1/session", body: ["requestID": UUID().uuidString, "provider": provider, "model": model, "config": value])
        try LearningRules.validate(result.questions, count: config.count)
        return LearningSession(config: config, questions: result.questions, day: day, provider: provider, model: model)
    }
    func grade(question: Question, attempt: Attempt) async throws -> GradeResponse {
        let q = try JSONSerialization.jsonObject(with: JSONEncoder().encode(question))
        let result: GradeResponse = try await request("v1/grade", body: ["requestID": UUID().uuidString, "provider": provider, "model": model, "question": q, "answer": attempt.answer, "hintsUsed": attempt.hintsUsed, "mode": attempt.mode.rawValue])
        guard !result.feedback.isEmpty, result.feedback.count <= 12000, result.reviewTopic.count <= 200 else { throw DataError.invalid("Invalid AI feedback") }
        return result
    }
}
final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
