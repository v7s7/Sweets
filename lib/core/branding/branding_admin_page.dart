// lib/core/branding/branding_admin_page.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'branding.dart';
import 'branding_providers.dart';

/// App host for the customer menu link (query params only).
const String kAppHost =
    String.fromEnvironment('APP_HOST', defaultValue: 'https://localhost');

/// Cloudinary (unsigned) config for logo uploads.
const String _kCloudName = 'dkirkzbfa';
const String _kUnsignedPreset = 'unsigned_products';

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
  final _note = TextEditingController(
      text: 'Nutrition values are approximate.'); // admin-editable sentence

  bool _dirty = false; // branding text/color/note edited by user
  String? _logoUrl; // local preview; persisted to Firestore

  @override
  void initState() {
    super.initState();
    for (final c in [_title, _header, _primary, _secondary, _note]) {
      c.addListener(() => _dirty = true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // One-time initial population (no asserts; ref.read is safe here).
    final b = ref.read(brandingProvider).maybeWhen(
          data: (v) => v,
          orElse: () => null,
        );
    if (b != null && !_dirty) {
      _applyBrandingToFields(b);
      _logoUrl ??= b.logoUrl;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _header.dispose();
    _primary.dispose();
    _secondary.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = ref.watch(merchantIdProvider);
    final br = ref.watch(branchIdProvider);
    final repo = ref.watch(brandingRepoProvider);

    // Live branding stream (keeps fields/logo persistent across restarts)
    ref.listen<AsyncValue<Branding>>(brandingProvider, (prev, next) {
      next.whenOrNull(data: (b) {
        // Do not overwrite user's current typing.
        if (!_dirty) _applyBrandingToFields(b);
        // Keep preview if user hasn't just uploaded in this session.
        _logoUrl ??= b.logoUrl;
        setState(() {}); // refresh preview if needed
      });
    });

    final brandingRef = FirebaseFirestore.instance
        .collection('merchants')
        .doc(m)
        .collection('branches')
        .doc(br)
        .collection('config')
        .doc('branding');

    final menuUrl = '$kAppHost/#/?m=$m&b=$br';

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
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(
              labelText:
                  'Nutrition note (shown below categories when Nutrition is open)',
              helperText: 'Example: "Nutrition values are approximate."',
            ),
            controller: _note,
            textInputAction: TextInputAction.newline,
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: const Icon(Icons.save),
            label: const Text('Save Branding'),
            onPressed: () async {
              try {
                final currentBranding =
                    ref.read(brandingProvider).maybeWhen<Branding?>(
                          data: (b) => b,
                          orElse: () => null,
                        );

                final value = Branding(
                  title:
                      _title.text.trim().isEmpty ? 'App' : _title.text.trim(),
                  headerText: _header.text.trim(),
                  primaryHex: _sanitizeHex(_primary.text),
                  secondaryHex: _sanitizeHex(_secondary.text),
                  logoUrl: _logoUrl ?? currentBranding?.logoUrl,
                  nutritionNote: _note.text.trim().isEmpty
                      ? 'Nutrition values are approximate.'
                      : _note.text.trim(),
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

          // -------------------- Logo (click to upload) --------------------
          Text(
            'Logo',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          _LogoCard(
            url: _logoUrl,
            onTap: () => _onPickAndUploadLogo(brandingRef),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.upload),
                label: const Text('Upload / Replace Logo'),
                onPressed: () => _onPickAndUploadLogo(brandingRef),
              ),
              const SizedBox(width: 12),
              if (_logoUrl != null && _logoUrl!.isNotEmpty)
                OutlinedButton.icon(
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove Logo'),
                  onPressed: () async {
                    await brandingRef.set({'logoUrl': FieldValue.delete()},
                        SetOptions(merge: true));
                    setState(() => _logoUrl = null);
                  },
                ),
            ],
          ),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),

          // -------------------- Copy Menu Link (no pretty URLs) --------------------
          Text(
            'Copy Menu Link',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          SelectableText(menuUrl),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text('Copy'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: menuUrl));
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Link copied')),
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
    _note.text = b.nutritionNote;
  }

  Future<void> _onPickAndUploadLogo(
    DocumentReference<Map<String, dynamic>> brandingRef,
  ) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true, // web & mobile
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;

    // 1) Try in-memory bytes
    Uint8List? bytes = file.bytes;

    // 2) Fallback to readStream (safe on all platforms; no dart:io)
    if (bytes == null && file.readStream != null) {
      final builder = BytesBuilder(copy: false);
      await for (final chunk in file.readStream!) {
        builder.add(chunk);
      }
      bytes = builder.takeBytes();
    }

    if (bytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not read selected file')),
      );
      return;
    }

    if (_kCloudName.isEmpty || _kUnsignedPreset.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Cloudinary not configured. Set CLOUDINARY_CLOUD & CLOUDINARY_PRESET.'),
        ),
      );
      return;
    }

    try {
      final url = await _uploadToCloudinary(bytes, filename: file.name);
      await brandingRef.set({'logoUrl': url}, SetOptions(merge: true));
      setState(() => _logoUrl = url);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Logo uploaded')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e')),
      );
    }
  }

  Future<String> _uploadToCloudinary(Uint8List bytes, {String? filename}) async {
    final uri =
        Uri.parse('https://api.cloudinary.com/v1_1/$_kCloudName/image/upload');

    final req = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = _kUnsignedPreset
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: filename ?? 'logo.png',
      ));

    final res = await req.send();
    final body = await http.Response.fromStream(res);
    if (body.statusCode >= 200 && body.statusCode < 300) {
      final Map<String, dynamic> json = jsonDecode(body.body);
      return (json['secure_url'] ?? json['url']) as String;
    }
    throw Exception('HTTP ${body.statusCode}: ${body.body}');
  }

  String _sanitizeHex(String raw) {
    var s = raw.trim();
    if (s.isEmpty) throw Exception('Color cannot be empty');
    if (!s.startsWith('#')) s = '#$s';
    s = s.toUpperCase();
    if (s.length == 7 || s.length == 9) return s;
    throw Exception('Use #RRGGBB or #AARRGGBB for colors');
  }
}

class _LogoCard extends StatelessWidget {
  final String? url;
  final VoidCallback onTap;
  const _LogoCard({required this.url, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return InkWell(
      onTap: onTap, // opens picker immediately
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 96,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: onSurface.withOpacity(0.15)),
          color: onSurface.withOpacity(0.04),
        ),
        alignment: Alignment.center,
        child: url != null && url!.isNotEmpty
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  url!,
                  height: 72,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      Icon(Icons.image_not_supported, color: onSurface),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_photo_alternate_outlined,
                      color: onSurface.withOpacity(0.8)),
                  const SizedBox(width: 8),
                  Text('Tap to upload logo',
                      style: TextStyle(
                        color: onSurface.withOpacity(0.8),
                        fontWeight: FontWeight.w600,
                      )),
                ],
              ),
      ),
    );
  }
}
