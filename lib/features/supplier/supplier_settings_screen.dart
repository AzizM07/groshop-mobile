import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/api/network_error.dart';
import '../../data/api/subscriptions_api.dart';
import '../../data/api/supplier_api.dart';
import '../../data/models/supplier_models.dart';
import '../../state/auth_provider.dart';
import '../../widgets/no_connection_view.dart';

// ═══════ Palette (identique au dashboard) ═══════
const _orange = Color(0xFFFF8A00);
const _orangeSoft = Color(0xFFFFEEDB);
const _blue = Color(0xFF4F7CFF);
const _blueSoft = Color(0xFFE8EEFF);
const _pink = Color(0xFFF25C6E);
const _pinkSoft = Color(0xFFFFE8EA);
const _green = Color(0xFF1FB57A);
const _greenSoft = Color(0xFFE2F8EE);
const _violet = Color(0xFF8B5CF6);
const _violetSoft = Color(0xFFF0EAFF);
const _bg = Color(0xFFFAFAFB);
const _ink = Color(0xFF1E1E2D);
const _mute = Color(0xFF8A8A99);
const _faint = Color(0xFFB5B5C3);
const _tile = Color(0xFFF4F4F6);
const _divider = Color(0xFFF1F1F4);

const _bannerH = 150.0;
const _cardOverlap = 64.0;
const _logoSize = 80.0;

const _shadow = <BoxShadow>[
  BoxShadow(color: Color(0x121B1B3A), blurRadius: 26, offset: Offset(0, 10)),
];

String _fmtTnd(num v) => v.toStringAsFixed(3);

String _maskEmail(String e) {
  final at = e.indexOf('@');
  if (at < 0) return e;
  final u = e.substring(0, at);
  return '${u.length > 3 ? u.substring(0, 3) : u}***${e.substring(at)}';
}

class _Verif {
  final String label;
  final Color color;
  final Color bg;
  final IconData icon;
  const _Verif(this.label, this.color, this.bg, this.icon);
}

const _verif = {
  'approved': _Verif('Vérifié', _green, _greenSoft, Icons.verified_rounded),
  'pending': _Verif('Vérification en cours', _orange, _orangeSoft, Icons.schedule_rounded),
  'rejected': _Verif('Vérification refusée', _pink, _pinkSoft, Icons.cancel_rounded),
};

class SupplierSettingsScreen extends ConsumerWidget {
  const SupplierSettingsScreen({super.key});

  void _snack(BuildContext c, String m) =>
      ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

