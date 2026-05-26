import XCTest
@testable import Zyquo

final class RedactionTests: XCTestCase {
    func testRedactsAPIKey() {
        let input = "key is sk-ant-api03-abcdefghijklmnopqrstuvwxyz"
        let result = Redaction.redact(input)
        XCTAssertTrue(result.contains("[REDACTED_API_KEY]"))
        XCTAssertFalse(result.contains("sk-ant-api03"))
    }

    func testRedactsBearerToken() {
        let input = "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.abcdef"
        let result = Redaction.redact(input)
        XCTAssertTrue(result.contains("[REDACTED_BEARER]"))
    }

    func testRedactsEnvVarSecrets() {
        let input = "API_TOKEN=mysecrettoken123"
        let result = Redaction.redact(input)
        XCTAssertTrue(result.contains("[REDACTED]"))
        XCTAssertFalse(result.contains("mysecrettoken123"))
    }

    func testPreservesNonSecretText() {
        let input = "This is a normal log message with no secrets"
        let result = Redaction.redact(input)
        XCTAssertEqual(input, result)
    }
}
