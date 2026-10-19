# Review video pipeline: working notes

Progress log for the automated App Review recordings (`.github/workflows/review-videos.yml`).
Newest entries at the bottom of each section.

## How it fits together

- `run.json`: what a push to the `review-videos` branch records (apps, mode, debug).
- `tours.json`: per app, the UI-test class and settings (StoreKit, location, real clock).
- `add-target.rb`: on the build Mac only, adds the `ReviewTour` UI-test target + scheme to `native/ios/App/App.xcodeproj`
  (after `tools/prepare.mjs`). The committed project and the App Store build never contain it.
- `Sources/Tour.swift`: shared helpers (find by visible label in the web view, reveal by slow drags, tap with pauses,
  type, system alerts, notifications). Writes `marks.tsv` (time, kind, detail) for post-processing.
- `Sources/<App>Tour.swift`: one tour per app, following `app-store/<id>/review-notes.txt` section 1 and the
  step lists in `_tools/work/videos/build9.py` (source of "App Review Videos.pdf").
- `storekit.mjs`: local StoreKit configuration for the exam apps, from `iap-products.json` (a copy of
  `app-store/iap-products.json`).
- `postprocess.mjs`: trims to the Home Screen + icon tap, draws tap circles, speeds up waits with a visible caption,
  makes `sheet.jpg` (every 5 s), `steps.jpg` (end of each step), `last.jpg`, `info.json`.
- `attach.mjs`: App Review attachment upload (reserve, PUT parts, commit with MD5). Dry run unless `--upload`.
- `ci.mjs`: small helpers (tour settings, runtime pick, Test Lab device pick, time zone, run summary).
- Feedback: branch `review-videos-out`, `<run>/<app>/<mode>/`; only the latest runs are kept (orphan commit, force-pushed).

## Decisions

- Simulator runtime iOS 26.2 (installed on `macos-26` runners): local StoreKit testing through `xcodebuild test` is
  reported broken on 26.3/26.4/26.5 runtimes (purchase returns userCancelled / config not pushed), works on 26.2.
- Status bar 9:41 except FirstSip and MinuteBank (they show times and wait for notifications), which keep the real clock.
  The Mac's time zone is set before boot so the local time is late morning (MinuteBank allows screen time 7 AM-8 PM).
- Test Lab: device chosen = newest iPhone on iOS 16-17, because Test Lab records no video on iOS 18+.
  Signing: ad hoc (`CODE_SIGN_IDENTITY=-`), relying on Test Lab re-signing; untested yet.
- Test Lab videos cannot be aligned with the marks (unknown video start), so they are kept whole (no circles/speed-up).

## Log

- Run 1: plan, simulator boot (iOS 26.2), npm ci, prepare, add-target.rb and build-for-testing all worked first time.
  The "Set up the simulator for filming" step then hung (>5 min, no logs visible without a token). Fix: every simctl
  call there now has a time limit (perl alarm) and a line in setup.log (pushed with the feedback); step time limits added.
- Labels for all 9 apps were collected by running each built web app (apps/<id>/www) in a local browser at 402x874
  and listing buttons/links/inputs with their accessible names. Notable: duplicate labels when a sheet is open
  (find() prefers the hittable match, else the last); Settings back buttons are named after the parent screen in
  FirstSip ("Settings", "More"), hence the generic top-left back().
- Test Lab runs every test in the .xctestrun, so `xctestrun.py` limits it to the app's tour (OnlyTestIdentifiers).