  void _soon(BuildContext c, String w) => _snack(c, '$w — bientôt disponible.');

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(supplierProfileProvider);
    ref.invalidate(mySubscriptionProvider);
    ref.invalidate(plansProvider);
    try {
      await ref.read(supplierProfileProvider.future);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(supplierProfileProvider);
    final productsCount = ref.watch(supplierMyProductsProvider).valueOrNull?.length;

    if (async.isLoading && !async.hasValue) {
      return const ColoredBox(
        color: _bg,
        child: Center(child: CircularProgressIndicator(color: _orange)),
      );
    }

    if (async.hasError && !async.hasValue) {
      if (isNetworkError(async.error)) {
        return ColoredBox(
          color: _bg,
          child: NoConnectionView(onRetry: () => ref.invalidate(supplierProfileProvider)),
        );
      }
      return ColoredBox(color: _bg, child: GenericErrorView(onRetry: () => ref.invalidate(supplierProfileProvider)));
    }

    final p = async.valueOrNull;
    if (p == null) {
      return ColoredBox(
        color: _bg,
        child: Center(child: Text('Profil introuvable.', style: AppTheme.body(size: 14, color: _mute))),
      );
    }

    final place = [p.city, p.wilaya].where((x) => x != null && x.isNotEmpty).join(', ');

    return ColoredBox(
      color: _bg,
      child: RefreshIndicator(
        color: _orange,
        onRefresh: () => _refresh(ref),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            _Hero(
              profile: p,
              productsCount: productsCount,
              onCopyId: () {
                Clipboard.setData(ClipboardData(text: p.id));
                _snack(context, 'Identifiant copié.');
              },
              onStorefront: () => _soon(context, 'Vitrine'),
            ),
            const SizedBox(height: 24),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _SubscriptionSection(productsCount: productsCount),
            ),

            _SettingsGroup(
              title: 'Ma boutique',
              rows: [
                _RowData(Icons.star_outline_rounded, _orange, _orangeSoft, 'Avis clients', '',
                    onTap: () => context.push('/supplier/reviews')),
                _RowData(Icons.lock_open_rounded, _violet, _violetSoft, 'Accès accordés', 'Prix masqués',
                    onTap: () => context.push('/supplier/access')),
              ],
            ),

            _SettingsGroup(
              title: 'Informations de la boutique',
              rows: [
                _RowData(Icons.storefront_outlined, _orange, _orangeSoft, 'Nom de la boutique',
                    p.companyName.isNotEmpty ? p.companyName : '—'),
                _RowData(Icons.location_on_outlined, _blue, _blueSoft, 'Ville', place.isEmpty ? '—' : place),
                _RowData(Icons.home_work_outlined, _violet, _violetSoft, 'Adresse',
                    p.address?.isNotEmpty == true ? p.address! : '—'),
                _RowData(Icons.description_outlined, _green, _greenSoft, 'Registre de commerce',
                    p.rcNumber?.isNotEmpty == true ? p.rcNumber! : '—'),
                _RowData(Icons.receipt_long_outlined, _pink, _pinkSoft, 'Matricule fiscal',
                    p.taxNumber?.isNotEmpty == true ? p.taxNumber! : '—'),
                _RowData(Icons.shopping_bag_outlined, _orange, _orangeSoft, 'Commande minimum',
                    p.minOrderTnd != null ? '${_fmtTnd(p.minOrderTnd!)} TND' : '—'),
              ],
            ),

            _SettingsGroup(
              title: 'Sécurité du compte',
              rows: [
                _RowData(Icons.lock_outline_rounded, _violet, _violetSoft, 'Mot de passe', '',
                    onTap: () => _soon(context, 'Mot de passe')),
                _RowData(Icons.mail_outline_rounded, _blue, _blueSoft, 'Adresse e-mail', _maskEmail(p.email),
                    onTap: () => _soon(context, 'E-mail')),
                _RowData(Icons.phone_outlined, _green, _greenSoft, 'Téléphone',
                    p.phone?.isNotEmpty == true ? p.phone! : '—',
                    onTap: () => _soon(context, 'Téléphone')),
              ],
            ),

            // Déconnexion
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: () async {
                    await ref.read(authProvider.notifier).logout();
                    if (context.mounted) context.go('/login');
                  },
                  child: Ink(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: _shadow,
                    ),
                    child: Row(
                      children: [
                        _iconCircle(Icons.logout_rounded, _pink, _pinkSoft),
                        const SizedBox(width: 12),
                        Text('Se déconnecter',
                            style: AppTheme.body(size: 14, weight: FontWeight.w700, color: _pink)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _iconCircle(IconData icon, Color fg, Color bg, {double size = 36}) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Icon(icon, size: size * 0.48, color: fg),
    );

// ═══════ Haut : bannière + carte identité ═══════
class _Hero extends StatelessWidget {
  final SupplierProfileInfo profile;
  final int? productsCount;
  final VoidCallback onCopyId;
  final VoidCallback onStorefront;
  const _Hero({
    required this.profile,
    required this.productsCount,
    required this.onCopyId,
    required this.onStorefront,
  });

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final v = _verif[p.verificationStatus] ?? _verif['pending']!;
    final company = p.companyName.isNotEmpty ? p.companyName : (p.fullName ?? p.email.split('@').first);
    final initial = company.isNotEmpty ? company[0].toUpperCase() : '?';
    final shortId = p.id.length > 8 ? p.id.substring(0, 8).toUpperCase() : p.id.toUpperCase();

    final fallback = Center(
      child: Text(initial, style: AppTheme.body(size: 30, weight: FontWeight.w800, color: _orange)),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Bannière orange
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: _bannerH,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFA940), _orange],
              ),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Stack(
              children: [
                const Positioned(
                  right: -10,
                  top: -6,
                  child: Icon(Icons.storefront_rounded, size: 110, color: Color(0x26FFFFFF)),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Mon profil',
                        style: AppTheme.body(size: 22, weight: FontWeight.w800, color: Colors.white)),
                    const SizedBox(height: 2),
                    Text('Compte fournisseur',
                        style: AppTheme.body(size: 12, color: const Color(0xE6FFFFFF))),
                  ],
                ),
              ],
            ),
          ),
        ),

        // Carte identité
        Padding(
          padding: const EdgeInsets.fromLTRB(16, _bannerH - _cardOverlap, 16, 0),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: _logoSize / 2),
                padding: const EdgeInsets.fromLTRB(16, _logoSize / 2 + 12, 16, 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: _shadow,
                ),
                child: Column(
                  children: [
                    Text(company,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: AppTheme.body(size: 19, weight: FontWeight.w800, color: _ink)),
                    const SizedBox(height: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: v.bg, borderRadius: BorderRadius.circular(999)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(v.icon, size: 13, color: v.color),
                          const SizedBox(width: 5),
                          Text(v.label, style: AppTheme.body(size: 11.5, weight: FontWeight.w700, color: v.color)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    // E-mail · ID (copiable)
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _chip(Icons.mail_outline_rounded, _maskEmail(p.email)),
                        GestureDetector(
                          onTap: onCopyId,
                          child: _chip(Icons.copy_rounded, 'ID $shortId'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Stats pastel
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _stat(_orangeSoft, productsCount?.toString() ?? '—', 'produits'),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: _PlanStat()),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _stat(
                              _blueSoft,
                              p.minOrderTnd != null ? p.minOrderTnd!.round().toString() : '—',
                              'min. TND',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Vitrine
                    GestureDetector(
                      onTap: onStorefront,
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: _orange,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: const [
                            BoxShadow(color: Color(0x40FF8A00), blurRadius: 14, offset: Offset(0, 5)),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.storefront_outlined, size: 18, color: Colors.white),
                            const SizedBox(width: 8),
                            Text('Gérer ma vitrine',
                                style: AppTheme.body(size: 14.5, weight: FontWeight.w700, color: Colors.white)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Logo en relief
              Container(
                width: _logoSize,
                height: _logoSize,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: _shadow,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: ColoredBox(
                    color: _orangeSoft,
                    child: (p.logoUrl != null && p.logoUrl!.isNotEmpty)
                        ? Image.network(
                            p.logoUrl!,
                            width: _logoSize,
                            height: _logoSize,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => fallback,
                          )
                        : fallback,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static Widget _chip(IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: _tile, borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: _mute),
            const SizedBox(width: 5),
            Flexible(
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.body(size: 11.5, weight: FontWeight.w500, color: _mute)),
            ),
          ],
        ),
      );
}

Widget _stat(Color bg, String value, String label) => Container(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: AppTheme.body(size: 17, weight: FontWeight.w800, color: _ink)),
          ),
          const SizedBox(height: 2),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.body(size: 10.5, color: _mute)),
        ],
      ),
    );

