// scripts/seed-menu.prod.js  (PRODUCTION)
delete process.env.FIRESTORE_EMULATOR_HOST;

const admin = require('firebase-admin');
admin.initializeApp({
  credential: admin.credential.cert(require('./serviceAccount.json')),
  projectId: 'sweets-c4f6b',
});
const db = admin.firestore();

async function run() {
  const base = db.doc('merchants/demo_merchant/branches/dev_branch');
  const col = base.collection('menuItems');
  const items = [
    { id: 'donut',    name: 'Glazed Donut',     price: 0.600 },
    { id: 'cookie',   name: 'Chocolate Cookie', price: 0.500 },
    { id: 'cinnabon', name: 'Cinnabon Roll',    price: 1.200 },
  ];
  const batch = db.batch();
  for (const it of items) batch.set(col.doc(it.id), { name: it.name, price: it.price });
  await batch.commit();
  console.log('Seeded menuItems for dev_branch (PRODUCTION)');
}
run().catch(e => { console.error(e); process.exit(1); });
