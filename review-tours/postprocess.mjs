// Turns the raw screen recording into the App Review video, and makes small pictures to check it by.
//   node review-tours/postprocess.mjs <dir>
// <dir> holds raw.mp4 (the simulator's recording), rec-start.txt (when the recording started, Unix
// seconds) and marks.tsv (written by the tour; if it is missing, the TOURMARK lines of test.log are used).
// It writes:
//   final.mp4   trimmed to start on the Home Screen just before the app's icon is tapped and to end after
//               the last step; a grey circle shows each tap; waiting parts (marks "wait"/"waitend") are
//               sped up, with a caption on screen saying how long the wait was and that it is sped up.
//   sheet.jpg   a frame every 5 seconds of final.mp4, tiled.
//   steps.jpg   the screen at the end of each step, numbered as in info.json.
//   last.jpg    the last frame (where a failed tour stopped).
//   info.json   durations, steps and their times in final.mp4.
// Needs ffmpeg and ffprobe.
import fs from 'node:fs'
import path from 'node:path'
import { execFileSync } from 'node:child_process'

const dir = path.resolve(process.argv[2] || '.')
const at = (f) => path.join(dir, f)
// ffmpeg runs inside <dir> and is given plain file names, so no path needs escaping in a filter.
const run = (cmd, args) => execFileSync(cmd, args, { cwd: dir, stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 1 << 26 }).toString()
const ff = (args) => run('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', ...args])
const probe = (file) => {
  const out = JSON.parse(run('ffprobe', ['-v', 'error', '-print_format', 'json', '-show_format', '-show_streams', file]))
  const v = out.streams.find((s) => s.codec_type === 'video')
  return { duration: Number(out.format.duration), width: v.width, height: v.height }
}
const FONT = ['/System/Library/Fonts/Helvetica.ttc', '/System/Library/Fonts/Supplemental/Arial.ttf', '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'].find((f) => fs.existsSync(f))
const fontArg = FONT ? `fontfile='${FONT}':` : ''

// ---- marks ----
let text = fs.existsSync(at('marks.tsv')) ? fs.readFileSync(at('marks.tsv'), 'utf8') : ''
if (!text.trim() && fs.existsSync(at('test.log'))) {
  text = fs.readFileSync(at('test.log'), 'utf8').split('\n').filter((l) => l.startsWith('TOURMARK\t')).map((l) => l.slice(9)).join('\n')
}
const marks = text.split('\n').filter(Boolean).map((l) => {
  const [t, kind, ...rest] = l.split('\t')
  return { t: Number(t), kind, detail: rest.join('\t').trim() }
}).filter((m) => Number.isFinite(m.t))

// Without rec-start.txt (a Test Lab video, whose start time is not known) the marks cannot be placed on
// the video: it is kept whole, with no circles, no speeding up and no step pictures.
const aligned = fs.existsSync(at('rec-start.txt'))
const recStart = aligned ? Number(fs.readFileSync(at('rec-start.txt'), 'utf8').trim()) : 0
const raw = probe('raw.mp4')
const first = (kind) => marks.find((m) => m.kind === kind)
const last = (kind) => [...marks].reverse().find((m) => m.kind === kind)
const rel = (m) => m.t - recStart

const startMark = first('start')
const endMark = last('end') || marks[marks.length - 1]
const t0 = aligned ? Math.max(0, startMark ? rel(startMark) - 0.8 : 0) : 0
const t1 = aligned ? Math.min(raw.duration, endMark ? rel(endMark) + 1.2 : raw.duration) : raw.duration
const T = (m) => rel(m) - t0 // time in the trimmed video