/// Tuile « plan » : lit l'abonnement actuel.
class _PlanStat extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(mySubscriptionProvider).valueOrNull?.plan?.name;
    return _stat(_violetSoft, name ?? '—', 'plan');
  }
}

// ═══════ Abonnement : plan actuel + carrousel ═══════
class _SubscriptionSection extends ConsumerStatefulWidget {
  final int? productsCount;
  const _SubscriptionSection({required this.productsCount});

  @override
  ConsumerState<_SubscriptionSection> createState() => _SubscriptionSectionState();
}

class _SubscriptionSectionState extends ConsumerState<_SubscriptionSection> {
  static const _tints = [
    (_blueSoft, _blue),
    (_orangeSoft, _orange),
    (_violetSoft, _violet),
    (_greenSoft, _green),
  ];

  String? _changing;
  String? _msg;
  bool _msgErr = false;

  Future<void> _pick(String planId, String? currentId) async {
    if (planId == currentId) return;
    setState(() {
      _changing = planId;
      _msg = null;
    });
    try {
      final res = await ref.read(subscriptionsApiProvider).changePlan(planId);
      if (!mounted) return;
      if (res == null) {
        setState(() {
          _msg = 'Changement impossible.';
          _msgErr = true;
        });
      } else {
        ref.invalidate(mySubscriptionProvider);
        setState(() {
          _msg = 'Plan mis à jour.';
          _msgErr = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _msg = isNetworkError(e) ? 'Pas de connexion Internet. Plan non modifié.' : 'Changement impossible.';
          _msgErr = true;
        });
      }
    } finally {
      if (mounted) setState(() => _changing = null);
    }
  }

