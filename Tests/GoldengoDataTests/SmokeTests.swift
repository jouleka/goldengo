import XCTest
@testable import GoldengoData
final class DataSmokeTests: XCTestCase {
    func test_moduleLoads() { _ = GoldengoData.self }
}
