import XCTest

/// The shared base of the App Review tours.
///
/// A tour drives the real, unmodified app from outside, the way a person does: it finds what is on
/// screen by its visible label (web content inside the app's web view is exposed to UI tests like
/// native controls), scrolls until it is in view, pauses so a viewer can follow, and taps it.
/// Nothing is added to the app; this bundle only exists on the build machine.
///
/// Looking things up: every XCUIElement property read makes XCTest copy the whole screen from the app,
/// and a web view's screen is large. So the tour takes one snapshot of the screen and searches it here
/// (`screen()`, `find`), and taps by coordinates. System UI outside the app (alerts, the share sheet,
/// notifications) is still reached through ordinary XCUIElement queries.
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
    /// Which match to use when several elements show the same text.
    enum Pick {
        /// The last one on screen: an open sheet's button rather than the same-named one behind it.
        case lastOnScreen
        /// The first one in the page.
        case first
        /// The lowest on screen (a tab in the tab bar).
        case lowest
    }
    typealias Kind = XCUIElement.ElementType
    static let actionable: [Kind] = [.button, .link, .radioButton, .checkBox, .switch, .cell, .menuItem, .tab, .segmentedControl,
                                     .disclosureTriangle, .popUpButton, .comboBox, .textField, .image]
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
        let screenFrame = springboard.windows.firstMatch.frame
        mark("screen", "\(Int(screenFrame.width)) \(Int(screenFrame.height))")
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

    // MARK: - What is on screen

    /// One element of a snapshot of the screen.
    struct Node {
        let type: Kind
        let label: String
        let identifier: String
        let value: String
        let placeholder: String
        let frame: CGRect
        let enabled: Bool
    }

    /// The app's screen at one moment: every element, the window and the keyboard (if it is up).
    struct Screen {
        let nodes: [Node]
        let window: CGRect
        let keyboard: CGRect?
    }

    /// A found element, and what is needed to find it again after the screen scrolls.
    struct Found {
        let node: Node
        let text: String
        let how: How
        let ordinal: Int
        var frame: CGRect { node.frame }
        var label: String { node.label }
    }

    func screen() -> Screen {
        var nodes: [Node] = []
        var window = CGRect.zero
        var keyboard: CGRect?
        if let snap = try? app.snapshot() {
            func walk(_ s: XCUIElementSnapshot) {
                nodes.append(Node(type: s.elementType, label: s.label, identifier: s.identifier, value: (s.value as? String) ?? "",
                                  placeholder: s.placeholderValue ?? "", frame: s.frame, enabled: s.isEnabled))
                if s.elementType == .window && window == .zero && !s.frame.isEmpty { window = s.frame }
                if s.elementType == .keyboard && !s.frame.isEmpty { keyboard = s.frame }
                for child in s.children { walk(child) }
            }
            walk(snap)
            if window == .zero { window = snap.frame }
        }
        return Screen(nodes: nodes, window: window, keyboard: keyboard)
    }

    func matches(_ n: Node, _ text: String, _ how: How) -> Bool {
        switch how {
        case .exact: return n.label.compare(text, options: .caseInsensitive) == .orderedSame || n.identifier == text
        case .prefix: return n.label.range(of: text, options: [.caseInsensitive, .anchored]) != nil
        case .contains: return n.label.range(of: text, options: .caseInsensitive) != nil
        }
    }

    func onScreen(_ f: CGRect, _ s: Screen) -> Bool {
        f.intersects(s.window) && (s.keyboard.map { f.midY < $0.minY } ?? true)
    }

    /// The element showing `text`: exact label first, then a label starting with it (unless `how` is given),
    /// trying each group of element kinds in order.
    func find(_ text: String, how: How? = nil, kinds: [[Kind]] = [Tour.actionable, Tour.passive], pick: Pick = .lastOnScreen, in given: Screen? = nil) -> Found? {
        let s = given ?? screen()
        let hows: [How] = how.map { [$0] } ?? [.exact, .prefix]
        for h in hows {
            for group in kinds {
                let hits = s.nodes.indices.filter { group.contains(s.nodes[$0].type) && !s.nodes[$0].frame.isEmpty && matches(s.nodes[$0], text, h) }
                if hits.isEmpty { continue }
                let visible = hits.filter { onScreen(s.nodes[$0].frame, s) }
                let chosen: Int
                switch pick {
                case .first: chosen = hits[0]
                case .lastOnScreen: chosen = visible.last ?? hits[hits.count - 1]
                case .lowest: chosen = (visible.isEmpty ? hits : visible).max { s.nodes[$0].frame.midY < s.nodes[$1].frame.midY }!
                }
                let node = s.nodes[chosen]
                let sameType = hits.filter { s.nodes[$0].type == node.type }
                return Found(node: node, text: text, how: h, ordinal: sameType.firstIndex(of: chosen) ?? 0)
            }
        }
        return nil
    }

    /// The same element in a newer snapshot.
    func refind(_ f: Found, in s: Screen) -> Found? {
        let same = s.nodes.filter { $0.type == f.node.type && !$0.frame.isEmpty && matches($0, f.text, f.how) }
        guard !same.isEmpty else { return nil }
        let k = min(f.ordinal, same.count - 1)
        return Found(node: same[k], text: f.text, how: f.how, ordinal: k)
    }

    func exists(_ text: String, how: How? = nil, kinds: [[Kind]] = [Tour.actionable, Tour.passive]) -> Bool {
        find(text, how: how, kinds: kinds) != nil
    }

    @discardableResult
    func waitFor(_ text: String, how: How? = nil, kinds: [[Kind]] = [Tour.actionable, Tour.passive], pick: Pick = .lastOnScreen,
                 timeout: Double = 15, file: StaticString = #filePath, line: UInt = #line) -> Found {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let found = find(text, how: how, kinds: kinds, pick: pick) { return found }
            Thread.sleep(forTimeInterval: 0.3)
        } while Date() < deadline
        dumpTree("missing " + text, force: true)
        XCTFail("Could not find \"\(text)\" on screen within \(Int(timeout)) s", file: file, line: line)
        return Found(node: Node(type: .other, label: "", identifier: "", value: "", placeholder: "", frame: .zero, enabled: false),
                     text: text, how: .exact, ordinal: 0)
    }

    /// Waits for some text to be on screen.
    @discardableResult
    func waitText(_ text: String, timeout: Double = 15, file: StaticString = #filePath, line: UInt = #line) -> Found {
        waitFor(text, how: .contains, kinds: [Tour.passive, Tour.actionable], timeout: timeout, file: file, line: line)
    }

    /// Waits for some text without failing the tour; returns whether it appeared.
    func waitOptional(_ text: String, how: How = .contains, kinds: [[Kind]] = [Tour.passive, Tour.actionable], timeout: Double) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if find(text, how: how, kinds: kinds) != nil { return true }
            Thread.sleep(forTimeInterval: 0.3)
        } while Date() < deadline
        return false
    }

    /// Waits until `text` is gone (for example a sheet closing).
    func waitGone(_ text: String, how: How = .contains, timeout: Double = 15) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline && exists(text, how: how) { Thread.sleep(forTimeInterval: 0.3) }
    }

    // MARK: - Scrolling

    var window: CGRect { screen().window }

    /// Scrolls (slowly, with no fling) until the element sits comfortably on screen; returns it as it is then.
    @discardableResult
    func reveal(_ found: Found) -> Found {
        var current = found
        var s = screen()
        if let again = refind(found, in: s) { current = again }
        for _ in 0..<15 {
            let f = current.frame
            let w = s.window
            let top = w.minY + w.height * topBand
            var bottom = w.minY + w.height * bottomBand
            if let kb = s.keyboard, kb.minY - 50 > top + 80 { bottom = min(bottom, kb.minY - 50) }
            if f.midY >= top && f.midY <= bottom { return current }
            let target = top + (bottom - top) * 0.4
            let limit = w.height * 0.42
            drag(max(-limit, min(limit, target - f.midY)), in: s)
            s = screen()
            guard let moved = refind(current, in: s) else { return current }
            // Nothing moved: a fixed bar (or the end of the page). Use it where it is.
            if abs(moved.frame.midY - f.midY) < 2 { return moved }
            current = moved
        }
        return current
    }

    /// Drags the content by `dy` points (negative shows what is below), slowly and without a fling.
    func drag(_ dy: CGFloat, x: CGFloat = 0.5, in given: Screen? = nil) {
        let s = given ?? screen()
        let w = s.window
        let origin = app.coordinate(withNormalizedOffset: .zero)
        // Drag only where the content is: above the keyboard when it is up.
        let low = s.keyboard.map { max(w.height * 0.3, $0.minY - 70) } ?? w.height * 0.70
        let high = w.height * 0.25
        let move = dy < 0 ? max(dy, high - low) : min(dy, low - high)
        let startY = dy < 0 ? low : high
        let start = origin.withOffset(CGVector(dx: w.width * x, dy: startY))
        let end = origin.withOffset(CGVector(dx: w.width * x, dy: startY + move))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: XCUIGestureVelocity(rawValue: 650), thenHoldForDuration: 0.25)
        pause(0.4)
    }

    /// Scrolls down by part of a screen, `times` times, holding after each so the viewer can read.
    func scrollDown(_ fraction: CGFloat = 0.35, times: Int = 1, hold: Double = 1.4) {
        let s = screen()
        for _ in 0..<times {
            drag(-s.window.height * fraction, in: s)
            pause(hold)
        }
    }

    func scrollUp(_ fraction: CGFloat = 0.35, times: Int = 1, hold: Double = 0.8) {
        let s = screen()
        for _ in 0..<times {
            drag(s.window.height * fraction, in: s)
            pause(hold)
        }
    }

    /// Scrolls to the top of the screen quickly (a few big drags).
    func scrollToTop() {
        let s = screen()
        for _ in 0..<5 { drag(s.window.height * 0.6, in: s) }
    }

    // MARK: - Tapping and typing

    func markTap(_ frame: CGRect) {
        mark("tap", "\(Int(frame.midX)) \(Int(frame.midY))")
    }

    func tapPoint(_ frame: CGRect) {
        markTap(frame)
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
    }

    /// Brings the element into view and taps its centre, with a pause before and after.
    func tapFound(_ found: Found, scroll: Bool = true, before: Double = 0.7, after: Double = 1.3) {
        let target = scroll ? reveal(found) : found
        pause(before)
        tapPoint(target.frame)
        pause(after)
    }

    /// Finds `text` (a button, link, choice...) and taps it.
    @discardableResult
    func tap(_ text: String, how: How? = nil, kinds: [[Kind]] = [Tour.actionable, Tour.passive], pick: Pick = .lastOnScreen, timeout: Double = 15,
             before: Double = 0.7, after: Double = 1.3, file: StaticString = #filePath, line: UInt = #line) -> Found {
        let found = waitFor(text, how: how, kinds: kinds, pick: pick, timeout: timeout, file: file, line: line)
        tapFound(found, before: before, after: after)
        return found
    }

    /// A tab in the app's tab bar at the bottom: tapped where it is, no scrolling.
    func tab(_ name: String, after: Double = 1.5, file: StaticString = #filePath, line: UInt = #line) {
        let found = waitFor(name, how: .exact, kinds: [[.button, .link, .tab]], pick: .lowest, file: file, line: line)
        tapFound(found, scroll: false, before: 0.6, after: after)
    }

    /// Taps `text` only if it is on screen now. Returns whether it was there.
    @discardableResult
    func tapIfPresent(_ text: String, how: How? = nil, kinds: [[Kind]] = [Tour.actionable], before: Double = 0.6, after: Double = 1.2) -> Bool {
        guard let found = find(text, how: how, kinds: kinds) else { return false }
        tapFound(found, before: before, after: after)
        return true
    }

    /// Brings some text into view and holds on it, for "point at ..." in the guide.
    func show(_ text: String, hold: Double = 2.0, timeout: Double = 15, file: StaticString = #filePath, line: UInt = #line) {
        let found = waitFor(text, how: .contains, kinds: [Tour.passive, Tour.actionable], timeout: timeout, file: file, line: line)
        reveal(found)
        mark("show", text)
        pause(hold)
    }

    /// Taps the text field labelled `label`, clears it and types `text` at a readable speed.
    func type(_ text: String, into label: String, clear: Bool = true, how: How? = nil, file: StaticString = #filePath, line: UInt = #line) {
        let field = waitFor(label, how: how, kinds: [Tour.fields], file: file, line: line)
        tapFound(field, before: 0.5, after: 0.4)
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 4)
        let current = field.node.value
        if clear && !current.isEmpty && current != field.node.placeholder {
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
        let s = screen()
        guard let kb = s.keyboard else { return }
        pause(0.4)
        // The web view's Done sits in the bar just above the keyboard.
        let done = s.nodes.filter { $0.type == .button && ($0.label == "Done" || $0.identifier == "Done") && $0.frame.maxY <= kb.minY + 4 && $0.frame.minY > kb.minY - 80 }
        if let d = done.first {
            tapPoint(d.frame)
        } else if let d = s.nodes.first(where: { $0.type == .button && $0.label == "Done" && kb.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }) {
            tapPoint(d.frame)
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.09)).tap()
        }
        pause(0.8)
    }

    /// The back arrow at the top left of an app screen (labelled "Back", or with the previous screen's name).
    func back(after: Double = 1.3, file: StaticString = #filePath, line: UInt = #line) {
        let s = screen()
        if let b = find("Back", how: .exact, kinds: [[.button, .link]], in: s), onScreen(b.frame, s) {
            tapFound(b, scroll: false, before: 0.6, after: after)
            return
        }
        let w = s.window
        if let b = s.nodes.first(where: { ($0.type == .button || $0.type == .link) && !$0.frame.isEmpty && $0.frame.minY >= w.minY + 30
                                          && $0.frame.maxY < w.minY + w.height * 0.16 && $0.frame.midX < w.width * 0.4 }) {
            pause(0.6)
            tapPoint(b.frame)
            pause(after)
            return
        }
        dumpTree("no back button", force: true)
        XCTFail("No back button at the top left", file: file, line: line)
    }

    /// Sets an <input type="time"> with iOS's own time picker: taps the field, turns the wheels to the hour,
    /// minute and AM/PM of `date`, then closes the picker with Done.
    func setTime(_ label: String, to date: Date, file: StaticString = #filePath, line: UInt = #line) {
        let field = waitFor(label, kinds: [Tour.fields, [.button, .other, .staticText, .datePicker]], file: file, line: line)
        tapFound(field, before: 0.6, after: 1.2)
        dumpTree("time picker")
        let cal = Calendar.current
        var hour = cal.component(.hour, from: date)
        let minute = cal.component(.minute, from: date)
        let pm = hour >= 12
        hour = hour % 12 == 0 ? 12 : hour % 12
        mark("note", "time picker: \(hour):\(String(format: "%02d", minute)) \(pm ? "PM" : "AM")")
        let wheels = app.pickerWheels
        if wheels.firstMatch.waitForExistence(timeout: 6) {
            let all = wheels.allElementsBoundByIndex
            mark("note", "picker wheels: " + all.map { ($0.value as? String) ?? "?" }.joined(separator: " | "))
            if all.count >= 2 {
                all[0].adjust(toPickerWheelValue: "\(hour)")
                pause(0.7)
                all[1].adjust(toPickerWheelValue: String(format: "%02d", minute))
                pause(0.7)
                if all.count >= 3 {
                    all[2].adjust(toPickerWheelValue: pm ? "PM" : "AM")
                    pause(0.7)
                }
            }
        } else {
            mark("note", "no picker wheels for the time")
            dumpTree("time picker without wheels", force: true)
        }
        pause(1.0)
        for candidate in [app.toolbars.buttons["Done"], app.buttons["Done"]] where candidate.exists && candidate.isHittable {
            markTap(candidate.frame)
            candidate.tap()
            pause(1.0)
            break
        }
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

    // MARK: - Share sheet

    /// The iOS share sheet that an export opens: holds on it, then Save to Files, On My iPhone, Save.
    /// If a part of that is missing, the sheet is closed instead and the tour carries on.
    func shareSheetSaveToFiles() {
        let saveToFiles = app.descendants(matching: .any).matching(NSPredicate(format: "label ==[c] 'Save to Files'")).firstMatch
        guard saveToFiles.waitForExistence(timeout: 20) else {
            mark("note", "the share sheet did not appear")
            dumpTree("no share sheet", force: true)
            return
        }
        mark("show", "share sheet")
        pause(2.5)
        dumpTree("share sheet")
        markTap(saveToFiles.frame)
        saveToFiles.tap()
        pause(2.5)
        dumpTree("save to files")
        let onPhone = app.descendants(matching: .any).matching(NSPredicate(format: "label ==[c] 'On My iPhone'")).firstMatch
        if onPhone.exists && onPhone.isHittable {
            markTap(onPhone.frame)
            onPhone.tap()
            pause(1.5)
        }
        let save = app.buttons.matching(NSPredicate(format: "label ==[c] 'Save'")).firstMatch
        if save.waitForExistence(timeout: 8) && save.isHittable {
            pause(1.0)
            markTap(save.frame)
            save.tap()
            pause(2.0)
            // Saving again over the same name asks first.
            let replace = app.buttons.matching(NSPredicate(format: "label ==[c] 'Replace'")).firstMatch
            if replace.waitForExistence(timeout: 2) {
                markTap(replace.frame)
                replace.tap()
                pause(1.5)
            }
        } else {
            mark("note", "Save to Files had no Save button")
            dumpTree("no save button", force: true)
            for name in ["Cancel", "Close"] {
                let b = app.buttons[name]
                if b.exists && b.isHittable {
                    markTap(b.frame)
                    b.tap()
                    pause(1.5)
                    break
                }
            }
        }
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
