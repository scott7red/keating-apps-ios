// Turns the workflow's "apps" input into the list of apps to build, as a GitHub Actions output line.
// Input: app ids separated by commas or spaces, or wave1 / wave2 / wave3 / all.
import fs from 'node:fs'

const registry = JSON.parse(fs.readFileSync(new URL('../apps.json', import.meta.url), 'utf8'))
const words = (process.env.APPS_INPUT || '').split(/[\s,]+/).filter(Boolean)
const ids = new Set()
for (const w of words) {
  const wave = /^wave([123])$/.exec(w)
  if (w === 'all') registry.forEach((a) => ids.add(a.id))
  else if (wave) registry.filter((a) => a.wave === Number(wave[1])).forEach((a) => ids.add(a.id))
  else if (registry.some((a) => a.id === w)) ids.add(w)
  else {
    console.error(`Unknown app "${w}". Known: ${registry.map((a) => a.id).join(', ')}`)
    process.exit(1)
  }
}
if (!ids.size) {
  console.error('No apps chosen.')
  process.exit(1)
}
console.log(`apps=${JSON.stringify([...ids])}`)
