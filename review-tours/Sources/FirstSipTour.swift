import XCTest

/// FirstSip: app-store/firstsip/review-notes.txt, section 1, and its page in "App Review Videos.pdf".
/// The first-run screens and "Before you start", a medicine, the label checklist, a dose and the wait timer,
/// the notification prompt and the "wait is over" notification (with the dose logged as taken 28 minutes ago,
/// so the 30-minute wait ends in about 2 minutes), History, weight, a symptom, the doctor report PDF through
/// the share sheet, the calendar reminder screen, the example data, Help, Privacy policy, About, Erase all data.
final class FirstSipTour: Tour {
    override var iconName: String { "FirstSip" }

    func testTour() throws {
        step("Launch from the Home Screen") {
            launchFromHomeScreen()
            waitText("Get started", timeout: 30)
            pause(2.0)
        }
        step("Welcome") {
            show("It is not medical advice", hold: 2.0)
            tap("Get started", how: .exact)
        }
        step("Before you start") {
            waitText("Before you start")
            show("It never recommends, calculates or adjusts a dose", hold: 2.5)
            tap("I understand", how: .exact)
        }
        step("Which medicine") {
            waitText("Which medicine do you take?")
            pause(1.0)
            tap("Semaglutide tablets (Wegovy pill)", how: .prefix)
            tap("Continue", how: .exact)
        }
        step("A few details") {
            waitText("A few details")
            tap("Pounds (lb)", how: .exact)
            tap("Start using FirstSip")
        }
        step("The label checklist and a dose") {
            waitText("Before your first sip")
            pause(1.5)
            tap("Take it on an empty stomach", how: .prefix, after: 0.8)
            tap("Swallow the tablet whole", how: .prefix, after: 1.0)
            tap("I took my pill", how: .exact, after: 0.5)
        }
        step("Notification permission and the wait timer") {
            answerSystemAlert(["Allow"])
            show("Time left", hold: 1.5)
            if waitOptional("notification when the wait is over", timeout: 4) {
                show("notification when the wait is over", hold: 2.0)
            }
        }
        step("Logged earlier: 28 minutes ago") {
            tap("Logged by mistake? Undo", how: .prefix)
            tap("Remove dose", how: .exact, after: 1.5)
            tap("I took it earlier", how: .exact, after: 1.5)
            setTime("Time taken today", to: Date().addingTimeInterval(-28 * 60))
            tap("Log dose", how: .exact, after: 2.0)
            show("Time left", hold: 2.5)
        }
        step("The notification, with the app closed") {
            goToHomeScreen()
            mark("wait", "Waiting for the notification")
            let banner = waitForNotification("clear to eat", timeout: 200)
            mark("waitend")
            if banner == nil {
                mark("note", "the 'clear to eat' notification did not arrive")
                dumpTree("no notification", force: true)
            }
            pause(3.0)
            openNotificationCenter()
            pause(2.5)
            let entry = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] 'clear to eat'")).firstMatch
            if entry.exists && entry.isHittable {
                markTap(entry.frame)
                entry.tap()
                pause(2.0)
            }
            if app.state != .runningForeground { reopenFromIcon() }
            pause(1.5)
        }
        step("History") {
            tap("History", how: .exact, after: 1.5)
            show("Doses", hold: 2.0)
        }
        step("Weight") {
            tap("Weight", how: .exact, after: 1.2)
            tap("Log weight", how: .exact)
            type("180", into: "Weight (lb)", how: .prefix)
            hideKeyboard()
            tap("Save weight", how: .exact, after: 2.0)
        }
        step("A symptom") {
            tap("Symptoms", how: .exact, after: 1.2)
            tap("Log a symptom", how: .exact)
            tap("Nausea", how: .exact, after: 0.8)
            show("How bad is it?", hold: 0.8)
            tap("Mild", how: .exact, after: 0.8)
            tap("Save symptom", how: .exact, after: 2.0)
        }
        step("The doctor report PDF, through the share sheet") {
            tap("More", how: .exact, after: 1.2)
            tap("Doctor report", how: .prefix, after: 1.5)
            show("In this report", hold: 2.0)
            tap("Share or save PDF", how: .exact, after: 1.5)
            shareSheetSaveToFiles()
        }
        step("The calendar reminder screen") {
            tap("More", how: .exact, after: 1.2)
            tap("Daily reminder", how: .prefix, after: 1.5)
            show("Add a daily reminder to the Calendar app", hold: 2.0)
            show("How it works", hold: 2.0)
            tap("More", how: .exact, after: 1.2)
        }
        step("Example data") {
            tap("Settings", how: .prefix, after: 1.5)
            tap("Try the app with example data", how: .prefix, after: 2.0)
            tapIfPresent("Show example data", how: .exact)
            tap("History", how: .exact, after: 2.0)
            scrollDown(0.3, times: 1, hold: 1.2)
            tap("Weight", how: .exact, after: 2.0)
            scrollDown(0.3, times: 1, hold: 1.2)
            tap("More", how: .exact, after: 1.2)
            tap("Settings", how: .prefix, after: 1.5)
            tap("Remove example data", how: .exact)
            tapIfPresent("Remove example data", how: .exact)
            pause(1.5)
        }
        step("Help, Privacy policy and About") {
            tap("Help", how: .prefix, after: 1.5)
            scrollDown(0.3, times: 2, hold: 1.2)
            back()
            tap("Privacy policy", how: .prefix, after: 1.5)
            scrollDown(0.3, times: 2, hold: 1.2)
            back()
            tap("About FirstSip", how: .prefix, after: 1.5)
            scrollDown(0.3, times: 1, hold: 1.5)
            back()
        }
        step("Erase all data") {
            tap("Erase all data", how: .exact)
            tap("Erase everything", how: .exact, after: 2.0)
            waitText("Get started", timeout: 20)
            pause(2.5)
        }
    }
}
