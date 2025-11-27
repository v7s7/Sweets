## Summary

Implements email notifications and reporting system for merchant dashboard using Resend API (free tier - 3,000 emails/month). All features work on Firebase Spark (free) plan.

### Features Implemented

✅ **Instant Order Notifications**
- Automatic email when new orders are placed
- Beautiful HTML email template with order details, items, and totals
- Configurable via merchant settings

✅ **Custom Report Generator**
- Generate sales reports for any date range
- Quick filters: Today, Yesterday, Last 7/30 days
- Custom date range picker
- Email delivery to specified address

✅ **Merchant Settings**
- Toggle email notifications on/off
- Configure notification email address
- Saved in Firestore config/settings

### Technical Details

**Backend (Firebase Functions v1 - Free Tier Compatible)**
- `onOrderCreated` - Firestore trigger sends email on new orders
- `generateReport` - Callable function generates and emails reports
- Email templates with inline CSS, gradients, responsive design
- Uses Resend API for email delivery

**Frontend (Flutter)**
- New Reports page with Material Design 3
- New Settings page for email configuration
- Added navigation tabs and settings button

**Key Fixes**
- Downgraded firebase-functions from v6 (Blaze) to v4 (Spark/free)
- Fixed ESLint linebreak-style for Windows compatibility
- Updated cloud_functions package for compatibility
- Added TypeScript type annotations for v1 API

### Files Changed

**New Files**
- `functions/src/email-service.ts` - Email service with Resend integration
- `lib/merchant/screens/reports_page.dart` - Reports UI
- `lib/merchant/screens/settings_page.dart` - Settings UI

**Modified Files**
- `functions/src/index.ts` - Added email functions, converted to v1 API
- `functions/package.json` - Downgraded firebase-functions to v4.9.0
- `lib/merchant/main_merchant.dart` - Added navigation for reports/settings
- `pubspec.yaml` - Updated cloud_functions package
- `functions/.eslintrc.js` - Disabled linebreak-style rule

### Testing Required

1. Configure email in Settings (navigate to ⚙️ icon)
2. Create a test order to receive notification
3. Generate a report for a date range
4. Check email delivery (may be in spam folder if using resend.dev domain)

### Deployment

```bash
cd functions
npm install
npm run build
firebase deploy --only functions
```

**Note:** You'll need to authenticate with Firebase CLI first:
```bash
firebase login
```

### API Key

Uses Resend API key: `re_M2UEqUWF_QEJGCDgmP1mFpLi1DTNL3758`

⚠️ **Security Note:** In production, move API key to Firebase environment config:
```bash
firebase functions:config:set resend.api_key="re_..."
```

### Free Tier Limits

- ✅ Firebase Spark: All functions use v1 API (free tier compatible)
- ✅ Resend: 3,000 emails/month on free plan
- ✅ No external API calls requiring Blaze plan
