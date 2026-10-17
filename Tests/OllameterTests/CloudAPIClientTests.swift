import XCTest
@testable import Ollameter

final class HTTPStubSession: CloudAPIHTTPSession {
    private let statuses: [Int]
    var numberOfCalls = 0
    var lastRequest: URLRequest?

    init(statuses: [Int]) {
        self.statuses = statuses
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        defer { numberOfCalls += 1 }

        let index = min(numberOfCalls, statuses.count - 1)
        let statusCode = statuses[index]
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        self.lastRequest = request
        return (Data("{}".utf8), response)
    }
}

final class CloudAPIClientTests: XCTestCase {
    func testFetchUsageRetriesRateLimitThenSucceeds() async throws {
        let session = HTTPStubSession(statuses: [429, 200])
        let client = CloudAPIClient(
            baseURL: URL(string: "https://test.local")!,
            session: session
        )
        let response = try await client.fetchUsage(apiKey: "test-key", range: .h24)

        XCTAssertEqual(session.numberOfCalls, 2)
        XCTAssertTrue(session.lastRequest?.url?.query?.contains("group_by=model") ?? false)
        XCTAssertTrue(session.lastRequest?.url?.query?.contains("range=24h") ?? false)
        XCTAssertNil(response.range)
    }

    func testFetchUsageDoesNotRetryServerError() async throws {
        let session = HTTPStubSession(statuses: [500])
        let client = CloudAPIClient(
            baseURL: URL(string: "https://test.local")!,
            session: session
        )

        do {
            _ = try await client.fetchUsage(apiKey: "test-key", range: .h24)
            XCTFail("Expected 500 status to throw")
        } catch let error as CloudAPIError {
            XCTAssertEqual(error, .badResponse)
        }

        XCTAssertEqual(session.numberOfCalls, 1)
    }

    func testFetchUsageUsesModelGroupingAndRetriesRateLimits() async throws {
        let session = HTTPStubSession(statuses: [429, 429, 200])
        let client = CloudAPIClient(
            baseURL: URL(string: "https://test.local")!,
            session: session
        )

        do {
            _ = try await client.fetchUsage(apiKey: "test-key", range: .h24)
        } catch let error as CloudAPIError {
            XCTAssertEqual(error, .badResponse)
        }

        XCTAssertEqual(session.numberOfCalls, 3)
        XCTAssertTrue(session.lastRequest?.url?.query?.contains("group_by=model") ?? false)
        XCTAssertTrue(session.lastRequest?.url?.query?.contains("range=24h") ?? false)
    }

    func testFetchBalanceDoesNotRetryUnauthorized() async throws {
        let session = HTTPStubSession(statuses: [401])
        let client = CloudAPIClient(
            baseURL: URL(string: "https://test.local")!,
            session: session
        )

        var caught = false
        do {
            _ = try await client.fetchBalance(apiKey: "bad-key")
        } catch let error as CloudAPIError {
            caught = true
            XCTAssertEqual(error, .unauthorized)
        }

        XCTAssertTrue(caught)
        XCTAssertEqual(session.numberOfCalls, 1)
    }
}
