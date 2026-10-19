// Small helpers for .github/workflows/review-videos.yml.
//   node review-tours/ci.mjs tour <appId>          GitHub output lines: the tour's class and settings
//   node review-tours/ci.mjs runtime <wanted>      reads `xcrun simctl list runtimes -j` on stdin, prints a runtime id
//   node review-tours/ci.mjs testlab-device        reads `gcloud firebase test ios models list --format=json` on stdin,
//                                                  prints "model=...,version=..." (newest iPhone on iOS 16 or 17:
//                                                  Test Lab records no video on iOS 18 and later)
//   node review-tours/ci.mjs summary <runDir> <runNumber> <runUrl>   writes <runDir>/README.md from each app's info.json
import fs from 'node:fs'
import path from 'node:path'

const [cmd, ...rest] = process.argv.slice(2)
const stdin = () => fs.readFileSync(0, 'utf8')
const here = (f) => new URL(f, import.meta.url)

if (cmd === 'tour') {
  const id = rest[0]
  const tour = JSON.parse(fs.readFileSync(here('./tours.json'), 'utf8')).tours[id]
  const app = JSON.parse(fs.readFileSync(here('../apps.json'), 'utf8')).find((a) => a.id === id)
  if (!tour || !app) throw new Error(`No tour or app for ${id}`)
  const out = {
    class: tour.class,
    storekit: tour.storekit ? 'true' : 'false',
    location: tour.location || '',
    clock: tour.clock === false ? 'false' : 'true',
    icon: app.displayName,
    bundle: app.bundleId,
    video: `${app.name.replace(/:/g, ' -')} - App Review`,
  }
  for (const [k, v] of Object.entries(out)) console.log(`${k}=${v}`)
} else if (cmd === 'runtime') {
  const wanted = rest[0] || '26.2'
  const runtimes = JSON.parse(stdin()).runtimes.filter((r) => r.platform === 'iOS' && r.isAvailable)
  const num = (v) => v.split('.').map(Number).reduce((a, n, i) => a + n / 100 ** i, 0)
  runtimes.sort((a, b) => num(b.version) - num(a.version))
  const pick = runtimes.find((r) => r.version === wanted) || runtimes.find((r) => r.version.startsWith(wanted)) || runtimes[0]
  if (!pick) throw new Error('No iOS simulator runtime')
  console.error(`iOS runtimes: ${runtimes.map((r) => r.version).join(', ')}; using ${pick.version}`)
  console.log(pick.identifier)
} else if (cmd === 'testlab-device') {
  const models = JSON.parse(stdin())
  const num = (v) => v.split('.').map(Number).reduce((a, n, i) => a + n / 100 ** i, 0)
  const options = []
  for (const m of models) {
    if (!/^iphone/i.test(m.id) || (m.tags || []).some((t) => /deprecated/i.test(t))) continue
    for (const v of m.supportedVersionIds || []) {
      const n = num(v)
      if (n >= 16 && n < 18) options.push({ model: m.id, name: m.name, version: v, n })
    }
  }
  options.sort((a, b) => b.n - a.n || String(b.model).localeCompare(String(a.model), 'en', { numeric: true }))
  console.error(`Test Lab iPhones on iOS 16-17: ${options.map((o) => `${o.model} ${o.version}`).join(', ') || 'none'}`)
  if (!options.length) throw new Error('No Test Lab iPhone on iOS 16 or 17 (videos are not recorded on iOS 18 and later)')
  console.log(`model=${options[0].model},version=${options[0].version},locale=en_US,orientation=portrait`)
} else if (cmd === 'timezone') {
  // A time zone where it is now late morning, so the recording shows a daytime clock wherever the run
  // happens (MinuteBank only starts screen time from 7 AM to 8 PM). US zones first.
  const us = ['America/New_York', 'America/Chicago', 'America/Denver', 'America/Los_Angeles', 'America/Anchorage', 'Pacific/Honolulu']
  const world = ['Europe/London', 'Europe/Paris', 'Europe/Athens', 'Asia/Dubai', 'Asia/Kolkata', 'Asia/Bangkok', 'Asia/Singapore', 'Asia/Tokyo', 'Australia/Sydney', 'Pacific/Auckland', 'America/Sao_Paulo', 'Atlantic/Azores']
  const hour = (tz) => {
    const p = new Intl.DateTimeFormat('en-US', { timeZone: tz, hour: 'numeric', minute: 'numeric', hourCycle: 'h23' }).formatToParts(new Date())
    return Number(p.find((x) => x.type === 'hour').value) + Number(p.find((x) => x.type === 'minute').value) / 60
  }
  const score = (tz) => Math.abs(hour(tz) - 11)
  const pick = [...us].sort((a, b) => score(a) - score(b))[0]
  const best = score(pick) <= 3 ? pick : [...us, ...world].sort((a, b) => score(a) - score(b))[0]
  console.error(`Local time in ${best}: ${hour(best).toFixed(2)}`)
  console.log(best)
} else if (cmd === 'summary') {
  const [runDir, runNumber, runUrl] = rest
  const lines = [`# Review videos, run ${runNumber}`, '', `[The run on GitHub](${runUrl}) (the MP4s are its artifacts).`, '']
  lines.push('| App | Mode | Result | Video | Steps | Notes |', '|---|---|---|---|---|---|')
  for (const app of fs.readdirSync(runDir).filter((d) => fs.statSync(path.join(runDir, d)).isDirectory()).sort()) {
    for (const mode of ['simulator', 'testlab']) {
      const d = path.join(runDir, app, mode)
      if (!fs.existsSync(d)) continue
      const read = (f) => (fs.existsSync(path.join(d, f)) ? fs.readFileSync(path.join(d, f), 'utf8').trim() : '')
      const info = read('info.json') ? JSON.parse(read('info.json')) : null
      const status = read('status.txt') || '?'
      const notes = [...(info?.notes || []), ...(info?.spedUp || []).map((w) => w.caption.replace(/\n/g, ': '))].join('; ')
      lines.push(`| ${app} | ${mode} | ${status} | ${info ? `${info.finalMinutes} (${info.megabytes} MB)` : '-'} | ${info ? (info.stepsRun || info.steps).length : '-'} | ${notes.replace(/\|/g, '/')} |`)
    }
  }
  fs.writeFileSync(path.join(runDir, 'README.md'), lines.join('\n') + '\n')
  console.log(lines.join('\n'))
} else {
  throw new Error(`Unknown command ${cmd}`)
}
