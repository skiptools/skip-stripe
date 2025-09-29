// SPDX-License-Identifier: LGPL-3.0-only WITH LGPL-3.0-linking-exception

import XCTest
import OSLog
import Foundation
@testable import SkipStripe

let logger: Logger = Logger(subsystem: "SkipStripe", category: "Tests")

@available(macOS 13, *)
final class SkipStripeTests: XCTestCase {

    func testSkipStripe() throws {
        logger.log("running testSkipStripe")
        XCTAssertEqual(1 + 2, 3, "basic test")
    }

    func testDecodeType() throws {
        // load the TestData.json file from the Resources folder and decode it into a struct
        let resourceURL: URL = try XCTUnwrap(Bundle.module.url(forResource: "TestData", withExtension: "json"))
        let testData = try JSONDecoder().decode(TestData.self, from: Data(contentsOf: resourceURL))
        XCTAssertEqual("SkipStripe", testData.testModuleName)
    }

}

struct TestData : Codable, Hashable {
    var testModuleName: String
}
