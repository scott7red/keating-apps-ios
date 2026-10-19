import XCTest
#if targetEnvironment(simulator)
import StoreKitTest
#endif

/// The four exam apps share one engine and one tour: app-store/<id>/review-notes.txt, section 1, and the exam
/// pages of "App Review Videos.pdf". Setup with an exam, the free sample, a lock opening the purchase sheet,
/// the purchase (in the simulator, through a local StoreKit configuration: Apple's own sheet, no account, no
/// money), the study tools, a timed test, Erase all data and Restore Purchases, Terms, Privacy, Help, and
/// deleting the profile. On a real iPhone in Test Lab there is no sandbox account, so the tour shows the
/// purchase sheet and Apple's response to Buy, then carries on with what the free sample allows.
class ExamTour: Tour {
    /// The exam picked during setup (its name in the list) and its short name (in "<short> is unlocked").
    var examName: String { "" }
    var shortName: String { "" }
    override var tabBars: [[String]] { [["Home", "Learn", "Practice", "Tests", "Progress"]] }
    let profileName = "Alex"
    private var storeSession: Any?

    override func setUpWithError() throws {
        try super.setUpWithError()
        #if targetEnvironment(simulator)
        if let url = Bundle(for: ExamTour.self).url(forResource: "Review", withExtension: "storekit") {
            let session = try SKTestSession(contentsOf: url)
            session.resetToDefaultState()
            session.disableDialogs = false
            session.clearTransactions()
            storeSession = session
            mark("note", "StoreKit test session from Review.storekit")
        } else {
            mark("note", "no Review.storekit in the test bundle")
        }
        #endif
    }