  String _pct(double v) => '${v.toStringAsFixed(v % 1 == 0 ? 0 : 2)}%';

  @override
  Widget build(BuildContext context) {
    final plansAsync = ref.watch(plansProvider);
    final mine = ref.watch(mySubscriptionProvider).valueOrNull;
    final currentId = mine?.plan?.id;
    final plans = plansAsync.valueOrNull ?? const <SubPlan>[];
    SubPlan? current;
    for (final pl in plans) {
      if (pl.id == currentId) current = pl;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Abonnement', style: AppTheme.body(size: 17, weight: FontWeight.w800, color: _ink)),
        const SizedBox(height: 12),

        // Plan actuel
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: _shadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(color: _orange, shape: BoxShape.circle),
                    child: const Icon(Icons.bolt_rounded, size: 24, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Plan actuel', style: AppTheme.body(size: 11.5, color: _mute)),
                        const SizedBox(height: 1),
                        Text(mine?.plan?.name ?? 'Aucun plan actif',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.body(size: 19, weight: FontWeight.w800, color: _ink)),
                      ],
                    ),
                  ),
                  if (current != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(_fmtTnd(current.priceTnd),
                            style: AppTheme.body(size: 18, weight: FontWeight.w800, color: _ink)),
                        Text('TND / mois', style: AppTheme.body(size: 10.5, color: _mute)),
                      ],
                    ),
                ],
              ),
              if (current != null) ...[
                const SizedBox(height: 16),
                _usage(current),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: _tile, borderRadius: BorderRadius.circular(999)),
                  child: Text('Commission ${_pct(current.commissionPct)}',
                      style: AppTheme.body(size: 11.5, weight: FontWeight.w600, color: _mute)),
                ),
              ],
              if (_msg != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: _msgErr ? _pinkSoft : _greenSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(_msg!,
                      style: AppTheme.body(size: 12.5, weight: FontWeight.w600, color: _msgErr ? _pink : _green)),
                ),
              ],
            ],
          ),
        ),

        // Carrousel des plans
        const SizedBox(height: 18),
        Text('Changer de plan', style: AppTheme.body(size: 13, weight: FontWeight.w600, color: _mute)),
        const SizedBox(height: 10),
        if (plansAsync.isLoading && plans.isEmpty)
          const SizedBox(height: 120, child: Center(child: CircularProgressIndicator(color: _orange)))
        else if (plansAsync.hasError && plans.isEmpty)
          Text('Impossible de charger les plans.', style: AppTheme.body(size: 13, color: _mute))
        else if (plans.isEmpty)
          Text('Aucun plan disponible.', style: AppTheme.body(size: 13, color: _mute))
        else
          SizedBox(
            height: 206,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: plans.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) => _planTile(plans[i], _tints[i % _tints.length], currentId),
            ),
          ),
      ],
    );
  }

  Widget _usage(SubPlan current) {
    final used = widget.productsCount;
    final max = current.maxProducts;
    final ratio = (used != null && max != null && max > 0) ? (used / max).clamp(0.0, 1.0) : null;
    final full = ratio != null && ratio >= 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('Produits utilisés', style: AppTheme.body(size: 12, color: _mute))),
            Text(
              max == null ? '${used ?? '—'} · illimité' : '${used ?? '—'} / $max',
              style: AppTheme.body(size: 12, weight: FontWeight.w700, color: full ? _pink : _ink),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: ratio ?? (max == null ? 1 : 0),
            minHeight: 8,
            backgroundColor: _orangeSoft,
            valueColor: AlwaysStoppedAnimation(full ? _pink : _orange),
          ),
        ),
      ],
    );
  }

  Widget _planTile(SubPlan pl, (Color, Color) tint, String? currentId) {
    final isCurrent = pl.id == currentId;
    final busy = _changing == pl.id;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 176,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tint.$1,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: isCurrent ? _orange : Colors.transparent, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(pl.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.body(size: 15, weight: FontWeight.w800, color: _ink)),
              ),
              if (isCurrent) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: _orange, borderRadius: BorderRadius.circular(999)),
                  child: Text('Actuel',
                      style: AppTheme.body(size: 9.5, weight: FontWeight.w700, color: Colors.white)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(TextSpan(
              text: _fmtTnd(pl.priceTnd),
              style: AppTheme.body(size: 22, weight: FontWeight.w800, color: _ink),
              children: [
                TextSpan(text: ' TND/mois', style: AppTheme.body(size: 10.5, weight: FontWeight.w500, color: _mute)),
              ],
            )),
          ),
          const SizedBox(height: 10),
          _feature(tint.$2, pl.maxProducts == null ? 'Produits illimités' : '${pl.maxProducts} produits'),
          const SizedBox(height: 4),
          _feature(tint.$2, 'Commission ${_pct(pl.commissionPct)}'),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 38,
            child: GestureDetector(
              onTap: (isCurrent || busy || _changing != null) ? null : () => _pick(pl.id, currentId),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isCurrent ? Colors.white : _orange,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(isCurrent ? 'Plan actuel' : 'Choisir',
                        style: AppTheme.body(
                            size: 13, weight: FontWeight.w700, color: isCurrent ? _faint : Colors.white)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _feature(Color color, String text) => Row(
        children: [
          Icon(Icons.check_circle_rounded, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.body(size: 12, color: _ink)),
          ),
        ],
      );
}

