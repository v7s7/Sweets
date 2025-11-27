import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";
import * as functions from "firebase-functions";

// Email service
import { sendOrderNotification, sendReport, type OrderNotificationData, type ReportData } from "./email-service";

admin.initializeApp();
const db = admin.firestore();

/* -------------------------------------------------------------------------- */
/*                               Shared helpers                               */
/* -------------------------------------------------------------------------- */

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

/**
 * Check if transition is allowed
 * @param {OrderStatus} from - Current status
 * @param {OrderStatus} to - Next status
 * @return {boolean} Whether transition is allowed
 */
function isAllowedTransition(from: OrderStatus, to: OrderStatus): boolean {
  const order = ["pending", "accepted", "preparing", "ready", "served", "cancelled"];
  const iFrom = order.indexOf(from);
  const iTo = order.indexOf(to);
  if (iFrom === -1 || iTo === -1) return false;
  if (to === "cancelled") return from !== "served" && from !== "cancelled";
  return iTo === iFrom + 1;
}

/**
 * Check if user is staff
 * @param {string} uid - User ID
 * @param {string} m - Merchant ID
 * @param {string} b - Branch ID
 * @return {Promise<boolean>} Whether user is staff
 */
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

/**
 * Normalize slug
 * @param {string} s - Slug to normalize
 * @return {string} Normalized slug
 */
function normalizeSlug(s: string): string {
  const trimmed = (s || "").toLowerCase().trim();
  const norm = trimmed
    .replace(/[^a-z0-9-]/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");
  if (norm.length < 3 || norm.length > 32) {
    throw new functions.https.HttpsError("invalid-argument", "Slug must be 3–32 characters.");
  }
  const reserved = new Set([
    "admin", "api", "app", "assets", "s", "m", "b",
    "login", "signup", "merchant", "console",
  ]);
  if (reserved.has(norm)) {
    throw new functions.https.HttpsError("failed-precondition", "Slug is reserved.");
  }
  return norm;
}

export const setBranchSlug = functions.https.onCall(async (data, context) => {
  try {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Sign in required.");
    }
    const { merchantId, branchId, slug } = data as SetBranchSlugPayload;
    if (!merchantId || !branchId || !slug) {
      throw new functions.https.HttpsError("invalid-argument", "Missing merchantId, branchId, or slug.");
    }

    const uid = context.auth.uid;
    if (!(await isStaff(uid, merchantId, branchId))) {
      throw new functions.https.HttpsError("permission-denied", "Staff only.");
    }

    const norm = normalizeSlug(slug);

    await db.runTransaction(async (tx) => {
      const slugRef = db.doc(`slugs/${norm}`);
      const slugSnap = await tx.get(slugRef);
      if (slugSnap.exists) {
        throw new functions.https.HttpsError("already-exists", "Slug already taken.");
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

    console.log("[setBranchSlug] reserved", { merchantId, branchId, slug: slug.toLowerCase() });
    return { slug: slug.toLowerCase() };
  } catch (err: any) {
    console.error("[setBranchSlug] error", err);
    if (err instanceof functions.https.HttpsError) throw err;
    throw new functions.https.HttpsError("internal", "Unexpected error in setBranchSlug.");
  }
});

/* -------------------------------------------------------------------------- */
/*                                createOrder                                 */
/* -------------------------------------------------------------------------- */

export const createOrder = functions.https.onCall(async (data, context) => {
  const t0 = Date.now();
  try {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Sign in required.");
    }

    const { merchantId, branchId, items, table } = data as CreateOrderPayload;

    if (!merchantId || !branchId || !Array.isArray(items) || items.length === 0) {
      throw new functions.https.HttpsError("invalid-argument", "Missing merchantId, branchId, or items.");
    }

    console.log("[createOrder] input", { merchantId, branchId, itemsCount: items.length, table: table ?? null, uid: context.auth.uid });

    const menuSnap = await db
      .collection(`merchants/${merchantId}/branches/${branchId}/menuItems`)
      .get();

    if (menuSnap.empty) {
      throw new functions.https.HttpsError("failed-precondition", "Menu not configured.");
    }

    const menu = new Map<string, { name: string; price: number }>();
    menuSnap.forEach((d) => {
      const v = d.data();
      menu.set(d.id, {
        name: String(v.name ?? d.id),
        price: Number(v.price) || 0,
      });
    });

    const lines: Array<{ productId: string; name: string; price: number; qty: number }> = [];
    let subtotal = 0;

    for (const it of items) {
      const row = menu.get(it.productId);
      if (!row) {
        throw new functions.https.HttpsError("invalid-argument", `Unknown productId: ${it.productId}`);
      }
      const qty = Math.min(Math.max(Number(it.qty) || 1, 1), 99);
      lines.push({ productId: it.productId, name: row.name, price: row.price, qty });
      subtotal += row.price * qty;
    }

    subtotal = Number(subtotal.toFixed(3));

    const counterRef = db.doc(`counters/${merchantId}_${branchId}_orders`);
    const orderNo = await db.runTransaction(async (tx) => {
      const snap = await tx.get(counterRef);
      const next = (snap.exists ? (snap.get("seq") as number) : 0) + 1;
      tx.set(counterRef, { seq: next }, { merge: true });
      return `A-${String(next).padStart(3, "0")}`;
    });

    const ordersCol = db.collection(`merchants/${merchantId}/branches/${branchId}/orders`);
    const ref = ordersCol.doc();
    await ref.set({
      orderNo,
      status: "pending" as OrderStatus,
      items: lines,
      subtotal,
      userId: context.auth.uid,
      table: table ?? null,
      createdAt: FieldValue.serverTimestamp(),
      merchantId,
      branchId,
    });

    console.log("[createOrder] created", { orderId: ref.id, orderNo, subtotal, ms: Date.now() - t0 });

    return { orderId: ref.id, orderNo, subtotal, status: "pending" as OrderStatus };
  } catch (err: any) {
    console.error("[createOrder] error", err);
    if (err instanceof functions.https.HttpsError) throw err;
    throw new functions.https.HttpsError("internal", "Unexpected error in createOrder.");
  }
});

/* -------------------------------------------------------------------------- */
/*                             updateOrderStatus                               */
/* -------------------------------------------------------------------------- */

export const updateOrderStatus = functions.https.onCall(async (data, context) => {
  try {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Sign in required.");
    }

    const { merchantId, branchId, orderId, nextStatus } = data as UpdateStatusPayload;

    if (!merchantId || !branchId || !orderId || !nextStatus) {
      throw new functions.https.HttpsError("invalid-argument", "Missing fields.");
    }
    if (!ORDER_STATUSES.includes(nextStatus)) {
      throw new functions.https.HttpsError("invalid-argument", "Invalid status.");
    }

    const uid = context.auth.uid;
    if (!(await isStaff(uid, merchantId, branchId))) {
      throw new functions.https.HttpsError("permission-denied", "Staff only.");
    }

    const ref = db.doc(`merchants/${merchantId}/branches/${branchId}/orders/${orderId}`);

    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) {
        throw new functions.https.HttpsError("not-found", "Order not found.");
      }
      const current = snap.get("status") as OrderStatus;
      if (!isAllowedTransition(current, nextStatus)) {
        throw new functions.https.HttpsError("failed-precondition", `Illegal transition ${current} -> ${nextStatus}`);
      }
      tx.update(ref, { status: nextStatus });
    });

    console.log("[updateOrderStatus] ok", { merchantId, branchId, orderId, nextStatus, actor: uid });

    return { ok: true };
  } catch (err: any) {
    console.error("[updateOrderStatus] error", err);
    if (err instanceof functions.https.HttpsError) throw err;
    throw new functions.https.HttpsError("internal", "Unexpected error in updateOrderStatus.");
  }
});

