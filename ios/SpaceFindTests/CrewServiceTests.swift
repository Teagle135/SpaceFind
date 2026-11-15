import XCTest
@testable import SpaceFind

final class CrewServiceTests: XCTestCase {
    func testPairingRequiresHTTPSAndAValidPin() throws {
        let pin = String(repeating: "ab", count: 32)
        func code(_ address: String, _ fingerprint: String) -> String {
            #"{"url":"\#(address)","invite":"private","fingerprint":"\#(fingerprint)"}"#
        }
        XCTAssertThrowsError(try Pairing(code("http://laptop.local:8443", pin)))
        XCTAssertThrowsError(try Pairing(code("https://laptop.local:8443", "abc")))
        XCTAssertThrowsError(try Pairing(code("https://laptop.local:8443/elsewhere", pin)))
        XCTAssertEqual(try Pairing(code("https://laptop.local:8443", pin)).fingerprint, pin)
    }
}
