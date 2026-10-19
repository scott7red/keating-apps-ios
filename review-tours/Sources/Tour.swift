import XCTest

/// The shared base of the App Review tours.
///
/// A tour drives the real, unmodified app from outside, the way a person does: it finds what is on
/// screen by its visible label (web content inside the app's web view is exposed to UI tests like
/// native controls), scrolls until it is in view, pauses so a viewer can follow, and taps it.
/// Nothing is added to the app; this bundle only exists on the build machine.
///
/// Every step writes a line to marks.tsv (time, kind, detail). The workflow uses the marks to trim
/// the video to the app's launch, to draw a circle where each tap lands, to speed up waiting parts
/// (with a caption saying so) and to make the contact sheets.
class Tour: XCTestCase {
    let app = XCUIApplication()
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    /// The name under the app's icon on the Home Screen (displayName in apps.json).
    var iconName: String { "" }

    /// Parts of the screen kept clear of the app's fixed header (top) and tab bar (bottom) when scrolling.
    var topBand: CGFloat = 0.14
    var bottomBand: CGFloat = 0.78

    enum How { case exact, prefix, contains }
    typealias Kind = XCUIElement.ElementType
    static let actionable: [Kind] = [.button, .link, .radioButton, .checkBox, .switch, .cell, .menuItem, .tab, .segmentedControl, .textField, .image]
    static let passive: [Kind] = [.staticText, .other]
    static let fields: [Kind] = [.textField, .secureTextField, .textView, .searchField]

    // MARK: - Setup

    override func setUpWithError() throws {
        continueAfterFailure = false
        try? FileManager.default.createDirectory(at: Tour.outDir, withIntermediateDirectories: true)
        mark("setup", name)
    }

    override func tearDownWithError() throws {
        if let run = testRun, !run.hasSucceeded {
            mark("fail", name)
            dumpTree("failure", force: true)
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "failure"
            shot.lifetime = .keepAlways
            add(shot)
        } else {
            mark("done", name)
        }
        mark("end")
    }

    static func env(_ key: String) -> String? {
        let value = ProcessInfo.processInfo.environment[key]
        return (value?.isEmpty ?? true) ? nil : value
    }

    static let outDir: URL = {
        if let dir = env("TOUR_OUT") { return URL(fileURLWithPath: dir) }
        return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tour")
    }()

    var debugTrees: Bool { Tour.env("TOUR_DEBUG") == "1" }
    /// TOUR_PACE=0.3 makes the pauses shorter, for quick checks of a tour.
    var pace: Double { Double(Tour.env("TOUR_PACE") ?? "") ?? 1 }

    // MARK: - Marks and pacing

    func mark(_ kind: String, _ detail: String = "") {
        let clean = detail.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
        let line = String(format: "%.3f", Date().timeIntervalSince1970) + "\t" + kind + "\t" + clean + "\n"
        print("TOURMARK\t" + line, terminator: "")
        let url = Tour.outDir.appendingPathComponent("marks.tsv")
        let data = Data(line.utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try? data.write(to: url)
        }
    }

    func pause(_ seconds: Double) {
        if seconds > 0 { Thread.sleep(forTimeInterval: seconds * pace) }
    }

    private var treeCount = 0

    /// Saves the app's element tree (what the tour can see) when TOUR_DEBUG=1, and always on failure.
    func dumpTree(_ label: String, force: Bool = false) {
        guard debugTrees || force else { return }
        treeCount += 1
        let dir = Tour.outDir.appendingPathComponent("trees")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = String(label.map { $0.isLetter || $0.isNumber ? $0 : "-" }.prefix(40))
        let file = dir.appendingPathComponent(String(format: "%02d-", treeCount) + safe + ".txt")
        var text = app.debugDescription
        if force { text += "\n\n===== Springboard =====\n" + springboard.debugDescription }
        try? text.write(to: file, atomically: true, encoding: .utf8)
    }

    /// One step of the tour: a named activity in the test report and a mark for the step sheet.
    func step(_ title: String, _ body: () throws -> Void) rethrows {
        mark("step", title)
        try XCTContext.runActivity(named: title) { _ in try body() }
        dumpTree(title)
    }

    // MARK: - Launch

