import XCTest

/// TidyQuote: app-store/tidyquote/review-notes.txt, section 1, and the TidyQuote page of "App Review Videos.pdf".
/// Launch, setup with English/Spanish, a quote with its price breakdown, the PDF through the share sheet,
/// quote to invoice, a payment, a logo, the example data, Help, Privacy policy, About, and Erase all data.
final class TidyQuoteTour: Tour {
    override var iconName: String { "TidyQuote" }
    override var tabBars: [[String]] { [["Home", "Quotes", "Invoices", "Clients", "Settings"]] }

    func testTour() throws {
        step("Launch from the Home Screen") {
            launchFromHomeScreen()
            waitText("Welcome to TidyQuote", timeout: 30)
            pause(2.0)
        }
        step("Welcome, in English and Spanish") {
            show("Everything stays on this phone", hold: 2.0)
            tap("Español", how: .exact, after: 2.5)
            tap("English", how: .exact, after: 1.5)
            tap("Get started")
        }
        step("Your business") {
            waitText("Your business")
            pause(1.0)
            type("Sparkle Test Cleaning", into: "Business name")
            hideKeyboard()
            tap("Continue", how: .exact)
        }
        step("Your starting prices") {
            waitText("Your starting prices")
            show("With these prices", hold: 2.5)
            tap("Start using TidyQuote")
        }
        step("A new quote for a new client") {
            waitText("Price your first home")
            pause(1.5)
            tap("New quote", how: .exact)
            tap("Add a new client")
            type("Pat Example", into: "Client name")
            hideKeyboard()
        }
        step("Home details and the service") {
            tap("Increase Bedrooms", before: 0.5, after: 0.7)
            tap("Increase Bedrooms", before: 0.2, after: 0.7)
            tap("Increase Full bathrooms", before: 0.4, after: 1.0)
            tap("Deep clean", how: .prefix)
            tap("Every 2 weeks", how: .prefix)
            tap("Inside oven", how: .prefix)
        }
        step("Price breakdown, then save") {
            show("Price breakdown", hold: 1.0)
            show("Each visit after", hold: 2.5)
            tap("Save as draft", after: 2.0)
        }
        step("The quote as a PDF, through the share sheet") {
            waitText("Q-0001")
            pause(1.0)
            tap("Send PDF", after: 1.5)
            shareSheetSaveToFiles()
        }
        step("Accepted, then turned into an invoice") {
            tap("Mark accepted", after: 1.5)
            tap("Convert to invoice", how: .exact)
            waitText("Which amounts go on the invoice?")
            pause(1.5)
            tap("Create invoice", after: 2.0)
        }
        step("A payment") {
            waitText("INV-0001")
            tap("Record payment", how: .exact)
            waitText("Paid by")
            pause(1.5)
            tap("Mark $", how: .prefix, after: 2.0)
            show("Paid", hold: 2.0)
        }
        step("A logo for the quotes and invoices") {
            tab("Settings")
            tap("Business profile", how: .prefix)
            tap("Upload logo", how: .exact, after: 1.5)
            pickLogo()
            back()
        }
        step("Language") {
            tap("Language", how: .prefix)
            show("App language", hold: 1.2)
            show("Language for quotes and invoices", hold: 2.0)
            back()
        }
        step("Example data") {
            tap("Try the app with example data", how: .prefix)
            tap("Add examples", how: .exact, after: 1.5)
            tab("Home", after: 1.5)
            show("Needs attention", hold: 2.5)
            scrollDown(0.3, times: 1, hold: 1.5)
            tap("Remove example data", how: .exact)
            tap("Remove examples", how: .exact, after: 1.5)
        }
        step("Help, Privacy policy and About") {
            tab("Settings")
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
            tap("Erase all data", how: .prefix)
            tap("Erase everything", how: .exact, after: 2.0)
            waitText("Welcome to TidyQuote", timeout: 20)
            pause(2.5)
        }
    }

    /// Adds the logo. On a real iPhone: the camera, with iOS asking for camera access first. In the simulator,
    /// which has no camera: a made-up logo picture from the photo library (put there by the workflow).
    func pickLogo() {
        let menu = ["Take Photo", "Photo Library", "Choose File"]
        var options: [String: XCUIElement] = [:]
        let deadline = Date().addingTimeInterval(8)
        while options.isEmpty && Date() < deadline {
            for name in menu {
                if let e = find(name, how: .exact, kinds: [[.button, .menuItem, .cell, .staticText]]), onScreen(e) { options[name] = e }
            }
            if options.isEmpty { Thread.sleep(forTimeInterval: 0.4) }
        }
        dumpTree("logo menu")
        if let camera = options["Take Photo"], !onSimulator {
            tapFound(camera, scroll: false, before: 1.2, after: 1.0)
            answerSystemAlert(["Allow", "OK"], timeout: 10)
            let shutter = app.buttons["PhotoCapture"].exists ? app.buttons["PhotoCapture"] : app.buttons["Take Picture"]
            if shutter.waitForExistence(timeout: 10) {
                pause(2.0)
                markTap(shutter.frame)
                shutter.tap()
                pause(2.0)
                let use = app.buttons["Use Photo"]
                if use.waitForExistence(timeout: 10) {
                    markTap(use.frame)
                    use.tap()
                }
            } else {
                mark("note", "no camera shutter button")
                dumpTree("camera", force: true)
            }
        } else if let library = options["Photo Library"] {
            tapFound(library, scroll: false, before: 1.2, after: 2.0)
            let photos = app.images.matching(NSPredicate(format: "label BEGINSWITH[c] 'Photo'"))
            _ = photos.firstMatch.waitForExistence(timeout: 10)
            dumpTree("photo picker")
            let shown = photos.allElementsBoundByIndex.filter { $0.isHittable }
            // The newest picture (the logo the workflow added) is last in the grid.
            if let newest = shown.max(by: { ($0.frame.maxY, $0.frame.maxX) < ($1.frame.maxY, $1.frame.maxX) }) {
                pause(1.0)
                markTap(newest.frame)
                newest.tap()
                pause(1.5)
                tapIfPresent("Choose", how: .exact, kinds: [[.button]])
            } else {
                mark("note", "no photos in the picker")
                dumpTree("photo picker empty", force: true)
                tapIfPresent("Cancel", how: .exact, kinds: [[.button]])
            }
        } else {
            mark("note", "no image menu appeared")
            dumpTree("no logo menu", force: true)
        }
        if find("Logo saved", how: .contains, kinds: [Tour.passive]) != nil || waitOptional("Logo saved", timeout: 6) {
            mark("show", "Logo saved")
        }
        pause(2.0)
    }
}
