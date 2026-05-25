import Foundation

protocol QuoteProvider: Sendable {
    var supportedMarkets: Set<Market> { get }
    func fetch(_ keys: [SymbolKey]) async throws -> [SymbolKey: Quote]
}

enum QuoteError: Error, LocalizedError {
    case invalidResponse
    case missingSymbol(String)
    case parseFailure(String)
    case allProvidersFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "行情接口返回异常"
        case .missingSymbol(let s): "未找到代码 \(s)"
        case .parseFailure(let s): "解析失败: \(s)"
        case .allProvidersFailed: "所有数据源都失败了"
        }
    }
}

enum HTTPHelper {
    nonisolated static let gb18030: String.Encoding = {
        let cfEnc = CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEnc))
    }()

    nonisolated static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    nonisolated static func get(_ url: URL, referer: String? = nil, decodeAs encoding: String.Encoding = .utf8) async throws -> String {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        if let referer {
            req.setValue(referer, forHTTPHeaderField: "Referer")
        }
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw QuoteError.invalidResponse
        }
        if let s = String(data: data, encoding: encoding) { return s }
        // Fallback: try utf8 if requested encoding fails
        if encoding != .utf8, let s = String(data: data, encoding: .utf8) { return s }
        throw QuoteError.invalidResponse
    }

    nonisolated static func getJSON(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw QuoteError.invalidResponse
        }
        return data
    }
}
