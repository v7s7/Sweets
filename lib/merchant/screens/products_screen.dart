import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sweets_app/features/categories/screens/category_admin_page.dart';
import '../../core/branding/branding_admin_page.dart';

/// Merchant product manager (Cloudinary + Firestore).
/// Override at build time:
///   --dart-define=CLOUDINARY_CLOUD=<cloud_name>
///   --dart-define=CLOUDINARY_PRESET=<unsigned_preset>
class ProductsScreen extends StatelessWidget {
  final String merchantId;
  final String branchId;
  const ProductsScreen({
    super.key,
    required this.merchantId,
    required this.branchId,
  });

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final roleDoc = FirebaseFirestore.instance
        .doc('merchants/$merchantId/branches/$branchId/roles/$uid')
        .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: roleDoc,
      builder: (context, roleSnap) {
        if (roleSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (roleSnap.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Products')),
            body: Center(child: Text('Failed to verify access: ${roleSnap.error}')),
          );
        }
        if (!roleSnap.hasData || !roleSnap.data!.exists) {
          return Scaffold(
            appBar: AppBar(title: const Text('Products')),
            body: const Center(
              child: Text('No access. Ask the owner to grant your role.'),
            ),
          );
        }

        final itemsQuery = FirebaseFirestore.instance
            .collection('merchants').doc(merchantId)
            .collection('branches').doc(branchId)
            .collection('menuItems')
            .orderBy('sort', descending: false);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Products'),
            actions: [
              IconButton(
                tooltip: 'Branding',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BrandingAdminPage()),
                ),
                icon: const Icon(Icons.palette_outlined),
              ),
              IconButton(
                tooltip: 'Categories',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CategoryAdminPage()),
                ),
                icon: const Icon(Icons.category_outlined),
              ),
              IconButton(
                tooltip: 'Sign out',
                onPressed: () => FirebaseAuth.instance.signOut(),
                icon: const Icon(Icons.logout),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _openEditor(context, merchantId, branchId, null),
            label: const Text('Add product'),
            icon: const Icon(Icons.add),
          ),
          body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: itemsQuery.snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(child: Text('Failed to load products: ${snap.error}'));
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snap.data!.docs;
              if (docs.isEmpty) {
                return const Center(
                  child: Text('No products yet. Click “Add product”.'),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final d = docs[i];
                  final v = d.data();

                  final double price = _asDouble(v['price']);
                  final String priceStr = price.toStringAsFixed(3);
                  final String name = (v['name'] ?? d.id).toString();
                  final String imageUrl = (v['imageUrl'] ?? '').toString();
                  final String kcal = (v['calories']?.toString() ?? '').trim();
                  final subtitle = kcal.isNotEmpty
                      ? 'BHD $priceStr • $kcal kcal'
                      : 'BHD $priceStr';

                  return ListTile(
                    leading: _ProductThumb(imageUrl: imageUrl),
                    title: Text(name),
                    subtitle: Text(subtitle),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => _openEditor(context, merchantId, branchId, d),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _openEditor(
    BuildContext context,
    String m,
    String b,
    QueryDocumentSnapshot<Map<String, dynamic>>? doc,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) {
        return ProductEditorSheet(
          merchantId: m,
          branchId: b,
          existing: doc,
        );
      },
    );
  }
}

class _ProductThumb extends StatelessWidget {
  final String imageUrl;
  const _ProductThumb({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final bg = onSurface.withOpacity(0.08);
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: onSurface.withOpacity(0.12)),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl.isNotEmpty
          ? Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) {
                debugPrint('Thumbnail failed to load: $imageUrl');
                return const SizedBox.shrink();
              },
            )
          : const Icon(Icons.add_a_photo),
    );
  }
}

class ProductEditorSheet extends ConsumerStatefulWidget {
  final String merchantId;
  final String branchId;
  final QueryDocumentSnapshot<Map<String, dynamic>>? existing;
  const ProductEditorSheet({
    super.key,
    required this.merchantId,
    required this.branchId,
    this.existing,
  });

  @override
  ConsumerState<ProductEditorSheet> createState() => _ProductEditorSheetState();
}

