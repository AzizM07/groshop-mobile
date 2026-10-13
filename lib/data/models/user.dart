class User {
  final String id;
  final String email;
  final String fullName;
  final String role; // 'buyer' | 'supplier'
  final bool isActive;
  final bool isVerified;

  const User({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    this.isActive = true,
    this.isVerified = false,
  });

  bool get isSupplier => role == 'supplier';

  factory User.fromJson(Map<String, dynamic> j) => User(
        id: '${j['id']}',
        email: j['email'] ?? '',
        fullName: j['full_name'] ?? '',
        role: j['role'] ?? 'buyer',
        isActive: j['is_active'] ?? true,
        isVerified: j['is_verified'] ?? false,
      );
}