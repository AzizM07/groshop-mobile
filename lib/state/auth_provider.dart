import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/config.dart';
import '../data/api/api_client.dart';
import '../data/api/auth_api.dart';
import '../data/models/user.dart';
import '../data/models/supplier.dart';

class AuthState {
  final User? user;
  final Supplier? supplier;
  const AuthState({this.user, this.supplier});
  bool get isAuthenticated => user != null;
  bool get isSupplier => user?.role == 'supplier';
}

class AuthNotifier extends AsyncNotifier<AuthState> {
  @override
  Future<AuthState> build() async {
    final store = ref.read(cookieStoreProvider);
    final hasSession = await store.hasSession(Uri.parse(AppConfig.apiBaseUrl));
    if (!hasSession) return const AuthState();
    try {
      final api = ref.read(authApiProvider);
      final user = await api.me();
      final sup = user.isSupplier ? await api.supplierMe() : null;
      return AuthState(user: user, supplier: sup);
    } catch (_) {
      await store.clear();
      return const AuthState();
    }
  }
  Future<void> signInWithGoogle(String idToken) async {
  state = const AsyncLoading();
  state = await AsyncValue.guard(() async {
    final api = ref.read(authApiProvider);
    final user = await api.googleNativeSignIn(idToken);
    final sup = user.isSupplier ? await api.supplierMe() : null;
    return AuthState(user: user, supplier: sup);
  });
}
  Future<void> login(String email, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final api = ref.read(authApiProvider);
      final user = await api.login(email, password);
      final sup = user.isSupplier ? await api.supplierMe() : null;
      return AuthState(user: user, supplier: sup);
    });
  }

  /// Connexion sociale (Google/Facebook/LinkedIn) via le flow deep link mobile.
  Future<void> exchangeSocialCode(String code) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final api = ref.read(authApiProvider);
      final user = await api.exchangeSocialCode(code);
      final sup = user.isSupplier ? await api.supplierMe() : null;
      return AuthState(user: user, supplier: sup);
    });
  }

  Future<void> logout() async {
    await ref.read(authApiProvider).logout();
    state = const AsyncData(AuthState());
  }
}

final authProvider = AsyncNotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);