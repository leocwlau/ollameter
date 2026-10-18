import XCTest
@testable import Ollameter

final class OllameterTests: XCTestCase {
    func testDecodesCreditPlanBalance() throws {
        let fixture = """
        {
          "included": {
            "balance_usd": 72.5,
            "allowance_usd": 100.0,
            "period": {
              "from": "2026-10-01T00:00:00Z",
              "until": "2026-11-01T00:00:00Z"
            }
          },
          "purchased": { "balance_usd": 5.0 }
        }
        """
        let response = try CloudJSON.decoder.decode(BalanceResponse.self, from: fixture.data(using: .utf8)!)
        XCTAssertEqual(response.included?.balanceUsd, 72.5)
        XCTAssertEqual(response.included?.allowanceUsd, 100.0)
        XCTAssertEqual(response.purchased?.balanceUsd, 5.0)
        let snapshot = BalanceSnapshot(included: response.included!, purchasedUsd: response.purchased?.balanceUsd, fetchedAt: Date())
        XCTAssertTrue(snapshot.isCreditShape)
        XCTAssertFalse(snapshot.isLegacyShape)
    }

    func testDecodesLegacyPlanBalance() throws {
        let fixture = """
        {
          "included": {
            "session": { "remaining_percent": 64, "resets_at": "2026-10-17T18:30:00Z" },
            "weekly": { "remaining_percent": 81, "resets_at": "2026-10-22T12:00:00Z" }
          },
          "purchased": { "balance_usd": 5.0 }
        }
        """
        let response = try CloudJSON.decoder.decode(BalanceResponse.self, from: fixture.data(using: .utf8)!)
        XCTAssertEqual(response.included?.session?.remainingPercent, 64)
        XCTAssertEqual(response.included?.weekly?.remainingPercent, 81)
        let snapshot = BalanceSnapshot(included: response.included!, purchasedUsd: response.purchased?.balanceUsd, fetchedAt: Date())
        XCTAssertTrue(snapshot.isLegacyShape)
        XCTAssertFalse(snapshot.isCreditShape)
    }

    func testDeltaTitleAndColor() {
        XCTAssertEqual(Metrics.creditDelta(usedPercent: 40, elapsedPercent: 20).text, "+20.0%")
        XCTAssertEqual(Metrics.creditDelta(usedPercent: 40, elapsedPercent: 20).color, MetricColor.red)
        XCTAssertEqual(Metrics.creditDelta(usedPercent: 10, elapsedPercent: 20).text, "-10.0%")
        XCTAssertEqual(Metrics.creditDelta(usedPercent: 10, elapsedPercent: 20).color, MetricColor.green)
        XCTAssertEqual(Metrics.creditDelta(usedPercent: 20, elapsedPercent: 20).text, "0.0%")
        XCTAssertEqual(Metrics.creditDelta(usedPercent: 20, elapsedPercent: 20).color, MetricColor.green)
    }

    func testTimeTtlFormatting() {
        XCTAssertEqual(Metrics.hHmm(7800), "2:10")
        XCTAssertEqual(Metrics.dHh(5 * 86400 + 4 * 3600), "5d:4h")
    }

    func testLegacySummaryText() {
        XCTAssertEqual(
            Metrics.legacySummary(sessionRemainingPercent: 64, sessionTtl: 7800, weeklyRemainingPercent: 81, weeklyTtl: 5 * 86400 + 4 * 3600),
            "S 64.0% 2:10 W 81.0% 5d:4h"
        )
    }

    func testParsesDates() {
        XCTAssertNotNil(CloudDates.parse("2026-10-01T00:00:00Z"))
        XCTAssertNotNil(CloudDates.parse("2026-10-17T18:30:00.123Z"))
        XCTAssertNil(CloudDates.parse(nil))
    }
}
