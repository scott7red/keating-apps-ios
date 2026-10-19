// Decides what the "Review videos" workflow records, as GitHub Actions output lines.
// A manual run (workflow_dispatch) uses its inputs; a push to the review-videos branch uses review-tours/run.json.
//   apps:  ids separated by commas or spaces, or all / tools / exams
//   mode:  simulator | testlab | both
import fs from 'node:fs'

const here = (f) => new URL(f, import.meta.url)
const registry = JSON.parse(fs.readFileSync(here('../apps.json'), 'utf8'))
const tours = JSON.parse(fs.readFileSync(here('./tours.json'), 'utf8')).tours
const run = JSON.parse(fs.readFileSync(here('./run.json'), 'utf8'))

const manual = process.env.EVENT === 'workflow_dispatch'
const appsText = manual ? process.env.IN_APPS : Array.isArray(run.apps) ? run.apps.join(',') : String(run.apps || '')
const mode = (manual ? process.env.IN_MODE : run.mode) || 'simulator'
const attach = manual ? process.env.IN_ATTACH === 'true' : run.attach === true
const debug = manual ? process.env.IN_DEBUG === 'true' : run.debug === true

const ids = new Set()
for (const w of String(appsText || '').split(/[\s,]+/).filter(Boolean)) {
  const pick = (f) => registry.filter(f).forEach((a) => ids.add(a.id))
  if (w === 'all') pick(() => true)
  else if (w === 'tools') pick((a) => a.kind === 'tool')
  else if (w === 'exams') pick((a) => a.kind === 'exam')
  else if (registry.some((a) => a.id === w)) ids.add(w)
  else {
    console.error(`Unknown app "${w}". Known: ${registry.map((a) => a.id).join(', ')}`)
    process.exit(1)
  }
}
for (const id of ids) {
  if (!tours[id]) {
    console.error(`No tour for "${id}" in review-tours/tours.json`)
    process.exit(1)
  }
}
if (!ids.size) {
  console.error('No apps chosen.')
  process.exit(1)
}
if (!['simulator', 'testlab', 'both'].includes(mode)) {
  console.error(`Unknown mode "${mode}" (simulator, testlab or both)`)
  process.exit(1)
}

console.log(`apps=${JSON.stringify([...ids])}`)
console.log(`simulator=${mode !== 'testlab'}`)
console.log(`testlab=${mode !== 'simulator'}`)
console.log(`attach=${attach}`)
console.log(`debug=${debug}`)
console.error(`Recording ${[...ids].join(', ')} (${mode}${attach ? ', attach to App Store Connect' : ''}${debug ? ', debug trees' : ''})`)
