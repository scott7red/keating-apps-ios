// Writes a local StoreKit configuration (.storekit) with an exam app's in-app purchases, for the
// simulator recording: StoreKit then shows its own purchase sheet and completes the purchase on the
// Mac, with no App Store account and no money. The products come from iap-products.json (a copy of
// app-store/iap-products.json, the list that was entered in App Store Connect).
//   node review-tours/storekit.mjs <appId> <out.storekit>
import fs from 'node:fs'
import crypto from 'node:crypto'

const [id, out] = process.argv.slice(2)
if (!id || !out) throw new Error('usage: node review-tours/storekit.mjs <appId> <out.storekit>')
const all = JSON.parse(fs.readFileSync(new URL('./iap-products.json', import.meta.url), 'utf8')).products
const products = all.filter((p) => p.appId === id)
if (!products.length) throw new Error(`No in-app purchases for ${id} in review-tours/iap-products.json`)

// Stable 8-hex-digit and 10-digit ids, so the same app always gets the same file.
const hex = (s, n) => crypto.createHash('sha256').update(s).digest('hex').slice(0, n).toUpperCase()
const digits = (s) => String(1e9 + (parseInt(hex(s, 8), 16) % 8e9))

const config = {
  identifier: hex(id, 8),
  nonRenewingSubscriptions: [],
  products: products.map((p) => ({
    displayPrice: p.price,
    familyShareable: false,
    internalID: digits(p.productId),
    localizations: [{ description: p.description, displayName: p.displayName, locale: 'en_US' }],
    productID: p.productId,
    referenceName: p.referenceName,
    type: 'NonConsumable',
  })),
  settings: {
    _developerTeamID: '9T738SVTZZ',
    _failTransactionsEnabled: false,
    _locale: 'en_US',
    _storefront: 'USA',
    _storeKitErrors: [],
  },
  subscriptionGroups: [],
  version: { major: 4, minor: 0 },
}
fs.writeFileSync(out, JSON.stringify(config, null, 2) + '\n')
console.log(`${out}: ${products.length} products for ${id} (${products.map((p) => p.productId.split('.').pop()).join(', ')})`)
