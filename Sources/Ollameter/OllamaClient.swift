import Foundation

struct OllamaVersionResponse: Codable {
    let version: String?
}

struct OllamaProcessResponse: Codable {
    let models: [OllamaRunningModel]?
}

struct OllamaRunningModel: Codable {
    let name: String?
    let model: String?
    let size: Int64?
    let sizeVram: Int64?
}

struct OllamaSnapshot {
    let version: String?
    let models: [OllamaRunningModel]
    let isReachable: Bool

    var displayTitle: String {
        guard isReachable else {
            return "Offline"
        }

        let totalMemory = models.reduce(Int64(0)) { total, model in
            total + (model.sizeVram ?? model.size ?? 0)
        }

        if totalMemory > 0 {
            return "\(models.count) · \(Self.formatBytes(totalMemory))"
        }

        return models.isEmpty ? "0" : "\(models.count)"
    }

    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: bytes)
    }
}

actor OllamaClient {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = URL(string: "http://127.0.0.1:11434")!) {
        self.baseURL = baseURL
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 2
        configuration.timeoutIntervalForResource = 3
        self.session = URLSession(configuration: configuration)
    }

    func fetchSnapshot() async throws -> OllamaSnapshot {
        let version = try await fetch(
            OllamaVersionResponse.self,
            path: "/api/version"
        )
        let processes = try await fetch(
            OllamaProcessResponse.self,
            path: "/api/ps"
        )

        return OllamaSnapshot(
            version: version.version,
            models: processes.models ?? [],
            isReachable: true
        )
    }

    private func fetch<T: Decodable>(
        _ type: T.Type,
        path: String
    ) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: data)
    }
}
