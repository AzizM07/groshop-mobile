import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/api/messaging_api.dart';
import '../data/models/messaging_models.dart';

// Observe le cycle de vie de l'app pour mettre le polling en pause quand
// l'app n'est pas au premier plan (équivalent du visibilitychange du web).
class LifecycleObserver extends WidgetsBindingObserver {
  final void Function(bool visible) onChange;
  bool visible = true;
  LifecycleObserver(this.onChange);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    visible = state == AppLifecycleState.resumed;
    onChange(visible);
  }
}

// Liste des conversations, rechargée toutes les 6 s (pause en arrière-plan).
class SupplierConversationsNotifier extends AutoDisposeNotifier<List<Conversation>?> {
  Timer? _timer;
  LifecycleObserver? _obs;

  @override
  List<Conversation>? build() {
    _obs = LifecycleObserver((v) { if (v) refresh(); });
    WidgetsBinding.instance.addObserver(_obs!);
    ref.onDispose(() {
      _timer?.cancel();
      final o = _obs;
      if (o != null) WidgetsBinding.instance.removeObserver(o);
    });
    Future.microtask(refresh);
    _timer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (_obs?.visible ?? true) refresh();
    });
    return null;
  }

  Future<void> refresh() async {
    try {
      state = await ref.read(messagingApiProvider).conversations();
    } catch (_) {
      state = state ?? const [];
    }
  }
}

final supplierConversationsProvider =
    AutoDisposeNotifierProvider<SupplierConversationsNotifier, List<Conversation>?>(SupplierConversationsNotifier.new);