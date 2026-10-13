// Modèles de l'espace fournisseur (dashboard).
// Champs déduits de la consommation dans MobileSupplierDashboard.jsx.

double _d(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

int _i(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

class SubOrderItem {
  final String productName;
  final String? productCategory;
  final double totalTnd;
  const SubOrderItem({required this.productName, this.productCategory, this.totalTnd = 0});

  factory SubOrderItem.fromJson(Map m) => SubOrderItem(
        productName: m['product_name']?.toString() ?? '',
        productCategory: m['product_category']?.toString(),
        totalTnd: _d(m['total_tnd']),
      );
}

class SubOrder {
  final String id;
  final String status;
  final DateTime? createdAt;
  final double subtotalTnd;
  final String? buyerName;
  final int itemsCount;
  final String? primaryImage;
  final String? paymentMethod;
  final List<SubOrderItem> items;

  const SubOrder({
    required this.id,
    required this.status,
    this.createdAt,
    this.subtotalTnd = 0,
    this.buyerName,
    this.itemsCount = 0,
    this.primaryImage,
    this.paymentMethod,
    this.items = const [],
  });

  factory SubOrder.fromJson(Map m) => SubOrder(
        id: '${m['id']}',
        status: m['status']?.toString() ?? 'pending',
        createdAt: DateTime.tryParse(m['created_at']?.toString() ?? ''),
        subtotalTnd: _d(m['subtotal_tnd']),
        buyerName: m['buyer_name']?.toString(),
        itemsCount: _i(m['items_count']),
        primaryImage: m['primary_image']?.toString(),
        paymentMethod: m['payment_method']?.toString(),
        items: (m['items'] is List)
            ? (m['items'] as List).whereType<Map>().map(SubOrderItem.fromJson).toList()
            : const [],
      );
}

class ViewsByDay {
  final String date;
  final int uniques;
  final int views;
  const ViewsByDay({required this.date, this.uniques = 0, this.views = 0});

  factory ViewsByDay.fromJson(Map m) => ViewsByDay(
        date: m['date']?.toString() ?? '',
        uniques: _i(m['uniques']),
        views: _i(m['views']),
      );
}

class ProductViewRow {
  final String productId;
  final String name;
  final int views;
  final int uniques;
  final double avgSeconds;
  final num engagementPct;
  const ProductViewRow({
    required this.productId,
    required this.name,
    this.views = 0,
    this.uniques = 0,
    this.avgSeconds = 0,
    this.engagementPct = 0,
  });

  factory ProductViewRow.fromJson(Map m) => ProductViewRow(
        productId: '${m['product_id']}',
        name: m['name']?.toString() ?? '',
        views: _i(m['views']),
        uniques: _i(m['uniques']),
        avgSeconds: _d(m['avg_seconds']),
        engagementPct: (m['engagement_pct'] is num) ? m['engagement_pct'] as num : _i(m['engagement_pct']),
      );
}

class ChannelCount {
  final String channel;
  final int count;
  const ChannelCount({required this.channel, this.count = 0});
  factory ChannelCount.fromJson(Map m) =>
      ChannelCount(channel: m['channel']?.toString() ?? 'unknown', count: _i(m['count']));
}

class ChannelConv {
  final String channel;
  final num rate;
  const ChannelConv({required this.channel, this.rate = 0});
  factory ChannelConv.fromJson(Map m) => ChannelConv(
        channel: m['channel']?.toString() ?? 'unknown',
        rate: (m['rate'] is num) ? m['rate'] as num : _d(m['rate']),
      );
}

class SupplierStats {
  final List<ViewsByDay> viewsByDay;
  final List<ProductViewRow> productViewsRanked;
  final int viewsMonth;
  final int uniqueVisitors;
  final int sessionsCount;
  final int convertedCount;
  final num conversionRate;
  final List<ChannelCount> byChannel;
  final List<ChannelConv> conversionByChannel;

  const SupplierStats({
    this.viewsByDay = const [],
    this.productViewsRanked = const [],
    this.viewsMonth = 0,
    this.uniqueVisitors = 0,
    this.sessionsCount = 0,
    this.convertedCount = 0,
    this.conversionRate = 0,
    this.byChannel = const [],
    this.conversionByChannel = const [],
  });

  factory SupplierStats.fromJson(Map m) => SupplierStats(
        viewsByDay: (m['views_by_day'] is List)
            ? (m['views_by_day'] as List).whereType<Map>().map(ViewsByDay.fromJson).toList()
            : const [],
        productViewsRanked: (m['product_views_ranked'] is List)
            ? (m['product_views_ranked'] as List).whereType<Map>().map(ProductViewRow.fromJson).toList()
            : const [],
        viewsMonth: _i(m['views_month']),
        uniqueVisitors: _i(m['unique_visitors']),
        sessionsCount: _i(m['sessions_count']),
        convertedCount: _i(m['converted_count']),
        conversionRate: (m['conversion_rate'] is num) ? m['conversion_rate'] as num : _d(m['conversion_rate']),
        byChannel: (m['by_channel'] is List)
            ? (m['by_channel'] as List).whereType<Map>().map(ChannelCount.fromJson).toList()
            : const [],
        conversionByChannel: (m['conversion_by_channel'] is List)
            ? (m['conversion_by_channel'] as List).whereType<Map>().map(ChannelConv.fromJson).toList()
            : const [],
      );
}

// Produit du catalogue fournisseur.
class MyProduct {
  final String id;
  final String name;
  final String status;
  final double basePriceTnd;
  final int stockQty;
  final int soldCount;
  final double ratingAvg;
  final int ratingCount;
  final String? categoryName;
  final String? primaryImage;

  const MyProduct({
    this.id = '',
    this.name = '',
    this.status = 'draft',
    this.basePriceTnd = 0,
    this.stockQty = 0,
    this.soldCount = 0,
    this.ratingAvg = 0,
    this.ratingCount = 0,
    this.categoryName,
    this.primaryImage,
  });

  factory MyProduct.fromJson(Map m) => MyProduct(
        id: '${m['id']}',
        name: m['name']?.toString() ?? '',
        status: m['status']?.toString() ?? 'draft',
        basePriceTnd: _d(m['base_price_tnd']),
        stockQty: _i(m['stock_qty']),
        soldCount: _i(m['sold_count']),
        ratingAvg: _d(m['rating_avg']),
        ratingCount: _i(m['rating_count']),
        categoryName: m['category_name']?.toString(),
        primaryImage: m['primary_image']?.toString(),
      );
}


// Profil fournisseur (GET /auth/supplier/me/) — champs de l'écran Réglages.
class SupplierProfileInfo {
  final String id;
  final String email;
  final String? fullName;
  final String companyName;
  final String? city;
  final String? wilaya;
  final String? address;
  final String? rcNumber;
  final String? taxNumber;
  final double? minOrderTnd;
  final String? phone;
  final String verificationStatus;
  final String? logoUrl;

  const SupplierProfileInfo({
    this.id = '',
    this.email = '',
    this.fullName,
    this.companyName = '',
    this.city,
    this.wilaya,
    this.address,
    this.rcNumber,
    this.taxNumber,
    this.minOrderTnd,
    this.phone,
    this.verificationStatus = 'pending',
    this.logoUrl,
  });

  factory SupplierProfileInfo.fromJson(Map m) {
    final store = (m['store'] is Map) ? m['store'] as Map : const {};
    double? minOrder;
    final mo = m['min_order_tnd'];
    if (mo != null) minOrder = _d(mo);
    return SupplierProfileInfo(
      id: '${m['id']}',
      email: m['email']?.toString() ?? '',
      fullName: m['full_name']?.toString(),
      companyName: m['company_name']?.toString() ?? '',
      city: m['city']?.toString(),
      wilaya: m['wilaya']?.toString(),
      address: m['address']?.toString(),
      rcNumber: m['rc_number']?.toString(),
      taxNumber: m['tax_number']?.toString(),
      minOrderTnd: minOrder,
      phone: m['phone']?.toString(),
      verificationStatus: m['verification_status']?.toString() ?? 'pending',
      logoUrl: store['logo_url']?.toString(),
    );
  }
}


// Utilisateurs actifs (GET /analytics/supplier/active-users/).
class DauWauMau {
  final int dau, wau, mau;
  const DauWauMau({this.dau = 0, this.wau = 0, this.mau = 0});
  factory DauWauMau.fromJson(Map m) =>
      DauWauMau(dau: _i(m['dau']), wau: _i(m['wau']), mau: _i(m['mau']));
}

class ActiveUsers {
  final DauWauMau uniqueVisitors;
  final DauWauMau authenticatedUsers;
  final num stickinessRatio;
  const ActiveUsers({
    this.uniqueVisitors = const DauWauMau(),
    this.authenticatedUsers = const DauWauMau(),
    this.stickinessRatio = 0,
  });
  factory ActiveUsers.fromJson(Map m) => ActiveUsers(
        uniqueVisitors: (m['unique_visitors'] is Map)
            ? DauWauMau.fromJson(m['unique_visitors'] as Map) : const DauWauMau(),
        authenticatedUsers: (m['authenticated_users'] is Map)
            ? DauWauMau.fromJson(m['authenticated_users'] as Map) : const DauWauMau(),
        stickinessRatio: (m['stickiness_ratio'] is num) ? m['stickiness_ratio'] as num : _d(m['stickiness_ratio']),
      );
}

// Répartition par gouvernorat (GET /analytics/supplier/regions/).
class RegionStat {
  final String gouvernorat;
  final String label;
  final int ordersCount;
  final double revenue;
  const RegionStat({
    required this.gouvernorat,
    required this.label,
    this.ordersCount = 0,
    this.revenue = 0,
  });
  factory RegionStat.fromJson(Map m) => RegionStat(
        gouvernorat: m['gouvernorat']?.toString() ?? '',
        label: m['label']?.toString() ?? (m['gouvernorat']?.toString() ?? ''),
        ordersCount: _i(m['orders_count']),
        revenue: _d(m['revenue']),
      );
}