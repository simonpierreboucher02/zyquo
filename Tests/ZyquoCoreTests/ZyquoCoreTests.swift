import XCTest
@testable import ZyquoCore

final class ZyquoCoreTests: XCTestCase {
    func testVersionString() {
        let version = ZyquoInfo.versionString
        XCTAssertTrue(version.contains("Zyquo"))
        XCTAssertTrue(version.contains("0.1.0"))
    }
}