    func testTour() throws {
        step("Launch from the Home Screen") {
            launchFromHomeScreen()
            waitText("Get started", timeout: 40)
            pause(2.0)
        }
        step("Welcome") {
            show("What is inside", hold: 1.5)
            show("free sample", hold: 2.5)
            scrollDown(0.3, times: 1, hold: 1.0)
            tap("Get started", how: .exact)
        }
        setUpProfile(slow: true)
        step("The free sample: practice questions") {
            show("Free sample", hold: 2.5)
            tab("Practice", after: 1.5)
            tap("Start a Quick 10", how: .exact, after: 1.5)
            answer("A")
            show("Next question", hold: 2.0)
            tap("Next question", how: .exact, after: 1.2)
            answer("B")
            pause(1.5)
            tap("Close", how: .prefix, after: 1.5)
        }
        step("The free sample: the study guide") {
            tab("Learn", after: 1.5)
            tap("Start reading:", how: .prefix, after: 2.0)
            scrollDown(0.35, times: 2, hold: 1.2)
            back()
            show("Topics", hold: 1.0)
            show("included with the full exam", hold: 2.0)
        }
        step("A lock opens the purchase sheet") {
            tap("Flashcards", how: .prefix, after: 1.5)
            waitText("The full exam includes")
            pause(1.5)
            scrollDown(0.3, times: 1, hold: 1.0)
            waitPrice()
            show("One-time purchase", hold: 2.0)
            show("Restore Purchases", hold: 1.0)
            show("Not now", hold: 1.5)
        }
        if onSimulator {
            step("The purchase") {
                tap("Buy for", how: .prefix, after: 1.0)
                confirmStorePurchase()
                if !waitOptional("is unlocked", timeout: 20) {
                    mark("note", "no 'is unlocked' message after the purchase")
                    dumpTree("after purchase", force: true)
                }
                pause(2.5)
            }
            step("The study tools, now open") {
                tap("Flashcards", how: .prefix, after: 1.5)
                tap("Study all", how: .exact, after: 1.5)
                tap("Show answer", how: .exact, after: 2.0)
                tap("Good", how: .prefix, after: 1.5)
                tap("Close", how: .prefix, after: 1.5)
                scrollDown(0.35, times: 2, hold: 1.2)
                show("Glossary", hold: 2.0)
            }
            step("A timed test") {
                tab("Tests", after: 1.5)
                tap("Practice Test 1", how: .prefix, pick: .first, after: 1.5)
                show("Exam mode", hold: 1.5)
                tap("Start Practice Test 1", how: .exact, after: 2.0)
                pause(1.5)
                answer("A")
                tap("Next", how: .exact, after: 1.2)
                answer("B")
                tap("Flag", how: .exact, after: 1.5)
                tap("All questions", how: .exact, after: 1.5)
                tap("Submit test", how: .exact, after: 1.2)
                tap("Submit test", how: .exact, kinds: [[.button]], after: 2.5)
                scrollDown(0.3, times: 2, hold: 1.5)
            }
            step("Erase all data") {
                tab("Home", after: 1.5)
                tap("Settings", how: .exact, after: 1.5)
                tap("Erase all data", how: .prefix)
                tap("Erase everything", how: .exact, after: 2.0)
                waitText("Get started", timeout: 20)
                pause(1.5)
                tap("Get started", how: .exact)
            }
            setUpProfile(slow: false)
        } else {
            step("Buy, on a real iPhone without a sandbox account") {
                if let buy = find("Buy for", how: .prefix, kinds: [[.button]]), buy.isEnabled {
                    tapFound(buy, before: 1.0, after: 2.0)
                    dumpTree("device purchase", force: true)
                    pause(8.0)
                    for name in ["Cancel", "Not Now", "Close"] {
                        for root in [app, springboard] {
                            let b = root.buttons[name]
                            if b.exists && b.isHittable {
                                markTap(b.frame)
                                b.tap()
                                pause(1.5)
                            }
                        }
                    }
                } else {
                    mark("note", "no price from the App Store on this device")
                }
                tapIfPresent("Not now", how: .exact)
                pause(1.5)
            }
        }
        step("Restore Purchases") {
            tap("Settings", how: .exact, after: 1.5)
            tap("Restore Purchases", how: .exact, kinds: [[.button]], after: 0.5)
            confirmStoreSignInIfAsked()
            if waitOptional("Restored", timeout: 20) {
                mark("show", "Restored")
                pause(2.0)
            }
            show("Owned", hold: 2.5)
        }
        step("Terms of use, Privacy policy and Help") {
            tap("Terms of use", how: .prefix, after: 1.5)
            scrollDown(0.35, times: 1, hold: 1.2)
            back()
            tap("Privacy policy", how: .prefix, after: 1.5)
            scrollDown(0.35, times: 1, hold: 1.2)
            back()
            tap("Help", how: .prefix, after: 1.5)
            scrollDown(0.35, times: 1, hold: 1.2)
            back()
        }
        step("Delete the profile") {
            scrollToTop()
            tap("Delete profile", how: .prefix)
            type(profileName, into: "Type \(profileName) to confirm", how: .prefix)
            hideKeyboard()
            tap("Delete profile", how: .exact, kinds: [[.button]], after: 2.5)
            pause(2.0)
        }
    }

    /// Profile, exam and the three short setup screens. The second time (after Erase all data) goes quicker.
    func setUpProfile(slow: Bool) {
        step(slow ? "Setup: a profile and an exam" : "Set up again") {
            waitText("Create your profile")
            pause(slow ? 1.0 : 0.4)
            type(profileName, into: "First name or nickname")
            hideKeyboard()
            tap("Continue", how: .exact, after: slow ? 1.3 : 0.8)
            waitText("Which exam are you studying for?")
            if slow { scrollDown(0.25, times: 1, hold: 1.0) }
            tap(examName, how: .prefix, after: slow ? 1.2 : 0.6)
            tap("Continue", how: .exact, after: slow ? 1.3 : 0.8)
            waitText("Four steps to exam day")
            pause(slow ? 1.5 : 0.5)
            tap("Continue", how: .exact, after: slow ? 1.3 : 0.8)
            tap("I do not have a date yet", how: .exact, after: slow ? 1.3 : 0.8)
            tap("Start studying", how: .exact, after: 2.0)
        }
    }

    /// Taps an answer by its letter (the answers read "A ...", "B ...").
    func answer(_ letter: String, file: StaticString = #filePath, line: UInt = #line) {
        let choice = app.webViews.firstMatch.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", letter + " ", letter + ",")).firstMatch
        guard choice.waitForExistence(timeout: 15) else {
            dumpTree("no answer \(letter)", force: true)
            XCTFail("No answer \(letter)", file: file, line: line)
            return
        }
        tapElement(choice, before: 1.5, after: 2.0)
    }

