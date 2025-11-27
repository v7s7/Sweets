import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";

// v2 APIs
import {
  onCall,
  HttpsError,
  CallableRequest,
} from "firebase-functions/v2/https";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { setGlobalOptions } from "firebase-functions/v2/options";
import * as logger from "firebase-functions/logger";

// Email service
import { sendOrderNotification, sendReport, type OrderNotificationData, type ReportData } from "./email-service";

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
  },
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

/* -------------------------------------------------------------------------- */
/*                         Email Notifications & Reports                      */
/* -------------------------------------------------------------------------- */

/**
 * Firestore trigger: Send email notification when a new order is created
 */
export const onOrderCreated = onDocumentCreated(
  {
    document: "merchants/{merchantId}/branches/{branchId}/orders/{orderId}",
    region: REGION,
  },
  async (event) => {
    try {
      const { merchantId, branchId, orderId } = event.params;
      const orderData = event.data?.data();

      if (!orderData) {
        logger.warn("[onOrderCreated] No order data", { merchantId, branchId, orderId });
        return;
      }

      // Get merchant email settings
      const settingsDoc = await db
        .doc(`merchants/${merchantId}/branches/${branchId}/config/settings`)
        .get();

      const notificationsEnabled = settingsDoc.get("emailNotifications.enabled") ?? false;
      const merchantEmail = settingsDoc.get("emailNotifications.email");

      if (!notificationsEnabled || !merchantEmail) {
        logger.info("[onOrderCreated] Email notifications disabled or no email configured", {
          merchantId,
          branchId,
          enabled: notificationsEnabled,
          hasEmail: !!merchantEmail,
        });
        return;
      }

      // Get merchant name from branding
      const brandingDoc = await db
        .doc(`merchants/${merchantId}/branches/${branchId}/config/branding`)
        .get();
      const merchantName = brandingDoc.get("title") || "Your Store";

      // Prepare email data
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
        dashboardUrl: "https://sweetweb.web.app/merchant", // Update with actual URL
        toEmail: merchantEmail,
      };

      // Send email
      const result = await sendOrderNotification(emailData);

      if (result.success) {
        logger.info("[onOrderCreated] Email sent successfully", {
          messageId: result.messageId,
          orderNo: orderData.orderNo,
        });
      } else {
        logger.error("[onOrderCreated] Email failed", {
          error: result.error,
          orderNo: orderData.orderNo,
        });
      }
    } catch (error: any) {
      logger.error("[onOrderCreated] Exception", {
        error: error.message || String(error),
        stack: error.stack,
      });
    }
  },
);

type GenerateReportPayload = {
  merchantId: string;
  branchId: string;
  startDate: string; // ISO date string
  endDate: string; // ISO date string
  toEmail: string;
};

/**
 * Callable function: Generate and email a sales report for a custom date range
 */
export const generateReport = onCall(
  {
    cors: CORS_ORIGINS,
  },
  async (request: CallableRequest<GenerateReportPayload>) => {
    try {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Sign in required.");
      }

      const { merchantId, branchId, startDate, endDate, toEmail } =
        (request.data || {}) as GenerateReportPayload;

      if (!merchantId || !branchId || !startDate || !endDate || !toEmail) {
        throw new HttpsError("invalid-argument", "Missing required fields.");
      }

      // Verify user is staff
      const uid = request.auth.uid!;
      if (!(await isStaff(uid, merchantId, branchId))) {
        throw new HttpsError("permission-denied", "Staff only.");
      }

      // Parse dates
      const start = new Date(startDate);
      const end = new Date(endDate);
      end.setHours(23, 59, 59, 999); // Include full end day

      if (isNaN(start.getTime()) || isNaN(end.getTime())) {
        throw new HttpsError("invalid-argument", "Invalid date format.");
      }

      logger.info("[generateReport] Generating report", {
        merchantId,
        branchId,
        startDate,
        endDate,
        toEmail,
      });

      // Fetch orders in date range
      const ordersSnap = await db
        .collection(`merchants/${merchantId}/branches/${branchId}/orders`)
        .where("createdAt", ">=", start)
        .where("createdAt", "<=", end)
        .get();

      // Calculate metrics
      let totalRevenue = 0;
      let servedOrders = 0;
      let cancelledOrders = 0;
      const ordersByStatus: Record<string, number> = {};
      const itemCounts: Record<string, { count: number; revenue: number }> = {};

      ordersSnap.forEach((doc) => {
        const order = doc.data();
        const status = order.status as OrderStatus;

        // Count by status
        ordersByStatus[status] = (ordersByStatus[status] || 0) + 1;

        if (status === "served") {
          servedOrders++;
          totalRevenue += order.subtotal || 0;
        } else if (status === "cancelled") {
          cancelledOrders++;
        }

        // Count items (only from served orders)
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

      // Top items
      const topItems = Object.entries(itemCounts)
        .map(([name, data]) => ({ name, count: data.count, revenue: data.revenue }))
        .sort((a, b) => b.count - a.count);

      // Orders by status array
      const statusArray = Object.entries(ordersByStatus).map(([status, count]) => ({
        status,
        count,
      }));

      // Get merchant name
      const brandingDoc = await db
        .doc(`merchants/${merchantId}/branches/${branchId}/config/branding`)
        .get();
      const merchantName = brandingDoc.get("title") || "Your Store";

      // Format date range
      const dateRange = `${start.toLocaleDateString()} - ${end.toLocaleDateString()}`;

      // Prepare report data
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

      // Send report email
      const result = await sendReport(reportData);

      if (!result.success) {
        throw new HttpsError("internal", `Failed to send report: ${result.error}`);
      }

      logger.info("[generateReport] Report sent successfully", {
        messageId: result.messageId,
        totalOrders: ordersSnap.size,
        totalRevenue,
      });

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
      logger.error("[generateReport] error", {
        code: err?.code ?? "unknown",
        message: err?.message ?? String(err),
        stack: err?.stack ?? null,
      });
      if (err instanceof HttpsError) throw err;
      throw new HttpsError("internal", "Unexpected error in generateReport.");
    }
  },
);
