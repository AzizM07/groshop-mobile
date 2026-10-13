import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:url_launcher/url_launcher_string.dart';
import '../../../data/api/api_client.dart';
import '../../../data/storage/shared_preferences_provider.dart';

const _heroSlidesCacheKey = 'mobile_hero_slides';

/// Couleur dominante (assombrie) de l'image du hero actuellement affichée.
/// Le header l'écoute pour l'utiliser comme fond. `null` = pas d'image → le
/// header retombe sur son dégradé orange de repli.
final heroColorProvider = StateProvider<Color?>((ref) => null);

/// Chemin relatif — dioProvider porte déjà la base URL, qui inclut déjà `/api`
/// (base = https://api.groshop.tn/api). Donc PAS de `/api` ici, sinon on tape
/// `/api/api/banners/active/` → 404 Django → HTML → jsonDecode échoue.
const _bannersPath = '/banners/active/';

class HeroSlide {
  final String url;
  final String link;
  final String title;
  const HeroSlide({required this.url, required this.link, required this.title});

  factory HeroSlide.fromJson(Map<String, dynamic> j) => HeroSlide(
        url: j['url'] as String? ?? '',
        link: j['link'] as String? ?? '',
        title: j['title'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'url': url, 'link': link, 'title': title};
}

List<HeroSlide> _decodeSlides(String? raw) {
  if (raw == null) return const [];
  try {
    final parsed = jsonDecode(raw);
    if (parsed is! List) return const [];
    return parsed
        .whereType<Map<String, dynamic>>()
        .map(HeroSlide.fromJson)
        .toList();
  } catch (_) {
    return const [];
  }
}

// Ordre d'affichage des slides selon la zone. Toutes les zones sont incluses ;
// ce map ne fait que fixer l'ordre (aligné sur ZONE_ORDER dans MobileHome.jsx).
// Une zone inconnue tombe en dernier (99).
const _zoneOrder = {
  'hero_bg': 0,
  'bottom_slider': 1,
  'hero_slider': 2,
  'side_card': 3,
};

List<HeroSlide> _parseBanners(dynamic data) {
  // res.data peut arriver en String (JSON non décodé par dio) au lieu d'une
  // List/Map — on décode ici si nécessaire.
  dynamic decoded = data;
  if (decoded is String) {
    try {
      decoded = jsonDecode(decoded);
    } catch (_) {
      return const [];
    }
  }

  final list = (decoded is List)
      ? decoded
      : (decoded is Map ? (decoded['results'] as List? ?? const []) : const []);

  // On prend TOUTES les bannières actives (plus de filtre de zone), puis on
  // les ordonne par zone (_zoneOrder) puis par position.
  final banners = list
      .whereType<Map>()
      .where((b) => b['is_active'] == true)
      .toList()
    ..sort((a, b) {
      final za = _zoneOrder[a['zone']] ?? 99;
      final zb = _zoneOrder[b['zone']] ?? 99;
      if (za != zb) return za.compareTo(zb);
      final pa = (a['position'] as num?) ?? 0;
      final pb = (b['position'] as num?) ?? 0;
      return pa.compareTo(pb);
    });

  // Chaque bannière peut porter plusieurs images (galerie) : on aplatit tout
  // en une liste de slides. Fallback sur image_url si `images` est vide.
  final out = <HeroSlide>[];
  for (final b in banners) {
    final rawImages = b['images'];
    final imgs = <String>[
      if (rawImages is List && rawImages.isNotEmpty)
        ...rawImages.whereType<String>()
      else if (b['image_url'] is String)
        b['image_url'] as String,
    ].where((u) => u.isNotEmpty).toList();

    for (final url in imgs) {
      out.add(HeroSlide(
        url: url,
        link: b['link'] as String? ?? '',
        title: b['title'] as String? ?? '',
      ));
    }
  }
  return out;
}

class MobileHeroGrid extends ConsumerStatefulWidget {
  const MobileHeroGrid({super.key});
  @override
  ConsumerState<MobileHeroGrid> createState() => _MobileHeroGridState();
}

class _MobileHeroGridState extends ConsumerState<MobileHeroGrid> {
  static const _height = 180.0;
  static const _autoScrollInterval = Duration(milliseconds: 4500);

  late List<HeroSlide> _slides;
  late final PageController _controller;
  int _i = 0;
  bool _paused = false;
  Timer? _timer;

  // Cache couleur par URL (évite de relancer PaletteGenerator à chaque tour).
  final Map<String, Color> _colorCache = {};
  int _paletteToken = 0; // ignore les calculs obsolètes

  @override
  void initState() {
    super.initState();

    // Peinture instantanée depuis le cache (0 flash au remontage) —
    // équivalent de useState(() => JSON.parse(localStorage.getItem(...))).
    final prefs = ref.read(sharedPreferencesProvider);
    _slides = _decodeSlides(prefs.getString(_heroSlidesCacheKey));

    _controller = PageController(initialPage: 0);

    // Publie la couleur de la 1re slide dès le 1er frame (on ne peut pas
    // toucher un provider pendant initState).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _publishCurrentColor();
    });