class _ProductEditorSheetState extends ConsumerState<ProductEditorSheet> {
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _cal = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fat = TextEditingController();
  final _sugar = TextEditingController();
  final _tags = TextEditingController();

  String? _imageUrl;
  bool _busy = false;

  // Category selection
  String? _topCatId;   // parentId == null
  String? _subCatId;   // parentId == _topCatId
  bool _catInitDone = false;

  // Defaults to your account values; can be overridden with --dart-define.
  static const _cloudName =
      String.fromEnvironment('CLOUDINARY_CLOUD', defaultValue: 'dkirkzbfa');
  static const _unsignedPreset =
      String.fromEnvironment('CLOUDINARY_PRESET', defaultValue: 'unsigned_products');

  @override
  void initState() {
    super.initState();
    final v = widget.existing?.data();
    if (v != null) {
      _name.text = v['name']?.toString() ?? '';
      _price.text = (v['price'] ?? '').toString();
      _cal.text = (v['calories'] ?? '').toString();
      _protein.text = (v['protein'] ?? '').toString();
      _carbs.text = (v['carbs'] ?? '').toString();
      _fat.text = (v['fat'] ?? '').toString();
      _sugar.text = (v['sugar'] ?? '').toString();
      _tags.text = (v['tags'] is List ? (v['tags'] as List).join(', ') : '');
      _imageUrl = v['imageUrl']?.toString();
      // categoryId will be wired after categories are loaded
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _catsStream() {
    return FirebaseFirestore.instance
        .collection('merchants').doc(widget.merchantId)
        .collection('branches').doc(widget.branchId)
        .collection('categories')
        .where('isActive', isEqualTo: true)
        .orderBy('parentId')
        .orderBy('sort')
        .snapshots();
  }

  Future<void> _pickAndUpload() async {
    if (_cloudName.isEmpty || _unsignedPreset.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
          'Cloudinary not configured. Set CLOUDINARY_CLOUD & CLOUDINARY_PRESET.',
        ),
      ));
      return;
    }

    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
      allowMultiple: false,
    );
    if (res == null) return;

    final file = res.files.single;
    final Uint8List? bytes = file.bytes;
    if (bytes == null) return;

    setState(() => _busy = true);
    try {
      final uri =
          Uri.parse('https://api.cloudinary.com/v1_1/$_cloudName/image/upload');

      final req = http.MultipartRequest('POST', uri)
        ..fields['upload_preset'] = _unsignedPreset
        ..fields['folder'] =
            'sweets/${widget.merchantId}/${widget.branchId}/products'
        ..files.add(
          http.MultipartFile.fromBytes('file', bytes, filename: file.name),
        );

      final streamed = await req.send();
      final body = await streamed.stream.bytesToString();

      if (streamed.statusCode != 200 && streamed.statusCode != 201) {
        throw Exception('Cloudinary upload failed ${streamed.statusCode}: $body');
      }

      final json = jsonDecode(body) as Map<String, dynamic>;
      final url = json['secure_url'] as String?;
      if (url == null || url.isEmpty) {
        throw Exception('No secure_url in Cloudinary response');
      }
      setState(() => _imageUrl = url);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      // Price: parse and clamp to 3dp for BHD
      double price = _asDouble(_price.text.trim());
      price = double.parse(price.toStringAsFixed(3));

      // decide category: prefer leaf (sub) else top
      final String? categoryId = _subCatId ?? _topCatId;

      final data = {
        'merchantId': widget.merchantId,
        'branchId': widget.branchId,
        'name': _name.text.trim(),
        'price': price,
        'imageUrl': _imageUrl,
        'calories': _asIntOrNull(_cal.text.trim()),
        'protein': _asDoubleOrNull(_protein.text.trim()),
        'carbs': _asDoubleOrNull(_carbs.text.trim()),
        'fat': _asDoubleOrNull(_fat.text.trim()),
        'sugar': _asDoubleOrNull(_sugar.text.trim()),
        'tags': _tags.text
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
        'categoryId': categoryId, // <-- key piece
        'isActive': true,
        'sort': (widget.existing?.data()['sort'] as num?) ?? 0,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final col = FirebaseFirestore.instance
          .collection('merchants').doc(widget.merchantId)
          .collection('branches').doc(widget.branchId)
          .collection('menuItems');

      if (widget.existing == null) {
        await col.add({
          ...data,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        await col.doc(widget.existing!.id).set(data, SetOptions(merge: true));
      }
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPad),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.existing == null ? 'Add product' : 'Edit product',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  GestureDetector(
                    onTap: _busy ? null : _pickAndUpload,
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: onSurface.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: onSurface.withOpacity(0.12)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _imageUrl == null
                          ? const Icon(Icons.add_a_photo)
                          : Image.network(_imageUrl!, fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      children: [
                        TextField(
                          controller: _name,
                          decoration: const InputDecoration(labelText: 'Name'),
                        ),
                        TextField(
                          controller: _price,
                          decoration: const InputDecoration(
                            labelText: 'Price (BHD, 3dp)',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // ---------- Category pickers ----------
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _catsStream(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: LinearProgressIndicator(),
                    );
                  }
                  if (snap.hasError) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text('Failed to load categories: ${snap.error}'),
                    );
                  }
                  final docs = snap.data?.docs ?? const [];
                  final all = [
                    for (final d in docs)
                      {
                        'id': d.id,
                        ...d.data(),
                      }
                  ];
                  // map by id for lookups
                  final byId = {for (final c in all) c['id'] as String: c};
                  final tops = all.where((c) => c['parentId'] == null).toList()
                    ..sort((a, b) => (a['sort'] as num).compareTo(b['sort'] as num));
                  final subs = all
                      .where((c) => c['parentId'] == _topCatId)
                      .toList()
                    ..sort((a, b) => (a['sort'] as num).compareTo(b['sort'] as num));

                  // Initialize from existing.categoryId once
                  if (!_catInitDone && widget.existing != null) {
                    final existingCatId = widget.existing!.data()['categoryId'] as String?;
                    if (existingCatId != null && byId.containsKey(existingCatId)) {
                      final cat = byId[existingCatId]!;
                      final parentId = cat['parentId'] as String?;
                      if (parentId == null) {
                        _topCatId = existingCatId;
                        _subCatId = null;
                      } else {
                        _topCatId = parentId;
                        _subCatId = existingCatId;
                      }
                    }
                    _catInitDone = true;
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<String>(
                        value: _topCatId,
                        items: [
                          for (final c in tops)
                            DropdownMenuItem(
                              value: c['id'] as String,
                              child: Text((c['name'] ?? c['id']).toString()),
                            ),
                        ],
                        onChanged: (v) {
                          setState(() {
                            _topCatId = v;
                            _subCatId = null; // reset sub on top change
                          });
                        },
                        decoration: const InputDecoration(
                          labelText: 'Category',
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _subCatId,
                        items: [
                          for (final c in subs)
                            DropdownMenuItem(
                              value: c['id'] as String,
                              child: Text((c['name'] ?? c['id']).toString()),
                            ),
                        ],
                        onChanged: (v) => setState(() => _subCatId = v),
                        decoration: const InputDecoration(
                          labelText: 'Subcategory (optional)',
                        ),
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 12),
              Wrap(
                runSpacing: 8,
                spacing: 12,
                children: [
                  _numField(_cal, 'Energy (kcal)'),
                  _numField(_protein, 'Protein (g)'),
                  _numField(_fat, 'Fat (g)'),
                  _numField(_sugar, 'Sugar (g)'),
                  _numField(_carbs, 'Carbs (g)'),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _tags,
                decoration: const InputDecoration(
                  labelText: 'Tags (comma-separated)',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _numField(TextEditingController c, String label) {
    return SizedBox(
      width: 180,
      child: TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}

/* ---------- Shared parsing helpers (top-level) ---------- */

int? _asIntOrNull(String s) {
  final t = s.trim();
  if (t.isEmpty) return null;
  return int.tryParse(t);
}

double _asDouble(Object? v) {
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString().trim() ?? '') ?? 0.0;
}

double? _asDoubleOrNull(String s) {
  final t = s.trim();
  if (t.isEmpty) return null;
  return double.tryParse(t);
}
