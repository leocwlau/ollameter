import XCTest
@testable import Ollameter

final class DisplayTests: XCTestCase {
    func testModelsAssemblyAndSort() throws {
        let fixture = """
        {
          "range": "24h",
          "scope": "self",
          "granularity": "hour",
          "group_by": "model",
          "totals": {
            "request_count": 16,
            "usage_usd": 0.0268,
            "groups": [
              { "model": "glm-5.3-flash", "request_count": 12, "usage_usd": 0.0132 },
              { "model": "glm-5.3", "request_count": 2, "usage_usd": 0.0098 },
              { "model": "gpt-oss:120b", "request_count": 2, "usage_usd": 0.0038 }
            ]
          },
          "buckets": [
            {
              "from": "2026-10-16T15:00:00Z",
              "until": "2026-10-16T16:00:00Z",
              "request_count": 3,
              "usage_usd": 0.0076,
              "groups": [
                { "model": "glm-5.3-flash", "request_count": 2, "usage_usd": 0.005 }
              ]
            },
            {
              "from": "2026-10-17T15:00:00Z",
              "until": "2026-10-17T16:00:00Z",
              "partial": true,
              "request_count": 4,
              "usage_usd": 0.0081
            }
          ]
        }
        """
        let data = try XCTUnwrap(fixture.data(using: .utf8))
        let response = try CloudJSON.decoder.decode(UsageResponse.self, from: data)
        let models = DisplayAssembly.models(for: [UsageRange.h24: response], range: .h24)

        XCTAssertEqual(models.map(\.name), [
            "glm-5.3-flash",
            "glm-5.3",
            "gpt-oss:120b",
        ])
        XCTAssertEqual(models.map(\.requestCount), [12, 2, 2])
        XCTAssertTrue(DisplayAssembly.models(for: [UsageRange.h24: response], range: .d7).isEmpty)
    }

    func testModelsAssemblyFromBucketsWhenTotalsGroupsAreMissing() throws {
        let fixture = """
        {
          "buckets": [
            {
              "from": "2026-10-17T15:00:00Z",
              "until": "2026-10-17T16:00:00Z",
              "partial": true,
              "groups": [
                { "model": "glm-5.3", "request_count": 2, "usage_usd": 0.0098 },
                { "model": "glm-5.3-flash", "request_count": 3, "usage_usd": 0.004 }
              ]
            }
          ]
        }
        """
        let data = try XCTUnwrap(fixture.data(using: .utf8))
        let response = try CloudJSON.decoder.decode(UsageResponse.self, from: data)
        let models = DisplayAssembly.models(for: [UsageRange.h24: response], range: .h24)

        XCTAssertEqual(models.map(\.name), ["glm-5.3-flash", "glm-5.3"])
    }

    func testHistoryRowsAndUsdFallback() throws {
        let fixture = """
        {
          "range": "24h",
          "granularity": "hour",
          "totals": { "request_count": 15, "usage_usd": 0.01718 },
          "buckets": [
            {
              "from": "2026-10-17T13:00:00Z",
              "until": "2026-10-17T14:00:00Z",
              "request_count": 4,
              "usage_usd": 0.0052
            },
            {
              "from": "2026-10-17T14:00:00Z",
              "until": "2026-10-17T15:00:00Z",
              "request_count": 8,
              "usage_usd": 0.0088
            },
            {
              "from": "2026-10-17T15:00:00Z",
              "until": "2026-10-17T16:00:00Z",
              "partial": true,
              "request_count": 3,
              "usage_usd": 0.00318
            }
          ]
        }
        """
        let data = try XCTUnwrap(fixture.data(using: .utf8))
        let response = try CloudJSON.decoder.decode(UsageResponse.self, from: data)
        let history = DisplayAssembly.history(for: .h24, responses: [UsageRange.h24: response])

        XCTAssertTrue(history.isAvailable)
        XCTAssertTrue(history.hasUsdData)
        XCTAssertEqual(history.rows.count, 4)
        XCTAssertEqual(history.rows.first?.label, "Total")
        XCTAssertEqual(history.rows.first?.requestCount, 15)
        XCTAssertEqual(history.rows.last?.isPartial, true)
        XCTAssertEqual(history.rows.last?.requestCount, 3)

        let countsOnlyFixture = """
        {
          "totals": { "request_count": 24 },
          "buckets": [
            {
              "from": "2026-10-17T15:00:00Z",
              "until": "2026-10-17T16:00:00Z",
              "partial": true,
              "request_count": 11
            }
          ]
        }
        """
        let countsOnlyData = try XCTUnwrap(countsOnlyFixture.data(using: .utf8))
        let countsOnlyResponse = try CloudJSON.decoder.decode(UsageResponse.self, from: countsOnlyData)
        let countsHistory = DisplayAssembly.history(
            for: .h24,
            responses: [UsageRange.h24: countsOnlyResponse]
        )
        XCTAssertFalse(countsHistory.hasUsdData)

        let unavailable = DisplayAssembly.history(for: .d30, responses: [:])
        XCTAssertFalse(unavailable.isAvailable)
        XCTAssertTrue(unavailable.rows.isEmpty)
    }
}
