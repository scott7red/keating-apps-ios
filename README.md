# iPhone builds for the App Store

One shared iPhone shell (Capacitor, in `native/`) turns each of the 30 web apps into an iPhone app. GitHub's Macs build them and upload them to App Store Connect, so no Mac is needed. This is the same method Plumbline and Rule Breaker Chessboard use, with the same App Store Connect API key.

Each app is bundled whole inside its iPhone app and works offline. Nothing is loaded from the web, and no server is involved.

## What is here

- **`apps.json`**: one entry per app:
  - the App Store name;
  - the home-screen name;
  - the bundle ID (`com.keatingkonsultancy.<app>`) and the SKU;
  - the launch-screen color;
  - the permission texts Apple requires (TidyQuote: camera and photos; BRRR: location);
  - the submission wave (see `app-store/README.md`).
- **`apps/<id>/`**: the built web app (`www/`), the 1024 icon and the launch screen.
- **`native/`**: the shared Xcode project. `tools/prepare.mjs <id>` turns it into one app on the build machine. It sets the name, bundle ID, icon, launch screen and permissions, and makes the app iPhone-only, portrait-only and iOS 16 or later.
  - It includes two official Capacitor plugins, `@capacitor/filesystem` and `@capacitor/share`, because the iPhone web view cannot save downloads or share files. Each app's `src/lib/files.ts` uses them at run time through `window.Capacitor.Plugins`: it writes an export (PDF, CSV, backup, .ics) to the app's cache and opens the iOS share sheet with it.
  - `npx cap sync ios` lists the plugins in `ios/App/CapApp-SPM/Package.swift`. The workflow runs it on every build, and the committed copy matches.
  - `ios/App/App/PrivacyInfo.xcprivacy` declares the file-timestamp reason (C617.1) that Apple requires for the Filesystem plugin.
- **`.github/workflows/iphone-build.yml`**: the build.

## Updating the apps

1. Build the web apps: in `exam-prep`, `npm run build:all`; in each tool folder, `npm run build`.
2. `node tools/collect.mjs` copies the builds, icons and launch screens in here and rewrites `apps.json`.
3. Commit and push.
4. Run the workflow.

## Running a build

On GitHub, go to Actions > "iPhone builds" > "Run workflow". Type the apps to build: ids separated by commas, or `wave1`, `wave2`, `wave3` or `all`.

For each app, the build:
- registers the bundle ID if needed;
- builds and signs the app;
- uploads it to App Store Connect, where it appears under TestFlight a few minutes later.

The build number is the run number.

## One-time setup

1. **The key.** Add the repository secret `ASC_KEY_P8` (Settings > Secrets and variables > Actions). Paste in the whole .p8 file of the "GitHub build admin" key, the same one the Plumbline repository uses.
2. **The app records.** Each app must exist in App Store Connect before its first upload, because Apple's API cannot create apps. In App Store Connect, go to Apps > + > New App, and use the name, bundle ID and SKU from `apps.json`. If one is missing, the build stops early and says which.
