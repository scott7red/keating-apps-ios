// App Store Connect checks that run on the build machine with the API key, before the build:
//   - registers the app's bundle ID if it is not registered yet;
//   - stops with a plain message if the app does not exist in App Store Connect yet (Apple's API cannot create apps).
// node tools/asc.mjs <appId>
// Needs ASC_KEY_ID, ASC_ISSUER_ID and the key file at $ASC_KEY_PATH.
import fs from 'node:fs'
import path from 'node:path'
import crypto from 'node:crypto'
import { fileURLToPath } from 'node:url'

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const id = process.argv[2]
const app = JSON.parse(fs.readFileSync(path.join(repo, 'apps.json'), 'utf8')).find((a) => a.id === id)
if (!app) throw new Error(`No app "${id}" in apps.json`)
const { ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH } = process.env

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
  const json = await res.json().catch(() => ({}))
  if (!res.ok) throw new Error(`${method} ${url}: ${res.status} ${JSON.stringify(json.errors?.map((e) => e.detail) ?? json)}`)
  return json
}

const ident = encodeURIComponent(app.bundleId)
const found = await api('GET', `/v1/bundleIds?filter[identifier]=${ident}&filter[platform]=IOS`)
if (found.data.some((b) => b.attributes.identifier === app.bundleId)) {
  console.log(`Bundle ID ${app.bundleId} is registered.`)
} else {
  const name = app.name.replace(/[^A-Za-z0-9 ]/g, ' ').replace(/\s+/g, ' ').trim()
  await api('POST', '/v1/bundleIds', { data: { type: 'bundleIds', attributes: { identifier: app.bundleId, name, platform: 'IOS' } } })
  console.log(`Registered bundle ID ${app.bundleId} (${name}).`)
}

const apps = await api('GET', `/v1/apps?filter[bundleId]=${ident}`)
if (!apps.data.length) {
  console.log(`::error::"${app.name}" does not exist in App Store Connect yet. Create it (Apps > + > New App) with bundle ID ${app.bundleId} and SKU ${app.sku}, then run this build again.`)
  process.exit(1)
}
console.log(`App Store Connect app: ${apps.data[0].attributes.name} (Apple ID ${apps.data[0].id}).`)
