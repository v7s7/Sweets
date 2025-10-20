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
 * Default region (Gulf): me-central2
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

/* -------------------------------------------------------------------------- */
/*                               Shared helpers                               */
/* -------------------------------------------------------------------------- */

const CORS_ORIGINS = [
  /^https?:\/\/localhost(:\d+)?$/,
  /^https?:\/\/127\.0\.0\.1(:\d+)?$/,
  /\.web\.app$/,
  /\.firebaseapp\.com$/,
];

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

/* -------------------------------------------------------------------------- */
/*                              Slug reservations                             */
/* -------------------------------------------------------------------------- */

type SetBranchSlugPayload = {
  merchantId: string;
  branchId: string;
  slug: string;
};

function normalizeSlug(s: string): string {
  const trimmed = (s || "").toLowerCase().trim();
  const norm = trimmed
    .replace(/[^a-z0-9-]/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");
  if (norm.length < 3 || norm.length > 32) {
    throw new HttpsError("invalid-argument", "Slug must be 3–32 characters.");
  }
  const reserved = new Set([
    "admin", "api", "app", "assets", "s", "m", "b",
    "login", "signup", "merchant", "console",
  ]);
  if (reserved.has(norm)) {
    throw new HttpsError("failed-precondition", "Slug is reserved.");
  }
  return norm;
}

/**
 * Reserve or update a branch's public slug.
 * - Enforces uniqueness in /slugs/{slug}
 * - Ensures caller is staff under that branch
 * - Stores slug at branding doc: merchants/{m}/branches/{b}/config/branding.shareSlug
 * - Frees previous slug (if any)
 */
export const setBranchSlug = onCall(
  {
    cors: CORS_ORIGINS,
    // appCheck: true, // enable after you wire App Check in the client
  },
  async (request: CallableRequest<SetBranchSlugPayload>) => {
    try {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Sign in required.");
      }
      const { merchantId, branchId, slug } = (request.data || {}) as SetBranchSlugPayload;
      if (!merchantId || !branchId || !slug) {
        throw new HttpsError("invalid-argument", "Missing merchantId, branchId, or slug.");
      }

      const uid = request.auth.uid!;
      if (!(await isStaff(uid, merchantId, branchId))) {
        throw new HttpsError("permission-denied", "Staff only.");
      }

      const norm = normalizeSlug(slug);

      await db.runTransaction(async (tx) => {
        const slugRef = db.doc(`slugs/${norm}`);
        const slugSnap = await tx.get(slugRef);
        if (slugSnap.exists) {
          throw new HttpsError("already-exists", "Slug already taken.");
        }

        const brandingRef = db.doc(`merchants/${merchantId}/branches/${branchId}/config/branding`);
        const brandingSnap = await tx.get(brandingRef);
        const prevSlug: string | undefined = brandingSnap.exists ? brandingSnap.get("shareSlug") : undefined;

        if (prevSlug && prevSlug !== norm) {
          tx.delete(db.doc(`slugs/${prevSlug}`));
        }

        tx.set(slugRef, {
          merchantId,
          branchId,
          active: true,
          updatedAt: FieldValue.serverTimestamp(),
        });

        tx.set(brandingRef, { shareSlug: norm }, { merge: true });
      });

      logger.info("[setBranchSlug] reserved", { merchantId, branchId, slug: slug.toLowerCase() });
      return { slug: slug.toLowerCase() };
    } catch (err: any) {
      logger.error("[setBranchSlug] error", {
        code: err?.code ?? "unknown",
        message: err?.message ?? String(err),
        stack: err?.stack ?? null,
      });
      if (err instanceof HttpsError) throw err;
      throw new HttpsError("internal", "Unexpected error in setBranchSlug.");
    }
  }
);

/* -------------------------------------------------------------------------- */
/*                                createOrder                                 */
/* -------------------------------------------------------------------------- */

/** Callable + CORS so the Flutter Web app can call from localhost or Hosting. */
export const createOrder = onCall(
  {
    cors: CORS_ORIGINS,
    // appCheck: true, // enable later to enforce App Check
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
          "Missing merchantId, branchId, or items.",
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

      // Build menu price index from subcollection `menuItems`
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
        `merchants/${merchantId}/branches/${branchId}/orders`,
      );
      const ref = ordersCol.doc();
      await ref.set({
        orderNo,
        status: "pending" as OrderStatus,
        items: lines,
        subtotal,
        userId: request.auth.uid,
        table: table ?? null,
        createdAt: FieldValue.serverTimestamp(),
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
  },
);

/* -------------------------------------------------------------------------- */
/*                             updateOrderStatus                               */
/* -------------------------------------------------------------------------- */

/** Callable + CORS as above. */
export const updateOrderStatus = onCall(
  {
    cors: CORS_ORIGINS,
    // appCheck: true, // enable later to enforce App Check
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
        `merchants/${merchantId}/branches/${branchId}/orders/${orderId}`,
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
            `Illegal transition ${current} -> ${nextStatus}`,
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
  },
);