/* -------------------------------------------------------------------------- */
/*                         Email Notifications & Reports                      */
/* -------------------------------------------------------------------------- */

export const onOrderCreated = functions.firestore
  .document("merchants/{merchantId}/branches/{branchId}/orders/{orderId}")
  .onCreate(async (snap, context) => {
    try {
      const { merchantId, branchId, orderId } = context.params;
      const orderData = snap.data();

      if (!orderData) {
        console.warn("[onOrderCreated] No order data", { merchantId, branchId, orderId });
        return;
      }

      const settingsDoc = await db
        .doc(`merchants/${merchantId}/branches/${branchId}/config/settings`)
        .get();

      const notificationsEnabled = settingsDoc.get("emailNotifications.enabled") ?? false;
      const merchantEmail = settingsDoc.get("emailNotifications.email");

      if (!notificationsEnabled || !merchantEmail) {
        console.log("[onOrderCreated] Email notifications disabled", { merchantId, branchId });
        return;
      }

      const brandingDoc = await db
        .doc(`merchants/${merchantId}/branches/${branchId}/config/branding`)
        .get();
      const merchantName = brandingDoc.get("title") || "Your Store";

      const items = (orderData.items || []) as Array<{
        name: string;
        qty: number;
        price: number;
        note?: string;
      }>;

      const timestamp = orderData.createdAt ?
        new Date(orderData.createdAt.toDate()).toLocaleString() :
        new Date().toLocaleString();

      const emailData: OrderNotificationData = {
        orderNo: orderData.orderNo || orderId,
        table: orderData.table || null,
        items,
        subtotal: orderData.subtotal || 0,
        timestamp,
        merchantName,
        dashboardUrl: "https://sweetweb.web.app/merchant",
        toEmail: merchantEmail,
      };

      const result = await sendOrderNotification(emailData);

      if (result.success) {
        console.log("[onOrderCreated] Email sent", { messageId: result.messageId, orderNo: orderData.orderNo });
      } else {
        console.error("[onOrderCreated] Email failed", { error: result.error, orderNo: orderData.orderNo });
      }
    } catch (error: any) {
      console.error("[onOrderCreated] Exception", error);
    }
  });