// ---- sped-up waits ----
const waits = []
for (let i = 0; aligned && i < marks.length; i++) {
  if (marks[i].kind !== 'wait') continue
  const end = marks.slice(i + 1).find((m) => m.kind === 'waitend')
  if (!end) continue
  const a = Math.max(0, T(marks[i]))
  const b = Math.min(t1 - t0, T(end))
  const real = b - a
  if (real < 20) continue
  const target = 10
  const factor = Math.max(2, Math.round(real / target))
  const minutes = real / 60
  const howLong = minutes >= 1.5 ? `${Math.round(minutes)} minutes` : `${Math.round(real)} seconds`
  const caption = `${marks[i].detail || 'Waiting'}\n${howLong} sped up ${factor}x`
  waits.push({ a, b, factor, caption, real })
}
// Final time of a moment in the trimmed video.
const finalTime = (t) => {
  let out = t
  for (const w of waits) {
    if (t <= w.a) continue
    const inside = Math.min(t, w.b) - w.a
    out -= inside - inside / w.factor
  }
  return out
}

// ---- tap circles ----
const screen = first('screen')
const [pw] = screen ? screen.detail.split(' ').map(Number) : [0]
const scale = pw ? raw.width / pw : raw.width / 402
const R = Math.round(22 * scale)
const taps = marks.filter((m) => aligned && m.kind === 'tap').map((m) => {
  const [x, y] = m.detail.split(' ').map(Number)
  return { t: T(m), x: Math.round(x * scale), y: Math.round(y * scale) }
}).filter((p) => p.t > 0 && p.t < t1 - t0 && Number.isFinite(p.x))

const D = 2 * R + 8
ff(['-f', 'lavfi', '-i', `color=c=black@0.0:s=${D}x${D},format=rgba`, '-vf',
  `geq=r='if(gte(hypot(X-${D / 2},Y-${D / 2}),${R - 5}),255,70)':g='if(gte(hypot(X-${D / 2},Y-${D / 2}),${R - 5}),255,70)':b='if(gte(hypot(X-${D / 2},Y-${D / 2}),${R - 5}),255,70)':a='if(lte(hypot(X-${D / 2},Y-${D / 2}),${R}),if(gte(hypot(X-${D / 2},Y-${D / 2}),${R - 5}),235,120),0)'`,
  '-frames:v', '1', 'circle.png'])

