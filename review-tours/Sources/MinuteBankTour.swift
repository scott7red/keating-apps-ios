import XCTest

/// MinuteBank: app-store/minutebank/review-notes.txt, section 1, and its page in "App Review Videos.pdf".
/// Setup (parent PIN, a child), earning with the math challenge and a chore, the parent approving behind the PIN,
/// a 10-minute screen-time countdown with the notification prompt, the "5 minutes left" notification with the app
/// closed, ending early, the parent's Kids, Rules and Activity, the example data, Help, Privacy policy, About,
/// and Erase all data. The wait for the notification is sped up in the video, with a caption saying so.
final class MinuteBankTour: Tour {
    override var iconName: String { "MinuteBank" }
    override var tabBars: [[String]] { [["Home", "Earn", "Use time", "Parents"], ["Approvals", "Kids", "Rules", "Activity", "Settings"]] }
    let pin = ["2", "4", "6", "8"]

    func enterPin() {
        for digit in pin { tap(digit, how: .exact, kinds: [[.button]], before: 0.25, after: 0.35) }
        pause(1.0)
    }

    func testTour() throws {
        step("Launch from the Home Screen") {
            launchFromHomeScreen()
            waitText("Get started", timeout: 30)
            pause(2.0)
            tap("Get started", how: .exact)
        }
        step("How it works") {
            waitText("A bank for screen time")
            show("They earn it", hold: 1.2)
            show("They spend it", hold: 1.2)
            show("You set the rules", hold: 1.2)
            show("Good to know", hold: 2.0)
            tap("Set up MinuteBank")
        }
        step("Parent PIN") {
            waitText("Create a parent PIN")
            pause(1.0)
            enterPin()
            waitText("Enter it again")
            enterPin()
            waitText("Add a hint, if you like")
            pause(1.0)
            tap("Continue", how: .exact)
        }
        step("Who is the bank for?") {
            waitText("Who is the bank for?")
            type("Sam", into: "Child", how: .prefix)
            hideKeyboard()
            tap("5 to 6", how: .exact)
            tap("Open the bank", how: .exact, after: 1.5)
            tap("Hand over to Sam", how: .exact, after: 1.5)
        }
        step("Earn with the math challenge") {
            tap("Math challenge", how: .prefix)
            tap("Start", how: .exact)
            for n in 1...10 {
                let problem = waitFor("equals blank", how: .contains, kinds: [[.other, .staticText, .group]])
                let answer = Self.solve(problem.label)
                mark("note", "question \(n): \(problem.label) = \(answer)")
                for digit in String(answer) { tap(String(digit), how: .exact, kinds: [[.button]], before: 0.3, after: 0.3) }
                tap("Check", how: .exact, before: 0.4, after: 1.0)
                if n < 10 { tap("Next", how: .exact, before: 0.3, after: 0.8) } else { tap("Finish", how: .exact, after: 1.5) }
            }
            show("Your score", hold: 2.5)
        }
        step("Earn with a chore") {
            tab("Earn", after: 1.2)
            tap("Chores", how: .prefix, after: 1.2)
            tap("Done: Make your bed", how: .exact, after: 1.2)
            show("Waiting for a parent", hold: 2.0)
        }
        step("The parent approves") {
            tab("Parents")
            waitText("Enter your 4-digit PIN")
            enterPin()
            waitText("Approvals")
            pause(1.0)
            tap("Approve Make your bed", how: .prefix, after: 1.5)
            tap("Lock", how: .exact, after: 1.5)
        }
        var started = Date()
        step("Start 10 minutes of screen time") {
            tab("Use time", after: 1.2)
            tap("Another amount", how: .exact, after: 1.2)
            tap("Start 10 minutes", how: .exact, after: 0.5)
            started = Date()
        }
        step("Notification permission and the countdown") {
            answerSystemAlert(["Allow"])
            show("left", hold: 2.5)
            tap("Hide timer", how: .exact, after: 1.5)
        }
        step("The parent area while the timer runs") {
            tab("Parents")
            waitText("Enter your 4-digit PIN")
            enterPin()
            for name in ["Kids", "Rules", "Activity"] {
                tap(name, how: .exact, after: 1.0)
                scrollDown(0.3, times: 1, hold: 1.0)
            }
            tab("Settings", after: 1.2)
            for name in ["Help", "Privacy policy", "About"] {
                tap(name, how: .prefix, after: 1.5)
                scrollDown(0.3, times: 1, hold: 1.2)
                back()
            }
            tap("Lock", how: .exact, after: 1.5)
        }
        step("The 5 minutes left notification, with the app closed") {
            goToHomeScreen()
            mark("wait", "Waiting for the 5 minutes left notification")
            let due = started.addingTimeInterval(5 * 60 + 30).timeIntervalSinceNow
            let banner = waitForNotification("5 minutes left", timeout: max(30, due + 60))
            mark("waitend")
            if banner == nil {
                mark("note", "the 5 minutes left notification did not arrive")
                dumpTree("no notification", force: true)
            }
            pause(3.0)
            openNotificationCenter()
            pause(3.0)
        }
        step("End the countdown early") {
            reopenFromIcon()
            tap("Screen time is running", how: .prefix, after: 1.5)
            tap("End early", how: .exact, after: 1.2)
            tap("End now", how: .exact, after: 2.0)
        }
        step("Example data") {
            tab("Parents")
            waitText("Enter your 4-digit PIN")
            enterPin()
            tab("Settings", after: 1.2)
            tap("Show example data", how: .exact)
            tap("Show example data", how: .exact, after: 1.5)
            tab("Activity", after: 1.5)
            scrollDown(0.3, times: 1, hold: 1.5)
            tap("Remove example data", how: .exact, after: 1.5)
        }
        step("Erase all data") {
            tab("Settings", after: 1.2)
            tap("Erase", how: .exact)
            tap("Erase all data", how: .exact, kinds: [[.button]], after: 2.0)
            waitText("Get started", timeout: 20)
            pause(2.5)
        }
    }

    /// "7 plus 4 equals blank" gives 11.
    static func solve(_ label: String) -> Int {
        let regex = try! NSRegularExpression(pattern: "(\\d+)\\s+(plus|minus|times)\\s+(\\d+)")
        let ns = label as NSString
        guard let m = regex.firstMatch(in: label, range: NSRange(location: 0, length: ns.length)) else { return 0 }
        let a = Int(ns.substring(with: m.range(at: 1))) ?? 0
        let b = Int(ns.substring(with: m.range(at: 3))) ?? 0
        switch ns.substring(with: m.range(at: 2)) {
        case "plus": return a + b
        case "minus": return a - b
        default: return a * b
        }
    }
}
