// Turns the shared iPhone shell (native/) into one app: runs on the build Mac before `cap sync ios`.
// node tools/prepare.mjs <appId>
// Uses only Node's standard library, so the build machine needs nothing extra.
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const id = process.argv[2]
const app = JSON.parse(fs.readFileSync(path.join(repo, 'apps.json'), 'utf8')).find((a) => a.id === id)
if (!app) throw new Error(`No app "${id}" in apps.json`)
const src = path.join(repo, 'apps', id)
const native = path.join(repo, 'native')
const ios = path.join(native, 'ios', 'App')

// 1. The web app ships inside the iPhone app.
fs.rmSync(path.join(native, 'www'), { recursive: true, force: true })
fs.cpSync(path.join(src, 'www'), path.join(native, 'www'), { recursive: true })

// 2. Capacitor settings. includePlugins limits cap sync to the plugins this app uses, so no app links
// a plugin it does not need (an unused location plugin would still need a usage string).
if (!Array.isArray(app.plugins) || app.plugins.length === 0) throw new Error(`${id}: apps.json has no plugins list`)
if (app.plugins.includes('@capacitor/geolocation') && !app.permissions?.NSLocationWhenInUseUsageDescription) {
  throw new Error(`${id}: @capacitor/geolocation needs NSLocationWhenInUseUsageDescription`)
}
fs.writeFileSync(
  path.join(native, 'capacitor.config.json'),
  JSON.stringify({ appId: app.bundleId, appName: app.name, webDir: 'www', backgroundColor: app.background, includePlugins: app.plugins, ios: { contentInset: 'never' } }, null, 2) + '\n',
)

// 3. Icon and launch screen.
fs.copyFileSync(path.join(src, 'icon.png'), path.join(ios, 'App', 'Assets.xcassets', 'AppIcon.appiconset', 'AppIcon-512@2x.png'))
for (const f of ['splash-2732x2732.png', 'splash-2732x2732-1.png', 'splash-2732x2732-2.png']) {
  fs.copyFileSync(path.join(src, 'splash.png'), path.join(ios, 'App', 'Assets.xcassets', 'Splash.imageset', f))
}

// 4. Info.plist: home-screen name, permission texts, portrait only.
const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
const plistFile = path.join(ios, 'App', 'Info.plist')
let plist = fs.readFileSync(plistFile, 'utf8')
plist = plist.replace(/(<key>CFBundleDisplayName<\/key>\s*<string>)[^<]*(<\/string>)/, `$1${esc(app.displayName)}$2`)
plist = plist.replace(/\s*<key>NS[A-Za-z]+UsageDescription<\/key>\s*<string>[^<]*<\/string>/g, '')
const perms = Object.entries(app.permissions || {})
  .map(([k, v]) => `\n\t<key>${k}</key>\n\t<string>${esc(v)}</string>`)
  .join('')
plist = plist.replace(/(<key>LSRequiresIPhoneOS<\/key>\s*<true\/>)/, `$1${perms}`)
plist = plist.replace(
  /(<key>UISupportedInterfaceOrientations<\/key>\s*<array>)[\s\S]*?(<\/array>)/,
  '$1\n\t\t<string>UIInterfaceOrientationPortrait</string>\n\t$2',
)
fs.writeFileSync(plistFile, plist)

// 5. Xcode project: bundle ID, iPhone only, iOS 16 and later.
const pbxFile = path.join(ios, 'App.xcodeproj', 'project.pbxproj')
let pbx = fs.readFileSync(pbxFile, 'utf8')
pbx = pbx.replace(/PRODUCT_BUNDLE_IDENTIFIER = [^;]+;/g, `PRODUCT_BUNDLE_IDENTIFIER = ${app.bundleId};`)
pbx = pbx.replace(/IPHONEOS_DEPLOYMENT_TARGET = [^;]+;/g, 'IPHONEOS_DEPLOYMENT_TARGET = 16.0;')
pbx = pbx.replace(/TARGETED_DEVICE_FAMILY = [^;]+;/g, 'TARGETED_DEVICE_FAMILY = 1;')
fs.writeFileSync(pbxFile, pbx)

console.log(`${id}: ${app.name} (${app.displayName}), ${app.bundleId}, permissions: ${perms ? Object.keys(app.permissions).join(', ') : 'none'}, plugins: ${app.plugins.join(', ')}`)
