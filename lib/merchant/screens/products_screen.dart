import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

import '../../core/branding/branding_admin_page.dart';

/// Merchant product manager (Cloudinary + Firestore).
/// Defaults can be overridden at build time with:
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

        final itemsCol = FirebaseFirestore.instance
            .collection('merchants/$merchantId/branches/$branchId/menuItems')
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
            stream: itemsCol.snapshots(),
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
                  final num priceNum = (v['price'] ?? 0) as num;
                  return ListTile(
                    leading: v['imageUrl'] != null && (v['imageUrl'] as String).isNotEmpty
                        ? Image.network(
                            v['imageUrl'],
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const SizedBox(width: 56, height: 56),
                          )
                        : const SizedBox(width: 56, height: 56),
                    title: Text((v['name'] ?? d.id).toString()),
                    subtitle: Text(
                      'BHD ${priceNum.toStringAsFixed(3)}'
                      '${v['calories'] != null ? ' • ${v['calories']} kcal' : ''}',
                    ),
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
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => ProductEditorSheet(
        merchantId: m,
        branchId: b,
        existing: doc,
      ),
    );
  }
}

class ProductEditorSheet extends StatefulWidget {
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
  State<ProductEditorSheet> createState() => _ProductEditorSheetState();
}

class _ProductEditorSheetState extends State<ProductEditorSheet> {
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

  // Defaults to your account values; can be overridden with --dart-define.
  static const _cloudName =
      String.fromEnvironment('CLOUDINARY_CLOUD', defaultValue: 'dkirkzbfa');
  static const _unsignedPreset = String.fromEnvironment(
      'CLOUDINARY_PRESET',
      defaultValue: 'unsigned_products');

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
    }
  }

  Future<void> _pickAndUpload() async {
    if (_cloudName.isEmpty || _unsignedPreset.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Cloudinary not configured. Set CLOUDINARY_CLOUD & CLOUDINARY_PRESET.'),
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
        // We pass folder dynamically; preset should have Asset folder blank.
        ..fields['folder'] = 'sweets/${widget.merchantId}/products'
        ..files.add(
          http.MultipartFile.fromBytes('file', bytes, filename: file.name),
        );

      final streamed = await req.send();
      final body = await streamed.stream.bytesToString();

      if (streamed.statusCode != 200 && streamed.statusCode != 201) {
        throw Exception(
            'Cloudinary upload failed ${streamed.statusCode}: $body');
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
      final data = {
        'name': _name.text.trim(),
        'price': double.tryParse(_price.text.trim()) ?? 0.0,
        'imageUrl': _imageUrl,
        'calories': int.tryParse(_cal.text.trim()),
        'protein': double.tryParse(_protein.text.trim()),
        'carbs': double.tryParse(_carbs.text.trim()),
        'fat': double.tryParse(_fat.text.trim()),
        'sugar': double.tryParse(_sugar.text.trim()),
        'tags': _tags.text
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
        'isActive': true,
        'sort': (widget.existing?.data()['sort'] as num?) ?? 0,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final col = FirebaseFirestore.instance.collection(
        'merchants/${widget.merchantId}/branches/${widget.branchId}/menuItems',
      );

      if (widget.existing == null) {
        await col.add(data);
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
                      color: Colors.grey.shade200,
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
                          decoration:
                              const InputDecoration(labelText: 'Name'),
                        ),
                        TextField(
                          controller: _price,
                          decoration: const InputDecoration(
                              labelText: 'Price (BHD, 3dp)'),
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
                    labelText: 'Tags (comma-separated)'),
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
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}
