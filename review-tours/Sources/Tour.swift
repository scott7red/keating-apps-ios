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
    static let actionable: [Kind] = [.button, .link, .radioButton, .checkBox, .switch, .cell, .menuItem, .tab, .segmentedControl,
                                     .disclosureTriangle, .popUpButton, .comboBox, .textField, .image]
    static let passive: [Kind] = [.staticText, .other]
    static let fields: [Kind] = [.textField, .secureTextField, .textView, .searchField]

    // MARK: - Setup

    /// The app's tab bars, each left to right (see tab()).
    var tabBars: [[String]] { [] }

    /// Which match to use when several elements show the same text.
    enum Pick {
        /// The one that can be tapped now (an open sheet's button rather than the same-named one behind it), else the last.
        case tappable
        /// The first one in the page.
        case first
        /// The lowest on screen.
        case lowest
    }

    override func setUpWithError() throws {
        // Carry on after a miss, so the recording always runs to the end (the miss is still reported).
        continueAfterFailure = true
        // Xcode's default limit per test is 10 minutes; MinuteBank's tour is longer.
        executionTimeAllowance = 3600
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
        // Not atomically: an atomic write goes through a temporary folder the simulator's runner cannot use.
        do {
            try Data(text.utf8).write(to: file)
        } catch {
            mark("note", "tree not saved: \(error.localizedDescription)")
        }
        // On a real iPhone (Test Lab) the file stays on the phone: the test report carries a copy.
        if !onSimulator || force {
            let attachment = XCTAttachment(string: text)
            attachment.name = file.lastPathComponent
            attachment.lifetime = .keepAlways
            add(attachment)
        }
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
        var icon = springboard.icons[iconName]
        if !icon.waitForExistence(timeout: 8) {
            // On some iOS versions the Home Screen icons are not of type "icon".
            icon = springboard.descendants(matching: .any).matching(NSPredicate(format: "label ==[c] %@", iconName)).firstMatch
            dumpTree("home screen", force: true)
        }
        if icon.waitForExistence(timeout: 8) {
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

    /// The element showing `text`, trying each group of element kinds in order. When several match
    /// (a button behind an open sheet and the sheet's own button with the same name), the one that can
    /// be tapped wins; if none can yet, the last one (sheets come last in the page).
    func find(_ text: String, how: How? = nil, kinds: [[Kind]] = [Tour.actionable, Tour.passive], pick: Pick = .tappable, in root: XCUIElement? = nil) -> XCUIElement? {
        let hows: [How] = how.map { [$0] } ?? [.exact, .prefix]
        for h in hows {
            for group in kinds {
                let q = query(text, h, group, in: root)
                let count = q.count
                if count == 0 { continue }
                if count == 1 || pick == .first { return q.element(boundBy: 0) }
                let all = (0..<min(count, 8)).map { q.element(boundBy: $0) }
                if pick == .lowest { return all.max { $0.frame.midY < $1.frame.midY }! }
                if let tappable = all.first(where: { $0.isHittable }) { return tappable }
                return all[all.count - 1]
            }
        }
        return nil
    }

    func exists(_ text: String, how: How? = nil, kinds: [[Kind]] = [Tour.actionable, Tour.passive]) -> Bool {
        find(text, how: how, kinds: kinds) != nil
    }

    @discardableResult
    func waitFor(_ text: String, how: How? = nil, kinds: [[Kind]] = [Tour.actionable, Tour.passive], pick: Pick = .tappable, in root: XCUIElement? = nil,
                 timeout: Double = 15, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let element = find(text, how: how, kinds: kinds, pick: pick, in: root) { return element }
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

    /// Waits for some text without failing the tour; returns whether it appeared.
    func waitOptional(_ text: String, how: How = .contains, kinds: [[Kind]] = [Tour.passive, Tour.actionable], timeout: Double) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if find(text, how: how, kinds: kinds) != nil { return true }
            Thread.sleep(forTimeInterval: 0.4)
        } while Date() < deadline
        return false
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
        guard element.exists else { return }
        // With the keyboard up, only the part above it (and its toolbar) counts as on screen.
        let keyboard = app.keyboards.firstMatch
        let keyboardTop: CGFloat? = keyboard.exists ? keyboard.frame.minY - 56 : nil
        for _ in 0..<20 {
            let f = element.frame
            if f.isEmpty || f.isNull || f.isInfinite { return }
            let w = window
            let top = w.minY + w.height * topBand
            var bottom = w.minY + w.height * bottomBand
            if let kt = keyboardTop, kt > top + 80 { bottom = min(bottom, kt) }
            if f.midY >= top && f.midY <= bottom { return }
            // Already fully on screen and tappable (for example in a fixed bar at the bottom): leave it.
            // (Not in the bottom 110 points, where a tab bar can cover it while the element still counts as hittable.)
            if f.minY >= w.minY + 44 && f.maxY <= min(w.maxY - 110, keyboardTop ?? w.maxY) && element.isHittable { return }
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
        // Drag only where the content is: above the keyboard when it is up.
        let keyboard = app.keyboards.firstMatch
        let low = keyboard.exists ? max(w.height * 0.3, keyboard.frame.minY - 70) : w.height * 0.70
        let high = w.height * 0.25
        var move = dy
        if dy < 0 { move = max(dy, high - low) } else { move = min(dy, low - high) }
        let startY = dy < 0 ? low : high
        let start = origin.withOffset(CGVector(dx: w.width * x, dy: startY))
        let end = origin.withOffset(CGVector(dx: w.width * x, dy: startY + move))
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
        guard element.exists else {
            mark("note", "skipped a tap: the element is not there")
            return
        }
        reveal(element)
        pause(before)
        // Wait for it to stop moving (a sheet sliding up, a list growing after the last tap).
        var f = element.frame
        for _ in 0..<8 {
            Thread.sleep(forTimeInterval: 0.25)
            let again = element.frame
            if abs(again.midY - f.midY) < 2 && abs(again.midX - f.midX) < 2 { break }
            f = again
        }
        markTap(f)
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: f.midX, dy: f.midY)).tap()
        pause(after)
    }

    /// Finds `text` (a button, link, choice...) and taps it.
    @discardableResult
    func tap(_ text: String, how: How? = nil, kinds: [[Kind]] = [Tour.actionable, Tour.passive], pick: Pick = .tappable, timeout: Double = 15,
             before: Double = 0.7, after: Double = 1.3, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let element = waitFor(text, how: how, kinds: kinds, pick: pick, timeout: timeout, file: file, line: line)
        tapElement(element, before: before, after: after)
        return element
    }

    /// Taps an element without scrolling first (when `scroll` is false), with the usual pauses.
    func tapFound(_ element: XCUIElement, scroll: Bool = true, before: Double = 0.7, after: Double = 1.3) {
        if scroll {
            tapElement(element, before: before, after: after)
            return
        }
        pause(before)
        let f = element.frame
        markTap(f)
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: f.midX, dy: f.midY)).tap()
        pause(after)
    }

    /// A tab in the app's tab bar. The bars are full-width rows of equal tabs, and WebKit can report a fixed,
    /// CSS-transformed bar's frames shifted sideways (TidyQuote's "Settings" came out over "Clients"), so the
    /// k-th of the n names in its bar (`tabBars`) is tapped at (k + 0.5) / n of the screen width.
    func tab(_ name: String, after: Double = 1.5, file: StaticString = #filePath, line: UInt = #line) {
        let found = waitFor(name, how: .exact, kinds: [[.button, .link, .tab]], pick: .lowest, file: file, line: line)
        pause(0.6)
        let f = found.frame
        if let bar = tabBars.first(where: { $0.contains(name) }), let k = bar.firstIndex(of: name) {
            let x = window.width * (CGFloat(k) + 0.5) / CGFloat(bar.count)
            if abs(x - f.midX) > 20 { mark("note", "tab \(name): reported at x \(Int(f.midX)), tapped at \(Int(x))") }
            let point = CGRect(x: x - 1, y: f.midY - 1, width: 2, height: 2)
            markTap(point)
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: f.midY)).tap()
        } else {
            markTap(f)
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: f.midX, dy: f.midY)).tap()
        }
        pause(after)
    }

    func onScreen(_ element: XCUIElement) -> Bool {
        element.exists && element.frame.intersects(window) && element.isHittable
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
        let field = findField(label, how: how) ?? waitFor(label, how: how, kinds: [Tour.fields], file: file, line: line)
        guard field.exists else { return }
        // A field behind the keyboard (or its bar) cannot always be scrolled above it inside a sheet: put the
        // keyboard away first, then scroll to the field and tap it.
        let keyboard = app.keyboards.firstMatch
        if keyboard.exists && field.frame.maxY > keyboard.frame.minY - 60 { hideKeyboard() }
        tapElement(field, before: 0.5, after: 0.4)
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 4)
        if clear, let current = field.value as? String, !current.isEmpty, current != (field.placeholderValue ?? "") {
            app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 1))
        }
        typeSlowly(text)
        pause(0.8)
        if let now = field.value as? String, !now.contains(text) {
            mark("note", "typed \(text) into \(label), but it shows \(now)")
        }
    }

    /// A text field by its label. Some iOS versions name a web field by its placeholder, or not at all; then the
    /// field is the one just below the visible label text.
    func findField(_ label: String, how: How?, timeout: Double = 15) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let f = find(label, how: how, kinds: [Tour.fields]) { return f }
            let types = Tour.fields.map { NSNumber(value: $0.rawValue) }
            let byPlaceholder = app.descendants(matching: .any)
                .matching(NSPredicate(format: "elementType IN %@ AND placeholderValue BEGINSWITH[c] %@", types, label)).firstMatch
            if byPlaceholder.exists { return byPlaceholder }
            if let text = find(label, how: how ?? .prefix, kinds: [Tour.passive]) {
                let lf = text.frame
                let fields = app.descendants(matching: .any).matching(NSPredicate(format: "elementType IN %@", types))
                let below = (0..<min(fields.count, 40)).map { fields.element(boundBy: $0) }
                    .filter { $0.frame.minY >= lf.maxY - 4 && $0.frame.minY < lf.maxY + 80 && $0.frame.maxX > lf.minX && $0.frame.minX < lf.maxX }
                if let nearest = below.min(by: { $0.frame.minY < $1.frame.minY }) {
                    mark("note", "field \(label) found below its label")
                    return nearest
                }
            }
            Thread.sleep(forTimeInterval: 0.4)
        } while Date() < deadline
        return nil
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
        for (i, candidate) in [app.toolbars.buttons["Done"], app.buttons["Done"], app.keyboards.buttons["Done"]].enumerated() {
            if candidate.exists && candidate.isHittable {
                if !keyboardDoneNoted { mark("note", "keyboard Done found as candidate \(i): \(candidate.label)"); keyboardDoneNoted = true }
                markTap(candidate.frame)
                candidate.tap()
                pause(0.7)
                return
            }
        }
        // A tap on plain text (nothing that reacts to a tap, and not a field's label, which would focus the field
        // again) takes the focus away from the field.
        guard let snap = try? app.snapshot() else { return }
        var texts: [CGRect] = []
        var controls: [CGRect] = []
        var keyboardTop = snap.frame.maxY
        func walk(_ s: XCUIElementSnapshot) {
            if s.elementType == .keyboard && !s.frame.isEmpty { keyboardTop = min(keyboardTop, s.frame.minY) }
            if s.elementType == .staticText && !s.frame.isEmpty { texts.append(s.frame) }
            if Tour.fields.contains(s.elementType) { controls.append(s.frame.insetBy(dx: -6, dy: -44)) }
            else if Tour.actionable.contains(s.elementType) { controls.append(s.frame.insetBy(dx: -6, dy: -6)) }
            for c in s.children { walk(c) }
        }
        walk(snap)
        if let plain = texts.first(where: { t in t.minY > snap.frame.height * 0.12 && t.maxY < keyboardTop - 60 && !controls.contains { $0.intersects(t) } }) {
            mark("note", "keyboard put away by tapping plain text")
            markTap(plain)
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: plain.midX, dy: plain.midY)).tap()
        } else {
            mark("note", "no Done button or plain text to put the keyboard away")
            dumpTree("keyboard stays", force: true)
        }
        pause(0.7)
    }
    private var keyboardDoneNoted = false

    /// The back arrow at the top left of an app screen (labelled "Back", or with the previous screen's name).
    func back(after: Double = 1.3, file: StaticString = #filePath, line: UInt = #line) {
        let w = window
        // "Back", "Back to Settings", "Back to deals"...
        if let b = find("Back", how: .prefix, kinds: [[.button, .link]]), b.isHittable, b.frame.minY < w.minY + w.height * 0.2 {
            tapElement(b, before: 0.6, after: after)
            return
        }
        for kind in [Kind.button, Kind.link] {
            let candidates = app.webViews.firstMatch.descendants(matching: kind)
            let count = min(candidates.count, 10)
            for i in 0..<count {
                let b = candidates.element(boundBy: i)
                let f = b.frame
                if f.minY < w.minY + w.height * 0.15 && f.midX < w.width * 0.4 && b.isHittable {
                    tapElement(b, before: 0.6, after: after)
                    return
                }
            }
        }
        dumpTree("no back button", force: true)
        XCTFail("No back button at the top left", file: file, line: line)
    }

    /// Sets an <input type="time"> with iOS's own time picker: taps the field, turns the wheels to the hour,
    /// minute and AM/PM of `date`, then closes the picker with Done.
    func setTime(_ label: String, to date: Date, file: StaticString = #filePath, line: UInt = #line) {
        let field = waitFor(label, kinds: [Tour.fields, [.button, .other, .staticText, .datePicker]], file: file, line: line)
        tapElement(field, before: 0.6, after: 1.2)
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
    func answerSystemAlert(_ choices: [String], timeout: Double = 20, hold: Double = 2.2, required: Bool = true,
                           file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let alert = springboard.alerts.firstMatch
        guard alert.waitForExistence(timeout: timeout) else {
            mark("note", "no iOS prompt appeared")
            dumpTree("no iOS prompt", force: true)
            if required { XCTFail("No iOS prompt appeared within \(Int(timeout)) s", file: file, line: line) }
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
        if let onPhone = find("On My iPhone", how: .exact, kinds: [[.cell, .button, .staticText, .other]]), onPhone.isHittable {
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
        var icon = springboard.icons[iconName]
        if !icon.waitForExistence(timeout: 3) {
            icon = springboard.descendants(matching: .any).matching(NSPredicate(format: "label ==[c] %@", iconName)).firstMatch
        }
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
