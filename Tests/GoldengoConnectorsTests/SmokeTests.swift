import XCTest
@testable import GoldengoConnectors
final class ConnectorsSmokeTests: XCTestCase {
    func test_moduleLoads() { _ = GoldengoConnectors.self }
}
