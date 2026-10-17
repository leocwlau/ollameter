import Foundation

enum UsageRange: String, CaseIterable {
    case h24
    case d7
    case d30

    var queryValue: String {
        switch self {
        case .h24: return "24h"
        case .d7: return "7d"
        case .d30: return "30d"
        }
    }
}

enum CloudAPIError: Error {
    case missingKey
    case unauthorized
    case rateLimited
    case badResponse
    case transport(Error)
}

extension CloudAPIError: Equatable {
    static func == (lhs: CloudAPIError, rhs: CloudAPIError) -> Bool {
        switch (lhs, rhs) {
        case (.missingKey, .missingKey),
             (.unauthorized, .unauthorized),
             (.rateLimited, .rateLimited),
             (.badResponse, .badResponse):
            return true
        case (.transport, .transport):
            return false
        default:
            return false
        }
    }
}

enum CloudDates {
    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let plain = ISO8601DateFormatter()

    static func parse(_ string: String?) -> Date? {
        guard let string else { return nil }
        return fractional.date(from: string) ?? plain.date(from: string)
    }
}

protocol CloudAPIHTTPSession {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: CloudAPIHTTPSession {}

enum CloudJSON {
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

enum CloudAPIRetryPolicy {
    static let maxAttempts = 3
    static let initialDelay: Duration = .seconds(2)
    static let backoffFactor = 2.0
}

struct BalanceWindow: Codable {
    var remainingPercent: Double?
    var resetsAt: String?
}

struct BalancePeriod: Codable {
    var from: String?
    var until: String?
}

struct BalanceIncluded: Codable {
    var balanceUsd: Double?
    var allowanceUsd: Double?
    var period: BalancePeriod?
    var session: BalanceWindow?
    var weekly: BalanceWindow?
}

struct BalancePurchased: Codable {
    var balanceUsd: Double?
}

struct BalanceResponse: Codable {
    var included: BalanceIncluded?
    var purchased: BalancePurchased?
}

struct BalanceSnapshot {
    var included: BalanceIncluded
    var purchasedUsd: Double?
    var fetchedAt: Date

    var isLegacyShape: Bool {
        included.session != nil || included.weekly != nil
    }

    var isCreditShape: Bool {
        !isLegacyShape && included.balanceUsd != nil && included.allowanceUsd != nil
    }
}

struct UsageTotals: Codable {
    var requestCount: Int?
    var usageUsd: Double?
    var inputTokens: Int?
    var cachedInputTokens: Int?
    var outputTokens: Int?
    var groups: [UsageGroup]?
}

struct UsageGroup: Codable {
    var model: String?
    var name: String?
    var requestCount: Int?
    var usageUsd: Double?
    var inputTokens: Int?
    var cachedInputTokens: Int?
    var outputTokens: Int?
}

struct UsageBucket: Codable {
    var from: String?
    var until: String?
    var partial: Bool?
    var requestCount: Int?
    var usageUsd: Double?
    var inputTokens: Int?
    var cachedInputTokens: Int?
    var outputTokens: Int?
    var groups: [UsageGroup]?
}

struct UsageResponse: Codable {
    var range: String?
    var scope: String?
    var granularity: String?
    var from: String?
    var until: String?
    var groupBy: String?
    var totals: UsageTotals?
    var buckets: [UsageBucket]?
}

actor CloudAPIClient {
    private let baseURL: URL
    private let session: CloudAPIHTTPSession
    private let maxAttempts: Int
    private let initialRetryDelay: Duration
    private let backoffFactor: Double

    init(
        baseURL: URL = URL(string: "https://ollama.com")!,
        session: CloudAPIHTTPSession = URLSession(configuration: .ephemeral),
        maxAttempts: Int = CloudAPIRetryPolicy.maxAttempts,
        initialRetryDelay: Duration = CloudAPIRetryPolicy.initialDelay,
        backoffFactor: Double = CloudAPIRetryPolicy.backoffFactor
    ) {
        self.baseURL = baseURL
        self.session = session
        self.maxAttempts = maxAttempts
        self.initialRetryDelay = initialRetryDelay
        self.backoffFactor = backoffFactor
    }

    func fetchBalance(apiKey: String) async throws -> BalanceSnapshot {
        let response = try await request(
            path: "/api/balance",
            apiKey: apiKey,
            as: BalanceResponse.self
        )
        guard let included = response.included else { throw CloudAPIError.badResponse }
        return BalanceSnapshot(
            included: included,
            purchasedUsd: response.purchased?.balanceUsd,
            fetchedAt: Date()
        )
    }

    func fetchUsage(apiKey: String, range: UsageRange) async throws -> UsageResponse {
        try await request(
            path: "/api/usage",
            query: ["range": range.queryValue, "group_by": "model"],
            apiKey: apiKey,
            as: UsageResponse.self
        )
    }

    private func request<T: Decodable>(
        path: String,
        query: [String: String]? = nil,
        apiKey: String,
        as type: T.Type
    ) async throws -> T {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = path
        if let query {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw CloudAPIError.badResponse }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        for attempt in 1...maxAttempts {
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw CloudAPIError.badResponse }
                switch http.statusCode {
                case 200...299:
                    guard !data.isEmpty else {
                        throw CloudAPIError.badResponse
                    }
                    return try CloudJSON.decoder.decode(type, from: data)
                case 401, 403:
                    throw CloudAPIError.unauthorized
                case 429:
                    throw CloudAPIError.rateLimited
                default:
                    throw CloudAPIError.badResponse
                }
            } catch let error as CloudAPIError {
                if case .rateLimited = error, attempt < maxAttempts {
                    let retryMultiplier = (1 << (attempt - 1))
                    try? await Task.sleep(for: initialRetryDelay * retryMultiplier)
                    continue
                }
                throw error
            } catch {
                throw CloudAPIError.transport(error)
            }
        }
        throw CloudAPIError.badResponse

    }
}
