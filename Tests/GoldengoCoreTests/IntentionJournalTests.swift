import XCTest
import GoldengoCore

final class IntentionJournalTests: XCTestCase {
    private let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 8) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    func test_append_keepsChronologicalOrder() {
        var history: [IntentionEntry] = []
        history = IntentionJournal.append(.init(date: day(2026, 6, 8), text: "rest"), to: history, calendar: cal)
        history = IntentionJournal.append(.init(date: day(2026, 6, 9), text: "focus"), to: history, calendar: cal)
        XCTAssertEqual(history.map(\.text), ["rest", "focus"], "Newest last — display layers reverse")
    }

    func test_sameDayAppend_replaces() {
        var history = [IntentionEntry(date: day(2026, 6, 9, hour: 7), text: "draft")]
        history = IntentionJournal.append(.init(date: day(2026, 6, 9, hour: 9), text: "final"), to: history, calendar: cal)
        XCTAssertEqual(history.count, 1, "Editing the morning note must not journal twice")
        XCTAssertEqual(history.first?.text, "final")
    }

    func test_capacity_dropsOldest() {
        var history = (0..<IntentionJournal.capacity).map {
            IntentionEntry(date: day(2025, 1, 1).addingTimeInterval(Double($0) * 86_400), text: "n\($0)")
        }
        history = IntentionJournal.append(.init(date: day(2026, 6, 9), text: "newest"), to: history, calendar: cal)
        XCTAssertEqual(history.count, IntentionJournal.capacity)
        XCTAssertEqual(history.first?.text, "n1", "Oldest entry dropped")
        XCTAssertEqual(history.last?.text, "newest")
    }

    func test_entryCodableRoundTrip() throws {
        let entry = IntentionEntry(date: day(2026, 6, 9), text: "be kind")
        let decoded = try JSONDecoder().decode([IntentionEntry].self,
                                               from: JSONEncoder().encode([entry]))
        XCTAssertEqual(decoded, [entry])
    }
}
