/* scripts/backfill-slugs.js
   - Finds all branches by scanning the `menuItems` collection group
   - Ensures parent docs merchants/{m} and branches/{b} exist
   - Creates/updates pretty slugs in /slugs/{slug}
   Usage: node scripts/backfill-slugs.js
*/

const path = require('path');
const admin = require('firebase-admin');

const WRITE_SLUG_TO_BRANCH_DOC = true;

const serviceAccount = require(path.join(__dirname, 'serviceAccount.json'));

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});
const db = admin.firestore();
const ts = admin.firestore.FieldValue.serverTimestamp();

function slugify(s) {
  return String(s || '')
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-zA-Z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .replace(/-+/g, '-')
    .toLowerCase();
}

async function uniqueSlug(base) {
  let s = base, n = 0;
  while (true) {
    const snap = await db.doc(`slugs/${s}`).get();
    if (!snap.exists) return s;
    n++;
    s = `${base}-${n}`;
  }
}

async function ensureDoc(path, data = {}) {
  const ref = db.doc(path);
  const snap = await ref.get();
  if (!snap.exists) {
    await ref.set({ createdAt: ts, ...data }, { merge: true });
    return true;
  } else {
    await ref.set({ updatedAt: ts, ...data }, { merge: true });
    return false;
  }
}

async function main() {
  const cg = await db.collectionGroup('menuItems').get();
  if (cg.empty) {
    console.log('No menuItems found. Nothing to do.');
    return;
  }

  // Collect unique (merchantId, branchId) pairs from paths:
  // merchants/{m}/branches/{b}/menuItems/{id}
  const pairs = new Map(); // key: m__b -> { m, b }
  for (const d of cg.docs) {
    const segs = d.ref.path.split('/'); // ["merchants", m, "branches", b, "menuItems", id]
    const iM = segs.indexOf('merchants');
    const iB = segs.indexOf('branches');
    const iMI = segs.indexOf('menuItems');
    if (iM >= 0 && iB >= 0 && iMI >= 0 && iM + 1 < segs.length && iB + 1 < segs.length) {
      const m = segs[iM + 1];
      const b = segs[iB + 1];
      pairs.set(`${m}__${b}`, { m, b });
    }
  }

  if (pairs.size === 0) {
    console.log('Found menuItems but could not derive any (merchant, branch) pairs.');
    return;
  }

  let createdSlugs = 0;
  let updatedSlugs = 0;
  let ensuredMerchants = 0;
  let ensuredBranches = 0;

  for (const { m, b } of pairs.values()) {
    // Ensure parent docs exist
    const didCreateMerchant = await ensureDoc(`merchants/${m}`);
    if (didCreateMerchant) ensuredMerchants++;

    const didCreateBranch = await ensureDoc(`merchants/${m}/branches/${b}`);
    if (didCreateBranch) ensuredBranches++;

    // Try a friendly title from branding
    let title;
    try {
      const branding = await db.doc(`merchants/${m}/branches/${b}/config/branding`).get();
      title = branding.exists ? branding.get('title') : undefined;
    } catch (_) {}

    // Prefer any existing slug on the branch doc
    const branchSnap = await db.doc(`merchants/${m}/branches/${b}`).get();
    let branchSlug = branchSnap.exists ? branchSnap.get('slug') : null;
    if (branchSlug && typeof branchSlug === 'string') {
      branchSlug = slugify(branchSlug);
    }

    const desiredBase = slugify(title || `${m}-${b}`) || `${m}-${b}`.toLowerCase();
    let finalSlug = branchSlug || desiredBase;

    // Ensure slug is unique or belongs to this branch
    const existing = await db.doc(`slugs/${finalSlug}`).get();
    if (existing.exists) {
      const data = existing.data() || {};
      if (data.merchantId === m && data.branchId === b) {
        await existing.ref.set(
          { title: title || data.title || null, updatedAt: ts },
          { merge: true }
        );
        updatedSlugs++;
        console.log(`= kept /slugs/${finalSlug} -> ${m}/${b}`);
      } else {
        finalSlug = await uniqueSlug(desiredBase);
        await db.doc(`slugs/${finalSlug}`).set({
          merchantId: m,
          branchId: b,
          title: title || null,
          createdAt: ts,
          updatedAt: ts,
        });
        createdSlugs++;
        console.log(`+ created unique /slugs/${finalSlug} -> ${m}/${b}`);
      }
    } else {
      await db.doc(`slugs/${finalSlug}`).set({
        merchantId: m,
        branchId: b,
        title: title || null,
        createdAt: ts,
        updatedAt: ts,
      });
      createdSlugs++;
      console.log(`+ created /slugs/${finalSlug} -> ${m}/${b}`);
    }

    // (optional) write back to branch doc
    if (WRITE_SLUG_TO_BRANCH_DOC) {
      await db.doc(`merchants/${m}/branches/${b}`).set(
        { slug: finalSlug, updatedAt: ts },
        { merge: true }
      );
    }
  }

  console.log('-----------------------------------------');
  console.log(`Ensured merchants: ${ensuredMerchants}`);
  console.log(`Ensured branches:  ${ensuredBranches}`);
  console.log(`Slugs created:     ${createdSlugs}`);
  console.log(`Slugs updated:     ${updatedSlugs}`);
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error(e);
    process.exit(1);
  });
