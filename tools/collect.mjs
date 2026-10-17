// Gathers everything the iPhone builds need from the app projects, on this Windows PC:
//   apps.json                 one entry per app: App Store name, home-screen name, bundle ID, colors, permissions
//   apps/<id>/www/            the built web app (exam apps: exam-prep/builds/<id>; tools: <tool>/dist)
//   apps/<id>/icon.png        1024 x 1024 App Store icon, flattened (Apple rejects icons with transparency)
//   apps/<id>/splash.png      2732 x 2732 launch screen: the app icon centered on its background color
// Build the web apps first (exam-prep: npm run build:all; each tool: npm run build).
// node tools/collect.mjs [appId ...]
import fs from 'node:fs'
import path from 'node:path'
import { createRequire } from 'node:module'
import { fileURLToPath } from 'node:url'

const here = path.dirname(fileURLToPath(import.meta.url))
const repo = path.resolve(here, '..')
const root = path.resolve(repo, '..')
const sharp = createRequire(path.join(root, '_tools', 'package.json'))('sharp')
const readJson = (f) => JSON.parse(fs.readFileSync(f, 'utf8'))

const TOOLS = {
  tidyquote: {
    permissions: {
      NSCameraUsageDescription: 'Take a photo of your logo for your quotes and invoices.',
      NSPhotoLibraryUsageDescription: 'Choose your logo for your quotes and invoices.',
    },
  },
  shiftledger: {},
  firstsip: {},
  minutebank: {},
  brrr: { permissions: { NSLocationWhenInUseUsageDescription: 'Find rental markets near you. Your location stays on your phone.' } },
}

// Submission waves from app-store/README.md ("Duplicate-app risk").
const WAVE1 = [
  'ca-real-estate-exam-prep', 'ca-real-estate-broker-exam-prep', 'private-pilot-test-prep', 'part-107-drone-test-prep',
  'ca-contractor-law-business-exam-prep', 'ca-life-health-insurance-exam-prep', 'ca-property-casualty-insurance-exam-prep',
  'tidyquote', 'shiftledger', 'firstsip', 'minutebank', 'brrr',
]
const LAST = ['wingprep', 'policyprep', 'tradeprep', 'deedprep', 'life-health-insurance-exam-prep', 'property-casualty-insurance-exam-prep']

const skipFiles = new Set(['vercel.json', 'sw.js', '.vercel', '.gitignore'])
const skipDirs = new Set(['support', 'privacy', 'terms']) // public web pages; the app has its own screens for these

function entries() {
  const list = []
  for (const id of fs.readdirSync(path.join(root, 'exam-prep', 'apps'))) {
    const app = readJson(path.join(root, 'exam-prep', 'apps', id, 'app.json'))
    list.push({ id, kind: 'exam', www: path.join(root, 'exam-prep', 'builds', id), displayName: app.shortName, background: app.theme.primary, permissions: {} })
  }
  for (const [id, extra] of Object.entries(TOOLS)) {
    const www = path.join(root, id, 'dist')
    const manifest = readJson(path.join(www, 'manifest.webmanifest'))
    list.push({ id, kind: 'tool', www, displayName: manifest.short_name || manifest.name, background: manifest.background_color, permissions: extra.permissions || {} })
  }
  return list.map((e) => {
    const listing = readJson(path.join(root, 'app-store', e.id, 'listing.json'))
    return {
      id: e.id,
      name: listing.name,
      displayName: e.displayName,
      bundleId: `com.keatingkonsultancy.${e.id.replace(/[^a-z0-9]/gi, '').toLowerCase()}`,
      sku: e.id,
      background: e.background,
      permissions: e.permissions,
      wave: WAVE1.includes(e.id) ? 1 : LAST.includes(e.id) ? 3 : 2,
      kind: e.kind,
      www: e.www,
    }
  })
}

function copyWww(from, to) {
  fs.rmSync(to, { recursive: true, force: true, maxRetries: 20, retryDelay: 250 })
  fs.cpSync(from, to, {
    recursive: true,
    filter: (src) => {
      const rel = path.relative(from, src)
      const base = path.basename(src)
      if (skipFiles.has(base) || base.startsWith('.env')) return false
      if (rel && !rel.includes(path.sep) && skipDirs.has(rel)) return false
      return true
    },
  })
}

const only = process.argv.slice(2)
const all = entries()
for (const e of all) {
  if (only.length && !only.includes(e.id)) continue
  if (!fs.existsSync(path.join(e.www, 'index.html'))) throw new Error(`${e.id}: no build at ${e.www}`)
  const dir = path.join(repo, 'apps', e.id)
  fs.mkdirSync(dir, { recursive: true })
  copyWww(e.www, path.join(dir, 'www'))

  const iconSrc = path.join(root, 'app-store', e.id, 'icon-1024.png')
  await sharp(iconSrc).resize(1024, 1024).flatten({ background: e.background }).removeAlpha().png().toFile(path.join(dir, 'icon.png'))
  const mark = await sharp(iconSrc).resize(512, 512).png().toBuffer()
  await sharp({ create: { width: 2732, height: 2732, channels: 3, background: e.background } })
    .composite([{ input: mark, gravity: 'center' }])
    .png()
    .toFile(path.join(dir, 'splash.png'))
  console.log(`${e.id}: www, icon, splash`)
}
const registry = all.map(({ www, ...rest }) => rest)
fs.writeFileSync(path.join(repo, 'apps.json'), JSON.stringify(registry, null, 2) + '\n')
console.log(`apps.json: ${registry.length} apps (wave 1: ${registry.filter((a) => a.wave === 1).length}, wave 2: ${registry.filter((a) => a.wave === 2).length}, wave 3: ${registry.filter((a) => a.wave === 3).length})`)
