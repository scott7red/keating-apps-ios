// Adds a finished review video to an app's App Store Connect version, as the attachment App Review sees
// (App Review Information > Attachment). Without --upload it only looks and reports what it would do.
//   node review-tours/attach.mjs <appId> <video.mp4> [--upload] [--replace]
// --upload   reserve the attachment, upload its parts, then commit it with the file's MD5 checksum.
// --replace  with --upload: first delete an earlier attachment with the same file name.
// It touches nothing else: it never creates review details, never edits any other field and never
// submits anything for review. It stops if the version has no App Review Information yet.
// Needs ASC_KEY_ID, ASC_ISSUER_ID and the key file at $ASC_KEY_PATH (as tools/asc.mjs).
import fs from 'node:fs'
import path from 'node:path'
import crypto from 'node:crypto'
import { fileURLToPath } from 'node:url'

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const args = process.argv.slice(2)
const [id, video] = args.filter((a) => !a.startsWith('--'))
const upload = args.includes('--upload')
const replace = args.includes('--replace')
if (!id || !video) throw new Error('usage: node review-tours/attach.mjs <appId> <video.mp4> [--upload] [--replace]')
const app = JSON.parse(fs.readFileSync(path.join(repo, 'apps.json'), 'utf8')).find((a) => a.id === id)
if (!app) throw new Error(`No app "${id}" in apps.json`)
const { ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH } = process.env
if (!ASC_KEY_ID || !ASC_ISSUER_ID || !ASC_KEY_PATH) throw new Error('ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH are needed')

// The same JWT as tools/asc.mjs.
const b64 = (v) => Buffer.from(typeof v === 'string' ? v : JSON.stringify(v)).toString('base64url')
function token() {
  const now = Math.floor(Date.now() / 1000)
  const head = b64({ alg: 'ES256', kid: ASC_KEY_ID, typ: 'JWT' })
  const body = b64({ iss: ASC_ISSUER_ID, iat: now, exp: now + 900, aud: 'appstoreconnect-v1' })
  const sig = crypto.sign('sha256', Buffer.from(`${head}.${body}`), { key: fs.readFileSync(ASC_KEY_PATH), dsaEncoding: 'ieee-p1363' })
  return `${head}.${body}.${sig.toString('base64url')}`
}
async function api(method, url, body) {
  const res = await fetch(`https://api.appstoreconnect.apple.com${url}`, {
    method,
    headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  })
  if (res.status === 204) return {}
  const json = await res.json().catch(() => ({}))
  if (!res.ok) throw new Error(`${method} ${url}: ${res.status} ${JSON.stringify(json.errors?.map((e) => e.detail) ?? json)}`)
  return json
}

// The file name Apple is told about in the review notes (section 1): the App Store name, colon as a dash.
const fileName = `${app.name.replace(/:/g, ' -')} - App Review.mp4`
const bytes = fs.readFileSync(video)
const md5 = crypto.createHash('md5').update(bytes).digest('hex')
console.log(`${id}: ${fileName}, ${(bytes.length / 1e6).toFixed(1)} MB, MD5 ${md5}${upload ? '' : ' (dry run: nothing is changed)'}`)

const apps = await api('GET', `/v1/apps?filter[bundleId]=${encodeURIComponent(app.bundleId)}&fields[apps]=name,bundleId`)
const record = apps.data.find((a) => a.attributes.bundleId === app.bundleId)
if (!record) throw new Error(`No App Store Connect app with bundle ID ${app.bundleId}`)
console.log(`App Store Connect app: ${record.attributes.name} (${record.id})`)