    /// Waits until the sheet shows the price (or says why not).
    func waitPrice() {
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if find("Buy for", how: .prefix, kinds: [[.button]]) != nil { break }
            if exists("could not be loaded", how: .contains) || exists("not available from the App Store", how: .contains) { break }
            Thread.sleep(forTimeInterval: 0.5)
        }
        if let b = find("Buy for", how: .prefix, kinds: [[.button]]) {
            mark("note", "price shown: \(b.label)")
            show("Buy for", hold: 1.5)
        } else {
            mark("note", "no price on the purchase sheet")
            dumpTree("no price", force: true)
            pause(2.0)
        }
    }

    /// Apple's purchase sheet runs outside the app. Finds its confirm button in the app, in SpringBoard or in
    /// the StoreKit UI service, leaves the sheet on screen for a moment, then taps it.
    func confirmStorePurchase() {
        let roots: [XCUIApplication] = [app, springboard, XCUIApplication(bundleIdentifier: "com.apple.ios.StoreKitUIService"),
                                        XCUIApplication(bundleIdentifier: "com.apple.StoreKitUIService")]
        let names = ["Purchase", "Buy", "Confirm", "Subscribe", "Pay", "OK"]
        let predicate = NSPredicate(format: "label IN %@ OR identifier IN %@", names, names)
        let deadline = Date().addingTimeInterval(25)
        var shown = false
        while Date() < deadline {
            for root in roots {
                let button = root.buttons.matching(predicate).firstMatch
                if button.exists && button.isHittable {
                    if !shown {
                        shown = true
                        mark("show", "App Store purchase sheet")
                        dumpTree("purchase sheet")
                        pause(2.5)
                        continue
                    }
                    mark("note", "confirmed the purchase with \(button.label)")
                    markTap(button.frame)
                    button.tap()
                    pause(2.0)
                    // "You're all set" and similar.
                    for root2 in roots {
                        let ok = root2.buttons.matching(NSPredicate(format: "label IN %@", ["OK", "Done"])).firstMatch
                        if ok.waitForExistence(timeout: 3) && ok.isHittable {
                            pause(1.5)
                            markTap(ok.frame)
                            ok.tap()
                            break
                        }
                    }
                    return
                }
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        mark("note", "no App Store purchase sheet found")
        dumpTree("no purchase sheet", force: true)
        for root in roots.dropFirst() {
            let text = root.debugDescription
            try? text.write(to: Tour.outDir.appendingPathComponent("trees/purchase-\(root.hashValue).txt"), atomically: true, encoding: .utf8)
        }
    }

    /// Restore can ask to sign in to the App Store. In the simulator's StoreKit test environment it does not.
    func confirmStoreSignInIfAsked() {
        let alert = springboard.alerts.firstMatch
        if alert.waitForExistence(timeout: 3) {
            mark("alert", alert.label)
            dumpTree("restore alert", force: true)
            pause(2.0)
            let cancel = alert.buttons["Cancel"]
            if cancel.exists {
                markTap(cancel.frame)
                cancel.tap()
            }
        }
    }
}

final class RealEstateTour: ExamTour {
    override var iconName: String { "RE Coach" }
    override var examName: String { "California Salesperson Exam" }
    override var shortName: String { "CA Sales" }
}

final class InsuranceTour: ExamTour {
    override var iconName: String { "Ins Coach" }
    override var examName: String { "Life Insurance (general knowledge)" }
    override var shortName: String { "Life" }
}

final class ContractorTour: ExamTour {
    override var iconName: String { "Contractor" }
    override var examName: String { "CSLB Law & Business" }
    override var shortName: String { "Law & Business" }
}

final class PilotDroneTour: ExamTour {
    override var iconName: String { "Pilot+Drone" }
    override var examName: String { "FAA Part 107 Remote Pilot (UAG)" }
    override var shortName: String { "Part 107" }
}