// ═══════ Groupes de réglages ═══════
class _RowData {
  final IconData icon;
  final Color fg;
  final Color bg;
  final String label;
  final String value;
  final VoidCallback? onTap;
  const _RowData(this.icon, this.fg, this.bg, this.label, this.value, {this.onTap});
}

class _SettingsGroup extends StatelessWidget {
  final String title;
  final List<_RowData> rows;
  const _SettingsGroup({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTheme.body(size: 17, weight: FontWeight.w800, color: _ink)),
          const SizedBox(height: 12),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: _shadow,
            ),
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) _row(rows[i], i == 0),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(_RowData r, bool first) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: r.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            border: first ? null : const Border(top: BorderSide(color: _divider)),
          ),
          child: Row(
            children: [
              _iconCircle(r.icon, r.fg, r.bg),
              const SizedBox(width: 12),
              Expanded(
                flex: 5,
                child: Text(r.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.body(size: 13.5, weight: FontWeight.w500, color: _ink)),
              ),
              if (r.value.isNotEmpty)
                Expanded(
                  flex: 4,
                  child: Text(r.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: AppTheme.body(size: 12.5, color: _faint)),
                ),
              if (r.onTap != null)
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(Icons.chevron_right_rounded, size: 20, color: _faint),
                ),
            ],
          ),
        ),
      ),
    );
  }
}