// Only a version that can still be edited takes an attachment.
const EDITABLE = new Set(['PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED', 'REJECTED', 'METADATA_REJECTED', 'INVALID_BINARY'])
const versions = await api('GET', `/v1/apps/${record.id}/appStoreVersions?filter[platform]=IOS&limit=10`)
for (const v of versions.data) console.log(`  version ${v.attributes.versionString}: ${v.attributes.appVersionState ?? v.attributes.appStoreState}`)
const version = versions.data.find((v) => EDITABLE.has(v.attributes.appVersionState ?? v.attributes.appStoreState))
if (!version) {
  console.log('No editable version (Prepare for Submission or Rejected): nothing to attach to.')
  process.exit(upload ? 1 : 0)
}
console.log(`Editable version: ${version.attributes.versionString} (${version.id})`)

const detail = await api('GET', `/v1/appStoreVersions/${version.id}/appStoreReviewDetail`).catch((e) => {
  console.log(`  App Review Information: ${e.message}`)
  return { data: null }
})
if (!detail.data) {
  console.log('This version has no App Review Information yet. Fill it in on the version page first (contact details, notes); this script never creates it.')
  process.exit(upload ? 1 : 0)
}
console.log(`App Review Information: ${detail.data.id}`)

const existing = await api('GET', `/v1/appStoreReviewDetails/${detail.data.id}/appStoreReviewAttachments?limit=50`)
for (const a of existing.data) {
  console.log(`  attachment: ${a.attributes.fileName} (${(a.attributes.fileSize / 1e6).toFixed(1)} MB, ${a.attributes.assetDeliveryState?.state ?? '?'})`)
}
const same = existing.data.filter((a) => a.attributes.fileName === fileName)

const reserve = {
  data: {
    type: 'appStoreReviewAttachments',
    attributes: { fileName, fileSize: bytes.length },
    relationships: { appStoreReviewDetail: { data: { type: 'appStoreReviewDetails', id: detail.data.id } } },
  },
}
if (!upload) {
  if (same.length) console.log(`An attachment named "${fileName}" is already there; an upload would ${replace ? 'delete it first' : 'stop (use --replace to swap it)'}.`)
  console.log(`Would POST /v1/appStoreReviewAttachments ${JSON.stringify(reserve)}`)
  console.log(`then PUT the file in the parts Apple returns, then PATCH it with uploaded: true and sourceFileChecksum ${md5}.`)
  process.exit(0)
}

if (same.length) {
  if (!replace) {
    console.log(`An attachment named "${fileName}" is already there. Stopping; run with --replace to swap it.`)
    process.exit(1)
  }
  for (const a of same) {
    await api('DELETE', `/v1/appStoreReviewAttachments/${a.id}`)
    console.log(`Deleted the earlier ${fileName} (${a.id}).`)
  }
}

const reserved = await api('POST', '/v1/appStoreReviewAttachments', reserve)
const attachment = reserved.data
const ops = attachment.attributes.uploadOperations || []
console.log(`Reserved ${attachment.id}: ${ops.length} part(s) to upload.`)
for (const [i, op] of ops.entries()) {
  const headers = Object.fromEntries((op.requestHeaders || []).map((h) => [h.name, h.value]))
  const res = await fetch(op.url, { method: op.method, headers, body: bytes.subarray(op.offset, op.offset + op.length) })
  if (!res.ok) throw new Error(`Part ${i + 1}/${ops.length}: ${res.status} ${await res.text()}`)
}
await api('PATCH', `/v1/appStoreReviewAttachments/${attachment.id}`, {
  data: { type: 'appStoreReviewAttachments', id: attachment.id, attributes: { uploaded: true, sourceFileChecksum: md5 } },
})
console.log('Committed. Waiting for App Store Connect to process it...')
for (let i = 0; i < 40; i++) {
  await new Promise((r) => setTimeout(r, 15000))
  const state = (await api('GET', `/v1/appStoreReviewAttachments/${attachment.id}`)).data.attributes.assetDeliveryState
  console.log(`  ${state?.state}${state?.errors?.length ? ` ${JSON.stringify(state.errors)}` : ''}`)
  if (state?.state === 'COMPLETE') process.exit(0)
  if (state?.state === 'FAILED') process.exit(1)
}
console.log('Still processing; check the version page later.')
