import Foundation

enum ConfigurationError: LocalizedError {
    case unavailable, invalidFile, invalidAddress, missingCredential

    var errorDescription: String? {
        switch self {
        case .unavailable: return "此版本尚未配置试用模型服务，暂时无法回答。已有词本仍可查看。"
        case .invalidFile: return "模型配置无法读取，请联系提供此安装包的人。"
        case .invalidAddress: return "模型服务地址无效，请检查连接配置。"
        case .missingCredential: return "模型服务的 Key 不可用，请检查连接配置。"
        }
    }
}

/// A private legacy configuration overrides the distributable trial profile.
/// Fresh installs need neither an OpenCode account nor an EPUB index.
struct Configuration: Decodable {
    enum ThinkingLevel: String, Decodable {
        case minimal, low, medium, high
    }

    let baseURL: String
    let authFile: String
    let authProvider: String
    let model: String
    let contextFile: String
    let bookTitle: String
    let thinkingLevel: ThinkingLevel?
    private let apiKey: String?

    init(baseURL: String = "", authFile: String = "", authProvider: String = "litellm",
         model: String = "", contextFile: String = "", bookTitle: String = "图书", apiKey: String? = nil,
         thinkingLevel: ThinkingLevel? = nil) {
        self.baseURL = baseURL; self.authFile = authFile; self.authProvider = authProvider
        self.model = model; self.contextFile = contextFile
        self.bookTitle = bookTitle.isEmpty ? "图书" : bookTitle
        self.apiKey = apiKey
        self.thinkingLevel = thinkingLevel
    }

    private enum CodingKeys: String, CodingKey {
        case baseURL, authFile, authProvider, model, contextFile, bookTitle, apiKey, thinkingLevel
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(baseURL: try c.decodeIfPresent(String.self, forKey: .baseURL) ?? "",
                  authFile: try c.decodeIfPresent(String.self, forKey: .authFile) ?? "",
                  authProvider: try c.decodeIfPresent(String.self, forKey: .authProvider) ?? "litellm",
                  model: try c.decodeIfPresent(String.self, forKey: .model) ?? "",
                  contextFile: try c.decodeIfPresent(String.self, forKey: .contextFile) ?? "",
                  bookTitle: try c.decodeIfPresent(String.self, forKey: .bookTitle) ?? "图书",
                  apiKey: try c.decodeIfPresent(String.self, forKey: .apiKey),
                  thinkingLevel: try c.decodeIfPresent(ThinkingLevel.self, forKey: .thinkingLevel))
    }

    static func load() throws -> Configuration {
        try load(homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
                 bundledConfigurationURL: Bundle.main.url(forResource: "TrialConfiguration", withExtension: "json"))
    }

    static func load(homeDirectory: URL, bundledConfigurationURL: URL?) throws -> Configuration {
        let local = homeDirectory.appendingPathComponent(".config/book-ask/config.json")
        let path = FileManager.default.fileExists(atPath: local.path) ? local : bundledConfigurationURL
        guard let path else { return Configuration() }
        do { return try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: path)) }
        catch { throw ConfigurationError.invalidFile }
    }

    var serviceName: String { model.isEmpty ? "模型服务" : model }

    func requestURL() throws -> URL {
        guard !baseURL.isEmpty, !model.isEmpty else { throw ConfigurationError.unavailable }
        guard var parts = URLComponents(string: baseURL),
              ["https", "http"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil else {
            throw ConfigurationError.invalidAddress
        }
        parts.path = parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        parts.path = "/" + (parts.path.isEmpty ? "" : parts.path + "/") + "chat/completions"
        guard let url = parts.url else { throw ConfigurationError.invalidAddress }
        return url
    }

    func credential() throws -> String {
        if let apiKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return apiKey }
        guard !authFile.isEmpty,
              let data = try? Data(contentsOf: URL(fileURLWithPath: authFile)),
              let value = (try? JSONSerialization.jsonObject(with: data)) as? [String: [String: Any]],
              let key = value[authProvider]?["key"] as? String, !key.isEmpty else {
            throw ConfigurationError.missingCredential
        }
        return key
    }

    func context(for selection: String) -> ContextMatch {
        guard !contextFile.isEmpty,
              let data = try? Data(contentsOf: URL(fileURLWithPath: contextFile)),
              let paragraphs = try? JSONDecoder().decode([BookParagraph].self, from: data) else {
            return ContextMatch(paragraphs: [], status: "仅使用选中文字")
        }
        return ReadingContext.match(selection, in: paragraphs)
    }
}

enum ModelServiceError: LocalizedError {
    case http(Int), stream

    var errorDescription: String? {
        switch self {
        case .http(let status):
            let detail: String
            switch status {
            case 401, 403: detail = "Key 无效或没有调用权限"
            case 402: detail = "服务额度不足或暂不可用"
            case 429: detail = "调用频率或额度受限"
            case 500...599: detail = "服务暂时不可用"
            default: detail = "调用失败"
            }
            return "模型服务\(detail)（HTTP \(status)）。"
        case .stream: return "模型服务返回错误，本次回答未完成。"
        }
    }
}
