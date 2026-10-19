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

- Run 1 (pending): infrastructure + first TidyQuote steps, simulator, debug trees on.
