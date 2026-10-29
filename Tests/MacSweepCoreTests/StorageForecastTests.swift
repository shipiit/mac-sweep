import Foundation
import Testing
@testable import MacSweepCore

@Suite struct StorageForecastTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    func samples(free: [UInt64], everyHours hours: Double = 24) -> [(date: Date, free: UInt64)] {
        free.enumerated().map { (start.addingTimeInterval(Double($0.offset) * hours * 3_600), $0.element) }
    }

    @Test func fillingDiskGivesDaysUntilFull() throws {
        let gb: UInt64 = 1_000_000_000
        let result = try #require(StorageForecast.forecast(samples(free: [100 * gb, 98 * gb, 96 * gb, 94 * gb, 92 * gb])))
        #expect(abs(result.bytesPerDay - 2e9) < 1)
        #expect(abs((result.daysUntilFull ?? 0) - 46) < 0.001)
    }

    @Test func flatOrGrowingFreeSpaceHasNoDate() throws {
        let gb: UInt64 = 1_000_000_000
        #expect(try #require(StorageForecast.forecast(samples(free: [50 * gb, 50 * gb, 50 * gb, 50 * gb]))).daysUntilFull == nil)
        #expect(try #require(StorageForecast.forecast(samples(free: [50 * gb, 52 * gb, 54 * gb, 56 * gb]))).daysUntilFull == nil)
    }

    @Test func needsEnoughHistory() {
        #expect(StorageForecast.forecast([]) == nil)
        #expect(StorageForecast.forecast(samples(free: [3, 2, 1])) == nil)
        #expect(StorageForecast.forecast(samples(free: [4, 3, 2, 1], everyHours: 1)) == nil, "under two days of data")
    }

    @Test func phrases() {
        #expect(StorageForecast.phrase(days: 1) == "within a couple of days")
        #expect(StorageForecast.phrase(days: 10) == "in about 10 days")
        #expect(StorageForecast.phrase(days: 42) == "in about 6 weeks")
        #expect(StorageForecast.phrase(days: 120) == "in about 4 months")
    }
}
