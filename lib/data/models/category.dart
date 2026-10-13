class Category {
  final String id;
  final String name;
  final String? imageUrl;
  final List<Category> children;

  const Category({
    required this.id,
    required this.name,
    this.imageUrl,
    this.children = const [],
  });

  factory Category.fromJson(Map<String, dynamic> j) => Category(
        id: '${j['id']}',
        name: j['name'] ?? '',
        imageUrl: j['image_url'],
        children: (j['children'] is List)
            ? (j['children'] as List)
                .whereType<Map>()
                .map((c) => Category.fromJson(c.cast<String, dynamic>()))
                .toList()
            : const [],
      );
}