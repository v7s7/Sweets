class Category {
  final String id;
  final String name;
  final String? parentId;
  final int sort;
  final bool isActive;
  const Category({
    required this.id,
    required this.name,
    this.parentId,
    required this.sort,
    required this.isActive,
  });

  factory Category.fromDoc(String id, Map<String, dynamic> d) => Category(
    id: id,
    name: (d['name'] ?? '').toString(),
    parentId: d['parentId'] as String?,
    sort: (d['sort'] as num?)?.toInt() ?? 0,
    isActive: (d['isActive'] as bool?) ?? true,
  );
}
