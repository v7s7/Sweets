// lib/core/branding/branding_admin_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'branding.dart';
import 'branding_providers.dart';

/// Public app host used in the share link
const String kAppHost =
    String.fromEnvironment('APP_HOST', defaultValue: 'https://your.app');

class BrandingAdminPage extends ConsumerStatefulWidget {
  const BrandingAdminPage({super.key});
  @override
  ConsumerState<BrandingAdminPage> createState() => _BrandingAdminPageState();
}

class _BrandingAdminPageState extends ConsumerState<BrandingAdminPage> {
  final _title = TextEditingController();
  final _header = TextEditingController();
  final _primary = TextEditingController(text: '#E91E63');
  final _secondary = TextEditingController(text: '#FFB300');

  // Slug editor
  final _slug = TextEditingController();

  bool _dirty = false;       // branding fields edited by user
  bool _slugDirty = false;   // slug field edited by user

  @override
  void initState() {
    super.initState();
    for (final c in [_title, _header, _primary, _secondary]) {
      c.addListener(() => _dirty = true);
    }
    _slug.addListener(() => _slugDirty = true);

    // Populate fields when branding stream emits (only if not dirty).

  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final b = ref.read(brandingProvider).maybeWhen(
          data: (v) => v,
          orElse: () => null,
        );
    if (b != null && !_dirty) _applyBrandingToFields(b);
  }

  @override
  void dispose() {
    _title.dispose();
    _header.dispose();
    _primary.dispose();
    _secondary.dispose();
    _slug.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
  ref.listen(brandingProvider, (prev, next) {
    next.maybeWhen(
      data: (b) {
        if (!_dirty) _applyBrandingToFields(b);
      },
      orElse: () {},
    );
  });
    final m = ref.watch(merchantIdProvider);
    final br = ref.watch(branchIdProvider);
    final repo = ref.watch(brandingRepoProvider);

    // Live branding doc to read/write shareSlug
    final brandingRef = FirebaseFirestore.instance
        .collection('merchants').doc(m)
        .collection('branches').doc(br)
        .collection('config').doc('branding');

    return Scaffold(
      appBar: AppBar(title: const Text('Branding Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // -------------------- Visual Branding --------------------
          TextField(
            decoration: const InputDecoration(labelText: 'App Title'),
            controller: _title,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(labelText: 'Header Text'),
            controller: _header,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Primary Color (#RRGGBB or #AARRGGBB)',
            ),
            controller: _primary,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F#]')),
              LengthLimitingTextInputFormatter(9),
            ],
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Secondary Color (#RRGGBB or #AARRGGBB)',
            ),
            controller: _secondary,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F#]')),
              LengthLimitingTextInputFormatter(9),
            ],
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: const Icon(Icons.save),
            label: const Text('Save Branding'),
            onPressed: () async {
              try {
                final value = Branding(
                  title: _title.text.trim().isEmpty ? 'App' : _title.text.trim(),
                  headerText: _header.text.trim(),
                  primaryHex: _sanitizeHex(_primary.text),
                  secondaryHex: _sanitizeHex(_secondary.text),
                );
                await repo.save(m, br, value);
                _dirty = false;
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Branding saved')),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(e.toString())),
                );
              }
            },
          ),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),

