import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

admin.initializeApp();
const db = admin.firestore();

type OrderItem = { productId: string; qty: number };
type CreateOrderPayload = {
  merchantId: string;
  branchId: string;
  items: OrderItem[];
  table?: string | null;
};

const ORDER_STATUSES = ["pending","accepted","preparing","ready","served","cancelled"] as const;
type OrderStatus = typeof ORDER_STATUSES[number];

type UpdateStatusPayload = {
  merchantId: string;
  branchId: string;
  orderId: string;
  nextStatus: OrderStatus;
};

// NOTE: With newer firebase-functions typings, onCall handlers receive a single
// `request` object (CallableRequest) that contains `data` and `auth`. There is no
// separate `(data, context)` pair anymore.

export const createOrder = functions.https.onCall(async (request) => {
  if (!request.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in required.");
  }

  const { merchantId, branchId, items, table } =
    (request.data || {}) as CreateOrderPayload;

  if (!merchantId || !branchId || !Array.isArray(items) || items.length === 0) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Missing merchant/branch/items."
    );
  }

  // Build menu price index
  const menuSnap = await db
    .collection(`merchants/${merchantId}/branches/${branchId}/menuItems`)
    .get();
  if (menuSnap.empty) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Menu not configured."
    );
  }
  const menu = new Map<string, { name: string; price: number }>();
  menuSnap.forEach((d) => {
    const v = d.data();
    menu.set(d.id, { name: String(v.name ?? d.id), price: Number(v.price) || 0 });
  });

  // Lines & subtotal (cap qty 1..99)
  const lines: Array<{
    productId: string;
    name: string;
    price: number;
    qty: number;
  }> = [];
  let subtotal = 0;
  for (const it of items) {
    const row = menu.get(it.productId);
    if (!row) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        `Unknown productId: ${it.productId}`
      );
    }
    const qty = Math.min(Math.max(Number(it.qty) || 1, 1), 99);
    lines.push({
      productId: it.productId,
      name: row.name,
      price: row.price,
      qty,
    });
    subtotal += row.price * qty;
  }
  subtotal = Math.round(subtotal * 1000) / 1000; // 3dp (BHD)

  // Per-branch counter -> A-001
  const counterRef = db.doc(`counters/${merchantId}_${branchId}_orders`);
  const orderNo = await db.runTransaction(async (tx) => {
    const snap = await tx.get(counterRef);
    const next = (snap.exists ? (snap.get("seq") as number) : 0) + 1;
    tx.set(counterRef, { seq: next }, { merge: true });
    return `A-${String(next).padStart(3, "0")}`;
  });

  // Create order
  const ordersCol = db.collection(
    `merchants/${merchantId}/branches/${branchId}/orders`
  );
  const ref = ordersCol.doc();
  await ref.set({
    orderNo,
    status: "pending" as OrderStatus,
    items: lines,
    subtotal,
    userId: request.auth.uid,
    table: table ?? null,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    merchantId,
    branchId,
  });

  return {
    orderId: ref.id,
    orderNo,
    subtotal,
    status: "pending" as OrderStatus,
  };
});

function isAllowedTransition(from: OrderStatus, to: OrderStatus): boolean {
  const order = [
    "pending",
    "accepted",
    "preparing",
    "ready",
    "served",
    "cancelled",
  ];
  const iFrom = order.indexOf(from),
    iTo = order.indexOf(to);
  if (iFrom === -1 || iTo === -1) return false;
  if (to === "cancelled") return from !== "served" && from !== "cancelled";
  return iTo === iFrom + 1; // step
}

async function isStaff(uid: string, m: string, b: string): Promise<boolean> {
  const roleDoc = await db
    .doc(`merchants/${m}/branches/${b}/roles/${uid}`)
    .get();
  return roleDoc.exists;
}

export const updateOrderStatus = functions.https.onCall(async (request) => {
  if (!request.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in required.");
  }

  const { merchantId, branchId, orderId, nextStatus } =
    (request.data || {}) as UpdateStatusPayload;

  if (!merchantId || !branchId || !orderId || !nextStatus) {
    throw new functions.https.HttpsError("invalid-argument", "Missing fields.");
  }
  if (!ORDER_STATUSES.includes(nextStatus)) {
    throw new functions.https.HttpsError("invalid-argument", "Invalid status.");
  }
  if (!(await isStaff(request.auth.uid!, merchantId, branchId))) {
    throw new functions.https.HttpsError("permission-denied", "Staff only.");
  }

  const ref = db.doc(
    `merchants/${merchantId}/branches/${branchId}/orders/${orderId}`
  );
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) {
      throw new functions.https.HttpsError("not-found", "Order not found.");
    }
    const current = snap.get("status") as OrderStatus;
    if (!isAllowedTransition(current, nextStatus)) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        `Illegal transition ${current} -> ${nextStatus}`
      );
    }
    tx.update(ref, { status: nextStatus });
  });

  return { ok: true };
});
