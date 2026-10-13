import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdIds {
  /// Factory enregistrée dans MainActivity.kt (layout groshop_native_ad.xml).
  static const factoryId = 'groshopNativeAd';

  // ⚠️ IDs de TEST — remplace en prod.
  static String get nativeUnit => Platform.isAndroid
      ? 'ca-app-pub-3940256099942544/2247696110'
      : 'ca-app-pub-3940256099942544/3986624511';
}

final nativeAdPoolProvider =
    NotifierProvider<NativeAdPool, List<NativeAd>>(NativeAdPool.new);

class NativeAdPool extends Notifier<List<NativeAd>> {
  static const _target = 4; // nombre d'ads préchargées
  final List<NativeAd> _ready = [];
  bool _loading = false;

  @override
  List<NativeAd> build() {
    ref.onDispose(() {
      for (final ad in _ready) ad.dispose();
      _ready.clear();
    });
    _fill();
    return const [];
  }

  void _fill() {
    if (_loading) return;
    final missing = _target - _ready.length;
    if (missing <= 0) return;
    _loading = true;
    var pending = missing;

    void done() {
      pending--;
      if (pending <= 0) {
        _loading = false;
        state = List.unmodifiable(_ready); // notifie les slots
      }
    }

    for (var i = 0; i < missing; i++) {
      NativeAd(
        adUnitId: AdIds.nativeUnit,
        factoryId: AdIds.factoryId,
        request: const AdRequest(),
        // AdChoices en haut à droite : l'en-tête de la carte lui laisse la place.
        nativeAdOptions: NativeAdOptions(adChoicesPlacement: AdChoicesPlacement.topRightCorner),
        listener: NativeAdListener(
          onAdLoaded: (ad) {
            debugPrint('NATIVE AD OK >>> chargée');
            _ready.add(ad as NativeAd);
            done();
          },
          onAdFailedToLoad: (ad, error) {
            // ⭐ LOG : révèle la vraie cause (factory non enregistrée, SDK non
            //    initialisé, no-fill, réseau…).
            debugPrint('NATIVE AD FAIL >>> code=${error.code} '
                'domain=${error.domain} msg=${error.message}');
            ad.dispose();
            done();
          },
        ),
      ).load();
    }
  }

  /// Donne une ad prête (et en recharge une pour garder le pool plein).
  NativeAd? take() {
    if (_ready.isEmpty) {
      _fill();
      return null;
    }
    final ad = _ready.removeAt(0);
    state = List.unmodifiable(_ready);
    _fill(); // recharge en arrière-plan
    return ad;
  }
}