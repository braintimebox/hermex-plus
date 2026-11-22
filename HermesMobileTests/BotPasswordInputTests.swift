import XCTest
@testable import HermesMobile

final class BotPasswordInputTests: XCTestCase {
    func testATrailingNewlineFromTheClipboardIsRemoved() {
        // The failure this fixes: Basic auth encodes the value verbatim, so "secret\n"
        // reaches the host as a different password and comes back as invalid_credentials.
        XCTAssertEqual(BotPasswordInput.normalized("secret\n"), "secret")
        XCTAssertEqual(BotPasswordInput.normalized("secret\r\n"), "secret")
        XCTAssertEqual(BotPasswordInput.normalized("\nsecret\n"), "secret")
        XCTAssertEqual(BotPasswordInput.normalized("sec ret"), "sec ret")
    }

    func testSpacesAreKeptBecauseTheyCanBePartOfAPassword() {
        XCTAssertEqual(BotPasswordInput.normalized(" secret "), " secret ")
        XCTAssertEqual(BotPasswordInput.normalized("pass word"), "pass word")
    }

    func testAWarningNamesTheInvisibleCharacterWithoutRepeatingTheSecret() {
        let newline = BotPasswordInput.warning("secret\n")
        XCTAssertNotNil(newline)
        XCTAssertFalse(newline?.contains("secret") ?? true, "the warning must not echo the password")

        let space = BotPasswordInput.warning(" secret")
        XCTAssertNotNil(space)
        XCTAssertFalse(space?.contains("secret") ?? true)

        XCTAssertNil(BotPasswordInput.warning("secret"))
        XCTAssertNil(BotPasswordInput.warning(""))
    }

    func testAnEmptyAfterTrimmingPasswordDoesNotEnableConnect() {
        // "\n" alone is not a password; Connect must stay off instead of sending it.
        XCTAssertTrue(BotPasswordInput.normalized("\n").isEmpty)
        XCTAssertFalse(BotPasswordInput.normalized("x").isEmpty)
    }
}
