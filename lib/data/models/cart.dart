double _d(v) => v == null ? 0.0 : double.tryParse(v.toString()) ?? 0.0;
int _i(v) => v == null ? 0 : int.tryParse(v.toString().split('.').first) ?? 0;

class CartSupplier {
  final String? id, name, slug, logoUrl;
  const CartSupplier({this.id, this.name, this.slug, this.logoUrl});
  factory CartSupplier.fromJson(Map j) => CartSupplier(
        id: j['id'] == null ? null : '${j['id']}',
        name: j['name'], slug: j['slug'], logoUrl: j['logo_url']);
}

class CartItem {
  final String id, productId;
  final String name;
  final String? imageUrl, unit, variantName;
  final int quantity, moq;
  final double unitPrice, oldPrice;
  final int? deliveryDays;
  final CartSupplier? supplier;

  const CartItem({
    required this.id, required this.productId, required this.name,
    this.imageUrl, this.unit, this.variantName,
    this.quantity = 1, this.moq = 1, this.unitPrice = 0, this.oldPrice = 0,
    this.deliveryDays, this.supplier,
  });

  double get lineTotal => unitPrice * quantity;
  double get lineSavings => oldPrice > unitPrice ? (oldPrice - unitPrice) * quantity : 0;

  factory CartItem.fromJson(Map<String, dynamic> j) {
    final p = (j['product'] is Map) ? (j['product'] as Map).cast<String, dynamic>() : <String, dynamic>{};
    final variant = (j['variant_data'] is Map) ? (j['variant_data'] as Map) : null;
    return CartItem(
      id: '${j['id']}',
      productId: '${p['id'] ?? j['product_id'] ?? ''}',
      name: p['name'] ?? '',
      imageUrl: p['image_url'] ?? p['primary_image'],
      unit: p['unit'] ?? 'pièce',
      variantName: variant?['name'],
      quantity: _i(j['quantity']),
      moq: _i(p['moq']) == 0 ? 1 : _i(p['moq']),
      unitPrice: _d(j['unit_price_tnd']),
      oldPrice: _d(p['old_price_tnd']),
      deliveryDays: p['delivery_days'] == null ? null : _i(p['delivery_days']),
      supplier: (p['supplier'] is Map) ? CartSupplier.fromJson(p['supplier']) : null,
    );
  }
}