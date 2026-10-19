import XCTest

/// BRRR Deal Analyzer: app-store/brrr/review-notes.txt, section 1, and its page in "App Review Videos.pdf".
/// Setup, analyzing a deal and its results, the PDF report through the share sheet, Deals, the Markets ZIP finder
/// with the optional location prompt (one prompt only), Learn, the example data, Help, Privacy policy, About,
/// and Erase all data. The simulator's location is set to Columbus, Ohio (ZIP 43215) by the workflow.
final class BRRRTour: Tour {
    override var iconName: String { "BRRR" }
    override var tabBars: [[String]] { [["Deals", "Analyze", "Markets", "Learn", "Settings"]] }

    func testTour() throws {
        step("Launch from the Home Screen") {
            launchFromHomeScreen()
            waitText("Get started", timeout: 30)
            pause(2.5)
            tap("Get started", how: .exact)
        }
        step("Starting assumptions") {
            waitText("How do you usually buy?")
            pause(2.0)
            tap("Continue", how: .exact)
            waitText("Two things to know first")
            pause(2.0)
            tap("Start my first deal", how: .exact, after: 1.5)
        }
        step("Analyze a deal: Buy, Rehab, Rent, Refinance") {
            type("120000", into: "Purchase price")
            hideKeyboard()
            tap("Next: Rehab", how: .exact)
            type("30000", into: "Rehab budget")
            hideKeyboard()
            tap("Next: Rent", how: .exact)
            type("1600", into: "Monthly rent")
            hideKeyboard()
            tap("Next: Refinance", how: .exact)
            type("210000", into: "After-repair value", how: .prefix)
            hideKeyboard()
            tap("Next: Repeat", how: .exact)
            tap("See the results", how: .exact, after: 2.0)
        }
        step("The results") {
            show("Verdict", hold: 2.0)
            show("BRRRR scorecard", hold: 1.5)
            scrollDown(0.35, times: 2, hold: 1.2)
            tap("show how it is calculated", how: .contains, after: 2.5)
            tap("Close", how: .exact, after: 1.0)
            show("Rules of thumb", hold: 1.5)
            show("Stress test", hold: 1.5)
            show("Long-term projection", hold: 2.0)
        }
        step("The property address") {
            scrollToTop()
            tap("Property:", how: .prefix, after: 1.5)
            type("100 Example St", into: "Street address")
            type("Columbus", into: "City", how: .exact)
            type("OH", into: "State", how: .exact)
            type("43215", into: "ZIP", how: .exact)
            hideKeyboard()
            tap("Done", how: .exact, kinds: [[.button]], after: 1.5)
        }
        step("The PDF report, through the share sheet") {
            tap("More actions", how: .exact)
            tap("PDF report", how: .prefix, after: 2.0)
            waitText("Report ready", timeout: 20)
            pause(1.0)
            tap("Share or save the PDF", how: .exact, after: 1.5)
            shareSheetSaveToFiles()
            tapIfPresent("Close", how: .exact)
        }
        step("Deals") {
            tab("Deals", after: 1.5)
            show("100 Example St", hold: 2.0)
        }
        step("Markets near me, with the location prompt") {
            tab("Markets", after: 1.5)
            tap("Near me", how: .exact, after: 1.2)
            tap("Use my location", how: .exact, after: 0.5)
            if answerSystemAlert(["Allow While Using App", "Allow Once", "Allow"], timeout: 45, required: false) {
                if springboard.alerts.firstMatch.waitForExistence(timeout: 3) {
                    mark("note", "a second location prompt appeared: \(springboard.alerts.firstMatch.label)")
                    dumpTree("second location prompt", force: true)
                }
            } else {
                // Location is optional in BRRR: the ZIP box gives the same list.
                type("43215", into: "Or type a ZIP or a city", how: .prefix)
                hideKeyboard()
            }
            waitText("Ranked by BRRR score", timeout: 20)
            pause(2.0)
            tap("Show details", how: .contains, after: 2.0)
            scrollDown(0.3, times: 1, hold: 1.2)
            show("See listings in this ZIP", hold: 2.0)
            tap("Close", how: .exact, after: 1.2)
            show("Census", hold: 2.5)
        }
        step("Learn") {
            tab("Learn", after: 1.5)
            scrollDown(0.35, times: 2, hold: 1.2)
        }
        step("Analyze") {
            tab("Analyze", after: 1.5)
            scrollDown(0.35, times: 2, hold: 1.0)
        }
        step("Example data") {
            tab("Settings", after: 1.2)
            tap("Try the app with example data", how: .prefix, after: 1.5)
            tapIfPresent("Add examples", how: .exact)
            tab("Deals", after: 2.0)
            scrollDown(0.3, times: 1, hold: 1.2)
            tab("Settings", after: 1.2)
            tap("Remove example data", how: .exact)
            tap("Remove examples", how: .exact, after: 1.5)
        }
        step("Help, Privacy policy and About") {
            tap("Help", how: .prefix, after: 1.5)
            scrollDown(0.3, times: 1, hold: 1.2)
            back()
            tap("Privacy policy", how: .prefix, after: 1.5)
            scrollDown(0.3, times: 1, hold: 1.2)
            back()
            tap("About", how: .prefix, after: 1.5)
            show("GeoNames", hold: 2.0)
            back()
        }
        step("Erase all data") {
            tap("Erase all data", how: .prefix)
            tap("Erase everything", how: .exact, after: 2.0)
            waitText("Get started", timeout: 20)
            pause(2.5)
        }
    }
}
