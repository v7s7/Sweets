import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";

// v2 APIs
import {
  onCall,
  HttpsError,
  CallableRequest,
} from "firebase-functions/v2/https";
import { setGlobalOptions } from "firebase-functions/v2/options";
import * as logger from "firebase-functions/logger";

/**
 * Keep your Functions region here. Dammam/Gulf → me-central2.
 * (Emulator ignores region, but production and the client SDK will use it.)
 */
const REGION = "me-central2";
setGlobalOptions({
  region: REGION,
  timeoutSeconds: 60,
  memory: "256MiB",
  maxInstances: 1,
});

admin.initializeApp();
const db = admin.firestore();

/* ----------------------------- Types & helpers ----------------------------- */

type OrderItemIn = { productId: string; qty: number };
type CreateOrderPayload = {
  merchantId: string;
  branchId: string;
  items: OrderItemIn[];
  table?: string | null;
};

const ORDER_STATUSES = [
  "pending",
  "accepted",
  "preparing",
  "ready",
  "served",
  "cancelled",
] as const;
type OrderStatus = (typeof ORDER_STATUSES)[number];

type UpdateStatusPayload = {
  merchantId: string;
  branchId: string;
  orderId: string;
  nextStatus: OrderStatus;
};

function isAllowedTransition(from: OrderStatus, to: OrderStatus): boolean {
  // Linear forward flow; cancel allowed from any non-final state.
  const order = ["pending", "accepted", "preparing", "ready", "served", "cancelled"];
  const iFrom = order.indexOf(from);
  const iTo = order.indexOf(to);
  if (iFrom === -1 || iTo === -1) return false;
  if (to === "cancelled") return from !== "served" && from !== "cancelled";
  return iTo === iFrom + 1;
}

async function isStaff(uid: string, m: string, b: string): Promise<boolean> {
  const roleDoc = await db.doc(`merchants/${m}/branches/${b}/roles/${uid}`).get();
  return roleDoc.exists;
}

/* -------------------------------- createOrder ------------------------------- */
/** CORS enabled to allow localhost & hosted web origins. */
export const createOrder = onCall(
  {
    // Simplest: allow all during development. Tighten later if desired:
    // cors: [/^http:\/\/localhost(:\d+)?$/, /\.web\.app$/, /\.firebaseapp\.com$/]
    cors: true,
  },
  async (request: CallableRequest<CreateOrderPayload>) => {
    const t0 = Date.now();
    try {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Sign in required.");
      }

      const { merchantId, branchId, items, table } =
        (request.data || {}) as CreateOrderPayload;

      if (!merchantId || !branchId || !Array.isArray(items) || items.length === 0) {
        throw new HttpsError(
          "invalid-argument",
          "Missing merchantId, branchId, or items."
        );
      }

      logger.info("[createOrder] input", {
        merchantId,
        branchId,
        itemsCount: items.length,
        table: table ?? null,
        uid: request.auth.uid,
        region: REGION,
      });

      // Build menu price index
      const menuSnap = await db
        .collection(`merchants/${merchantId}/branches/${branchId}/menuItems`)
        .get();

      logger.debug("[createOrder] menu size", {
        merchantId,
        branchId,
        count: menuSnap.size,
      });

      if (menuSnap.empty) {
        throw new HttpsError("failed-precondition", "Menu not configured.");
      }

      const menu = new Map<string, { name: string; price: number }>();
      menuSnap.forEach((d) => {
        const v = d.data();
        menu.set(d.id, {
          name: String(v.name ?? d.id),
          price: Number(v.price) || 0,
        });
      });

      // Lines & subtotal (cap qty 1..99)
      const lines: Array<{ productId: string; name: string; price: number; qty: number }> = [];
      let subtotal = 0;

      for (const it of items) {
        const row = menu.get(it.productId);
        if (!row) {
          throw new HttpsError("invalid-argument", `Unknown productId: ${it.productId}`);
        }
        const qty = Math.min(Math.max(Number(it.qty) || 1, 1), 99);
        lines.push({ productId: it.productId, name: row.name, price: row.price, qty });
        subtotal += row.price * qty;
      }

      // BHD → 3dp
      subtotal = Number(subtotal.toFixed(3));

      // Per-branch counter -> A-001, A-002, ...
      const counterRef = db.doc(`counters/${merchantId}_${branchId}_orders`);
      const orderNo = await db.runTransaction(async (tx) => {
        const snap = await tx.get(counterRef);
        const next = (snap.exists ? (snap.get("seq") as number) : 0) + 1;
        tx.set(counterRef, { seq: next }, { merge: true });
        return `A-${String(next).padStart(3, "0")}`;
      });

      // Create order doc
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
        createdAt: FieldValue.serverTimestamp(), // modular FieldValue
        merchantId,
        branchId,
      });

      logger.info("[createOrder] created", {
        orderId: ref.id,
        orderNo,
        subtotal,
        status: "pending",
        merchantId,
        branchId,
        ms: Date.now() - t0,
      });

      return { orderId: ref.id, orderNo, subtotal, status: "pending" as OrderStatus };
    } catch (err: any) {
      logger.error("[createOrder] error", {
        code: err?.code ?? "unknown",
        message: err?.message ?? String(err),
        stack: err?.stack ?? null,
      });
      if (err instanceof HttpsError) throw err;
      throw new HttpsError("internal", "Unexpected error in createOrder.");
    }
  }
);

/* ----------------------------- updateOrderStatus ---------------------------- */
/** CORS enabled here as well. */
export const updateOrderStatus = onCall(
  {
    cors: true,
  },
  async (request: CallableRequest<UpdateStatusPayload>) => {
    try {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Sign in required.");
      }

      const { merchantId, branchId, orderId, nextStatus } =
        (request.data || {}) as UpdateStatusPayload;

      if (!merchantId || !branchId || !orderId || !nextStatus) {
        throw new HttpsError("invalid-argument", "Missing fields.");
      }
      if (!ORDER_STATUSES.includes(nextStatus)) {
        throw new HttpsError("invalid-argument", "Invalid status.");
      }

      const uid = request.auth.uid!;
      if (!(await isStaff(uid, merchantId, branchId))) {
        throw new HttpsError("permission-denied", "Staff only.");
      }

      const ref = db.doc(
        `merchants/${merchantId}/branches/${branchId}/orders/${orderId}`
      );

      await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        if (!snap.exists) {
          throw new HttpsError("not-found", "Order not found.");
        }
        const current = snap.get("status") as OrderStatus;
        if (!isAllowedTransition(current, nextStatus)) {
          throw new HttpsError(
            "failed-precondition",
            `Illegal transition ${current} -> ${nextStatus}`
          );
        }
        tx.update(ref, { status: nextStatus });
      });

      logger.info("[updateOrderStatus] ok", {
        merchantId,
        branchId,
        orderId,
        nextStatus,
        actor: uid,
      });

      return { ok: true };
    } catch (err: any) {
      logger.error("[updateOrderStatus] error", {
        code: err?.code ?? "unknown",
        message: err?.message ?? String(err),
        stack: err?.stack ?? null,
      });
      if (err instanceof HttpsError) throw err;
      throw new HttpsError("internal", "Unexpected error in updateOrderStatus.");
    }
  }
);