// ---- the filter graph ----
const lines = []
lines.push(`[0:v]trim=start=${t0.toFixed(3)}:end=${t1.toFixed(3)},setpts=PTS-STARTPTS,fps=30,format=yuv420p[v0]`)
let cur = 'v0'
if (taps.length) {
  lines.push(`[1:v]split=${taps.length}${taps.map((_, i) => `[c${i}]`).join('')}`)
  taps.forEach((p, i) => {
    const next = `t${i}`
    lines.push(`[${cur}][c${i}]overlay=x=${p.x - D / 2}:y=${p.y - D / 2}:enable='between(t,${(p.t + 0.05).toFixed(2)},${(p.t + 0.6).toFixed(2)})':shortest=1[${next}]`)
    cur = next
  })
}
if (waits.length) {
  const cuts = [0]
  for (const w of waits) cuts.push(w.a, w.b)
  cuts.push(t1 - t0)
  const pieces = []
  for (let i = 0; i + 1 < cuts.length; i++) if (cuts[i + 1] - cuts[i] > 0.05) pieces.push({ a: cuts[i], b: cuts[i + 1], wait: waits.find((w) => w.a === cuts[i]) })
  lines.push(`[${cur}]split=${pieces.length}${pieces.map((_, i) => `[s${i}]`).join('')}`)
  pieces.forEach((p, i) => {
    let f = `[s${i}]trim=start=${p.a.toFixed(3)}:end=${p.b.toFixed(3)},setpts=PTS-STARTPTS`
    if (p.wait) {
      const capFile = `caption${i}.txt`
      fs.writeFileSync(at(capFile), p.wait.caption)
      f += `,setpts=PTS/${p.wait.factor},fps=30,drawtext=${fontArg}textfile='${capFile}':fontsize=${Math.round(raw.width / 20)}:fontcolor=white:line_spacing=18:box=1:boxcolor=black@0.7:boxborderw=36:x=(w-text_w)/2:y=h*0.58`
    }
    lines.push(`${f}[p${i}]`)
  })
  lines.push(`${pieces.map((_, i) => `[p${i}]`).join('')}concat=n=${pieces.length}:v=1:a=0[out]`)
} else {
  lines.push(`[${cur}]null[out]`)
}
fs.writeFileSync(at('filter.txt'), lines.join(';\n'))
ff(['-i', 'raw.mp4', '-loop', '1', '-i', 'circle.png', '-/filter_complex', 'filter.txt', '-map', '[out]',
  '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '23', '-pix_fmt', 'yuv420p', '-r', '30', '-movflags', '+faststart', 'final.mp4'])
const fin = probe('final.mp4')

// ---- pictures to check it by ----
const cols = 8
const rows = Math.max(1, Math.ceil(fin.duration / 5 / cols))
ff(['-i', 'final.mp4', '-vf', `fps=1/5,scale=180:-2,tile=${cols}x${rows}:padding=6:margin=6:color=white`, '-frames:v', '1', '-q:v', '5', 'sheet.jpg'])

const stepMarks = aligned ? marks.filter((m) => m.kind === 'step') : []
const steps = stepMarks.map((m, i) => {
  const next = marks.find((n) => n.t > m.t && (n.kind === 'step' || n.kind === 'end' || n.kind === 'fail'))
  const begin = finalTime(Math.max(0, T(m)))
  const end = finalTime(Math.max(0, next ? T(next) : t1 - t0))
  return { n: i + 1, title: m.detail, start: Number(begin.toFixed(1)), end: Number(end.toFixed(1)) }
})
const frames = path.join(dir, 'frames')
fs.mkdirSync(frames, { recursive: true })
steps.forEach((s) => {
  const t = Math.max(0, Math.min(fin.duration - 0.1, s.end - 0.3))
  const label = `frames/label${s.n}.txt`
  fs.writeFileSync(at(label), `${s.n}. ${s.title}`.slice(0, 40))
  ff(['-ss', t.toFixed(2), '-i', 'final.mp4', '-frames:v', '1', '-vf',
    `scale=260:-2,drawtext=${fontArg}textfile='${label}':fontsize=13:fontcolor=white:box=1:boxcolor=black@0.75:boxborderw=4:x=4:y=h-th-8`,
    '-q:v', '4', `frames/s${String(s.n).padStart(3, '0')}.jpg`])
})
if (steps.length) {
  const scols = Math.min(6, steps.length)
  ff(['-framerate', '1', '-start_number', '1', '-i', 'frames/s%03d.jpg', '-vf',
    `tile=${scols}x${Math.ceil(steps.length / scols)}:padding=6:margin=6:color=white`, '-frames:v', '1', '-q:v', '4', 'steps.jpg'])
}
ff(['-sseof', '-0.5', '-i', 'final.mp4', '-frames:v', '1', '-vf', 'scale=420:-2', '-q:v', '3', 'last.jpg'])

const info = {
  rawSeconds: Number(raw.duration.toFixed(1)),
  finalSeconds: Number(fin.duration.toFixed(1)),
  finalMinutes: `${Math.floor(fin.duration / 60)}:${String(Math.round(fin.duration % 60)).padStart(2, '0')}`,
  size: `${fin.width}x${fin.height}`,
  megabytes: Number((fs.statSync(at('final.mp4')).size / 1e6).toFixed(1)),
  trimmed: { from: Number(t0.toFixed(1)), to: Number(t1.toFixed(1)) },
  taps: taps.length,
  spedUp: waits.map((w) => ({ at: Number(finalTime(w.a).toFixed(1)), realSeconds: Math.round(w.real), factor: w.factor, caption: w.caption })),
  aligned,
  failed: marks.some((m) => m.kind === 'fail'),
  stepsRun: marks.filter((m) => m.kind === 'step').map((m) => m.detail),
  notes: marks.filter((m) => m.kind === 'note' || m.kind === 'alert').map((m) => `${m.kind}: ${m.detail}`),
  steps,
}
fs.writeFileSync(at('info.json'), JSON.stringify(info, null, 2) + '\n')
console.log(JSON.stringify({ ...info, steps: steps.length }, null, 2))
