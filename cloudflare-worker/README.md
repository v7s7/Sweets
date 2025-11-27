# Cloudflare Worker for SweetWeb Email Service

This worker handles email notifications and report generation using the Resend API, deployed on Cloudflare's free tier (100,000 requests/day).

## Why Cloudflare Workers?

- ✅ **Free tier**: 100,000 requests per day
- ✅ **No credit card required** for free tier
- ✅ **Fast global deployment**: Edge network
- ✅ **Secure**: API key stored as environment variable
- ✅ **No Firebase Blaze plan needed**

## Deployment Steps

### 1. Create Cloudflare Account

1. Go to https://dash.cloudflare.com/sign-up
2. Create a free account (no credit card required)
3. Verify your email

### 2. Deploy the Worker

**Option A: Dashboard (Easiest)**

1. Go to https://dash.cloudflare.com
2. Click **Workers & Pages** in the left sidebar
3. Click **Create application** > **Create Worker**
4. Name it: `sweetweb-email-service`
5. Click **Deploy**
6. Click **Edit code**
7. Delete all existing code
8. Copy and paste the entire content of `worker.js`
9. Click **Save and Deploy**

**Option B: CLI (Advanced)**

```bash
# Install Wrangler CLI
npm install -g wrangler

# Login
wrangler login

# Deploy
cd cloudflare-worker
wrangler deploy
```

### 3. Add Environment Variable

1. In the Cloudflare dashboard, go to your worker
2. Click **Settings** tab
3. Scroll to **Environment Variables**
4. Click **Add variable**
   - **Variable name**: `RESEND_API_KEY`
   - **Value**: `re_M2UEqUWF_QEJGCDgmP1mFpLi1DTNL3758`
   - Click **Encrypt** (recommended)
5. Click **Save and deploy**

### 4. Get Your Worker URL

Your worker will be deployed at:
```
https://sweetweb-email-service.YOUR_SUBDOMAIN.workers.dev
```

Copy this URL - you'll need it for the Flutter app configuration.

### 5. Test the Worker

Test with curl:

```bash
# Test order notification
curl -X POST https://sweetweb-email-service.YOUR_SUBDOMAIN.workers.dev \
  -H "Content-Type: application/json" \
  -d '{
    "action": "order-notification",
    "data": {
      "orderNo": "A-001",
      "table": "5",
      "items": [{"name": "Test Item", "qty": 2, "price": 1.5}],
      "subtotal": 3.0,
      "timestamp": "2025-01-15 10:30 AM",
      "merchantName": "Test Restaurant",
      "dashboardUrl": "https://sweetweb.web.app/merchant",
      "toEmail": "your-email@example.com"
    }
  }'
```

You should receive:
```json
{"success": true, "messageId": "..."}
```

## API Endpoints

### POST /

**Order Notification**
```json
{
  "action": "order-notification",
  "data": {
    "orderNo": "A-001",
    "table": "5",
    "items": [
      {
        "name": "Product Name",
        "qty": 2,
        "price": 1.500,
        "note": "Optional note"
      }
    ],
    "subtotal": 3.000,
    "timestamp": "2025-01-15 10:30 AM",
    "merchantName": "Store Name",
    "dashboardUrl": "https://sweetweb.web.app/merchant",
    "toEmail": "merchant@example.com"
  }
}
```

**Report Generation**
```json
{
  "action": "report",
  "data": {
    "merchantName": "Store Name",
    "dateRange": "1/1/2025 - 1/15/2025",
    "totalOrders": 50,
    "totalRevenue": 150.500,
    "servedOrders": 45,
    "cancelledOrders": 5,
    "averageOrder": 3.344,
    "topItems": [
      {"name": "Item 1", "count": 20, "revenue": 60.0},
      {"name": "Item 2", "count": 15, "revenue": 45.0}
    ],
    "ordersByStatus": [
      {"status": "served", "count": 45},
      {"status": "cancelled", "count": 5}
    ],
    "toEmail": "merchant@example.com"
  }
}
```

## Flutter Integration

After deploying, update the Flutter app with your worker URL:

1. Create a config file: `lib/core/config/email_config.dart`
2. Add the worker URL as a constant
3. Update `ReportsPage` and order creation logic to use HTTP calls

See the updated Flutter files for implementation details.

## Monitoring & Limits

- **Free tier limits**: 100,000 requests/day
- **Monitor usage**: Cloudflare Dashboard > Workers & Pages > Your Worker > Analytics
- **Logs**: Available in real-time in the dashboard

## Security Notes

- ✅ API key is stored as an encrypted environment variable
- ✅ Not exposed in client code
- ✅ CORS enabled for your Flutter web app
- ⚠️ Consider adding authentication for production (check Firebase Auth tokens)

## Troubleshooting

**Worker not receiving requests:**
- Check the worker URL is correct
- Verify CORS is working (check browser console)

**Emails not sending:**
- Check environment variable is set correctly
- Verify Resend API key is valid
- Check worker logs in Cloudflare dashboard

**Rate limiting:**
- Free tier: 100k requests/day
- If exceeded, consider upgrading or optimizing

## Production Recommendations

For production, consider adding:
1. Firebase Auth token validation
2. Rate limiting per merchant
3. Request logging to Firestore
4. Error monitoring (e.g., Sentry)
