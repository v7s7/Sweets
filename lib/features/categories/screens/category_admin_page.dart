import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/branding/branding_providers.dart';
import '../data/categories_repo.dart';
import '../data/category.dart';

class CategoryAdminPage extends ConsumerStatefulWidget {
  const CategoryAdminPage({super.key});
  @override
  ConsumerState<CategoryAdminPage> createState() => _CategoryAdminPageState();
}

class _CategoryAdminPageState extends ConsumerState<CategoryAdminPage> {
  String? _activeParent; // null => top level

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(categoriesStreamProvider).value ?? const <Category>[];
    final onSurface = Theme.of(context).colorScheme.onSurface;

    final level = cats.where((c) => c.parentId == _activeParent).toList()
      ..sort((a, b) => a.sort.compareTo(b.sort));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _activeParent == null ? 'Categories' : 'Subcategories',
          style: TextStyle(color: onSurface, fontWeight: FontWeight.w800),
        ),
      ),
      body: ReorderableListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
        itemCount: level.length,
        onReorder: (oldIndex, newIndex) => _reorder(level, oldIndex, newIndex),
        itemBuilder: (_, i) {
          final c = level[i];
          final hasChildren = cats.any((x) => x.parentId == c.id);
          return ListTile(
            key: ValueKey(c.id),
            title: Text(c.name, style: TextStyle(color: onSurface)),
            leading: const Icon(Icons.drag_indicator),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (_activeParent == null)
                IconButton(
                  tooltip: 'Open subcategories',
                  onPressed: () => setState(() => _activeParent = c.id),
                  icon: const Icon(Icons.chevron_right),
                ),
              IconButton(
                tooltip: 'Rename',
                onPressed: () => _rename(c),
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: 'Deactivate',
                onPressed: () => _setActive(c, false),
                icon: const Icon(Icons.visibility_off_outlined),
              ),
              IconButton(
                tooltip: 'Delete',
                onPressed: () => _delete(c, hasChildren),
                icon: const Icon(Icons.delete_outline),
              ),
            ]),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: Text(_activeParent == null ? 'Add category' : 'Add subcategory'),
      ),
      bottomNavigationBar: _activeParent == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _activeParent = null),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back to categories'),
                ),
              ),
            ),
    );
  }

  Future<void> _create() async {
    final name = await _prompt('Name');
    if (name == null || name.trim().isEmpty) return;

    final m = ref.read(merchantIdProvider);
    final b = ref.read(branchIdProvider);
    final col = FirebaseFirestore.instance
        .collection('merchants').doc(m)
        .collection('branches').doc(b)
        .collection('categories');

    await col.add({
      'name': name.trim(),
      'parentId': _activeParent,
      'sort': DateTime.now().millisecondsSinceEpoch, // lazy sort token
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _rename(Category c) async {
    final name = await _prompt('Rename', initial: c.name);
    if (name == null || name.trim().isEmpty || name.trim() == c.name) return;

    await _doc(c).update({
      'name': name.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _setActive(Category c, bool v) async {
    await _doc(c).update({'isActive': v, 'updatedAt': FieldValue.serverTimestamp()});
  }

  Future<void> _delete(Category c, bool hasChildren) async {
    final ok = await _confirm('Delete "${c.name}"?'
        '${hasChildren ? '\n\nThis has subcategories. Delete those first or reassign items.' : ''}');
    if (ok != true) return;
    await _doc(c).delete();
  }

  Future<void> _reorder(List<Category> level, int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    final moved = level.removeAt(oldIndex);
    level.insert(newIndex, moved);

    // commit new sort order
    final batch = FirebaseFirestore.instance.batch();
    for (var i = 0; i < level.length; i++) {
      batch.update(_doc(level[i]), {'sort': i, 'updatedAt': FieldValue.serverTimestamp()});
    }
    await batch.commit();
  }

  DocumentReference<Map<String, dynamic>> _doc(Category c) {
    final m = ref.read(merchantIdProvider);
    final b = ref.read(branchIdProvider);
    return FirebaseFirestore.instance
        .collection('merchants').doc(m)
        .collection('branches').doc(b)
        .collection('categories').doc(c.id);
  }

  Future<String?> _prompt(String title, {String? initial}) async {
    final c = TextEditingController(text: initial ?? '');
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Save')),
        ],
      ),
    );
  }

  Future<bool?> _confirm(String msg) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yes')),
        ],
      ),
    );
  }
}
