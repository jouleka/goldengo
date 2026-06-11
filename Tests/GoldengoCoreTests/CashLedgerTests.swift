import XCTest
import GoldengoCore

final class CashLedgerTests: XCTestCase {
    func test_expected_noFlows_isBaseline() {
        XCTAssertEqual(CashLedger.expected(baselineTotal: 5000, flows: []), 5000)
    }

    func test_expected_appliesInflowsAndOutflows() {
        let flows = [CashLedger.Flow(amount: 10000, isInflow: true),    // ATM withdrawal
                     CashLedger.Flow(amount: 2000, isInflow: true),     // cash income
                     CashLedger.Flow(amount: 350, isInflow: false),     // coffee
                     CashLedger.Flow(amount: 1200, isInflow: false)]
        XCTAssertEqual(CashLedger.expected(baselineTotal: 500, flows: flows), 10950)
    }

    func test_expected_canGoNegative_neverClamped() {
        // More logged cash spend than the wallet held — the drift at the next count surfaces it;
        // clamping here would hide the signal.
        let flows = [CashLedger.Flow(amount: 700, isInflow: false)]
        XCTAssertEqual(CashLedger.expected(baselineTotal: 500, flows: flows), -200)
    }

    func test_drift_signConventions() {
        XCTAssertEqual(CashLedger.drift(counted: 4000, expected: 5400), -1400,
                       "Negative = cash slipped by unlogged")
        XCTAssertEqual(CashLedger.drift(counted: 6000, expected: 5400), 600)
        XCTAssertEqual(CashLedger.drift(counted: 5400, expected: 5400), 0)
    }

    func test_flowEquatable() {
        XCTAssertEqual(CashLedger.Flow(amount: 1, isInflow: true), CashLedger.Flow(amount: 1, isInflow: true))
    }
}
