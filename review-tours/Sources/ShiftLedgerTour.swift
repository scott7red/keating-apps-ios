import XCTest

/// ShiftLedger: app-store/shiftledger/review-notes.txt, section 1, and its page in "App Review Videos.pdf".
/// Setup (a job and a tax profile), a shift with tips, the totals, the shift list, the deduction and how it is
/// worked out, the W-2 check, the PDF through the share sheet, the quick calculator, the example data,
/// Help, Privacy policy, About, and Erase all data.
final class ShiftLedgerTour: Tour {
    override var iconName: String { "ShiftLedger" }

    func testTour() throws {
        step("Launch from the Home Screen") {
            launchFromHomeScreen()
            waitText("Set up my first job", timeout: 30)
            pause(2.0)
        }
        step("Welcome") {
            show("Estimates only, not tax advice", hold: 2.0)
            tap("Set up my first job")
        }
        step("Your first job") {
            waitText("Your first job")
            pause(1.0)
            type("Test Diner server", into: "Job name")
            type("15", into: "Hourly rate")
            hideKeyboard()
            tap("W-2 employee", how: .exact)
            tap("I earn tips at this job", how: .prefix)
            show("IRS.gov", hold: 2.0)
            tap("Continue", how: .exact)
        }
        step("Your tax profile") {
            waitText("Your tax profile")
            show("Filing status", hold: 1.5)
            type("40000", into: "Estimated total income", how: .prefix)
            hideKeyboard()
            tap("Finish setup")
        }
        step("Log a shift with tips") {
            waitText("Log your first shift")
            pause(1.5)
            tap("Log shift", how: .exact)
            tap("Enter hours", how: .exact)
            type("9", into: "Paid hours")
            type("120", into: "Card tips")
            type("35", into: "Cash tips")
            hideKeyboard()
            show("Tips kept", hold: 1.5)
            show("Hourly with tips", hold: 2.0)
            tap("Log shift", how: .exact, after: 2.0)
        }
        step("This week and the year so far") {
            show("Hourly with tips", hold: 1.5)
            show("Tips logged", hold: 1.5)
            show("Estimated deduction", hold: 1.5)
            show("Toward the caps", hold: 2.0)
        }
        step("The shift list") {
            tab("Shifts", after: 2.5)
        }
        step("The deduction and how it is worked out") {
            tab("Deduction", after: 1.5)
            show("Total deduction", hold: 1.5)
            show("Est. federal tax saved", hold: 1.5)
            show("Breakdown", hold: 1.0)
            scrollDown(0.35, times: 3, hold: 1.3)
            tap("How this is calculated", how: .prefix, after: 2.0)
            scrollDown(0.35, times: 1, hold: 1.5)
        }
        step("The W-2 check") {
            show("W-2 check", hold: 1.5)
            type("150", into: "Qualified tips on your W-2", how: .prefix)
            hideKeyboard()
            show("Your log", hold: 1.0)
            show("Difference", hold: 2.5)
        }
        step("The summary PDF, through the share sheet") {
            tap("summary (PDF)", how: .contains, after: 2.0)
            if waitOptional("Share it", how: .exact, kinds: [Tour.actionable], timeout: 3) { tap("Share it", how: .exact) }
            shareSheetSaveToFiles()
        }
        step("The quick calculator") {
            tab("Tools", after: 1.5)
            show("Quick calculator", hold: 2.5)
        }
        step("Example data") {
            tab("Settings")
            tap("Try the app with example data", how: .prefix)
            tap("Show example data", how: .exact, after: 1.5)
            tab("Home", after: 1.5)
            show("You are looking at example data", hold: 1.5)
            scrollDown(0.35, times: 2, hold: 1.3)
            tab("Settings")
            tap("Remove example data", how: .exact)
            tap("Remove example data", how: .exact, after: 1.5)
        }
        step("Help, Privacy policy and About") {
            tap("Help", how: .prefix, after: 1.5)
            scrollDown(0.3, times: 2, hold: 1.2)
            back()
            tap("Privacy policy", how: .prefix, after: 1.5)
            scrollDown(0.3, times: 2, hold: 1.2)
            back()
            tap("About", how: .prefix, after: 1.5)
            scrollDown(0.3, times: 1, hold: 1.5)
            back()
        }
        step("Erase all data") {
            tap("Erase all data", how: .exact)
            tap("Erase everything", how: .exact, after: 2.0)
            waitText("Set up my first job", timeout: 20)
            pause(2.5)
        }
    }
}
