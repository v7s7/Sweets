/// Email service configuration
///
/// After deploying the Cloudflare Worker, update WORKER_URL with your worker's URL:
/// Example: https://sweetweb-email-service.YOUR_SUBDOMAIN.workers.dev
class EmailConfig {
  /// Cloudflare Worker URL
  ///
  /// TO CONFIGURE:
  /// 1. Deploy the worker from /cloudflare-worker/
  /// 2. Copy your worker URL from Cloudflare dashboard
  /// 3. Replace the URL below
  static const String workerUrl =
      'YOUR_WORKER_URL_HERE'; // Example: https://sweetweb-email-service.abc123.workers.dev

  /// Check if email service is configured
  static bool get isConfigured =>
      workerUrl != 'YOUR_WORKER_URL_HERE' && workerUrl.isNotEmpty;

  /// Order notification endpoint
  static String get orderNotificationEndpoint => workerUrl;

  /// Report generation endpoint
  static String get reportEndpoint => workerUrl;
}