    /// Starts on the Home Screen and taps the app's icon, as a person would.
    func launchFromHomeScreen() {
        XCUIDevice.shared.press(.home)
        pause(1.5)
        let screen = springboard.windows.firstMatch.frame
        mark("screen", "\(Int(screen.width)) \(Int(screen.height))")
        let icon = springboard.icons[iconName]
        if icon.waitForExistence(timeout: 15) {
            var swipes = 0
            while !icon.isHittable && swipes < 4 {
                springboard.swipeLeft()
                pause(1.0)
                swipes += 1
            }
            mark("start")
            pause(2.0)
            markTap(icon.frame)
            icon.tap()
        } else {
            mark("note", "icon \(iconName) not found; opening the app directly")
            mark("start")
            app.activate()
        }
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "The app did not open")
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 30), "The app's web view did not appear")
    }

    // MARK: - Finding things

    func query(_ text: String, _ how: How, _ kinds: [Kind], in root: XCUIElement? = nil) -> XCUIElementQuery {
        let types = kinds.map { NSNumber(value: $0.rawValue) }
        let predicate: NSPredicate
        switch how {
        case .exact: predicate = NSPredicate(format: "elementType IN %@ AND (label ==[c] %@ OR identifier ==[c] %@)", types, text, text)
        case .prefix: predicate = NSPredicate(format: "elementType IN %@ AND label BEGINSWITH[c] %@", types, text)
        case .contains: predicate = NSPredicate(format: "elementType IN %@ AND label CONTAINS[c] %@", types, text)
        }
        return (root ?? app).descendants(matching: .any).matching(predicate)
    }

    /// The first element showing `text`, trying each group of element kinds in order.
    func find(_ text: String, how: How? = nil, kinds: [[Kind]] = [Tour.actionable, Tour.passive], in root: XCUIElement? = nil) -> XCUIElement? {
        let hows: [How] = how.map { [$0] } ?? [.exact, .prefix]
        for h in hows {
            for group in kinds {
                let element = query(text, h, group, in: root).firstMatch
                if element.exists { return element }
            }
        }
        return nil
    }

    func exists(_ text: String, how: How? = nil, kinds: [[Kind]] = [Tour.actionable, Tour.passive]) -> Bool {
        find(text, how: how, kinds: kinds) != nil
    }

    @discardableResult
    func waitFor(_ text: String, how: How? = nil, kinds: [[Kind]] = [Tour.actionable, Tour.passive], in root: XCUIElement? = nil,
                 timeout: Double = 15, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let element = find(text, how: how, kinds: kinds, in: root) { return element }
            Thread.sleep(forTimeInterval: 0.4)
        } while Date() < deadline
        dumpTree("missing " + text, force: true)
        XCTFail("Could not find \"\(text)\" on screen within \(Int(timeout)) s", file: file, line: line)
        return app.otherElements["tour-missing-element"]
    }

    /// Waits for some text to be on screen.
    @discardableResult
    func waitText(_ text: String, timeout: Double = 15, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        waitFor(text, how: .contains, kinds: [Tour.passive, Tour.actionable], timeout: timeout, file: file, line: line)
    }

    /// Waits until `text` is gone (for example a sheet closing).
    func waitGone(_ text: String, how: How = .contains, timeout: Double = 15) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline && exists(text, how: how) { Thread.sleep(forTimeInterval: 0.4) }
    }

    // MARK: - Scrolling

    var window: CGRect { app.windows.firstMatch.frame }

    /// Scrolls (slowly, with no fling) until the element sits comfortably on screen.
    func reveal(_ element: XCUIElement) {
        for _ in 0..<20 {
            let f = element.frame
            if f.isEmpty || f.isNull || f.isInfinite { return }
            let w = window
            let top = w.minY + w.height * topBand
            let bottom = w.minY + w.height * bottomBand
            if f.midY >= top && f.midY <= bottom { return }
            // Already fully on screen and tappable (for example in a fixed bar at the bottom): leave it.
            if f.minY >= w.minY + 44 && f.maxY <= w.maxY - 8 && element.isHittable { return }
            let target = top + (bottom - top) * 0.4
            let limit = w.height * 0.42
            drag(max(-limit, min(limit, target - f.midY)))
            if abs(element.frame.midY - f.midY) < 2 { return }
        }
    }

    /// Drags the content by `dy` points (negative shows what is below), slowly and without a fling.
    func drag(_ dy: CGFloat, x: CGFloat = 0.5) {
        let w = window
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let startY = dy < 0 ? w.height * 0.70 : w.height * 0.30
        let start = origin.withOffset(CGVector(dx: w.width * x, dy: startY))
        let end = origin.withOffset(CGVector(dx: w.width * x, dy: startY + dy))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: XCUIGestureVelocity(rawValue: 650), thenHoldForDuration: 0.25)
        pause(0.5)
    }

    /// Scrolls down by part of a screen, `times` times, holding after each so the viewer can read.
    func scrollDown(_ fraction: CGFloat = 0.35, times: Int = 1, hold: Double = 1.4) {
        for _ in 0..<times {
            drag(-window.height * fraction)
            pause(hold)
        }
    }

    func scrollUp(_ fraction: CGFloat = 0.35, times: Int = 1, hold: Double = 0.8) {
        for _ in 0..<times {
            drag(window.height * fraction)
            pause(hold)
        }
    }

    /// Scrolls to the top of the screen quickly (a few big drags).
    func scrollToTop() {
        for _ in 0..<6 { drag(window.height * 0.6) }
    }

    // MARK: - Tapping and typing

    func markTap(_ frame: CGRect) {
        mark("tap", "\(Int(frame.midX)) \(Int(frame.midY))")
    }

    /// Taps the element at its centre after bringing it into view, with a pause before and after.
    func tapElement(_ element: XCUIElement, before: Double = 0.7, after: Double = 1.3) {
        reveal(element)
        pause(before)
        let f = element.frame
        markTap(f)
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: f.midX, dy: f.midY)).tap()
        pause(after)
    }

    /// Finds `text` (a button, link, choice...) and taps it.
    @discardableResult
    func tap(_ text: String, how: How? = nil, kinds: [[Kind]] = [Tour.actionable, Tour.passive], timeout: Double = 15,
             before: Double = 0.7, after: Double = 1.3, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let element = waitFor(text, how: how, kinds: kinds, timeout: timeout, file: file, line: line)
        tapElement(element, before: before, after: after)
        return element
    }

    /// Taps `text` only if it is on screen now. Returns whether it was there.
    @discardableResult
    func tapIfPresent(_ text: String, how: How? = nil, kinds: [[Kind]] = [Tour.actionable], before: Double = 0.6, after: Double = 1.2) -> Bool {
        guard let element = find(text, how: how, kinds: kinds) else { return false }
        tapElement(element, before: before, after: after)
        return true
    }

    /// Brings some text into view and holds on it, for "point at ..." in the guide.
    func show(_ text: String, hold: Double = 2.0, timeout: Double = 15, file: StaticString = #filePath, line: UInt = #line) {
        let element = waitFor(text, how: .contains, kinds: [Tour.passive, Tour.actionable], timeout: timeout, file: file, line: line)
        reveal(element)
        mark("show", text)
        pause(hold)
    }

    /// Taps the text field labelled `label`, clears it and types `text` at a readable speed.
    func type(_ text: String, into label: String, clear: Bool = true, how: How? = nil, file: StaticString = #filePath, line: UInt = #line) {
        let field = waitFor(label, how: how, kinds: [Tour.fields], file: file, line: line)
        tapElement(field, before: 0.5, after: 0.4)
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 4)
        if clear, let current = field.value as? String, !current.isEmpty, current != (field.placeholderValue ?? "") {
            app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 1))
        }
        typeSlowly(text)
        pause(0.8)
    }

    /// Types into whatever has the keyboard now.
    func typeSlowly(_ text: String) {
        var chunk = ""
        for ch in text {
            chunk.append(ch)
            if chunk.count >= 3 || ch == " " {
                app.typeText(chunk)
                chunk = ""
            }
        }
        if !chunk.isEmpty { app.typeText(chunk) }
    }

    /// Puts the keyboard away with the Done button above it (or a tap on the screen's title area).
    func hideKeyboard() {
        guard app.keyboards.firstMatch.exists else { return }
        pause(0.4)
        for candidate in [app.toolbars.buttons["Done"], app.buttons["Done"], app.keyboards.buttons["Done"]] {
            if candidate.exists && candidate.isHittable {
                markTap(candidate.frame)
                candidate.tap()
                pause(0.7)
                return
            }
        }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.09)).tap()
        pause(0.7)
    }

    func back(after: Double = 1.3) {
        tap("Back", how: .exact, kinds: [[.button, .link]], after: after)
    }

    // MARK: - System prompts

    /// Waits for an iOS prompt (notifications, location, camera), leaves it on screen so the viewer can
    /// read it, then taps the first of `choices` that it offers.
    @discardableResult
    func answerSystemAlert(_ choices: [String], timeout: Double = 20, hold: Double = 2.2, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let alert = springboard.alerts.firstMatch
        guard alert.waitForExistence(timeout: timeout) else {
            mark("note", "no iOS prompt appeared")
            XCTFail("No iOS prompt appeared within \(Int(timeout)) s", file: file, line: line)
            return false
        }
        mark("alert", alert.label)
        pause(hold)
        for choice in choices {
            let button = alert.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", choice)).firstMatch
            if button.exists {
                markTap(button.frame)
                button.tap()
                pause(1.2)
                return true
            }
        }
        dumpTree("alert", force: true)
        XCTFail("The iOS prompt had none of \(choices)", file: file, line: line)
        return false
    }

    /// An alert shown by the app itself (a web confirm() dialog).
    func answerAppAlert(_ choice: String, timeout: Double = 10) {
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: timeout), "No alert appeared")
        pause(1.5)
        let button = alert.buttons[choice]
        markTap(button.frame)
        button.tap()
        pause(1.0)
    }

    // MARK: - Home Screen and notifications

    func goToHomeScreen() {
        mark("home")
        XCUIDevice.shared.press(.home)
        pause(1.5)
    }

    /// Waits for a notification banner (on the Home Screen) whose text contains `text`.
    func waitForNotification(_ text: String, timeout: Double) -> XCUIElement? {
        let banner = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
        return banner.waitForExistence(timeout: timeout) ? banner : nil
    }

    /// Pulls down Notification Center from the top-left corner.
    func openNotificationCenter() {
        let start = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.005))
        let end = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.55))
        mark("swipe", "notification center")
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: XCUIGestureVelocity(rawValue: 900), thenHoldForDuration: 0.2)
        pause(2.0)
    }

    /// Opens the app again from its Home Screen icon.
    func reopenFromIcon() {
        XCUIDevice.shared.press(.home)
        pause(1.0)
        let icon = springboard.icons[iconName]
        if icon.waitForExistence(timeout: 5) && icon.isHittable {
            pause(0.8)
            markTap(icon.frame)
            icon.tap()
        } else {
            app.activate()
        }
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        pause(1.5)
    }

    var onSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
}