    _startAutoScroll();
    _refreshInBackground();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Color _pickHeaderColor(PaletteGenerator p) {
    // Couleur vive/dominante brute (PAS d'assombrissement) — c'est le header
    // qui l'éclaircit et gère le contraste du texte.
    return p.vibrantColor?.color ??
        p.lightVibrantColor?.color ??
        p.dominantColor?.color ??
        p.mutedColor?.color ??
        const Color(0xFFFF8A15);
  }

  // Détermine la couleur de la slide _i et la pousse dans le provider.
  void _publishCurrentColor() {
    final url = (_i >= 0 && _i < _slides.length) ? _slides[_i].url : '';
    if (url.isEmpty) {
      ref.read(heroColorProvider.notifier).state = null;
      return;
    }
    final cached = _colorCache[url];
    if (cached != null) {
      ref.read(heroColorProvider.notifier).state = cached;
      return;
    }
    _computeColor(url);
  }

  // Petit utilitaire : Color → "#AARRGGBB".
  String _hex(Color c) =>
      '#${c.value.toRadixString(16).padLeft(8, '0').toUpperCase()}';

  Future<void> _computeColor(String url) async {
    final token = ++_paletteToken;
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        // ✅ même cache que l'affichage → une seule descente réseau par image.
        CachedNetworkImageProvider(url),
        size: const Size(140, 90), // downscale → rapide
        maximumColorCount: 12,
      );
      final color = _pickHeaderColor(palette);

      // 🔎 DEBUG : couleur extraite de l'image du hero (retire-le en prod).
      debugPrint('HERO COLOR = ${_hex(color)}  ←  $url');

      _colorCache[url] = color;
      if (!mounted || token != _paletteToken) return;
      ref.read(heroColorProvider.notifier).state = color;
    } catch (_) {
      // on garde la couleur précédente
    }
  }

  // Rafraîchit en arrière-plan et met le cache à jour.
  Future<void> _refreshInBackground() async {
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.get(_bannersPath);
      if (!mounted) return;

      // res.data peut être une List/Map (dio décode) OU une String (dio ne
      // décode pas) — _parseBanners gère les deux cas.
      final slides = _parseBanners(res.data);

      setState(() {
        _slides = slides;
        _i = 0;
      });
      _publishCurrentColor();

      final prefs = ref.read(sharedPreferencesProvider);
      await prefs.setString(
        _heroSlidesCacheKey,
        jsonEncode(slides.map((s) => s.toJson()).toList()),
      );

      if (_controller.hasClients) {
        _controller.jumpToPage(0);
      }
      _restartAutoScroll();
    } catch (_) {
      // silencieux, comme le .catch(() => {}) côté web
    }
  }

  void _startAutoScroll() {
    _timer?.cancel();
    if (_slides.length <= 1) return;
    _timer = Timer.periodic(_autoScrollInterval, (_) {
      if (_paused || !_controller.hasClients || _slides.length <= 1) return;
      final next = (_i + 1) % _slides.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    });
  }

  void _restartAutoScroll() => _startAutoScroll();

  void _goToSlide(int idx) {
    _controller.animateToPage(
      idx,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
    );
  }

  Future<void> _openLink(String link) async {
    if (link.isEmpty) return;
    if (link.startsWith('http://') || link.startsWith('https://')) {
      await launchUrlString(link, mode: LaunchMode.externalApplication);
    } else {
      // route interne de l'app (équivalent navigate(l) côté web)
      if (mounted) context.push(link);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_slides.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: _height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Listener(
            onPointerDown: (_) => setState(() => _paused = true),
            onPointerUp: (_) => setState(() => _paused = false),
            onPointerCancel: (_) => setState(() => _paused = false),
            child: PageView.builder(
              controller: _controller,
              itemCount: _slides.length,
              onPageChanged: (idx) {
                setState(() => _i = idx);
                _publishCurrentColor(); // → met à jour la couleur du header
              },
              itemBuilder: (_, k) {
                final s = _slides[k];
                // ✅ image en cache + décodée en petit + fondu doux.
                final img = CachedNetworkImage(
                  imageUrl: s.url,
                  width: double.infinity,
                  height: _height,
                  fit: BoxFit.cover,
                  memCacheHeight: 360,
                  fadeInDuration: const Duration(milliseconds: 200),
                  placeholder: (_, __) =>
                      const ColoredBox(color: Color(0xFFF1F3F5)),
                  errorWidget: (_, __, ___) =>
                      const ColoredBox(color: Color(0xFFF1F3F5)),
                );
                return GestureDetector(
                  onTap: s.link.isNotEmpty ? () => _openLink(s.link) : null,
                  child: img,
                );
              },
            ),
          ),

          if (_slides.length > 1)
            Positioned(
              bottom: 10,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_slides.length, (k) {
                  final active = k == _i;
                  return GestureDetector(
                    onTap: () => _goToSlide(k),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 2.5),
                      width: active ? 16 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: active
                            ? Colors.white
                            : Colors.white.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}