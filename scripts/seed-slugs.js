/* scripts/seed-slugs.js
   Node script to create /slugs/{slug} docs for each merchants/{m}/branches/{b}

   Usage:
     node scripts/seed-slugs.js
*/

const path = require('path');
const admin = require('firebase-admin');

// ---- CONFIG ----
const WRITE_SLUG_TO_BRANCH_DOC = true; // also set branches/{b}.slug
// ----------------

// Service account JSON already in your repo at scripts/serviceAccount.json
const serviceAccount = require(path.join(__dirname, 'serviceAccount.json'));

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});
const db = admin.firestore();
const ts = admin.firestore.FieldValue.serverTimestamp();

function slugify(s) {
  return String(s || '')
    .normalize('NFKD')           // split accents
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-zA-Z0-9]+/g, '-') // non-word -> dash
    .replace(/^-+|-+$/g, '')
    .replace(/-+/g, '-')
    .toLowerCase();
}

async function uniqueSlug(base) {
  let s = base;
  let n = 0;
  while (true) {
    const snap = await db.doc(`slugs/${s}`).get();
    if (!snap.exists) return s;
    n++;
    s = `${base}-${n}`;
  }
}

async function main() {
  const merchants = await db.collection('merchants').get();
  if (merchants.empty) {
    console.log('No merchants found.');
    return;
  }

  let created = 0;
  let updated = 0;
  let skipped = 0;

  for (const mDoc of merchants.docs) {
    const m = mDoc.id;
    const branches = await db.collection(`merchants/${m}/branches`).get();
    if (branches.empty) {
      console.log(`merchant ${m}: no branches`);
      continue;
    }

    for (const bDoc of branches.docs) {
      const b = bDoc.id;

      // Try to read branding title to form a nice slug
      let title = undefined;
      try {
        const brandingSnap = await db.doc(`merchants/${m}/branches/${b}/config/branding`).get();
        title = brandingSnap.exists ? brandingSnap.get('title') : undefined;
      } catch (_) {}

      const base = slugify(title || `${m}-${b}`);
      const desired = base || slugify(`${m}-${b}`) || `${m}-${b}`.toLowerCase();

      // If a slug already points to this (m,b), reuse it (idempotent)
      // We’ll also prefer an existing slug stored on the branch doc.
      let branchSlug = bDoc.get('slug');
      if (branchSlug && typeof branchSlug === 'string' && branchSlug.trim()) {
        branchSlug = slugify(branchSlug);
      } else {
        branchSlug = desired;
      }

      // If an existing /slugs/{branchSlug} belongs to someone else, make it unique
      let finalSlug = branchSlug;
      const existing = await db.doc(`slugs/${finalSlug}`).get();
      if (existing.exists) {
        const data = existing.data() || {};
        if (data.merchantId === m && data.branchId === b) {
          // Same mapping → update title/updatedAt and continue
          await existing.ref.set(
            { title: title || data.title || null, updatedAt: ts },
            { merge: true }
          );
          updated++;
          console.log(`= kept slug: /slugs/${finalSlug} -> ${m}/${b}`);
        } else {
          // Taken by different branch/merchant → generate a unique one
          finalSlug = await uniqueSlug(desired);
          await db.doc(`slugs/${finalSlug}`).set({
            merchantId: m,
            branchId: b,
            title: title || null,
            createdAt: ts,
            updatedAt: ts,
          });
          created++;
          console.log(`+ created unique slug: /slugs/${finalSlug} -> ${m}/${b}`);
        }
      } else {
        // Free → create it
        await db.doc(`slugs/${finalSlug}`).set({
          merchantId: m,
          branchId: b,
          title: title || null,
          createdAt: ts,
          updatedAt: ts,
        });
        created++;
        console.log(`+ created slug: /slugs/${finalSlug} -> ${m}/${b}`);
      }

      // (optional) write slug back to branches/{b}.slug for convenience
      if (WRITE_SLUG_TO_BRANCH_DOC) {
        await bDoc.ref.set({ slug: finalSlug, updatedAt: ts }, { merge: true });
      }
    }
  }

  console.log('-----------------------------------');
  console.log(`Done. created=${created} updated=${updated} skipped=${skipped}`);
}

main().then(() => process.exit(0)).catch((e) => {
  console.error(e);
  process.exit(1);
});
