import XCTest
@testable import GoldengoCore

final class SpendingCategoryTests: XCTestCase {
    func test_keyExamplesResolveToDifferentPurposesAndParents() {
        let rent = SpendingCategoryCatalog.classify("rent")
        XCTAssertEqual(rent.groupName, "Housing")
        XCTAssertEqual(rent.subcategoryName, "Rent & mortgage")
        XCTAssertEqual(rent.purpose, .essential)

        let car = SpendingCategoryCatalog.classify("car maintenance")
        XCTAssertEqual(car.groupName, "Transport")
        XCTAssertEqual(car.purpose, .essential)

        let investing = SpendingCategoryCatalog.classify("stocks")
        XCTAssertEqual(investing.groupName, "Investments")
        XCTAssertEqual(investing.purpose, .wealth)

        let gambling = SpendingCategoryCatalog.classify("casino")
        XCTAssertEqual(gambling.groupName, "Waste & risk")
        XCTAssertEqual(gambling.purpose, .waste)
    }

    func test_existingLooseNamesMapIntoCanonicalSubcategories() {
        XCTAssertEqual(SpendingCategoryCatalog.classify("Food").subcategoryName, "Dining out")
        XCTAssertEqual(SpendingCategoryCatalog.classify("Vape").subcategoryName, "Tobacco & vape")
        XCTAssertEqual(SpendingCategoryCatalog.classify("house stuff").subcategoryName, "Household")
    }

    func test_unknownCategoryRemainsVisibleAsCustomWithStableColor() {
        let first = SpendingCategoryCatalog.classify("Unexpected hobby")
        let second = SpendingCategoryCatalog.classify("Unexpected hobby")
        XCTAssertEqual(first.groupName, "Custom")
        XCTAssertEqual(first.subcategoryName, "Unexpected hobby")
        XCTAssertEqual(first.colorHex, second.colorHex)
        XCTAssertEqual(first.purpose, .other)
    }
}
