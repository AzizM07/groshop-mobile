class Supplier {
  final String id;
  final String companyName;
  final String slug;
  final String verificationStatus; // 'pending' | 'approved' | 'rejected'
  final bool hasActiveSubscription;
  final int followersCount;

  const Supplier({
    required this.id,
    required this.companyName,
    required this.slug,
    required this.verificationStatus,
    this.hasActiveSubscription = false,
    this.followersCount = 0,
  });

  bool get isApproved => verificationStatus == 'approved';

  factory Supplier.fromJson(Map<String, dynamic> j) => Supplier(
        id: '${j['id']}',
        companyName: j['company_name'] ?? '',
        slug: j['slug'] ?? '',
        verificationStatus: j['verification_status'] ?? 'pending',
        hasActiveSubscription: j['has_active_subscription'] ?? false,
        followersCount: j['followers_count'] ?? 0,
      );
}