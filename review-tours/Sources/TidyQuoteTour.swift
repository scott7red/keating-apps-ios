import XCTest

/// TidyQuote: app-store/tidyquote/review-notes.txt, section 1, and the TidyQuote page of "App Review Videos.pdf".
final class TidyQuoteTour: Tour {
    override var iconName: String { "TidyQuote" }

    func testTour() throws {
        step("Launch from the Home Screen") {
            launchFromHomeScreen()
            waitText("Welcome to TidyQuote", timeout: 30)
            pause(1.5)
        }
        step("Welcome, English and Spanish") {
            show("Everything stays on this phone", hold: 2.0)
            tap("Español")
            pause(1.5)
            tap("English")
            tap("Get started")
        }
        step("Your business") {
            waitText("Your business")
            type("Sparkle Test Cleaning", into: "Business name")
            hideKeyboard()
            tap("Continue")
        }
        step("Your starting prices") {
            waitText("Your starting prices")
            show("With these prices", hold: 2.5)
            tap("Start using TidyQuote")
        }
        step("Home") {
            pause(2.0)
            tap("New quote")
            pause(2.0)
        }
    }
}
