// Read-only look at the team's signing assets, to choose how to sign builds for Firebase Test Lab:
// registered devices, certificates, and the bundle IDs / profiles of the app and its UI-test runner.
// It changes nothing.
//   node review-tours/signing-check.mjs <appId>
// Needs ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH (as tools/asc.mjs).
import fs from 'node:fs'
import crypto from 'node:crypto'

const id = process.argv[2]
const app = JSON.parse(fs.readFileSync(new URL('../apps.json', import.meta.url), 'utf8')).find((a) => a.id === id)
const { ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH } = process.env
const b64 = (v) => Buffer.from(typeof v === 'string' ? v : JSON.stringify(v)).toString('base64url')
function token() {
  const now = Math.floor(Date.now() / 1000)
  const head = b64({ alg: 'ES256', kid: ASC_KEY_ID, typ: 'JWT' })
  const body = b64({ iss: ASC_ISSUER_ID, iat: now, exp: now + 900, aud: 'appstoreconnect-v1' })
  const sig = crypto.sign('sha256', Buffer.from(`${head}.${body}`), { key: fs.readFileSync(ASC_KEY_PATH), dsaEncoding: 'ieee-p1363' })
  return `${head}.${body}.${sig.toString('base64url')}`
}
async function get(url) {
  const res = await fetch(`https://api.appstoreconnect.apple.com${url}`, { headers: { Authorization: `Bearer ${token()}` } })
  const json = await res.json().catch(() => ({}))
  if (!res.ok) return { error: `${res.status} ${JSON.stringify(json.errors?.map((e) => e.detail) ?? json)}` }
  return json
}

const devices = await get('/v1/devices?limit=200&fields[devices]=name,platform,status,deviceClass')
console.log(`Registered devices: ${devices.error ?? devices.data.length} ${devices.data ? devices.data.map((d) => `${d.attributes.deviceClass}/${d.attributes.status}`).join(', ') : ''}`)
const certs = await get('/v1/certificates?limit=50&fields[certificates]=certificateType,displayName,expirationDate')
console.log(`Certificates: ${certs.error ?? certs.data.map((c) => `${c.attributes.certificateType} (${c.attributes.displayName}, until ${c.attributes.expirationDate?.slice(0, 10)})`).join('; ')}`)
for (const ident of [app.bundleId, `${app.bundleId}.ReviewTour.xctrunner`, `${app.bundleId}.ReviewTour`]) {
  const ids = await get(`/v1/bundleIds?filter[identifier]=${encodeURIComponent(ident)}&include=profiles&limit=5`)
  const match = ids.data?.find((b) => b.attributes.identifier === ident)
  const profiles = (ids.included || []).filter((p) => p.type === 'profiles').map((p) => `${p.attributes.profileType} ${p.attributes.profileState}`)
  console.log(`${ident}: ${ids.error ?? (match ? `registered, profiles: ${profiles.join(', ') || 'none'}` : 'not registered')}`)
}
