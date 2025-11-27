/**
 * Cloudflare Worker for SweetWeb Email Service
 * Handles order notifications and report generation via Resend API
 *
 * Deployment:
 * 1. Go to https://dash.cloudflare.com
 * 2. Workers & Pages > Create application > Create Worker
 * 3. Copy this code
 * 4. Add environment variable: RESEND_API_KEY = re_M2UEqUWF_QEJGCDgmP1mFpLi1DTNL3758
 * 5. Deploy
 *
 * Free tier: 100,000 requests/day
 */

const FROM_EMAIL = 'SweetWeb <onboarding@resend.dev>';

// CORS headers for Flutter web app
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

export default {
  async fetch(request, env) {
    // Handle CORS preflight
    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders });
    }

    if (request.method !== 'POST') {
      return new Response('Method not allowed', { status: 405, headers: corsHeaders });
    }

    try {
      const { action, data } = await request.json();

      if (action === 'order-notification') {
        return await sendOrderNotification(data, env.RESEND_API_KEY);
      } else if (action === 'customer-confirmation') {
        return await sendCustomerConfirmation(data, env.RESEND_API_KEY);
      } else if (action === 'report') {
        return await sendReport(data, env.RESEND_API_KEY);
      } else {
        return new Response(
          JSON.stringify({ error: 'Invalid action' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }
    } catch (error) {
      return new Response(
        JSON.stringify({ error: error.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }
  },
};

async function sendOrderNotification(data, apiKey) {
  const { orderNo, table, items, subtotal, timestamp, merchantName, dashboardUrl, toEmail } = data;

  const html = orderNotificationTemplate({
    orderNo, table, items, subtotal, timestamp, merchantName, dashboardUrl
  });

  const response = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: FROM_EMAIL,
      to: toEmail,
      subject: `🔔 New Order ${orderNo}${table ? ` - Table ${table}` : ''}`,
      html,
    }),
  });

  const result = await response.json();

  if (!response.ok) {
    return new Response(
      JSON.stringify({ success: false, error: result.message || 'Failed to send email' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }

  return new Response(
    JSON.stringify({ success: true, messageId: result.id }),
    { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
  );
}

async function sendReport(data, apiKey) {
  const {
    merchantName, dateRange, totalOrders, totalRevenue,
    servedOrders, cancelledOrders, averageOrder,
    topItems, ordersByStatus, toEmail
  } = data;

  const html = reportTemplate({
    merchantName, dateRange, totalOrders, totalRevenue,
    servedOrders, cancelledOrders, averageOrder, topItems, ordersByStatus
  });

  const response = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: FROM_EMAIL,
      to: toEmail,
      subject: `📊 Sales Report - ${dateRange}`,
      html,
    }),
  });

  const result = await response.json();

  if (!response.ok) {
    return new Response(
      JSON.stringify({ success: false, error: result.message || 'Failed to send email' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }

  return new Response(
    JSON.stringify({ success: true, messageId: result.id }),
    { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
  );
}

async function sendCustomerConfirmation(data, apiKey) {
  const { orderNo, table, items, subtotal, timestamp, merchantName, estimatedTime, toEmail } = data;

  const html = customerConfirmationTemplate({
    orderNo, table, items, subtotal, timestamp, merchantName, estimatedTime
  });

  const response = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: FROM_EMAIL,
      to: toEmail,
      subject: `✅ Order Confirmed ${orderNo} - ${merchantName}`,
      html,
    }),
  });

  const result = await response.json();

  if (!response.ok) {
    return new Response(
      JSON.stringify({ success: false, error: result.message || 'Failed to send email' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }

  return new Response(
    JSON.stringify({ success: true, messageId: result.id }),
    { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
  );
}

function orderNotificationTemplate(data) {
  const itemsHtml = data.items
    .map(item => `
      <tr>
        <td style="padding: 8px; border-bottom: 1px solid #eee;">
          ${item.name} ${item.qty > 1 ? `(x${item.qty})` : ''}
          ${item.note ? `<br/><span style="font-size: 12px; color: #666;">Note: ${item.note}</span>` : ''}
        </td>
        <td style="padding: 8px; border-bottom: 1px solid #eee; text-align: right;">
          ${item.price.toFixed(3)} BHD
        </td>
      </tr>
    `)
    .join('');

  return `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 0; padding: 20px; background-color: #f5f5f5;">
  <div style="max-width: 600px; margin: 0 auto; background: white; border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.1);">
    <div style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 24px; border-radius: 8px 8px 0 0;">
      <h1 style="margin: 0; font-size: 24px;">🔔 New Order Received!</h1>
      <p style="margin: 8px 0 0 0; opacity: 0.9;">You have a new order at ${data.merchantName}</p>
    </div>
    <div style="padding: 24px;">
      <div style="background: #f8f9fa; padding: 16px; border-radius: 6px; margin-bottom: 20px;">
        <h2 style="margin: 0 0 12px 0; font-size: 18px; color: #333;">Order Details</h2>
        <table style="width: 100%;">
          <tr>
            <td style="padding: 4px 0; color: #666;">Order Number:</td>
            <td style="padding: 4px 0; text-align: right; font-weight: 600; color: #667eea;">${data.orderNo}</td>
          </tr>
          ${data.table ? `
          <tr>
            <td style="padding: 4px 0; color: #666;">Table:</td>
            <td style="padding: 4px 0; text-align: right; font-weight: 600;">${data.table}</td>
          </tr>
          ` : ''}
          <tr>
            <td style="padding: 4px 0; color: #666;">Time:</td>
            <td style="padding: 4px 0; text-align: right;">${data.timestamp}</td>
          </tr>
          <tr>
            <td style="padding: 4px 0; color: #666;">Status:</td>
            <td style="padding: 4px 0; text-align: right;">
              <span style="background: #fef3c7; color: #92400e; padding: 4px 12px; border-radius: 12px; font-size: 12px; font-weight: 600;">
                PENDING
              </span>
            </td>
          </tr>
        </table>
      </div>
      <h3 style="margin: 0 0 12px 0; font-size: 16px; color: #333;">Items</h3>
      <table style="width: 100%; border-collapse: collapse;">
        ${itemsHtml}
        <tr>
          <td style="padding: 16px 8px 8px 8px; font-weight: 600; font-size: 16px;">Subtotal</td>
          <td style="padding: 16px 8px 8px 8px; text-align: right; font-weight: 600; font-size: 16px; color: #667eea;">
            ${data.subtotal.toFixed(3)} BHD
          </td>
        </tr>
      </table>
      <div style="margin-top: 24px; text-align: center;">
        <a href="${data.dashboardUrl}" style="display: inline-block; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; text-decoration: none; padding: 12px 32px; border-radius: 6px; font-weight: 600;">
          View in Dashboard →
        </a>
      </div>
    </div>
    <div style="padding: 16px 24px; background: #f8f9fa; border-radius: 0 0 8px 8px; text-align: center; color: #666; font-size: 12px;">
      <p style="margin: 0;">This is an automated notification from SweetWeb</p>
    </div>
  </div>
</body>
</html>
  `;
}

function reportTemplate(data) {
  const topItemsHtml = data.topItems
    .slice(0, 5)
    .map((item, idx) => `
      <tr>
        <td style="padding: 8px; border-bottom: 1px solid #eee;">${idx + 1}. ${item.name}</td>
        <td style="padding: 8px; border-bottom: 1px solid #eee; text-align: center;">${item.count}</td>
        <td style="padding: 8px; border-bottom: 1px solid #eee; text-align: right;">${item.revenue.toFixed(3)} BHD</td>
      </tr>
    `)
    .join('');

  const statusHtml = data.ordersByStatus
    .map(s => `
      <div style="margin-bottom: 8px;">
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 4px;">
          <span style="font-size: 14px; text-transform: capitalize;">${s.status}</span>
          <span style="font-weight: 600;">${s.count}</span>
        </div>
        <div style="background: #e5e7eb; height: 8px; border-radius: 4px; overflow: hidden;">
          <div style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); height: 100%; width: ${(s.count / data.totalOrders) * 100}%;"></div>
        </div>
      </div>
    `)
    .join('');

  return `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 0; padding: 20px; background-color: #f5f5f5;">
  <div style="max-width: 700px; margin: 0 auto; background: white; border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.1);">
    <div style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 24px; border-radius: 8px 8px 0 0;">
      <h1 style="margin: 0; font-size: 24px;">📊 Sales Report</h1>
      <p style="margin: 8px 0 0 0; opacity: 0.9;">${data.merchantName} • ${data.dateRange}</p>
    </div>
    <div style="padding: 24px;">
      <div style="display: grid; grid-template-columns: repeat(2, 1fr); gap: 16px; margin-bottom: 24px;">
        <div style="background: #f0fdf4; padding: 16px; border-radius: 6px; border-left: 4px solid #22c55e;">
          <div style="font-size: 12px; color: #166534; font-weight: 600; margin-bottom: 4px;">TOTAL REVENUE</div>
          <div style="font-size: 24px; font-weight: 700; color: #15803d;">${data.totalRevenue.toFixed(3)} BHD</div>
        </div>
        <div style="background: #eff6ff; padding: 16px; border-radius: 6px; border-left: 4px solid #3b82f6;">
          <div style="font-size: 12px; color: #1e40af; font-weight: 600; margin-bottom: 4px;">TOTAL ORDERS</div>
          <div style="font-size: 24px; font-weight: 700; color: #1e3a8a;">${data.totalOrders}</div>
        </div>
        <div style="background: #fef3c7; padding: 16px; border-radius: 6px; border-left: 4px solid #f59e0b;">
          <div style="font-size: 12px; color: #92400e; font-weight: 600; margin-bottom: 4px;">AVG ORDER VALUE</div>
          <div style="font-size: 24px; font-weight: 700; color: #b45309;">${data.averageOrder.toFixed(3)} BHD</div>
        </div>
        <div style="background: #fef2f2; padding: 16px; border-radius: 6px; border-left: 4px solid #ef4444;">
          <div style="font-size: 12px; color: #991b1b; font-weight: 600; margin-bottom: 4px;">CANCELLED</div>
          <div style="font-size: 24px; font-weight: 700; color: #b91c1c;">${data.cancelledOrders}</div>
        </div>
      </div>
      <div style="margin-bottom: 24px;">
        <h2 style="margin: 0 0 12px 0; font-size: 18px; color: #333;">🏆 Top Selling Items</h2>
        <table style="width: 100%; border-collapse: collapse;">
          <thead>
            <tr style="background: #f8f9fa;">
              <th style="padding: 8px; text-align: left; font-size: 12px; color: #666;">Item</th>
              <th style="padding: 8px; text-align: center; font-size: 12px; color: #666;">Orders</th>
              <th style="padding: 8px; text-align: right; font-size: 12px; color: #666;">Revenue</th>
            </tr>
          </thead>
          <tbody>
            ${topItemsHtml}
          </tbody>
        </table>
      </div>
      <div style="margin-bottom: 24px;">
        <h2 style="margin: 0 0 12px 0; font-size: 18px; color: #333;">📈 Orders by Status</h2>
        ${statusHtml}
      </div>
    </div>
    <div style="padding: 16px 24px; background: #f8f9fa; border-radius: 0 0 8px 8px; text-align: center; color: #666; font-size: 12px;">
      <p style="margin: 0;">Generated by SweetWeb</p>
    </div>
  </div>
</body>
</html>
  `;
}

function customerConfirmationTemplate(data) {
  const itemsHtml = data.items
    .map(item => `
      <tr>
        <td style="padding: 12px 8px; border-bottom: 1px solid #eee;">
          <div style="font-weight: 500; margin-bottom: 4px;">${item.name}</div>
          ${item.note ? `<div style="font-size: 12px; color: #666; font-style: italic;">Note: ${item.note}</div>` : ''}
        </td>
        <td style="padding: 12px 8px; border-bottom: 1px solid #eee; text-align: center; color: #666;">
          x${item.qty}
        </td>
        <td style="padding: 12px 8px; border-bottom: 1px solid #eee; text-align: right; font-weight: 500;">
          ${item.price.toFixed(3)} BHD
        </td>
      </tr>
    `)
    .join('');

  return `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 0; padding: 20px; background-color: #f5f5f5;">
  <div style="max-width: 600px; margin: 0 auto; background: white; border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.1);">
    <!-- Header -->
    <div style="background: linear-gradient(135deg, #10b981 0%, #059669 100%); color: white; padding: 32px 24px; border-radius: 8px 8px 0 0; text-align: center;">
      <div style="font-size: 48px; margin-bottom: 8px;">✅</div>
      <h1 style="margin: 0; font-size: 28px; font-weight: 700;">Order Confirmed!</h1>
      <p style="margin: 12px 0 0 0; opacity: 0.95; font-size: 16px;">Thank you for your order</p>
    </div>

    <!-- Content -->
    <div style="padding: 32px 24px;">
      <!-- Order Info -->
      <div style="background: #f0fdf4; padding: 20px; border-radius: 8px; margin-bottom: 24px; border-left: 4px solid #10b981;">
        <table style="width: 100%;">
          <tr>
            <td style="padding: 6px 0; color: #666; font-size: 14px;">Order Number:</td>
            <td style="padding: 6px 0; text-align: right; font-weight: 700; font-size: 18px; color: #059669;">${data.orderNo}</td>
          </tr>
          <tr>
            <td style="padding: 6px 0; color: #666; font-size: 14px;">Restaurant:</td>
            <td style="padding: 6px 0; text-align: right; font-weight: 600; color: #333;">${data.merchantName}</td>
          </tr>
          ${data.table ? `
          <tr>
            <td style="padding: 6px 0; color: #666; font-size: 14px;">Table Number:</td>
            <td style="padding: 6px 0; text-align: right; font-weight: 600; color: #333;">${data.table}</td>
          </tr>
          ` : ''}
          <tr>
            <td style="padding: 6px 0; color: #666; font-size: 14px;">Order Time:</td>
            <td style="padding: 6px 0; text-align: right; color: #333;">${data.timestamp}</td>
          </tr>
          ${data.estimatedTime ? `
          <tr>
            <td style="padding: 6px 0; color: #666; font-size: 14px;">Estimated Time:</td>
            <td style="padding: 6px 0; text-align: right; font-weight: 600; color: #059669;">${data.estimatedTime}</td>
          </tr>
          ` : ''}
        </table>
      </div>

      <!-- Order Status -->
      <div style="text-align: center; margin-bottom: 24px;">
        <div style="display: inline-block; background: #fef3c7; color: #92400e; padding: 12px 24px; border-radius: 24px; font-weight: 600; font-size: 14px;">
          🕐 Your order is being prepared
        </div>
      </div>

      <!-- Items -->
      <h2 style="margin: 0 0 16px 0; font-size: 18px; color: #333; padding-bottom: 8px; border-bottom: 2px solid #f3f4f6;">Order Details</h2>
      <table style="width: 100%; border-collapse: collapse; margin-bottom: 20px;">
        <thead>
          <tr style="background: #f9fafb;">
            <th style="padding: 10px 8px; text-align: left; font-size: 13px; color: #6b7280; font-weight: 600;">Item</th>
            <th style="padding: 10px 8px; text-align: center; font-size: 13px; color: #6b7280; font-weight: 600;">Qty</th>
            <th style="padding: 10px 8px; text-align: right; font-size: 13px; color: #6b7280; font-weight: 600;">Price</th>
          </tr>
        </thead>
        <tbody>
          ${itemsHtml}
        </tbody>
      </table>

      <!-- Total -->
      <div style="background: #f9fafb; padding: 20px; border-radius: 8px; margin-bottom: 24px;">
        <div style="display: flex; justify-content: space-between; align-items: center;">
          <span style="font-size: 18px; font-weight: 600; color: #333;">Total Amount</span>
          <span style="font-size: 24px; font-weight: 700; color: #059669;">${data.subtotal.toFixed(3)} BHD</span>
        </div>
      </div>

      <!-- Thank You Message -->
      <div style="text-align: center; padding: 24px; background: linear-gradient(135deg, #f0fdf4 0%, #dcfce7 100%); border-radius: 8px;">
        <p style="margin: 0 0 8px 0; font-size: 16px; color: #333; font-weight: 500;">Thank you for choosing ${data.merchantName}!</p>
        <p style="margin: 0; font-size: 14px; color: #666;">We're preparing your order with care</p>
      </div>
    </div>

    <!-- Footer -->
    <div style="padding: 20px 24px; background: #f9fafb; border-radius: 0 0 8px 8px; text-align: center; color: #6b7280; font-size: 12px; border-top: 1px solid #e5e7eb;">
      <p style="margin: 0 0 8px 0;">This is an automated confirmation email from SweetWeb</p>
      <p style="margin: 0; color: #9ca3af;">Please do not reply to this email</p>
    </div>
  </div>
</body>
</html>
  `;
}
