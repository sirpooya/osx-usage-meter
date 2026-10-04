import XCTest
@testable import UsageMeterCore

/// Regression test: a JWT payload uses the base64url alphabet (with `-` and `_`, and no padding).
/// The implementation before the fix decoded with the standard `Data(base64Encoded:)`, so any payload whose
/// base64 form contained `-` or `_` failed to decode and `jwtExpiry` returned nil.
final class JWTTests: XCTestCase {

    private func makeToken(payloadJSON: String) -> String {
        let base64url = Data(payloadJSON.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(base64url).signature"
    }

    func testJwtExpiryDecodesSimplePayload() {
        let exp: TimeInterval = 1_893_456_000
        let token = makeToken(payloadJSON: #"{"exp":\#(Int(exp))}"#)

        XCTAssertEqual(jwtExpiry(from: token)?.timeIntervalSince1970, exp)
    }

    /// The "??????" in the payload guarantees its standard base64 encoding contains a `/` (verifiable with
    /// `Data(payloadJSON.utf8).base64EncodedString()`), which really exercises the base64url to base64 alphabet
    /// conversion this fix added, rather than only the padding branch.
    func testJwtExpiryHandlesPayloadsRequiringURLSafeCharacters() {
        let exp: TimeInterval = 1_893_456_000
        let payloadJSON = #"{"exp":1893456000,"pad":"??????"}"#
        precondition(Data(payloadJSON.utf8).base64EncodedString().contains("/"))

        let token = makeToken(payloadJSON: payloadJSON)

        XCTAssertEqual(jwtExpiry(from: token)?.timeIntervalSince1970, exp)
    }

    func testJwtExpiryReturnsNilForMalformedToken() {
        XCTAssertNil(jwtExpiry(from: "not-a-jwt"))
        XCTAssertNil(jwtExpiry(from: "only.two"))
    }

    func testJwtExpiryReturnsNilWhenExpMissing() {
        let token = makeToken(payloadJSON: #"{"sub":"user"}"#)
        XCTAssertNil(jwtExpiry(from: token))
    }
}