type GenerateReportPayload = {
  merchantId: string;
  branchId: string;
  startDate: string;
  endDate: string;
  toEmail: string;
};

export const generateReport = functions.https.onCall(async (data, context) => {
  try {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Sign in required.");
    }

    const { merchantId, branchId, startDate, endDate, toEmail } = data as GenerateReportPayload;

    if (!merchantId || !branchId || !startDate || !endDate || !toEmail) {
      throw new functions.https.HttpsError("invalid-argument", "Missing required fields.");
    }

    const uid = context.auth.uid;
    if (!(await isStaff(uid, merchantId, branchId))) {
      throw new functions.https.HttpsError("permission-denied", "Staff only.");
    }

    const start = new Date(startDate);
    const end = new Date(endDate);
    end.setHours(23, 59, 59, 999);

    if (isNaN(start.getTime()) || isNaN(end.getTime())) {
      throw new functions.https.HttpsError("invalid-argument", "Invalid date format.");
    }

    console.log("[generateReport] Generating", { merchantId, branchId, startDate, endDate, toEmail });

    const ordersSnap = await db
      .collection(`merchants/${merchantId}/branches/${branchId}/orders`)
      .where("createdAt", ">=", start)
      .where("createdAt", "<=", end)
      .get();

    let totalRevenue = 0;
    let servedOrders = 0;
    let cancelledOrders = 0;
    const ordersByStatus: Record<string, number> = {};
    const itemCounts: Record<string, { count: number; revenue: number }> = {};

    ordersSnap.forEach((doc) => {
      const order = doc.data();
      const status = order.status as OrderStatus;

      ordersByStatus[status] = (ordersByStatus[status] || 0) + 1;

      if (status === "served") {
        servedOrders++;
        totalRevenue += order.subtotal || 0;
      } else if (status === "cancelled") {
        cancelledOrders++;
      }

      if (status === "served" && order.items) {
        for (const item of order.items) {
          const key = item.name;
          if (!itemCounts[key]) {
            itemCounts[key] = { count: 0, revenue: 0 };
          }
          itemCounts[key].count += item.qty;
          itemCounts[key].revenue += item.price * item.qty;
        }
      }
    });

    const topItems = Object.entries(itemCounts)
      .map(([name, data]) => ({ name, count: data.count, revenue: data.revenue }))
      .sort((a, b) => b.count - a.count);

    const statusArray = Object.entries(ordersByStatus).map(([status, count]) => ({ status, count }));

    const brandingDoc = await db
      .doc(`merchants/${merchantId}/branches/${branchId}/config/branding`)
      .get();
    const merchantName = brandingDoc.get("title") || "Your Store";

    const dateRange = `${start.toLocaleDateString()} - ${end.toLocaleDateString()}`;

    const reportData: ReportData = {
      merchantName,
      dateRange,
      totalOrders: ordersSnap.size,
      totalRevenue,
      servedOrders,
      cancelledOrders,
      averageOrder: servedOrders > 0 ? totalRevenue / servedOrders : 0,
      topItems,
      ordersByStatus: statusArray,
      toEmail,
    };

    const result = await sendReport(reportData);

    if (!result.success) {
      throw new functions.https.HttpsError("internal", `Failed to send report: ${result.error}`);
    }

    console.log("[generateReport] Sent", { messageId: result.messageId, totalOrders: ordersSnap.size });

    return {
      success: true,
      messageId: result.messageId,
      stats: {
        totalOrders: ordersSnap.size,
        totalRevenue,
        servedOrders,
        cancelledOrders,
      },
    };
  } catch (err: any) {
    console.error("[generateReport] error", err);
    if (err instanceof functions.https.HttpsError) throw err;
    throw new functions.https.HttpsError("internal", "Unexpected error in generateReport.");
  }
});