          // -------------------- Public Link / Slug --------------------
          Text(
            'Public Link (Pretty URL)',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),

          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: brandingRef.snapshots(),
            builder: (context, snap) {
              final data = snap.data?.data();
              final shareSlug = (data?['shareSlug'] as String?)?.trim() ?? '';

              if (!_slugDirty && shareSlug.isNotEmpty && _slug.text != shareSlug) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && !_slugDirty) _slug.text = shareSlug;
                });
              }

              final url = _buildShareUrl(
                merchantId: m,
                branchId: br,
                slug: _slug.text.trim().isNotEmpty ? _slug.text.trim() : shareSlug,
              );

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _slug,
                    decoration: const InputDecoration(
                      labelText: 'Public link slug (e.g., donuts-budaiya)',
                      helperText:
                          'Customers will use https://…/s/<slug>. Must be 3–32 lowercase letters, numbers, or hyphens.',
                    ),
                    textInputAction: TextInputAction.done,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.link),
                        label: const Text('Save Slug'),
                        onPressed: () async {
                          final raw = _slug.text.trim();
                          if (raw.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Slug cannot be empty')),
                            );
                            return;
                          }
                          try {
                            final norm = _normalizeSlug(raw);
                            await _reserveSlugClientTx(
                              merchantId: m,
                              branchId: br,
                              normSlug: norm,
                            );
                            _slugDirty = false;
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Slug saved')),
                            );
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(e.toString())),
                            );
                          }
                        },
                      ),
                      const SizedBox(width: 12),
                      if (url != null)
                        OutlinedButton.icon(
                          icon: const Icon(Icons.copy),
                          label: const Text('Copy Public Link'),
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: url));
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Link copied')),
                            );
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (url != null) ...[
                    const Text('Public URL:', style: TextStyle(fontWeight: FontWeight.w700)),
                    SelectableText(url),
                  ] else ...[
                    Text(
                      'No slug yet. Customers can still use the fallback query link below.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Text('Fallback (query) link:', style: TextStyle(fontWeight: FontWeight.w700)),
                  SelectableText(_buildQueryLink(m, br)),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.copy_all),
                    label: const Text('Copy Fallback Link'),
                    onPressed: () async {
                      final q = _buildQueryLink(m, br);
                      await Clipboard.setData(ClipboardData(text: q));
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Fallback link copied')),
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  void _applyBrandingToFields(Branding b) {
    _title.text = b.title;
    _header.text = b.headerText;
    _primary.text = b.primaryHex;
    _secondary.text = b.secondaryHex;
  }

  /// Firestore client transaction to reserve/update slug without Cloud Functions.
  Future<void> _reserveSlugClientTx({
    required String merchantId,
    required String branchId,
    required String normSlug,
  }) async {
    final fs = FirebaseFirestore.instance;

    final brandingRef = fs
        .collection('merchants').doc(merchantId)
        .collection('branches').doc(branchId)
        .collection('config').doc('branding');

    final newSlugRef = fs.doc('slugs/$normSlug');
    final branchRef = fs.doc('merchants/$merchantId/branches/$branchId');

    await fs.runTransaction((tx) async {
      final brandingSnap = await tx.get(brandingRef);
      final prevSlug = brandingSnap.exists
          ? (brandingSnap.data()?['shareSlug'] as String?)
          : null;

      final newSlugSnap = await tx.get(newSlugRef);

      if (newSlugSnap.exists) {
        final d = newSlugSnap.data()!;
        final same =
            d['merchantId'] == merchantId && d['branchId'] == branchId;
        if (!same) {
          throw Exception('Slug already taken.');
        }
        // If same mapping, idempotent update continues.
      }

      // Free previous slug if changed
      if (prevSlug != null && prevSlug.isNotEmpty && prevSlug != normSlug) {
        tx.delete(fs.doc('slugs/$prevSlug'));
      }

      // Reserve/refresh slug
      tx.set(newSlugRef, {
        'merchantId': merchantId,
        'branchId': branchId,
        'active': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Write slug into branding
      tx.set(brandingRef, {'shareSlug': normSlug},
          SetOptions(merge: true));

      // Optional mirror on branch doc (matches your screenshot)
      tx.set(
        branchRef,
        {'slug': normSlug, 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    });
  }

  /// Normalize & validate slug (client-side).
  String _normalizeSlug(String s) {
    final trimmed = (s).toLowerCase().trim();
    final norm = trimmed
        .replaceAll(RegExp('[^a-z0-9-]'), '-')
        .replaceAll(RegExp('-+'), '-')
        .replaceAll(RegExp('^-|-\$'), '');
    if (norm.length < 3 || norm.length > 32) {
      throw Exception('Slug must be 3–32 characters.');
    }
    const reserved = {
      'admin','api','app','assets','s','m','b',
      'login','signup','merchant','console'
    };
    if (reserved.contains(norm)) {
      throw Exception('Slug is reserved.');
    }
    return norm;
  }

  /// Pretty link if `slug` present; else null.
  String? _buildShareUrl({
    required String merchantId,
    required String branchId,
    String? slug,
  }) {
    if (merchantId.isEmpty || branchId.isEmpty) return null;
    final s = (slug ?? '').trim();
    if (s.isEmpty) return null;
    return '$kAppHost/#/s/$s';
  }

  /// Stable query link: https://<host>/#/?m=<m>&b=<b>
  String _buildQueryLink(String m, String br) {
    if (m.isEmpty || br.isEmpty) return '';
    return '$kAppHost/#/?m=$m&b=$br';
  }

  /// Normalize & validate hex color input.
  String _sanitizeHex(String raw) {
    var s = raw.trim();
    if (s.isEmpty) throw Exception('Color cannot be empty');
    if (!s.startsWith('#')) s = '#$s';
    s = s.toUpperCase();
    if (s.length == 7 || s.length == 9) return s;
    throw Exception('Use #RRGGBB or #AARRGGBB for colors');
  }
}
