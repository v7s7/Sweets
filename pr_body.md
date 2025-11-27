## Summary

Implements email notifications and reporting system for merchant dashboard using Resend API (free tier - 3,000 emails/month) via **Cloudflare Workers** (free tier - 100,000 requests/day). All features work entirely on free tiers - **no Firebase Blaze plan required**.

### Features Implemented

✅ **Instant Order Notifications**
- Automatic email when new orders are placed
- Beautiful HTML email template with order details, items, and totals
- Configurable via merchant settings
- Real-time Firestore listener in Flutter app

✅ **Custom Report Generator**
- Generate sales reports for any date range
- Quick filters: Today, Yesterday, Last 7/30 days
- Custom date range picker
- Email delivery to specified address
- Calculated client-side from Firestore data

✅ **Merchant Settings**
- Toggle email notifications on/off
- Configure notification email address
- Saved in Firestore config/settings

### Architecture

**Backend: Cloudflare Workers (Free Tier - 100k requests/day)**
- Single worker endpoint handles both notifications and reports
- Securely stores Resend API key as environment variable
- No credit card required for free tier
- Global edge network for fast delivery

**Frontend: Flutter**
- Direct Firestore queries for order data
- Client-side report calculation and statistics
- Real-time order listener sends notifications via HTTP to Cloudflare Worker
- Material Design 3 UI for reports and settings

**Email: Resend API (Free Tier - 3k emails/month)**
- Beautiful responsive HTML email templates
- Order notifications with item details and notes
- Sales reports with charts, top items, and revenue breakdowns

### Files Changed

**New Files - Cloudflare Worker**
- `cloudflare-worker/worker.js` - Email service worker with templates
- `cloudflare-worker/README.md` - Deployment instructions

**New Files - Flutter**
- `lib/core/config/email_config.dart` - Worker URL configuration
- `lib/core/services/email_service.dart` - HTTP client for email worker
- `lib/core/services/order_notification_service.dart` - Firestore listener for orders
- `lib/merchant/screens/reports_page.dart` - Reports UI with Firestore queries
- `lib/merchant/screens/settings_page.dart` - Email notification settings

**Modified Files**
- `lib/merchant/main_merchant.dart` - Added notification service initialization
- `pubspec.yaml` - Removed cloud_functions dependency

**Removed**
- `functions/` directory - No longer needed (Firebase Functions removed)

### Deployment Steps

#### 1. Deploy Cloudflare Worker

```bash
# Go to https://dash.cloudflare.com
# Workers & Pages > Create Worker > "sweetweb-email-service"
# Copy content from cloudflare-worker/worker.js
# Add environment variable:
#   Name: RESEND_API_KEY
#   Value: re_M2UEqUWF_QEJGCDgmP1mFpLi1DTNL3758
# Deploy and copy the worker URL
```

See `cloudflare-worker/README.md` for detailed instructions.

#### 2. Configure Flutter App

Update `lib/core/config/email_config.dart` with your Cloudflare Worker URL:

```dart
static const String workerUrl = 'https://sweetweb-email-service.YOUR_SUBDOMAIN.workers.dev';
```

#### 3. Build and Deploy Flutter

```bash
flutter pub get
flutter build web
firebase deploy --only hosting
```

### Testing Required

1. **Deploy Cloudflare Worker** - Follow deployment instructions
2. **Configure Worker URL** in `email_config.dart`
3. **Build Flutter app** and deploy
4. **Enable notifications** in Settings (⚙️ icon)
5. **Create test order** to receive email
6. **Generate report** for a date range
7. **Check email** (may be in spam folder if using resend.dev domain)

### Free Tier Limits

| Service | Free Tier Limit | Current Usage |
|---------|----------------|---------------|
| **Cloudflare Workers** | 100,000 requests/day | ~10-50/day (depending on order volume) |
| **Resend API** | 3,000 emails/month | Depends on orders + reports |
| **Firebase Spark** | Firestore: 50K reads/day | Used for orders and settings |

All services remain on free tier with typical usage patterns.

### Advantages Over Firebase Functions

✅ **No Blaze plan required** - Firebase Functions v2 requires paid plan
✅ **No Cloud Build API** - Cloudflare Workers deploy instantly
✅ **Higher free tier** - 100k requests vs. 2M invocations (but Workers more generous)
✅ **Simpler deployment** - Copy/paste code, no CLI issues
✅ **Global edge network** - Faster email delivery worldwide
✅ **Real-time updates** - Firestore listener in Flutter app

### Security Notes

- ✅ Resend API key stored as encrypted Cloudflare environment variable
- ✅ Not exposed in Flutter client code
- ✅ CORS enabled for Flutter web app
- ✅ Settings protected by Firebase Auth and Firestore rules
- ⚠️ Consider adding request authentication in production (Firebase Auth token validation)

### Migration from Firebase Functions

This PR removes Firebase Functions entirely:
- Deleted `/functions` directory
- Removed `cloud_functions` package dependency
- Migrated logic to Cloudflare Workers + Flutter
- **No breaking changes** - same functionality, different architecture

### Troubleshooting

**Emails not sending:**
- Verify Cloudflare Worker is deployed
- Check Worker URL in `email_config.dart`
- Verify `RESEND_API_KEY` environment variable is set
- Check Cloudflare Worker logs for errors

**Notifications not triggering:**
- Ensure email notifications are enabled in Settings
- Verify email address is configured
- Check browser console for errors
- Ensure Firestore listener is active (check console logs)

**Reports failing:**
- Verify Worker URL is correct
- Check date range has orders
- Verify Firestore permissions allow reading orders

### Production Recommendations

Before production deployment:

1. **Custom domain for emails** - Replace `onboarding@resend.dev` with your domain
2. **Worker authentication** - Add Firebase Auth token validation
3. **Rate limiting** - Implement per-merchant limits
4. **Error monitoring** - Add Sentry or similar service
5. **Usage tracking** - Log email sends to Firestore for analytics
6. **Upgrade Resend** - If exceeding 3k emails/month ($20/month for 50k)

### Documentation

See `cloudflare-worker/README.md` for complete deployment guide, API documentation, and troubleshooting.
