import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'services/saree_backend.dart';
import 'theme/saree_design_system.dart';
import 'features/cart/cart_controller.dart';


List<String> _mealPhotoUrls(Map<String, dynamic> item) {
  final raw = item['image_url']?.toString().trim() ?? '';
  if (raw.isEmpty) return [];
  if (raw.startsWith('[')) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final urls = decoded.map((value) => value.toString().trim())
            .where((value) => value.startsWith('https://') || value.startsWith('http://'))
            .toSet().toList();
        if (urls.isNotEmpty) return urls;
      }
    } catch (_) {}
  }
  if (raw.startsWith('https://') || raw.startsWith('http://')) return [raw];
  return [];
}

String _mealPhotoUrl(Map<String, dynamic> item) {
  final saved = _mealPhotoUrls(item).firstOrNull ?? '';
  final restaurantData = item['restaurants'];
  final restaurantCover = restaurantData is Map
      ? restaurantData['cover_image_url']?.toString().trim() ?? ''
      : '';
  // Restaurant covers belong to restaurant cards/headers, never individual meal tiles.
  if ((saved.startsWith('https://') || saved.startsWith('http://')) &&
      saved != restaurantCover) return saved;
  final category = item['menu_categories'];
  final text = '${item['name'] ?? ''} ${item['description'] ?? ''} ${category is Map ? category['name'] ?? '' : ''}'.toLowerCase();
  String photo;
  if (text.contains('برجر') || text.contains('burger')) {
    photo = 'photo-1568901346375-23c9450c58cd';
  } else if (text.contains('بيتزا') || text.contains('pizza')) {
    photo = 'photo-1571407970349-bc81e7e96d47';
  } else if (text.contains('شاورما') || text.contains('shawarma')) {
    photo = 'photo-1529006557810-274b9b2fc783';
  } else if (text.contains('سمك') || text.contains('جمبري') || text.contains('بحري') || text.contains('fish')) {
    photo = 'photo-1519708227418-c8fd9a32b7a2';
  } else if (text.contains('حلويات') || text.contains('كيك') || text.contains('حلو') || text.contains('dessert')) {
    photo = 'photo-1488477181946-6428a0291777';
  } else if (text.contains('بروست') || text.contains('دجاج') || text.contains('chicken')) {
    photo = 'photo-1626082927389-6cd097cdc6ec';
  } else if (text.contains('مندي') || text.contains('رز') || text.contains('لحم') || text.contains('كبسة')) {
    photo = 'photo-1604908176997-125f25cc6f3d';
  } else if (text.contains('سلتة') || text.contains('فحسة') || text.contains('يمني')) {
    photo = 'photo-1547592180-85f173990554';
  } else {
    photo = 'photo-1546069901-ba9599a7e63c';
  }
  return 'https://images.unsplash.com/$photo?auto=format&fit=crop&w=720&q=82';
}

Map<String, dynamic>? _activeItemPromotion(Map<String, dynamic> item) {
  final candidates = <Map<String, dynamic>>[];
  final raw = item['promotions'];
  if (raw is List) {
    candidates.addAll(raw.whereType<Map>().map((row) => Map<String, dynamic>.from(row)));
  } else if (raw is Map) {
    candidates.add(Map<String, dynamic>.from(raw));
  }
  final links = item['promotion_menu_items'];
  if (links is List) {
    for (final link in links.whereType<Map>()) {
      final promotion = link['promotions'];
      if (promotion is Map) candidates.add(Map<String, dynamic>.from(promotion));
    }
  }
  final now = DateTime.now().toUtc();
  for (final promotion in candidates) {
    if (promotion['is_active'] != true) continue;
    final startsAt = DateTime.tryParse(promotion['starts_at']?.toString() ?? '');
    final endsAt = DateTime.tryParse(promotion['ends_at']?.toString() ?? '');
    if (startsAt != null && startsAt.isAfter(now)) continue;
    if (endsAt != null && !endsAt.isAfter(now)) continue;
    return promotion;
  }
  return null;
}

int _effectiveItemPrice(Map<String, dynamic> item) {
  final basePrice = (item['price_yer'] as num? ?? 0).toInt();
  final promotion = _activeItemPromotion(item);
  if (promotion == null) return basePrice;
  final value = (promotion['discount_value'] as num? ?? 0).toInt();
  if (promotion['discount_type'] == 'percentage') {
    final discounted = (basePrice * (100 - value) / 100).floor();
    return discounted < 1 ? 1 : discounted;
  }
  final discounted = basePrice - value;
  return discounted < 1 ? 1 : discounted;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SareeBackend.initialize();
  final cartController = await CartController.create();
  runApp(ChangeNotifierProvider.value(
    value: cartController,
    child: const SareeApp(),
  ));
}

Future<void> showAccountSignOutOptions(BuildContext context) async {
  final scope = await showDialog<SignOutScope>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('تسجيل الخروج'),
      content: const Text('اختر طريقة تسجيل الخروج. يمكنك تسجيل الدخول إلى الحساب مرة أخرى في أي وقت.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, SignOutScope.local), child: const Text('من هذا الجهاز فقط')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, SignOutScope.global), child: const Text('من جميع الأجهزة')),
      ],
    ),
  );
  if (scope == null) return;
  try {
    await SareeBackend.signOut(scope: scope);
  } catch (error) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تعذر تسجيل الخروج: ${SareeBackend.arabicError(error)}')),
    );
  }
}

Future<void> showRestaurantSignOutOptions(BuildContext context) async {
  final choice = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('حساب المطعم'),
      content: const Text('يمكنك الخروج من هذا الجهاز أو من جميع الأجهزة. إغلاق الحساب نهائياً يمنع استخدام الحساب القديم ويتيح إنشاء حساب جديد.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, 'cancel'), child: const Text('إلغاء')),
        TextButton(onPressed: () => Navigator.pop(dialogContext, 'local'), child: const Text('خروج من هذا الجهاز')),
        TextButton(onPressed: () => Navigator.pop(dialogContext, 'global'), child: const Text('خروج من جميع الأجهزة')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF065F46)),
          onPressed: () => Navigator.pop(dialogContext, 'close'),
          child: const Text('إغلاق الحساب نهائياً'),
        ),
      ],
    ),
  );
  if (choice == null || choice == 'cancel') return;
  if (choice == 'local' || choice == 'global') {
    await SareeBackend.signOut(scope: choice == 'global' ? SignOutScope.global : SignOutScope.local);
    return;
  }
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('تأكيد إغلاق الحساب نهائياً'),
      content: const Text('سيتم إيقاف المطعم وإغلاق حساب الدخول القديم نهائياً. ستبقى سجلات الطلبات السابقة محفوظة، ولن يمكن استعادة الحساب القديم. هل تريد المتابعة؟'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('تراجع')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF065F46)),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('نعم، أغلق الحساب'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  try {
    await SareeBackend.permanentlyCloseRestaurantAccount();
  } catch (error) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تعذر إغلاق الحساب: ${SareeBackend.arabicError(error)}')),
    );
  }
}

class SareeApp extends StatelessWidget {
  const SareeApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'سريع',
    debugShowCheckedModeBanner: false,
    theme: SareeDesignSystem.lightTheme,
    darkTheme: SareeDesignSystem.darkTheme,
    themeMode: ThemeMode.system,
    builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: SareeFoodBackdrop(child: child ?? const SizedBox.shrink())),
    home: const BrandSplashGate(),
  );
}

class SareeFoodBackdrop extends StatelessWidget {
  const SareeFoodBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Stack(fit: StackFit.expand, children: [
      DecoratedBox(decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: isDark
              ? const [Color(0xFF101B17), Color(0xFF14231D), Color(0xFF182820)]
              : const [Color(0xFFFFF8E7), Color(0xFFFFFDF5), Color(0xFFEAF3E9)],
        ),
      )),
      Positioned(top: 115, right: 12, child: Opacity(opacity: isDark ? .035 : .055, child: const Icon(Icons.lunch_dining_rounded, size: 112, color: Color(0xFFFFD60A)))),
      Positioned(top: 330, left: -18, child: Opacity(opacity: isDark ? .025 : .045, child: const Icon(Icons.local_pizza_rounded, size: 145, color: Color(0xFF047857)))),
      Positioned(bottom: 125, right: -15, child: Opacity(opacity: isDark ? .03 : .05, child: const Icon(Icons.ramen_dining_rounded, size: 132, color: Color(0xFFFFD60A)))),
      Positioned(bottom: 18, left: 75, child: Opacity(opacity: isDark ? .025 : .04, child: const Icon(Icons.local_cafe_rounded, size: 92, color: Color(0xFF047857)))),
      Positioned.fill(child: child),
    ]);
  }
}

class RotatingFoodImage extends StatefulWidget {
  const RotatingFoodImage({
    super.key,
    required this.urls,
    this.fallbackIcon = Icons.restaurant_rounded,
  });

  final List<String> urls;
  final IconData fallbackIcon;

  @override
  State<RotatingFoodImage> createState() => _RotatingFoodImageState();
}

class _RotatingFoodImageState extends State<RotatingFoodImage> {
  int _index = 0;
  Timer? _timer;

  List<String> get _photos => widget.urls.where((url) => url.trim().isNotEmpty).toList();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted && _photos.length > 1) setState(() => _index = (_index + 1) % _photos.length);
    });
  }

  @override
  void didUpdateWidget(covariant RotatingFoodImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.urls != widget.urls) _index = 0;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photos = _photos;
    if (photos.isEmpty) {
      return ColoredBox(
        color: const Color(0xFFFFF8E7),
        child: Center(child: Icon(widget.fallbackIcon, size: 36, color: const Color(0xFF047857))),
      );
    }
    final index = _index % photos.length;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      child: Image.network(
        photos[index],
        key: ValueKey<String>(photos[index]),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => ColoredBox(
          color: const Color(0xFFFFF8E7),
          child: Center(child: Icon(widget.fallbackIcon, size: 36, color: const Color(0xFF047857))),
        ),
      ),
    );
  }
}

class FoodPhotoBanner extends StatefulWidget {
  const FoodPhotoBanner({
    super.key,
    required this.title,
    required this.subtitle,
    this.height = 190,
  });

  final String title;
  final String subtitle;
  final double height;

  static const List<String> photoUrls = [
    'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?auto=format&fit=crop&w=1200&q=88',
    'https://images.unsplash.com/photo-1571407970349-bc81e7e96d47?auto=format&fit=crop&w=1200&q=88',
    'https://images.unsplash.com/photo-1626082927389-6cd097cdc6ec?auto=format&fit=crop&w=1200&q=88',
  ];

  @override
  State<FoodPhotoBanner> createState() => _FoodPhotoBannerState();
}

class _FoodPhotoBannerState extends State<FoodPhotoBanner> {
  int _photoIndex = 0;
  Timer? _photoTimer;

  @override
  void initState() {
    super.initState();
    _photoTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) setState(() => _photoIndex = (_photoIndex + 1) % FoodPhotoBanner.photoUrls.length);
    });
  }

  @override
  void dispose() {
    _photoTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(24),
    child: SizedBox(
      height: widget.height,
      width: double.infinity,
      child: Stack(fit: StackFit.expand, children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 650),
          switchInCurve: Curves.easeInOut,
          switchOutCurve: Curves.easeInOut,
          child: Image.network(
            FoodPhotoBanner.photoUrls[_photoIndex],
            key: ValueKey<int>(_photoIndex),
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (context, error, stack) => const ColoredBox(
              color: Color(0xFF065F46),
              child: Center(child: Icon(Icons.restaurant_menu_rounded, size: 54, color: Color(0xFFFFD60A))),
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x22000000), Color(0xE6000000)],
              stops: [0.08, 1],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(widget.title, style: const TextStyle(
                color: Colors.white, fontSize: 23, fontWeight: FontWeight.w900,
                shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
              )),
              const SizedBox(height: 5),
              Text(widget.subtitle, style: const TextStyle(
                color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700,
                shadows: [Shadow(color: Colors.black87, blurRadius: 7)],
              )),
            ],
          ),
        ),
      ]),
    ),
  );
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 88});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF10A879), Color(0xFF047857), Color(0xFF064E3B)],
      ),
      borderRadius: BorderRadius.circular(size * .29),
      border: Border.all(color: const Color(0xFFFFD60A), width: size * .025),
      boxShadow: const [
        BoxShadow(color: Color(0x55000000), blurRadius: 18, offset: Offset(0, 7)),
      ],
    ),
    child: Stack(alignment: Alignment.center, children: [
      Positioned(
        left: size * .10,
        top: size * .29,
        child: Column(children: [
          Container(width: size * .25, height: size * .045, decoration: BoxDecoration(color: const Color(0xFFFFD60A), borderRadius: BorderRadius.circular(8))),
          SizedBox(height: size * .075),
          Container(width: size * .18, height: size * .04, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8))),
        ]),
      ),
      Container(
        width: size * .68,
        height: size * .68,
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8E7),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF047857), width: size * .045),
        ),
        child: Icon(Icons.delivery_dining_rounded, color: const Color(0xFFFFD60A), size: size * .48),
      ),
      Positioned(
        right: size * .08,
        bottom: size * .10,
        child: Icon(Icons.bolt_rounded, color: Colors.white, size: size * .25),
      ),
    ]),
  );
}

class BrandSplashGate extends StatefulWidget {
  const BrandSplashGate({super.key});
  @override
  State<BrandSplashGate> createState() => _BrandSplashGateState();
}

class _BrandSplashGateState extends State<BrandSplashGate> {
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 1900), () {
      if (mounted) setState(() => _finished = true);
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 450),
    switchInCurve: Curves.easeOutCubic,
    switchOutCurve: Curves.easeInCubic,
    child: _finished
      ? const SareeGate(key: ValueKey('app'))
      : Scaffold(
          key: const ValueKey('splash'),
          body: Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [Color(0xFF047857), Color(0xFF047857), Color(0xFF123B2F)],
                stops: [0, .58, 1],
              ),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.65, end: 1),
                    duration: const Duration(milliseconds: 850),
                    curve: Curves.elasticOut,
                    builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
                    child: Container(
                    width: 142,
                    height: 142,
                    decoration: BoxDecoration(
                      color: const Color(0xFF123B2F),
                      borderRadius: BorderRadius.circular(42),
                      border: Border.all(color: Colors.white.withValues(alpha: .85), width: 3),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .22), blurRadius: 28, offset: const Offset(0, 12))],
                    ),
                    child: const BrandMark(size: 112),
                  ),
                  ),
                  const SizedBox(height: 22),
                  const Text('سريع', style: TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.w900, letterSpacing: 1)),
                  const SizedBox(height: 6),
                  const Text('طعامك يصل إليك', style: TextStyle(color: Colors.white70, fontSize: 17, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 34),
                  const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white)),
                ],
              ),
            ),
          ),
        ),
  );
}

class SareeGate extends StatelessWidget {
  const SareeGate({super.key});

  @override
  Widget build(BuildContext context) {
    if (!SareeBackend.isConfigured) return const SetupRequiredPage();
    return StreamBuilder<AuthState>(
      stream: SareeBackend.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (SareeBackend.user == null) return const AuthPage();
        return FutureBuilder<Map<String, dynamic>>(
          future: SareeBackend.profile(),
          builder: (context, profile) {
            if (profile.connectionState != ConnectionState.done) {
              return const LoadingPage();
            }
            if (profile.hasError) return ErrorPage(message: SareeBackend.arabicError(profile.error));
            if (profile.data?['is_blocked'] == true) return const AccountClosedPage();
            final role = profile.data?['role']?.toString() ?? 'customer';
            final approval = profile.data?['approval_status']?.toString() ?? 'approved';
            if (role == 'courier') {
              return FutureBuilder<bool>(
                future: SareeBackend.hasCourierVerificationDocuments(),
                builder: (context, docs) {
                  if (docs.connectionState != ConnectionState.done) return const LoadingPage();
                  if (docs.hasError) return ErrorPage(message: SareeBackend.arabicError(docs.error));
                  if (docs.data != true) return const CourierVerificationPage();
                  return const CourierPortal();
                },
              );
            }
            if (approval != 'approved' && role != 'admin') return PendingApprovalPage(status: approval, note: profile.data?['approval_note']?.toString());
            if (role == 'restaurant_owner') return const RestaurantPortal();
            if (role == 'admin') return const AdminPortal();
            return FutureBuilder<Map<String, dynamic>?>(
              future: SareeBackend.cashierRestaurant(),
              builder: (context, cashier) {
                if (cashier.connectionState != ConnectionState.done) return const LoadingPage();
                if (cashier.hasError) return ErrorPage(message: SareeBackend.arabicError(cashier.error));
                if (cashier.data != null) return CashierPortal(restaurant: cashier.data!);
                return const CustomerHome();
              },
            );
          },
        );
      },
    );
  }
}


class AccountClosedPage extends StatelessWidget {
  const AccountClosedPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.no_accounts_rounded, size: 64, color: Color(0xFFFFD60A)),
        const SizedBox(height: 16),
        const Text('تم إغلاق هذا الحساب نهائياً', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900), textAlign: TextAlign.center),
        const SizedBox(height: 10),
        const Text('لم يعد بإمكانك الدخول بهذا الحساب. يمكنك إنشاء حساب جديد للانضمام إلى سريع.', textAlign: TextAlign.center),
        const SizedBox(height: 20),
        FilledButton(onPressed: () => SareeBackend.signOut(scope: SignOutScope.local), child: const Text('العودة إلى تسجيل الدخول')),
      ]),
    )),
  );
}

class PendingApprovalPage extends StatelessWidget {
  const PendingApprovalPage({super.key, required this.status, this.note});
  final String status;
  final String? note;
  @override
  Widget build(BuildContext context) {
    final rejected = status == 'rejected';
    return Scaffold(
      body: Center(child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(rejected ? Icons.cancel_outlined : Icons.hourglass_top_rounded, size: 68, color: rejected ? Colors.red : const Color(0xFFFFD60A)),
          const SizedBox(height: 16),
          Text(rejected ? 'لم تتم الموافقة على الحساب' : 'حسابك قيد المراجعة', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Text(note?.isNotEmpty == true ? note! : rejected ? 'يرجى التواصل مع إدارة سريع لمعرفة التفاصيل.' : 'سيتم تفعيل حسابك بعد مراجعة الإدارة واعتماد بياناتك.', textAlign: TextAlign.center),
          const SizedBox(height: 20),
          FilledButton(onPressed: () => showAccountSignOutOptions(context), child: const Text('تسجيل الخروج')),
        ]),
      )),
    );
  }
}

class WalletPage extends StatefulWidget {
  const WalletPage({super.key});
  @override State<WalletPage> createState() => _WalletPageState();
}
class _WalletPageState extends State<WalletPage> {
  late Future<Map<String,dynamic>> _balance;
  late Future<List<Map<String,dynamic>>> _transactions;
  @override
  void initState() { super.initState(); _load(); }
  void _load() { _balance=SareeBackend.walletBalance(); _transactions=SareeBackend.walletTransactions(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('محفظتي'), actions: [IconButton(onPressed: () => setState(_load), icon: const Icon(Icons.refresh))]),
    body: RefreshIndicator(onRefresh: () async => setState(_load), child: ListView(padding: const EdgeInsets.all(16), children: [
      FutureBuilder<Map<String,dynamic>>(future:_balance,builder:(context,snap) {
        if(snap.hasError) return Text('تعذر تحميل الرصيد: ${SareeBackend.arabicError(snap.error)}');
        if(!snap.hasData) return const LinearProgressIndicator();
        final amount=(snap.data!['balance_yer'] as num?)?.toInt() ?? 0;
        return Container(padding:const EdgeInsets.all(22),decoration:BoxDecoration(gradient:const LinearGradient(colors:[Color(0xFF047857),Color(0xFFFFD60A)]),borderRadius:BorderRadius.circular(22)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          const Text('الرصيد الحالي',style:TextStyle(color:Colors.white70)),
          const SizedBox(height:8),
          Text('$amount ريال يمني'.replaceFirst('$amount', amount.toString()),style:const TextStyle(color:Colors.white,fontSize:28,fontWeight:FontWeight.w900)),
          const SizedBox(height:6),
          const Text('الرصيد يعكس الحركات المسجلة فعليًا في حسابك.',style:TextStyle(color:Colors.white)),
        ]));
      }),
      const Padding(padding:EdgeInsets.symmetric(vertical:18),child:Text('سجل العمليات',style:TextStyle(fontSize:19,fontWeight:FontWeight.w900))),
      FutureBuilder<List<Map<String,dynamic>>>(future:_transactions,builder:(context,snap) {
        if(snap.hasError) return Text('تعذر تحميل العمليات: ${SareeBackend.arabicError(snap.error)}');
        if(!snap.hasData) return const Center(child:CircularProgressIndicator());
        final rows=snap.data!;
        if(rows.isEmpty) return const Padding(padding:EdgeInsets.all(20),child:Text('لا توجد عمليات مالية مسجلة حتى الآن.'));
        return Column(children:rows.map((row) {
          final amount=(row['amount_yer'] as num).toInt();
          return Card(child:ListTile(leading:Icon(amount>0?Icons.add_circle:Icons.remove_circle,color:amount>0?Colors.green:Colors.red),title:Text(row['note']?.toString().isNotEmpty==true?row['note'].toString():row['kind'].toString()),subtitle:Text(row['created_at'].toString()),trailing:Text('${amount>0?'+':''}$amount ريال',style:TextStyle(fontWeight:FontWeight.bold,color:amount>0?Colors.green:Colors.red))));
        }).toList());
      }),
      const SizedBox(height:12),
      const Text('لا تتوفر تعبئة ذاتية للمحفظة حاليًا؛ تُسجّل الحركات من الإدارة أو عبر استرداد موثق.',style:TextStyle(color:Colors.black54)),
    ])),
  );
}

class SetupRequiredPage extends StatelessWidget {
  const SetupRequiredPage({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(child: Padding(
      padding: EdgeInsets.all(28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.cloud_off, size: 64, color: const Color(0xFF047857)),
        SizedBox(height: 16),
        Text('سريع يحتاج إلى ربط الخادم', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        SizedBox(height: 8),
        Text('لم تُضف بيانات مشروع Supabase إلى إعدادات البناء بعد. أضف SUPABASE_URL و SUPABASE_ANON_KEY ثم أعد بناء التطبيق.', textAlign: TextAlign.center),
      ]),
    )),
  );
}

class LoadingPage extends StatelessWidget {
  const LoadingPage({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class ErrorPage extends StatelessWidget {
  const ErrorPage({super.key, required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline, size: 52, color: Colors.red),
        const SizedBox(height: 12),
        const Text('تعذر تحميل الحساب'),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        FilledButton(onPressed: () => showAccountSignOutOptions(context), child: const Text('تسجيل الخروج')),
      ]),
    )),
  );
}

class CourierVerificationPage extends StatefulWidget {
  const CourierVerificationPage({super.key});
  @override State<CourierVerificationPage> createState() => _CourierVerificationPageState();
}

class _CourierVerificationPageState extends State<CourierVerificationPage> {
  final ImagePicker _picker = ImagePicker();
  final Map<String, XFile?> _files = {'id_front': null, 'id_back': null, 'selfie': null, 'residence': null};
  bool _busy = false;
  String? _message;

  Future<void> _pick(String type) async {
    final file = await _picker.pickImage(
      source: type == 'selfie' ? ImageSource.camera : ImageSource.gallery,
      preferredCameraDevice: CameraDevice.front,
      imageQuality: 82,
      maxWidth: 1800,
    );
    if (file != null && mounted) setState(() { _files[type] = file; _message = null; });
  }

  Future<String> _validateIdentityImages() async {
    final front = _files['id_front']!;
    final back = _files['id_back']!;
    final selfie = _files['selfie']!;
    final frontBytes = await front.readAsBytes();
    final backBytes = await back.readAsBytes();
    final selfieBytes = await selfie.readAsBytes();

    if ([frontBytes, backBytes, selfieBytes].any((bytes) => bytes.length < 18 * 1024 || bytes.length > 8 * 1024 * 1024)) {
      return 'إحدى الصور صغيرة جدًا أو كبيرة جدًا. أعد تصوير الهوية والسيلفي بوضوح.';
    }
    bool sameBytes(List<int> a, List<int> b) =>
        a.length == b.length && a.asMap().entries.every((entry) => entry.value == b[entry.key]);
    if (sameBytes(frontBytes, backBytes) || sameBytes(frontBytes, selfieBytes) || sameBytes(backBytes, selfieBytes)) {
      return 'لا يمكن استخدام الصورة نفسها لأكثر من مستند. التقط كل صورة بشكل مستقل.';
    }

    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    final detector = FaceDetector(options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      enableLandmarks: false,
      enableContours: false,
      enableClassification: false,
    ));
    try {
      final frontText = await recognizer.processImage(InputImage.fromFilePath(front.path));
      final backText = await recognizer.processImage(InputImage.fromFilePath(back.path));
      final selfieText = await recognizer.processImage(InputImage.fromFilePath(selfie.path));
      final frontPlain = frontText.text.replaceAll(RegExp(r'\s+'), '');
      final backPlain = backText.text.replaceAll(RegExp(r'\s+'), '');
      final selfiePlain = selfieText.text.replaceAll(RegExp(r'\s+'), '');
      final allIdText = '$frontPlain$backPlain';
      final digitCount = RegExp(r'\d').allMatches(allIdText).length;

      if (frontPlain.length < 5 || backPlain.length < 3 || digitCount < 3) {
        return 'لم نستطع قراءة بيانات كافية من صور البطاقة. أعد تصوير الوجهين بإضاءة جيدة، واجعل النص والأرقام واضحين بالكامل.';
      }
      if (selfiePlain.length < 3) {
        return 'يجب أن تظهر البطاقة بوضوح بجانب وجهك في صورة السيلفي، مع ظهور بعض بياناتها.';
      }

      final faces = await detector.processImage(InputImage.fromFilePath(selfie.path));
      if (faces.length != 1) {
        return faces.isEmpty
            ? 'لم يتم اكتشاف وجه في السيلفي. التقط صورة مباشرة يظهر فيها وجهك والبطاقة معًا.'
            : 'يجب أن يظهر وجه شخص واحد فقط في صورة السيلفي.';
      }
      return '';
    } finally {
      await recognizer.close();
      await detector.close();
    }
  }

  Future<void> _submit() async {
    if (_files['id_front'] == null || _files['id_back'] == null || _files['selfie'] == null) {
      setState(() => _message = 'يرجى إرفاق صورتي الهوية والتقاط سيلفي مع البطاقة قبل الإرسال.');
      return;
    }
    setState(() { _busy = true; _message = null; });
    try {
      final validationMessage = await _validateIdentityImages();
      if (validationMessage.isNotEmpty) {
        if (mounted) setState(() => _message = validationMessage);
        return;
      }
      await SareeBackend.uploadCourierVerificationDocuments(Map.fromEntries(_files.entries.where((entry) => entry.value != null).map((entry) => MapEntry(entry.key, entry.value!))));
      if (!mounted) return;
      setState(() => _message = 'اجتازت الصور فحص وضوح النصوص ووجود الوجه في السيلفي. هذا فحص آلي أولي وليس إثباتًا رسميًا لأصالة الهوية. يمكنك الآن التقديم للمطاعم.');
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (mounted) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const CourierPortal()));
    } catch (e) {
      if (mounted) setState(() => _message = SareeBackend.arabicError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _documentTile(String type, String title, String hint, IconData icon) {
    final file = _files[type];
    return Card(child: ListTile(
      leading: Icon(icon, size: 30),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(file?.name ?? hint, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Icon(file == null ? Icons.upload_file_rounded : Icons.check_circle_rounded,
        color: file == null ? Colors.amber : Colors.green),
      onTap: _busy ? null : () => _pick(type),
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('إرفاق مستندات الهوية'), automaticallyImplyLeading: false,
      actions: [IconButton(tooltip: 'خيارات تسجيل الخروج', onPressed: _busy ? null : () => showAccountSignOutOptions(context), icon: const Icon(Icons.logout_rounded))]),
    body: SafeArea(child: ListView(padding: const EdgeInsets.all(18), children: [
      const Icon(Icons.verified_user_rounded, size: 58, color: Color(0xFFFFD60A)),
      const SizedBox(height: 12),
      const Text('أرفق مستندات هويتك للتقديم للعمل لدى مطاعم سريع', textAlign: TextAlign.center,
        style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      const Text('لن نقبل الصور العشوائية: يفحص التطبيق وضوح النصوص والأرقام في وجهي البطاقة، ويتأكد من وجود وجه واحد وظهور نص البطاقة في السيلفي. هذا فحص آلي أولي ولا يثبت وحده أن الهوية أصلية أو غير مزورة.',
        textAlign: TextAlign.center),
      const SizedBox(height: 18),
      _documentTile('id_front', 'الهوية الشخصية – الوجه الأمامي', 'صورة واضحة للوجه الأمامي للبطاقة', Icons.badge_outlined),
      _documentTile('id_back', 'الهوية الشخصية – الوجه الخلفي', 'صورة واضحة للوجه الخلفي للبطاقة', Icons.badge_rounded),
      _documentTile('selfie', 'سيلفي مباشر مع البطاقة', 'التقط صورة بالكاميرا الأمامية وأنت تحمل هويتك بجانب وجهك، مع ظهور الوجه والبطاقة بوضوح', Icons.camera_front_rounded),
      _documentTile('residence', 'إثبات محل الإقامة (اختياري)', 'يمكنك إرفاق فاتورة أو مستند يوضح محل إقامتك، ويمكنك تركه فارغًا', Icons.home_work_outlined),
      const Padding(padding: EdgeInsets.only(top: 2, bottom: 10), child: Text('إثبات محل الإقامة اختياري تمامًا ولن يمنع إرسال طلبك إذا لم ترفقه. لا ترفع صورة شخصية منفصلة؛ المطلوب سيلفي مباشر مع البطاقة.', style: TextStyle(color: Color(0xFF536B61), height: 1.5))),
      if (_message != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(_message!, textAlign: TextAlign.center,
          style: TextStyle(color: _message!.startsWith('تم') ? Colors.green : Colors.red))),
      const SizedBox(height: 8),
      FilledButton.icon(onPressed: _busy ? null : _submit,
        icon: _busy ? const SizedBox(width: 18,height:18,child:CircularProgressIndicator(strokeWidth:2)) : const Icon(Icons.cloud_upload_outlined),
        label: Text(_busy ? 'جارٍ رفع المستندات...' : 'إرسال المستندات وتفعيل الحساب')),
    ])),
  );
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _otp = TextEditingController();
  bool _awaitingEmailCode = false;
  bool _register = false;
  String _requestedRole = 'customer';
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _name.dispose(); _phone.dispose(); _email.dispose(); _password.dispose(); _otp.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() { _busy = true; _message = null; });
    try {
      if (_awaitingEmailCode) {
        await SareeBackend.verifySignupEmail(email: _email.text, token: _otp.text);
        if (mounted) setState(() => _message = 'تم تأكيد البريد الإلكتروني بنجاح.');
      } else if (_register) {
        await SareeBackend.signUp(
          email: _email.text,
          password: _password.text,
          fullName: _name.text,
          phone: _phone.text,
          requestedRole: _requestedRole,
        );
        if (mounted) setState(() {
          _awaitingEmailCode = true;
          _message = 'أرسلنا رمز تحقق من 6 أرقام إلى بريدك الإلكتروني. أدخل الرمز لإكمال إنشاء الحساب.';
        });
      } else {
        await SareeBackend.signIn(_email.text, _password.text);
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _message = SareeBackend.arabicError(e));
    } catch (e) {
      if (mounted) setState(() => _message = SareeBackend.arabicError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resendEmailCode() async {
    setState(() { _busy = true; _message = null; });
    try {
      await SareeBackend.resendSignupEmail(_email.text);
      if (mounted) setState(() => _message = 'تم إرسال رمز تحقق جديد إلى بريدك الإلكتروني.');
    } on AuthException catch (e) {
      if (mounted) setState(() => _message = SareeBackend.arabicError(e));
    } catch (e) {
      if (mounted) setState(() => _message = SareeBackend.arabicError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Form(key: _form, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const FoodPhotoBanner(
            title: 'وجبات شهية من مطاعم قريب منك',
            subtitle: 'اختر وجبتك المفضلة ودع سريع يوصلها إليك',
            height: 172,
          ),
          const SizedBox(height: 14),
          const Text('سريع', textAlign: TextAlign.center, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
          const Text('طعامك يصل إليك', textAlign: TextAlign.center),
          const SizedBox(height: 28),
          Text(_register ? 'إنشاء حساب جديد' : 'تسجيل الدخول', textAlign: TextAlign.center, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
          const SizedBox(height: 18),
          if (_awaitingEmailCode) ...[
            const Text('تأكيد البريد الإلكتروني', textAlign: TextAlign.center, style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('أدخل الرمز المكوّن من 6 أرقام الذي أرسلناه إلى ${_email.text.trim()}', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            TextFormField(
              controller: _otp,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(labelText: 'رمز التحقق', hintText: '000000', counterText: ''),
              validator: (v) => (v == null || !RegExp(r'^\d{6}$').hasMatch(v.trim())) ? 'أدخل رمز التحقق المكوّن من 6 أرقام' : null,
            ),
          ] else ...[
            if (_register) ...[
              DropdownButtonFormField<String>(
                value: _requestedRole,
                decoration: const InputDecoration(labelText: 'نوع الحساب'),
                items: const [
                  DropdownMenuItem(value: 'customer', child: Text('عميل')),
                  DropdownMenuItem(value: 'courier', child: Text('مندوب توصيل — يتطلب فحص الهوية')),
                  DropdownMenuItem(value: 'restaurant_owner', child: Text('صاحب مطعم — يتطلب اعتماد الإدارة')),
                ],
                onChanged: (value) => setState(() => _requestedRole = value ?? 'customer'),
              ),
              if (_requestedRole == 'courier') ...[
                const SizedBox(height: 10),
                Card(
                  color: const Color(0xFFFFF8E7),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Row(children: [
                        Icon(Icons.verified_user_outlined, color: Color(0xFF765B00)),
                        SizedBox(width: 8),
                        Expanded(child: Text('متطلبات توثيق حساب المندوب', style: TextStyle(fontWeight: FontWeight.w900))),
                      ]),
                      const SizedBox(height: 8),
                      const Text('بعد إنشاء الحساب ستحتاج إلى إرفاق:'),
                      const SizedBox(height: 5),
                      const Text('• صورة الهوية من الأمام (مطلوبة)'),
                      const Text('• صورة الهوية من الخلف (مطلوبة)'),
                      const Text('• سيلفي مباشر بالكاميرا الأمامية وأنت تحمل البطاقة بجانب وجهك (مطلوب)'),
                      const Text('• إثبات محل الإقامة غير مطلوب'),
                      const SizedBox(height: 6),
                      const Text('سيُفحص محتوى الصور آليًا قبل التفعيل. الصور غير الواضحة أو التي لا تحتوي على نصوص وبيانات كافية ستُرفض. الفحص الآلي لا يغني عن التحقق الرسمي من أصالة البطاقة.', style: TextStyle(height: 1.4)),
                    ]),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'الاسم الكامل'), validator: (v) => (v == null || v.trim().length < 2) ? 'أدخل اسمك' : null),
              const SizedBox(height: 12),
              TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف'), validator: (v) => (v == null || v.trim().length < 7) ? 'أدخل رقم هاتف صحيحاً' : null),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'البريد الإلكتروني'),
              validator: (v) {
                final value = (v ?? '').trim();
                if (_register) {
                  return !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)
                      ? 'أدخل بريدًا إلكترونيًا صحيحًا'
                      : null;
                }
                return value.isEmpty || (!value.contains('@') && value.replaceAll(RegExp(r'[^0-9]'), '').length < 7)
                    ? 'أدخل بريدًا صحيحًا أو رقم هاتف المندوب'
                    : null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة المرور'), validator: (v) => (v == null || v.length < 6) ? 'كلمة المرور 6 أحرف على الأقل' : null),
          ],
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(_message!, style: TextStyle(color: _message!.startsWith('تم') ? Colors.green : Colors.red)),
          ],
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(_awaitingEmailCode ? 'تأكيد البريد' : (_register ? 'إنشاء الحساب' : 'دخول')),
          ),
          if (!_register && !_awaitingEmailCode) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : () async {
                setState(() { _busy = true; _message = null; });
                try {
                  await SareeBackend.signInWithGoogle();
                } catch (error) {
                  if (mounted) setState(() => _message = SareeBackend.arabicError(error));
                } finally {
                  if (mounted) setState(() => _busy = false);
                }
              },
              icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
              label: const Text('المتابعة باستخدام Google'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Color(0xFFFFD60A)),
                minimumSize: const Size.fromHeight(50),
              ),
            ),
          ],
          if (_awaitingEmailCode) ...[
            TextButton(onPressed: _busy ? null : _resendEmailCode, child: const Text('إعادة إرسال رمز التحقق')),
            TextButton(
              onPressed: _busy ? null : () => setState(() {
                _awaitingEmailCode = false;
                _otp.clear();
                _message = null;
              }),
              child: const Text('العودة لتعديل البريد'),
            ),
          ] else
            TextButton(
              onPressed: _busy ? null : () => setState(() { _register = !_register; _message = null; }),
              child: Text(_register ? 'لديك حساب؟ سجل الدخول' : 'ليس لديك حساب؟ أنشئ حسابًا'),
            ),
        ])),
      ),
    ))),
  );
}


class CustomerOffersPage extends StatelessWidget {
  const CustomerOffersPage({super.key});
  List<Map<String, dynamic>> _itemsFor(Map<String, dynamic> promotion) {
    final result = <Map<String, dynamic>>[];
    final linked = promotion['promotion_menu_items'];
    if (linked is List) for (final link in linked.whereType<Map>()) {
      final raw = link['menu_items'];
      if (raw is Map && raw['id'] != null && raw['is_available'] != false) {
        final item = Map<String, dynamic>.from(raw);
        item['promotion_menu_items'] = [{'promotions': promotion}];
        result.add(item);
      }
    }
    final legacy = promotion['menu_items'];
    if (result.isEmpty && legacy is Map && legacy['id'] != null && legacy['is_available'] != false) {
      final item = Map<String, dynamic>.from(legacy);
      item['promotions'] = promotion;
      result.add(item);
    }
    final seen = <String>{};
    return result.where((item) => seen.add(item['id'].toString())).toList();
  }
  void _addSingleItem(BuildContext context, Map<String, dynamic> promotion, Map<String, dynamic> item, {required bool checkout}) {
    final restaurantId = promotion['restaurant_id']?.toString() ?? '';
    if (restaurantId.isEmpty || item['id'] == null) return;
    context.read<CartController>().add(item, restaurantId, price: _effectiveItemPrice(item));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تمت إضافة ${item['name'] ?? 'الصنف'} إلى السلة')));
    Navigator.push(context, MaterialPageRoute(builder: (_) => checkout ? const CheckoutPage() : const CartPage()));
  }
  void _addOffer(BuildContext context, Map<String, dynamic> promotion, {required bool checkout}) {
    final restaurantId = promotion['restaurant_id']?.toString() ?? '';
    final items = _itemsFor(promotion);
    if (restaurantId.isEmpty || items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أصناف هذا العرض غير متاحة حالياً')));
      return;
    }
    final cart = context.read<CartController>();
    for (final item in items) { cart.add(item, restaurantId, price: _effectiveItemPrice(item)); }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تمت إضافة ${items.length} صنف من العرض إلى السلة')));
    Navigator.push(context, MaterialPageRoute(builder: (_) => checkout ? const CheckoutPage() : const CartPage()));
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('عروض المطاعم')),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: SareeBackend.activePromotions(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const LoadingPage();
        if (snapshot.hasError) return Center(child: Text('تعذر تحميل العروض: ${SareeBackend.arabicError(snapshot.error)}'));
        final promotions = snapshot.data ?? [];
        if (promotions.isEmpty) return const Center(child: Text('لا توجد عروض نشطة حاليًا. تابع الصفحة لمعرفة العروض الجديدة.'));
        return ListView(padding: const EdgeInsets.all(16), children: promotions.map((promotion) {
          final restaurant = promotion['restaurants'] is Map ? promotion['restaurants']['name']?.toString() : null;
          final items = _itemsFor(promotion);
          final photos = items.expand((item) => _mealPhotoUrls(item)).toSet().toList();
          final discountValue = promotion['discount_value'] ?? 0;
          final discount = promotion['discount_type'] == 'percentage' ? 'خصم $discountValue٪' : 'خصم $discountValue ريال';
          final min = (promotion['minimum_order_yer'] as num? ?? 0).toInt();
          return Card(clipBehavior: Clip.antiAlias, child: Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [Color(0xFF047857), Color(0xFF065F46)])),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (photos.isNotEmpty) ...[MealPhotoGallery(urls: photos), const SizedBox(height: 12)],
              Text(promotion['title']?.toString() ?? 'عرض خاص', style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900)),
              const SizedBox(height: 7),
              Text(discount, style: const TextStyle(color: Color(0xFFFFD60A), fontSize: 20, fontWeight: FontWeight.w900)),
              if (restaurant != null) Text('المطعم: $restaurant', style: const TextStyle(color: Colors.white)),
              if ((promotion['description']?.toString() ?? '').isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 7), child: Text(promotion['description'].toString(), style: const TextStyle(color: Colors.white70))),
              const SizedBox(height: 10),
              const Text('الأصناف المشمولة في العرض:', style: TextStyle(color: Color(0xFFFFD60A), fontWeight: FontWeight.w900)),
              if (items.isEmpty) const Text('لم تُحدد أصناف متاحة لهذا العرض بعد', style: TextStyle(color: Colors.white70))
              else ...items.map((item) {
                final base = (item['price_yer'] as num? ?? 0).toInt();
                final sale = _effectiveItemPrice(item);
                return Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: .08), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white24)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(item['name']?.toString() ?? 'صنف', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 4),
                    Row(children: [
                      Text('$sale ريال', style: const TextStyle(color: Color(0xFFFFD60A), fontWeight: FontWeight.w900, fontSize: 15)),
                      const SizedBox(width: 8),
                      if (sale < base) Text('$base ريال', style: const TextStyle(color: Colors.white70, decoration: TextDecoration.lineThrough, fontSize: 12)),
                    ]),
                    const SizedBox(height: 7),
                    Row(children: [
                      Expanded(child: FilledButton.tonalIcon(
                        onPressed: () => _addSingleItem(context, promotion, item, checkout: true),
                        icon: const Icon(Icons.flash_on_rounded, size: 17),
                        label: const Text('اطلب الآن'),
                      )),
                      const SizedBox(width: 7),
                      Expanded(child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
                        onPressed: () => _addSingleItem(context, promotion, item, checkout: false),
                        icon: const Icon(Icons.add_shopping_cart_rounded, size: 17),
                        label: const Text('أضف للسلة'),
                      )),
                    ]),
                  ]),
                );
              }),
              if (min > 0) Padding(padding: const EdgeInsets.only(top: 8), child: Text('الحد الأدنى: $min ريال', style: const TextStyle(color: Colors.white70, fontSize: 12))),
              if ((promotion['code']?.toString() ?? '').isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 5), child: Text('كود العرض: ${promotion['code']}', style: const TextStyle(color: Color(0xFFFFD60A), fontWeight: FontWeight.w800))),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: FilledButton.icon(onPressed: items.isEmpty ? null : () => _addOffer(context, promotion, checkout: true), icon: const Icon(Icons.flash_on_rounded), label: const Text('اطلب العرض الآن'))),
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton.icon(onPressed: items.isEmpty ? null : () => _addOffer(context, promotion, checkout: false), icon: const Icon(Icons.add_shopping_cart_rounded), label: const Text('أضف للسلة'))),
              ]),
            ]),
          ));
        }).toList());
      },
    ),
  );
}

/// عناصر هيكلية خفيفة تُعرض أثناء تحميل المطاعم بدل شاشة فارغة أو مؤشر وحيد.
class _RestaurantLoadingSkeleton extends StatelessWidget {
  const _RestaurantLoadingSkeleton();

  Widget _block(double height, {double? width}) => Container(
    height: height,
    width: width,
    decoration: BoxDecoration(
      color: const Color(0xFFE5EDE6),
      borderRadius: BorderRadius.circular(16),
    ),
  );

  @override
  Widget build(BuildContext context) => ListView(
    physics: const NeverScrollableScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
    children: [
      _block(190),
      const SizedBox(height: 16),
      _block(52),
      const SizedBox(height: 18),
      Row(children: [
        _block(78, height: 86),
        const SizedBox(width: 10),
        _block(78, height: 86),
        const SizedBox(width: 10),
        _block(78, height: 86),
        const SizedBox(width: 10),
        _block(78, height: 86),
      ]),
      const SizedBox(height: 22),
      _block(22, width: 150),
      const SizedBox(height: 12),
      ...List.generate(3, (_) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          _block(88, width: 92),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _block(16, width: 150),
            const SizedBox(height: 9),
            _block(12, width: 210),
            const SizedBox(height: 9),
            _block(12, width: 90),
          ])),
        ]),
      )),
    ],
  );
}

class CustomerHome extends StatelessWidget {
  const CustomerHome({super.key});

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartController>();
    return Scaffold(
      appBar: AppBar(
        title: const Row(mainAxisSize: MainAxisSize.min, children: [
          BrandMark(size: 34),
          SizedBox(width: 9),
          Text('سريع', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
        ]),
        actions: [
          IconButton(tooltip: 'البحث', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerSearchPage())), icon: const Icon(Icons.search_rounded)),
          Stack(children: [
            IconButton(tooltip: 'السلة', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartPage())), icon: const Icon(Icons.shopping_bag_outlined)),
            if (cart.count > 0) Positioned(right: 5, top: 4, child: CircleAvatar(radius: 9, backgroundColor: const Color(0xFF047857), child: Text(cart.count.toString(), style: const TextStyle(fontSize: 10, color: Colors.white)))),
          ]),
          PopupMenuButton<String>(
            tooltip: 'القائمة',
            onSelected: (value) {
              final page = switch (value) {
                'notifications' => const CustomerNotificationsPage(),
                'favorites' => const CustomerFavoritesPage(),
                'orders' => const CustomerOrdersPage(),
                'account' => const CustomerAccountPage(),
                'wallet' => const WalletPage(),
                'support' => const CustomerSupportPage(),
                'offers' => const CustomerOffersPage(),
                'cashier_join' => const CashierJoinPage(),
                _ => null,
              };
              if (page != null) Navigator.push(context, MaterialPageRoute(builder: (_) => page));
              if (value == 'logout') showAccountSignOutOptions(context);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'notifications', child: ListTile(dense: true, leading: Icon(Icons.notifications_none), title: Text('الإشعارات'))),
              PopupMenuItem(value: 'favorites', child: ListTile(dense: true, leading: Icon(Icons.favorite_border), title: Text('المفضلة'))),
              PopupMenuItem(value: 'orders', child: ListTile(dense: true, leading: Icon(Icons.receipt_long), title: Text('طلباتي'))),
              PopupMenuItem(value: 'account', child: ListTile(dense: true, leading: Icon(Icons.person_outline), title: Text('حسابي والعناوين'))),
              PopupMenuItem(value: 'wallet', child: ListTile(dense: true, leading: Icon(Icons.account_balance_wallet_outlined), title: Text('محفظتي'))),
              PopupMenuItem(value: 'support', child: ListTile(dense: true, leading: Icon(Icons.support_agent), title: Text('الدعم والمساعدة'))),
              PopupMenuItem(value: 'offers', child: ListTile(dense: true, leading: Icon(Icons.local_offer_outlined), title: Text('عروض المطاعم'))),
              PopupMenuItem(value: 'cashier_join', child: ListTile(dense: true, leading: Icon(Icons.point_of_sale_rounded), title: Text('الانضمام ككاشير لمطعم'))),
              PopupMenuItem(value: 'logout', child: ListTile(dense: true, leading: Icon(Icons.logout), title: Text('تسجيل الخروج'))),
            ],
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: SareeBackend.restaurants(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const _RestaurantLoadingSkeleton();
          if (snapshot.hasError) return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_rounded, size: 54, color: Color(0xFF047857)),
                  const SizedBox(height: 12),
                  const Text('لم نتمكن من تحميل المطاعم', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text(SareeBackend.arabicError(snapshot.error), textAlign: TextAlign.center),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const CustomerHome())),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
          );
          final restaurants = snapshot.data ?? [];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              const FoodPhotoBanner(
                title: 'ماذا تشتهي اليوم؟',
                subtitle: 'وجبات شهية • توصيل سريع إلى باب بيتك • رداع، اليمن',
                height: 205,
              ),
              const SizedBox(height: 16),
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerSearchPage())),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE8E1CE))),
                  child: const Row(children: [
                    Icon(Icons.search_rounded, color: Color(0xFF047857)),
                    SizedBox(width: 10),
                    Expanded(child: Text('ابحث عن مطعمك أو وجبتك المفضلة', style: TextStyle(color: Color(0xFF647A70)))),
                    Icon(Icons.tune_rounded, color: Color(0xFF647A70), size: 20),
                  ]),
                ),
              ),
              const SizedBox(height: 18),
              const Text('تصفح حسب النوع', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Color(0xFF123B2F))),
              const SizedBox(height: 10),
              SizedBox(
                height: 94,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: const [
                    _FoodCategoryShortcut(label: 'وجبات', query: 'وجبات', icon: Icons.lunch_dining_rounded),
                    _FoodCategoryShortcut(label: 'برجر', query: 'برجر', icon: Icons.fastfood_rounded),
                    _FoodCategoryShortcut(label: 'بيتزا', query: 'بيتزا', icon: Icons.local_pizza_rounded),
                    _FoodCategoryShortcut(label: 'مشروبات', query: 'عصائر', icon: Icons.local_cafe_rounded),
                    _FoodCategoryShortcut(label: 'حلويات', query: 'حلويات', icon: Icons.cake_rounded),
                    _FoodCategoryShortcut(label: 'مندي', query: 'مندي', icon: Icons.rice_bowl_rounded),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              FutureBuilder<List<Map<String,dynamic>>>(
                future: SareeBackend.activePromotions(),
                builder: (context, promoSnap) {
                  final promos = promoSnap.data ?? [];
                  if (promos.isEmpty) return const SizedBox.shrink();
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('عروض المطاعم وتخفيضاتها', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 9),
                    SizedBox(height: 148, child: ListView(scrollDirection: Axis.horizontal, children: promos.map((promo) => Container(
                      width: 286, margin: const EdgeInsetsDirectional.only(end: 10), padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), gradient: const LinearGradient(colors: [Color(0xFF047857), Color(0xFF047857)])),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(promo['title']?.toString() ?? 'عرض خاص', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17)),
                        const SizedBox(height: 3),
                        Text(promo['discount_type'] == 'percentage' ? 'خصم ${promo['discount_value']}٪' : 'خصم ${promo['discount_value']} ريال', style: const TextStyle(color: Color(0xFFFFD60A), fontWeight: FontWeight.w900, fontSize: 16)),
                        Text((promo['restaurants'] is Map ? promo['restaurants']['name'] : null)?.toString() ?? 'مطعم مشارك', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                        if (promo['menu_items'] is Map && promo['menu_items']['name'] != null) Text('على صنف: ${promo['menu_items']['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFFFD60A), fontSize: 11, fontWeight: FontWeight.w800)),
                        Expanded(child: Text(promo['description']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12))),
                        if ((promo['code']?.toString() ?? '').isNotEmpty) Text('كود العرض: ${promo['code']} • الحد الأدنى: ${promo['minimum_order_yer'] ?? 0} ريال', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFFFD60A), fontWeight: FontWeight.w900, fontSize: 11)),
                      ]),
                    )).toList())),
                    const SizedBox(height: 18),
                  ]);
                },
              ),
              const Text('أصناف من المطاعم', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Color(0xFF123B2F))),
              const SizedBox(height: 8),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: SareeBackend.featuredMenuItems(),
                builder: (context, itemSnap) {
                  if (itemSnap.connectionState != ConnectionState.done && !itemSnap.hasData) {
                    return const SizedBox(height: 220, child: Center(child: CircularProgressIndicator()));
                  }
                  if (itemSnap.hasError) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text('تعذر تحميل الأصناف: ${SareeBackend.arabicError(itemSnap.error)}'),
                    );
                  }
                  final items = itemSnap.data ?? [];
                  if (items.isEmpty) {
                    return const Card(child: Padding(
                      padding: EdgeInsets.all(18),
                      child: Text('ستظهر هنا أصناف المطاعم المتاحة للطلب.'),
                    ));
                  }
                  return SizedBox(
                    height: 286,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: items.map((item) {
                        final restaurant = item['restaurants'];
                        final restaurantId = item['restaurant_id']?.toString() ?? '';
                        final restaurantName = restaurant is Map ? restaurant['name']?.toString() ?? 'مطعم' : 'مطعم';
                        final price = _effectiveItemPrice(item);
                        return SizedBox(
                          width: 238,
                          child: Card(
                            clipBehavior: Clip.antiAlias,
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(13),
                                    child: SizedBox(
                                      height: 104,
                                      child: Image.network(
                                        _mealPhotoUrl(item),
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => const ColoredBox(
                                          color: Color(0xFFE8E1CE),
                                          child: Icon(Icons.restaurant_menu_rounded, size: 38, color: Color(0xFF047857)),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 7),
                                  Text(item['name']?.toString() ?? 'صنف', maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Color(0xFF123B2F))),
                                  Text(restaurantName, maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11, color: Color(0xFF647A70))),
                                  const Spacer(),
                                  Text('$price ريال', style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF047857), fontSize: 15)),
                                  const SizedBox(height: 6),
                                  Row(children: [
                                    Expanded(child: FilledButton(
                                      style: FilledButton.styleFrom(minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 5),
                                        textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
                                      onPressed: restaurantId.isEmpty || item['is_available'] == false ? null : () {
                                        context.read<CartController>().add(item, restaurantId, price: price);
                                        Navigator.push(context, MaterialPageRoute(builder: (_) => const CheckoutPage()));
                                      },
                                      child: const Text('اطلب الآن'),
                                    )),
                                    const SizedBox(width: 6),
                                    Expanded(child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 4),
                                        foregroundColor: const Color(0xFF047857), side: const BorderSide(color: Color(0xFF047857)),
                                        textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
                                      onPressed: restaurantId.isEmpty || item['is_available'] == false ? null : () {
                                        context.read<CartController>().add(item, restaurantId, price: price);
                                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تمت إضافة ${item['name'] ?? 'الصنف'} إلى السلة')));
                                      },
                                      icon: const Icon(Icons.add_shopping_cart_rounded, size: 15),
                                      label: const Text('أضف للسلة'),
                                    )),
                                  ]),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('المطاعم المتاحة', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF123B2F))),
                Icon(Icons.tune_rounded, color: Color(0xFF047857)),
              ]),
              const SizedBox(height: 10),
              if (restaurants.isEmpty)
                const Card(child: Padding(
                  padding: EdgeInsets.all(22),
                  child: Column(children: [
                    Icon(Icons.restaurant_menu_rounded, size: 46, color: Color(0xFF047857)),
                    SizedBox(height: 10),
                    Text('لا توجد مطاعم مفعّلة حاليًا', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF123B2F))),
                    SizedBox(height: 5),
                    Text('ستظهر المطاعم هنا بعد إضافتها واعتمادها من الإدارة.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF536B61))),
                  ]),
                ))
              else
                ...restaurants.map((r) => Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RestaurantMenuPage(restaurant: r))),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: SizedBox(
                            width: 82, height: 82,
                            child: (r['cover_image_url']?.toString().trim().isNotEmpty == true)
                                ? Image.network(
                                    r['cover_image_url'].toString(),
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const ColoredBox(
                                      color: Color(0xFFE8E1CE),
                                      child: Icon(Icons.restaurant_rounded, size: 38, color: Color(0xFFFFD60A)),
                                    ),
                                  )
                                : const ColoredBox(
                                    color: Color(0xFFE8E1CE),
                                    child: Icon(Icons.restaurant_rounded, size: 38, color: Color(0xFFFFD60A)),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 13),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(r['name']?.toString() ?? 'مطعم', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFFFFD60A))),
                          const SizedBox(height: 5),
                          Text(r['description']?.toString() ?? 'وجبات شهية بانتظارك', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFDCE9DE), fontSize: 12)),
                          const SizedBox(height: 8),
                          Row(children: [
                            const Icon(Icons.delivery_dining_rounded, size: 16, color: Color(0xFF047857)),
                            const SizedBox(width: 4),
                            Text('رسوم التوصيل: ${r['delivery_fee_yer'] ?? '—'} ريال', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                          ]),
                        ])),
                        const Icon(Icons.chevron_left_rounded, color: Color(0xFF647A70)),
                      ]),
                    ),
                  ),
                )),
            ],
          );
        },
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        onDestinationSelected: (index) {
          final page = switch (index) {
            1 => const CustomerSearchPage(),
            2 => const CartPage(),
            3 => const CustomerOrdersPage(),
            4 => const CustomerAccountPage(),
            _ => null,
          };
          if (page != null) Navigator.push(context, MaterialPageRoute(builder: (_) => page));
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'الرئيسية'),
          NavigationDestination(icon: Icon(Icons.search_rounded), label: 'بحث'),
          NavigationDestination(icon: Icon(Icons.shopping_bag_outlined), label: 'السلة'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'طلباتي'),
          NavigationDestination(icon: Icon(Icons.person_outline_rounded), label: 'حسابي'),
        ],
      ),
    );
  }
}



/// اختصار بصري لفئات الطعام؛ يفتح البحث مع تعبئة اسم الفئة تلقائياً.
class _FoodCategoryShortcut extends StatelessWidget {
  const _FoodCategoryShortcut({
    required this.label,
    required this.query,
    required this.icon,
  });

  final String label;
  final String query;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(end: 10),
    child: Semantics(
      button: true,
      label: 'تصفح فئة $label',
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => CustomerSearchPage(initialQuery: query)),
        ),
        child: Container(
          width: 78,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color ?? const Color(0xFFFFFDF5),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE8E1CE)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5F3EA),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: const Color(0xFF047857), size: 23),
              ),
              const SizedBox(height: 5),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    ),
  );
}

class CustomerAccountPage extends StatefulWidget {
  const CustomerAccountPage({super.key});
  @override
  State<CustomerAccountPage> createState() => _CustomerAccountPageState();
}

class _CustomerAccountPageState extends State<CustomerAccountPage> {
  final _formKey = GlobalKey<FormState>();
  String _fullName = '';
  String _phone = '';
  bool _saving = false;
  late Future<Map<String, dynamic>> _profileFuture;
  late Future<List<Map<String, dynamic>>> _addressesFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _profileFuture = SareeBackend.profile();
    _addressesFuture = SareeBackend.myAddresses();
  }

  Future<void> _refresh() async {
    setState(_load);
    await Future.wait([_profileFuture, _addressesFuture]);
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    setState(() => _saving = true);
    try {
      await SareeBackend.updateMyProfile(fullName: _fullName, phone: _phone);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تحديث بيانات حسابك')),
      );
      await _refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر حفظ البيانات: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addAddress() async {
    final label = TextEditingController(text: 'المنزل');
    final area = TextEditingController();
    final address = TextEditingController();
    bool makeDefault = false;
    final form = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: const Text('إضافة عنوان توصيل'),
          content: Form(
            key: form,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(
                  controller: label,
                  decoration: const InputDecoration(labelText: 'اسم العنوان (المنزل، العمل...)'),
                  validator: (v) => v == null || v.trim().isEmpty ? 'اكتب اسم العنوان' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: area,
                  decoration: const InputDecoration(labelText: 'المنطقة أو الحي'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: address,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'وصف العنوان بالتفصيل'),
                  validator: (v) => v == null || v.trim().length < 5 ? 'اكتب عنواناً أوضح' : null,
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: makeDefault,
                  onChanged: (v) => setLocal(() => makeDefault = v ?? false),
                  title: const Text('اجعله عنواني الافتراضي'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(dialogContext, true);
            }, child: const Text('حفظ العنوان')),
          ],
        ),
      ),
    );
    if (saved == true) {
      try {
        await SareeBackend.saveAddress(
          label: label.text,
          addressText: address.text,
          area: area.text,
          isDefault: makeDefault,
        );
        await _refresh();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ عنوان التوصيل')),
        );
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر حفظ العنوان: $e')),
        );
      }
    }
    label.dispose();
    area.dispose();
    address.dispose();
  }

  Future<void> _addressAction(Map<String, dynamic> row, String action) async {
    try {
      if (action == 'default') {
        await SareeBackend.setDefaultAddress(row['id'].toString());
      } else {
        await SareeBackend.deleteAddress(row['id'].toString());
      }
      await _refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تنفيذ العملية: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('حسابي'),
      actions: [IconButton(tooltip: 'تحديث', onPressed: _refresh, icon: const Icon(Icons.refresh_rounded))],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FutureBuilder<Map<String, dynamic>>(
          future: _profileFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Card(child: Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())));
            }
            if (snapshot.hasError) return Card(child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('تعذر تحميل بيانات الحساب: ${SareeBackend.arabicError(snapshot.error)}'),
            ));
            final profile = snapshot.data!;
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Row(children: [
                      CircleAvatar(radius: 25, backgroundColor: Color(0xFFE5F3EA), child: Icon(Icons.person_rounded, color: Color(0xFF047857), size: 28)),
                      SizedBox(width: 12),
                      Expanded(child: Text('البيانات الشخصية', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
                    ]),
                    const SizedBox(height: 16),
                    TextFormField(
                      initialValue: profile['full_name']?.toString() ?? '',
                      decoration: const InputDecoration(labelText: 'الاسم الكامل', prefixIcon: Icon(Icons.person_outline)),
                      validator: (v) => v == null || v.trim().length < 2 ? 'أدخل الاسم' : null,
                      onSaved: (v) => _fullName = v!.trim(),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      initialValue: profile['phone']?.toString() ?? '',
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'رقم الهاتف', prefixIcon: Icon(Icons.phone_outlined)),
                      validator: (v) => v != null && v.trim().isNotEmpty && v.trim().length < 7 ? 'رقم الهاتف غير مكتمل' : null,
                      onSaved: (v) => _phone = v?.trim() ?? '',
                    ),
                    const SizedBox(height: 8),
                    Text('البريد الإلكتروني: ${SareeBackend.user?.email ?? '—'}', style: const TextStyle(color: Color(0xFF536B61))),
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: _saving ? null : _saveProfile,
                      child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('حفظ بياناتي'),
                    ),
                  ]),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('عناوين التوصيل', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
          FilledButton.tonalIcon(onPressed: _addAddress, icon: const Icon(Icons.add_location_alt_outlined), label: const Text('إضافة عنوان')),
        ]),
        const SizedBox(height: 8),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _addressesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Card(child: Padding(padding: EdgeInsets.all(22), child: Center(child: CircularProgressIndicator())));
            }
            if (snapshot.hasError) return Card(child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('تعذر تحميل العناوين: ${SareeBackend.arabicError(snapshot.error)}'),
            ));
            final rows = snapshot.data ?? [];
            if (rows.isEmpty) return const Card(child: Padding(
              padding: EdgeInsets.all(22),
              child: Column(children: [
                Icon(Icons.location_off_outlined, size: 38, color: Color(0xFF047857)),
                SizedBox(height: 8),
                Text('لم تحفظ عنوان توصيل بعد', style: TextStyle(fontWeight: FontWeight.w800)),
                Text('أضف عنوان المنزل أو العمل لتسهيل طلباتك القادمة.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF536B61))),
              ]),
            ));
            return Column(children: rows.map((row) => Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFE5F3EA),
                  child: Icon(row['label'] == 'العمل' ? Icons.work_outline : Icons.home_outlined, color: const Color(0xFF047857)),
                ),
                title: Row(children: [
                  Flexible(child: Text(row['label']?.toString() ?? 'عنوان', style: const TextStyle(fontWeight: FontWeight.w800))),
                  if (row['is_default'] == true) ...[
                    const SizedBox(width: 7),
                    const Chip(label: Text('افتراضي'), visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
                  ],
                ]),
                subtitle: Text('${row['area'] ?? ''} • ${row['address_text'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) => _addressAction(row, v),
                  itemBuilder: (_) => [
                    if (row['is_default'] != true) const PopupMenuItem(value: 'default', child: Text('جعله افتراضياً')),
                    const PopupMenuItem(value: 'delete', child: Text('حذف العنوان')),
                  ],
                ),
              ),
            )).toList());
          },
        ),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: () async {
            await showAccountSignOutOptions(context);
          },
          icon: const Icon(Icons.logout_rounded),
          label: const Text('تسجيل الخروج'),
        ),
      ],
    ),
  );
}

class RestaurantMenuPage extends StatelessWidget {
  const RestaurantMenuPage({super.key, required this.restaurant});
  final Map<String, dynamic> restaurant;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(restaurant['name'].toString(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
      actions: [
        FutureBuilder<bool>(
          future: SareeBackend.isFavorite(restaurant['id'].toString()),
          builder: (context, snap) => IconButton(
            tooltip: 'إضافة إلى المفضلة',
            onPressed: () async {
              try {
                await SareeBackend.toggleFavorite(restaurant['id'].toString());
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تحديث المفضلة')));
              } catch (e) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تحديث المفضلة: $e')));
              }
            },
            icon: Icon(snap.data == true ? Icons.favorite : Icons.favorite_border, color: const Color(0xFF047857)),
          ),
        ),
      ],
    ),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: SareeBackend.menu(restaurant['id'].toString()),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const LoadingPage();
        if (snapshot.hasError) return Center(child: Text('تعذر تحميل القائمة: ${SareeBackend.arabicError(snapshot.error)}'));
        final menu = snapshot.data ?? [];
        if (menu.isEmpty) return const Center(child: Text('لم يضف المطعم وجباته بعد'));
        final grouped = <String, List<Map<String, dynamic>>>{};
        for (final item in menu) {
          final category = item['menu_categories'];
          final categoryName = category is Map && category['name'] != null
              ? category['name'].toString()
              : 'أصناف أخرى';
          grouped.putIfAbsent(categoryName, () => []).add(item);
        }
        const categoryOrder = [
          'الأطباق الرئيسية والأصناف اليمنية',
          'البروست والوجبات السريعة',
          'المأكولات البحرية',
          'المخبوزات والبيتزا',
          'الحلويات',
          'أصناف أخرى',
        ];
        final orderedCategories = [...categoryOrder.where(grouped.containsKey), ...grouped.keys.where((name) => !categoryOrder.contains(name))];
        final coverUrl = restaurant['cover_image_url']?.toString() ?? '';
        return ListView(padding: const EdgeInsets.all(16), children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: SizedBox(height: 174, width: double.infinity, child: Stack(fit: StackFit.expand, children: [
              if (coverUrl.isNotEmpty) Image.network(coverUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const DecoratedBox(decoration: BoxDecoration(color: Color(0xFF123B2F)))),
              if (coverUrl.isEmpty) const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [Color(0xFF123B2F), Color(0xFF064E3B)]))),
              const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.center, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xE6000000)]))),
              Padding(padding: const EdgeInsets.all(18), child: Row(children: [
                const Icon(Icons.restaurant_menu_rounded, color: Color(0xFFFFD60A), size: 32),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text(restaurant['name'].toString(), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                  const Text('تصفح أقسام المنيو واختر وجبتك', style: TextStyle(color: Colors.white70)),
                ])),
              ])),
            ])),
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: SareeBackend.restaurantReviews(restaurant['id'].toString()),
            builder: (context, reviewSnap) {
              final reviews = reviewSnap.data ?? <Map<String, dynamic>>[];
              if (reviews.isEmpty) return const SizedBox.shrink();
              final average = reviews
                  .map((review) => (review['rating'] as num).toDouble())
                  .reduce((a, b) => a + b) / reviews.length;
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.star_rounded, color: Color(0xFFFFD60A), size: 30),
                  title: Text(
                    average.toStringAsFixed(1),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text('${reviews.length} تقييم من العملاء'),
                  trailing: TextButton(
                    onPressed: () {
                      showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        builder: (sheetContext) => SafeArea(
                          child: ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              const Text(
                                'تقييمات العملاء',
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                              ),
                              ...reviews.map((review) => ListTile(
                                leading: const Icon(Icons.star_rounded, color: Color(0xFFFFD60A)),
                                title: Text(
                                  '${review['rating']}/5 • ${(review['profiles'] is Map ? review['profiles']['full_name'] : null) ?? 'عميل'}',
                                ),
                                subtitle: Text(review['comment']?.toString() ?? ''),
                              )),
                            ],
                          ),
                        ),
                      );
                    },
                    child: const Text('عرض التقييمات'),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          ...orderedCategories.expand((category) => [
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
              child: Text(category, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Color(0xFF123B2F))),
            ),
            ...grouped[category]!.map((item) {
              final available = item['is_available'] == true && (item['price_yer'] as num? ?? 0) > 0;
              final imageUrl = _mealPhotoUrl(item);
              return Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MealDetailsPage(item: item, restaurantId: restaurant['id'].toString()))),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: SizedBox(
                          width: 82, height: 82,
                          child: RotatingFoodImage(urls: _mealPhotoUrls(item).isEmpty ? [imageUrl] : _mealPhotoUrls(item)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(item['name'].toString(), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Theme.of(context).colorScheme.onSurface)), 
                        const SizedBox(height: 4),
                        Text(item['description']?.toString() ?? 'وجبة شهية', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .72), fontSize: 12)), 
                        const SizedBox(height: 7),
                        if (!available)
                          const Text('السعر والتوفر يحددهما المطعم', style: TextStyle(color: Color(0xFF536B61), fontWeight: FontWeight.w900, fontSize: 12))
                        else if (_activeItemPromotion(item) != null)
                          Row(children: [
                            Text('${_effectiveItemPrice(item)} ريال يمني', style: const TextStyle(color: Color(0xFF047857), fontWeight: FontWeight.w900, fontSize: 12)),
                            const SizedBox(width: 7),
                            Text('${item['price_yer']} ريال', style: const TextStyle(color: Color(0xFF647A70), fontSize: 11, decoration: TextDecoration.lineThrough)),
                          ])
                        else
                          Text('${item['price_yer']} ريال يمني', style: const TextStyle(color: Color(0xFF047857), fontWeight: FontWeight.w900, fontSize: 12)),
                      ])),
                      Icon(available ? Icons.chevron_left_rounded : Icons.info_outline_rounded, color: const Color(0xFF647A70)),
                    ]),
                  ),
                ),
              );
            }),
          ]),
        ]);
      },
    ),
  );
}

String _promotionItemNames(Map<String, dynamic> promotion) {
  final names = <String>[];
  final links = promotion['promotion_menu_items'];
  if (links is List) for (final link in links.whereType<Map>()) {
    final meal = link['menu_items'];
    if (meal is Map && meal['name'] != null) names.add(meal['name'].toString());
  }
  final legacy = promotion['menu_items'];
  if (legacy is Map && legacy['name'] != null && names.isEmpty) names.add(legacy['name'].toString());
  return names.isEmpty ? 'عرض عام' : 'الأصناف: ${names.toSet().join('، ')}';
}

class MealPhotoGallery extends StatefulWidget {
  const MealPhotoGallery({super.key, required this.urls});
  final List<String> urls;

  @override
  State<MealPhotoGallery> createState() => _MealPhotoGalleryState();
}

class _MealPhotoGalleryState extends State<MealPhotoGallery> {
  late final PageController _controller = PageController();
  int _index = 0;
  Timer? _autoSlideTimer;

  @override
  void initState() {
    super.initState();
    _autoSlideTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      final count = widget.urls.where((url) => url.trim().isNotEmpty).length;
      if (!mounted || count < 2 || !_controller.hasClients) return;
      _controller.animateToPage(
        (_index + 1) % count,
        duration: const Duration(milliseconds: 550),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _autoSlideTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.urls.where((url) => url.trim().isNotEmpty).toList();
    if (photos.isEmpty) {
      return const SizedBox(
        height: 220,
        child: Center(child: Icon(Icons.restaurant_rounded, size: 72)),
      );
    }
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: SizedBox(
            height: 230,
            child: PageView.builder(
              controller: _controller,
              itemCount: photos.length,
              onPageChanged: (value) => setState(() => _index = value),
              itemBuilder: (context, index) => Image.network(
                photos[index],
                fit: BoxFit.cover,
                width: double.infinity,
                errorBuilder: (context, error, stack) => const ColoredBox(
                  color: Color(0xFFFFF8E7),
                  child: Center(
                    child: Icon(Icons.restaurant_rounded, size: 90, color: Color(0xFF047857)),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (photos.length > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(photos.length, (index) {
              final selected = _index == index;
              return GestureDetector(
                onTap: () => _controller.animateToPage(
                  index,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                ),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: selected ? 20 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: selected ? const Color(0xFF047857) : const Color(0xFF647A70),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }
}

class MealDetailsPage extends StatelessWidget {
  const MealDetailsPage({super.key, required this.item, required this.restaurantId});
  final Map<String, dynamic> item;
  final String restaurantId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('تفاصيل الوجبة')),
    body: Builder(builder: (context) {
      final available = item['is_available'] == true && (item['price_yer'] as num? ?? 0) > 0;
      final imageUrl = _mealPhotoUrl(item);
      final itemPromotion = _activeItemPromotion(item);
      final salePrice = _effectiveItemPrice(item);
      return ListView(padding: const EdgeInsets.all(18), children: [
        MealPhotoGallery(urls: _mealPhotoUrls(item).isEmpty ? [imageUrl] : _mealPhotoUrls(item)),
        const SizedBox(height: 20),
        Text(item['name'].toString(), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface)), 
        const SizedBox(height: 8),
        Text(item['description']?.toString() ?? 'وجبة شهية محضرة بعناية.', style: TextStyle(fontSize: 14, height: 1.7, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .75))), 
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Theme.of(context).cardTheme.color ?? Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: Theme.of(context).dividerColor)), 
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('السعر', style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .7))), 
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(available ? '$salePrice ريال يمني' : 'يُحدد من المطعم', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Color(0xFF047857))), 
              if (available && itemPromotion != null)
                Text('${item['price_yer']} ريال قبل الخصم', style: const TextStyle(fontSize: 12, color: Color(0xFF647A70), decoration: TextDecoration.lineThrough)),
            ]),
          ]),
        ),
        const SizedBox(height: 24),
        if (available)
          FilledButton.icon(
            onPressed: () {
              context.read<CartController>().add(item, restaurantId, price: _effectiveItemPrice(item));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أضيفت الوجبة إلى السلة')));
            },
            icon: const Icon(Icons.add_shopping_cart_rounded),
            label: const Text('أضف إلى السلة'),
          )
        else
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('هذا الصنف معروض في المنيو، وسيصبح متاحاً للطلب بعد تأكيد السعر والتوفر من المطعم.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF536B61), fontWeight: FontWeight.w700)),
          ),
      ]);
    }),
  );
}

class CartPage extends StatelessWidget {
  const CartPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartController>();
    return Scaffold(
      appBar: AppBar(title: const Text('سلة الطلب')),
      body: cart.items.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 112,
                      height: 112,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5F3EA),
                        borderRadius: BorderRadius.circular(34),
                      ),
                      child: const Icon(Icons.shopping_bag_outlined, size: 58, color: Color(0xFF047857)),
                    ),
                    const SizedBox(height: 18),
                    const Text('سلتك فارغة حالياً', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 7),
                    const Text('اكتشف المطاعم واختر وجباتك المفضلة، وستظهر هنا قبل إتمام الطلب.',
                      textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF536B61), height: 1.5)),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerSearchPage())),
                      icon: const Icon(Icons.search_rounded),
                      label: const Text('اكتشف الوجبات'),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                    itemCount: cart.items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = cart.items[index];
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE5F3EA),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(Icons.restaurant_rounded, color: Color(0xFF047857)),
                              ),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                                    const SizedBox(height: 4),
                                    Text('${item.total} ريال يمني',
                                      style: const TextStyle(color: Color(0xFF047857), fontWeight: FontWeight.w900)),
                                  ],
                                ),
                              ),
                              Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE5F3EA),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: 'تقليل الكمية',
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () => cart.change(item, -1),
                                      icon: const Icon(Icons.remove_rounded, size: 19),
                                    ),
                                    Text(item.quantity.toString(), style: const TextStyle(fontWeight: FontWeight.w900)),
                                    IconButton(
                                      tooltip: 'زيادة الكمية',
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () => cart.change(item, 1),
                                      icon: const Icon(Icons.add_rounded, size: 19),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(18, 15, 18, 16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardTheme.color ?? Colors.white,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                      boxShadow: const [BoxShadow(color: Color(0x18000000), blurRadius: 18, offset: Offset(0, -4))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('المجموع الفرعي', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF536B61))),
                            Text('${cart.subtotal} ريال يمني', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                          ],
                        ),
                        const SizedBox(height: 5),
                        const Text('تُعرض رسوم التوصيل وأي خصومات مستحقة في صفحة تأكيد الطلب.',
                          style: TextStyle(fontSize: 11, color: Color(0xFF647A70))),
                        const SizedBox(height: 13),
                        FilledButton.icon(
                          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CheckoutPage())),
                          icon: const Icon(Icons.arrow_forward_rounded),
                          label: const Text('متابعة لإتمام الطلب'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class CheckoutPage extends StatefulWidget {
  const CheckoutPage({super.key});
  @override State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _notes = TextEditingController();
  bool _busy = false;
  bool _locating = false;
  double? _deliveryLatitude;
  double? _deliveryLongitude;
  String? _error;
  List<Map<String, dynamic>> _savedAddresses = [];
  String? _selectedAddressId;
  bool _loadingAddresses = true;

  @override
  void initState() {
    super.initState();
    _loadCustomerDetails();
  }

  Future<void> _loadCustomerDetails() async {
    try {
      final results = await Future.wait([
        SareeBackend.profile(),
        SareeBackend.myAddresses(),
      ]);
      final profile = results[0] as Map<String, dynamic>;
      final addresses = results[1] as List<Map<String, dynamic>>;
      if (!mounted) return;
      _name.text = profile['full_name']?.toString() ?? '';
      _phone.text = profile['phone']?.toString() ?? '';
      setState(() {
        _savedAddresses = addresses;
        final preferred = addresses.where((a) => a['is_default'] == true);
        if (preferred.isNotEmpty) {
          _selectedAddressId = preferred.first['id'].toString();
          final a = preferred.first;
          _address.text = '${a['area'] ?? ''} ${a['address_text'] ?? ''}'.trim();
          _deliveryLatitude = (a['latitude'] as num?)?.toDouble();
          _deliveryLongitude = (a['longitude'] as num?)?.toDouble();
        }
        _loadingAddresses = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingAddresses = false);
    }
  }

  @override
  void dispose() { _name.dispose(); _phone.dispose(); _address.dispose(); _notes.dispose(); super.dispose(); }

  Future<void> _captureDeliveryLocation() async {
    if (_locating) return;
    setState(() { _locating = true; _error = null; });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) throw Exception('فعّل خدمة الموقع GPS أولاً');
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) throw Exception('اسمح للتطبيق بالوصول إلى الموقع من إعدادات الهاتف');
      final position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() { _deliveryLatitude = position.latitude; _deliveryLongitude = position.longitude; });
    } catch (e) {
      if (mounted) setState(() => _error = SareeBackend.arabicError(e));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _send() async {
    if (_name.text.trim().length < 2 || _phone.text.trim().length < 7 || _address.text.trim().length < 5) {
      setState(() => _error = 'أكمل الاسم ورقم الهاتف والعنوان بالتفصيل');
      return;
    }
    final cart = context.read<CartController>();
    if (cart.items.isEmpty || cart.restaurantId == null) return;
    setState(() { _busy = true; _error = null; });
    try {
      var deliveryAddress = _address.text.trim();
      double? deliveryLatitude = _deliveryLatitude;
      double? deliveryLongitude = _deliveryLongitude;
      final selectedAddresses = _savedAddresses.where((a) => a['id']?.toString() == _selectedAddressId);
      if (selectedAddresses.isNotEmpty) {
        final saved = selectedAddresses.first;
        deliveryLatitude ??= (saved['latitude'] as num?)?.toDouble();
        deliveryLongitude ??= (saved['longitude'] as num?)?.toDouble();
      }
      if (deliveryLatitude != null && deliveryLongitude != null && deliveryLatitude.abs() <= 90 && deliveryLongitude.abs() <= 180) {
        deliveryAddress = '$deliveryAddress\nالموقع: $deliveryLatitude,$deliveryLongitude';
      } else {
        deliveryLatitude = null;
        deliveryLongitude = null;
      }
      final id = await SareeBackend.createOrder(
        restaurantId: cart.restaurantId!,
        customerName: _name.text,
        customerPhone: _phone.text,
        address: deliveryAddress,
        deliveryLatitude: deliveryLatitude,
        deliveryLongitude: deliveryLongitude,
        notes: _notes.text,
        items: cart.items.map((line) => {'menu_item_id': line.id, 'quantity': line.quantity}).toList(),
      );
      await cart.clear();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => OrderCreatedPage(orderId: id)), (route) => route.isFirst);
    } catch (e) {
      setState(() => _error = SareeBackend.arabicError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('تأكيد الطلب')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      TextField(controller: _name, decoration: const InputDecoration(labelText: 'اسم المستلم')),
      const SizedBox(height: 12),
      TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف')),
      const SizedBox(height: 12),
      if (_loadingAddresses)
        const LinearProgressIndicator()
      else if (_savedAddresses.isNotEmpty) ...[
        DropdownButtonFormField<String>(
          value: _selectedAddressId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'اختر عنواناً محفوظاً', prefixIcon: Icon(Icons.location_on_outlined)),
          items: _savedAddresses.map((a) => DropdownMenuItem(
            value: a['id'].toString(),
            child: Text('${a['label']} • ${a['area'] ?? ''}', overflow: TextOverflow.ellipsis),
          )).toList(),
          onChanged: (id) {
            final selected = _savedAddresses.where((a) => a['id'].toString() == id);
            if (selected.isNotEmpty) {
              final a = selected.first;
              setState(() {
                _selectedAddressId = id;
                _address.text = '${a['area'] ?? ''} ${a['address_text'] ?? ''}'.trim();
                _deliveryLatitude = (a['latitude'] as num?)?.toDouble();
                _deliveryLongitude = (a['longitude'] as num?)?.toDouble();
              });
            }
          },
        ),
        const SizedBox(height: 12),
      ],
      TextField(controller: _address, maxLines: 2, decoration: const InputDecoration(labelText: 'عنوان التوصيل بالتفصيل')),
      const SizedBox(height: 8),
      OutlinedButton.icon(onPressed: _locating ? null : _captureDeliveryLocation, icon: _locating ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.my_location_rounded), label: Text(_locating ? 'جارٍ تحديد موقعك...' : 'تحديد موقعي بدقة GPS')),
      if (_deliveryLatitude != null && _deliveryLongitude != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text('تم حفظ الموقع: ${_deliveryLatitude!.toStringAsFixed(6)}, ${_deliveryLongitude!.toStringAsFixed(6)}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w700))),
      const SizedBox(height: 8),
      TextField(controller: _notes, maxLines: 2, decoration: const InputDecoration(labelText: 'ملاحظات للمطعم (اختياري)')),
      const SizedBox(height: 12),
      const Card(child: ListTile(leading: Icon(Icons.payments), title: Text('الدفع نقدًا عند الاستلام'))),
      if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
      FilledButton(onPressed: _busy ? null : _send, child: _busy ? const CircularProgressIndicator() : const Text('إرسال الطلب')),
    ]),
  );
}

class OrderCreatedPage extends StatelessWidget {
  const OrderCreatedPage({super.key, required this.orderId});
  final String orderId;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('تم إرسال الطلب')),
    body: Center(child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.check_circle, color: Colors.green, size: 72),
        const SizedBox(height: 12),
        const Text('وصل طلبك إلى النظام. يمكنك متابعة حالته من صفحة طلباتي.', textAlign: TextAlign.center),
        const SizedBox(height: 8),
        SelectableText('رقم الطلب: $orderId'),
        const SizedBox(height: 18),
        FilledButton(onPressed: () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const CustomerOrdersPage()), (route) => route.isFirst), child: const Text('متابعة الطلب')),
      ]),
    )),
  );
}

class CustomerOrdersPage extends StatelessWidget {
  const CustomerOrdersPage({super.key});
  String statusLabel(String status) {
    const labels = {
      'pending': 'بانتظار قبول المطعم',
      'accepted': 'قبل المطعم الطلب',
      'preparing': 'جاري التحضير',
      'ready_for_pickup': 'جاهز للاستلام',
      'assigned': 'تم تعيين مندوب',
      'picked_up': 'المندوب استلم الطلب',
      'delivered': 'تم التوصيل',
      'cancelled': 'ملغي',
    };
    return labels[status] ?? status;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('طلباتي')),
    body: StreamBuilder<List<Map<String, dynamic>>>(
      stream: SareeBackend.customerOrders(),
      builder: (context, snapshot) {
        if (!snapshot.hasData && snapshot.connectionState == ConnectionState.waiting) return const LoadingPage();
        if (snapshot.hasError) return Center(child: Text('تعذر تحميل الطلبات: ${SareeBackend.arabicError(snapshot.error)}'));
        final orders = snapshot.data ?? [];
        if (orders.isEmpty) return const Center(child: Text('لا توجد طلبات حتى الآن'));
        return ListView(padding: const EdgeInsets.all(16), children: orders.map((order) => Card(
          child: ListTile(
            leading: const Icon(Icons.receipt_long),
            title: Text('طلب #${order['order_number']}'),
            subtitle: Text('${statusLabel(order['status'].toString())}\nالإجمالي: ${order['total_yer']} ريال'),
            isThreeLine: true,
            trailing: order['status'] == 'delivered' ? IconButton(tooltip: 'قيّم المطعم', onPressed: () => _showSareeReviewDialog(context, order), icon: const Icon(Icons.star_rate_rounded, color: Color(0xFFFFD60A))) : null,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrderTrackingPage(order: order))),
          ),
        )).toList());
      },
    ),
  );
}


class OrderTrackingPage extends StatelessWidget {
  const OrderTrackingPage({super.key, required this.order});
  final Map<String, dynamic> order;

  static const steps = [
    ('pending', 'تم استلام الطلب', Icons.receipt_long_rounded),
    ('accepted', 'وافق المطعم على الطلب', Icons.thumb_up_alt_rounded),
    ('preparing', 'المطعم يحضّر طلبك', Icons.soup_kitchen_rounded),
    ('ready_for_pickup', 'الطلب جاهز للاستلام', Icons.inventory_2_rounded),
    ('assigned', 'تم تعيين مندوب', Icons.delivery_dining_rounded),
    ('picked_up', 'الطلب في الطريق إليك', Icons.two_wheeler_rounded),
    ('delivered', 'تم التوصيل بنجاح', Icons.check_circle_rounded),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('تتبع الطلب')),
    body: StreamBuilder<List<Map<String, dynamic>>>(
      stream: SareeBackend.trackOrder(order['id'].toString()),
      builder: (context, snap) {
        final current = snap.data?.isNotEmpty == true ? snap.data!.first : order;
        final status = current['status'].toString();
        final index = steps.indexWhere((step) => step.$1 == status);
        final cancelled = status == 'cancelled';
        return ListView(padding: const EdgeInsets.all(18), children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: const Color(0xFF123B2F), borderRadius: BorderRadius.circular(22)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('حالة طلبك الآن', style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 8),
              Text(cancelled ? 'تم إلغاء الطلب' : steps[index < 0 ? 0 : index].$2, style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text('رقم الطلب #${current['order_number']} • ${current['total_yer']} ريال', style: const TextStyle(color: Colors.white70)),
            ]),
          ),
          const SizedBox(height: 18),
          if (cancelled) const Card(child: ListTile(leading: Icon(Icons.info_outline), title: Text('هذا الطلب ملغي'))),
          ...steps.asMap().entries.map((entry) {
            final active = !cancelled && index >= entry.key;
            final done = !cancelled && index > entry.key;
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: active ? const Color(0xFFE5F3EA) : const Color(0xFFE8E1CE),
                child: Icon(done ? Icons.check_rounded : entry.value.$3, color: active ? const Color(0xFF047857) : const Color(0xFF647A70)),
              ),
              title: Text(entry.value.$2, style: TextStyle(fontWeight: active ? FontWeight.w900 : FontWeight.w500, color: active ? const Color(0xFF123B2F) : const Color(0xFF647A70))),
            );
          }),
          Card(child: ListTile(leading: const Icon(Icons.location_on_rounded), title: const Text('عنوان التوصيل'), subtitle: Text(current['delivery_address']?.toString() ?? ''))),
          if (current['courier_id'] != null && (status == 'assigned' || status == 'picked_up'))
            CourierLiveMap(
              courierId: current['courier_id'].toString(),
              deliveryLatitude: (current['delivery_latitude'] as num?)?.toDouble(),
              deliveryLongitude: (current['delivery_longitude'] as num?)?.toDouble(),
            ),
          if (status == 'pending')
            OutlinedButton.icon(
              onPressed: () async {
                try {
                  await SareeBackend.transition(current['id'].toString(), 'cancelled', reason: 'طلب العميل');
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إلغاء الطلب')));
                } catch(e) { if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(SareeBackend.arabicError(e)))); }
              },
              icon: const Icon(Icons.cancel_outlined), label: const Text('إلغاء الطلب'),
            ),
          const Padding(padding: EdgeInsets.only(top: 10), child: Text('تتحدث حالة الطلب تلقائيًا. عند مشاركة المندوب لموقعه مع السماح بإذن GPS أثناء استخدام التطبيق، ستظهر حركته هنا على الخريطة.', style: TextStyle(color: Color(0xFF536B61), height: 1.5))),
        ]);
      },
    ),
  );
}


class CourierLiveMap extends StatelessWidget {
  const CourierLiveMap({super.key, required this.courierId, this.deliveryLatitude, this.deliveryLongitude});
  final String courierId;
  final double? deliveryLatitude;
  final double? deliveryLongitude;
  @override
  Widget build(BuildContext context) => StreamBuilder<List<Map<String,dynamic>>>(
    stream: SareeBackend.courierLocation(courierId),
    builder: (context, snap) {
      if(snap.hasError) return const Card(child: ListTile(title: Text('تعذر تحميل موقع المندوب')));
      if(snap.data == null || snap.data!.isEmpty) return const Card(child: ListTile(leading: Icon(Icons.location_searching), title: Text('بانتظار مشاركة المندوب لموقعه')));
      final row = snap.data!.first;
      final point = LatLng((row['latitude'] as num).toDouble(), (row['longitude'] as num).toDouble());
      final destination = deliveryLatitude != null && deliveryLongitude != null ? LatLng(deliveryLatitude!, deliveryLongitude!) : null;
      final center = destination == null ? point : LatLng((point.latitude + destination.latitude) / 2, (point.longitude + destination.longitude) / 2);
      final route = destination == null ? <LatLng>[] : [point, destination];
      return Card(clipBehavior: Clip.antiAlias, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const ListTile(leading: Icon(Icons.map_rounded), title: Text('تتبع المندوب داخل سريع'), subtitle: Text('يتحدث موقع المندوب مباشرة داخل التطبيق')),
        SizedBox(height: 250, child: FlutterMap(
          options: MapOptions(initialCenter: center, initialZoom: destination == null ? 15 : 13),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.saree.delivery.saree'),
            if (route.isNotEmpty) PolylineLayer(polylines: [Polyline(points: route, strokeWidth: 5, color: Colors.blueAccent)]),
            MarkerLayer(markers: [
              Marker(point: point, width: 52, height: 52, child: const Icon(Icons.delivery_dining_rounded, color: Color(0xFF047857), size: 44)),
              if (destination != null) Marker(point: destination, width: 48, height: 48, child: const Icon(Icons.location_pin, color: Colors.green, size: 44)),
            ]),
          ],
        )),
        const Padding(padding: EdgeInsets.fromLTRB(12, 8, 12, 0), child: Text('الخط الأزرق يوضح الاتجاه المباشر بين المندوب وعنوانك، وليس توجيهاً انعطافياً على الطرق.', style: TextStyle(fontSize: 11, color: Color(0xFF536B61)))),
        Padding(padding: const EdgeInsets.all(10), child: Text('آخر تحديث: ${row['updated_at'] ?? ''}', style: const TextStyle(fontSize: 11, color: Color(0xFF536B61)))),
      ]));
    },
  );
}

class RestaurantPortal extends StatefulWidget {
  const RestaurantPortal({super.key});
  @override State<RestaurantPortal> createState() => _RestaurantPortalState();
}

class _RestaurantPortalState extends State<RestaurantPortal> {
  int _tab = 0;
  bool _busy = false;
  final TextEditingController _orderSearchController = TextEditingController();
  final Set<String> _archivedOrderIds = <String>{};

  @override
  void initState() {
    super.initState();
    _loadArchivedOrderIds();
  }

  Future<void> _loadArchivedOrderIds() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _archivedOrderIds.addAll(prefs.getStringList('saree_archived_orders_${SareeBackend.user?.id ?? 'restaurant'}') ?? const <String>[]));
  }

  Future<void> _exportRestaurantOrdersPdf(String restaurantId) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final orders = await SareeBackend.restaurantOrderHistory(restaurantId);
      if (orders.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا توجد طلبات لتصديرها')));
        return;
      }
      final arabicFont = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoNaskhArabic-Regular.ttf'));
      final boldFont = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoNaskhArabic-Bold.ttf'));
      final theme = pw.ThemeData.withFont(base: arabicFont, bold: boldFont);
      final document = pw.Document();
      final now = DateTime.now();
      final stamp = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      document.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: theme,
        textDirection: pw.TextDirection.rtl,
        header: (_) => pw.Container(
          alignment: pw.Alignment.center,
          margin: const pw.EdgeInsets.only(bottom: 12),
          child: pw.Column(children: [
            pw.Text('سريع - سجل طلبات المطعم', style: pw.TextStyle(font: boldFont, fontSize: 20)),
            pw.Text('تاريخ التصدير: $stamp • إجمالي الطلبات: ${orders.length}', style: pw.TextStyle(font: arabicFont, fontSize: 10)),
            pw.Divider(),
          ]),
        ),
        build: (_) => orders.map((order) {
          final items = (order['order_items'] as List? ?? const [])
              .whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
          final created = order['created_at']?.toString() ?? '';
          final date = created.length >= 16 ? created.substring(0, 16).replaceFirst('T', ' ') : created;
          final itemLines = items.map((item) {
            final qty = (item['quantity'] as num?)?.toInt() ?? 0;
            final unit = (item['unit_price_yer'] as num?)?.toInt() ?? 0;
            final line = (item['line_total_yer'] as num?)?.toInt() ?? qty * unit;
            return pw.Padding(
              padding: const pw.EdgeInsets.only(top: 3),
              child: pw.Text('${item['item_name'] ?? 'صنف'}  •  $qty × $unit = $line ريال', style: pw.TextStyle(font: arabicFont, fontSize: 9)),
            );
          }).toList();
          return pw.Container(
            width: double.infinity,
            margin: const pw.EdgeInsets.only(bottom: 10),
            padding: const pw.EdgeInsets.all(9),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400), borderRadius: pw.BorderRadius.circular(5)),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
              pw.Text('طلب #${order['order_number']}  •  $date  •  الحالة: ${order['status']}', style: pw.TextStyle(font: boldFont, fontSize: 11)),
              pw.SizedBox(height: 3),
              pw.Text('العميل: ${order['customer_name'] ?? ''}  •  الهاتف: ${order['customer_phone'] ?? ''}', style: pw.TextStyle(font: arabicFont, fontSize: 9)),
              pw.Text('العنوان: ${order['delivery_address'] ?? ''}', style: pw.TextStyle(font: arabicFont, fontSize: 9)),
              if ((order['notes'] ?? '').toString().trim().isNotEmpty)
                pw.Text('ملاحظات: ${order['notes']}', style: pw.TextStyle(font: arabicFont, fontSize: 9)),
              pw.SizedBox(height: 4),
              ...itemLines,
              pw.Divider(),
              pw.Text('قيمة الأصناف: ${order['subtotal_yer'] ?? 0} ريال  •  التوصيل: ${order['delivery_fee_yer'] ?? 0} ريال  •  الإجمالي: ${order['total_yer'] ?? 0} ريال', style: pw.TextStyle(font: boldFont, fontSize: 10)),
            ]),
          );
        }).toList(),
      ));
      await Printing.sharePdf(bytes: await document.save(), filename: 'saree_orders_$stamp.pdf');
      if (!mounted) return;
      final hide = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('تم تجهيز سجل الطلبات'),
          content: const Text('هل تريد إخفاء الطلبات المصدّرة من قائمة التطبيق؟ لن تُحذف الطلبات من قاعدة البيانات أو السجل المالي.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('الاحتفاظ بالطلبات')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إخفاؤها من القائمة')),
          ],
        ),
      );
      if (hide == true) {
        _archivedOrderIds.addAll(orders.map((o) => o['id'].toString()));
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('saree_archived_orders_${SareeBackend.user?.id ?? 'restaurant'}', _archivedOrderIds.toList());
        if (mounted) setState(() {});
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تصدير سجل الطلبات: ${SareeBackend.arabicError(error)}')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreArchivedOrders() async {
    _archivedOrderIds.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('saree_archived_orders_${SareeBackend.user?.id ?? 'restaurant'}');
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _orderSearchController.dispose();
    super.dispose();
  }
  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try { await action(); if(mounted) setState(() {}); }
    catch(e) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(SareeBackend.arabicError(e)))); }
    finally { if(mounted) setState(() => _busy = false); }
  }

  Future<void> _assignCourier(String restaurantId, Map<String, dynamic> order) async {
    List<Map<String, dynamic>> candidates;
    try {
      candidates = await SareeBackend.availableCouriersForRestaurant(restaurantId);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(SareeBackend.arabicError(e))),
      );
      return;
    }
    if (!mounted) return;
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('لا يوجد مندوب نشط ضمن فريق هذا المطعم. أضف مندوبًا معتمدًا من تبويب المندوبون.'),
      ));
      return;
    }

    String selected = candidates.first['courier_id'].toString();
    final courierId = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('اختيار مندوب للطلب #${order['order_number']}'),
          content: DropdownButtonFormField<String>(
            value: selected,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'مندوبو فريق المطعم'),
            items: candidates.map((courier) => DropdownMenuItem(
              value: courier['courier_id'].toString(),
              child: Text(
                '${courier['full_name'] ?? 'مندوب'} • ${courier['phone'] ?? 'بدون هاتف'} • ${courier['last_seen'] == null ? 'غير متصل' : 'متصل الآن'}',
                overflow: TextOverflow.ellipsis,
              ),
            )).toList(),
            onChanged: (value) {
              if (value != null) setLocal(() => selected = value);
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, selected), child: const Text('تعيين المندوب')),
          ],
        ),
      ),
    );
    if (courierId != null) {
      await _run(() => SareeBackend.assignCourierToOrder(
        orderId: order['id'].toString(),
        courierId: courierId,
      ));
    }
  }

  Future<void> _removeCourier(String restaurantId, Map<String, dynamic> courier) async {
    final accepted = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('إزالة المندوب من الفريق؟'),
      content: Text('سيتم إيقاف ربط ' + (courier['full_name'] ?? 'المندوب').toString() + ' بهذا المطعم. لن تتأثر حساباته أو طلباته السابقة.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إزالة'))],
    ));
    if (accepted == true) await _run(() => SareeBackend.removeRestaurantCourier(restaurantId, courier['courier_id'].toString()));
  }

  Future<void> _reviewCourierApplication(String applicationId, String decision) async {
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text(decision == 'accepted' ? 'قبول المندوب؟' : 'رفض طلب المندوب؟'),
      content: Text(decision == 'accepted'
        ? 'سيُضاف المندوب إلى فريق توصيل مطعمك بعد القبول.'
        : 'سيتم إبلاغ المندوب برفض طلب الانضمام.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(decision == 'accepted' ? 'قبول' : 'رفض')),
      ],
    ));
    if (confirmed != true) return;
    await _run(() async {
      await SareeBackend.restaurantReviewCourierApplication(applicationId, decision);
      if (mounted) setState(() {});
    });
  }

  Widget _courierDocumentPreview(String title, String? url) {
    if (url == null || url.isEmpty) {
      return Card(child: Padding(padding: const EdgeInsets.all(12), child: Text('$title: لم تُرفق الصورة')));
    }
    return Card(child: Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(
        url, height: 170, width: double.infinity, fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const SizedBox(height: 100, child: Center(child: Text('تعذر عرض الصورة، حدّث القائمة وحاول مجدداً'))),
      )),
    ])));
  }

  Widget _courierApplicationsSection(String restaurantId) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: SareeBackend.restaurantCourierApplications(restaurantId),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(14), child: LinearProgressIndicator());
        if (snap.hasError) return Padding(padding: const EdgeInsets.all(14), child: Text('تعذر تحميل طلبات الانضمام: ${SareeBackend.arabicError(snap.error)}'));
        // Only pending requests belong in the courier requests tab. Accepted couriers
        // are recorded in Account Settings and remain available in the active team list.
        final applications = (snap.data ?? []).where((a) => a['status'] == 'pending').toList();
        final pending = applications;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: const EdgeInsets.fromLTRB(14, 14, 14, 6), child: Row(children: [
            const Expanded(child: Text('طلبات انضمام المندوبين', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
            Chip(label: Text('قيد المراجعة: ${pending.length}')),
          ])),
          if (applications.isEmpty) const Padding(padding: EdgeInsets.all(14), child: Text('لا توجد طلبات انضمام حتى الآن.')),
          ...applications.map((a) {
            final status = a['status']?.toString() ?? 'pending';
            final canReview = status == 'pending';
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: ExpansionTile(
                leading: CircleAvatar(child: Icon(Icons.delivery_dining_rounded, color: status == 'accepted' ? Colors.green : status == 'rejected' ? Colors.red : Colors.orange)),
                title: Text(a['full_name']?.toString() ?? 'مندوب توصيل', style: const TextStyle(fontWeight: FontWeight.w900)),
                subtitle: Text(status == 'accepted' ? 'تم قبول الطلب' : status == 'rejected' ? 'تم رفض الطلب' : 'طلب جديد • بانتظار مراجعة المطعم'),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                children: [
                  if (a['platform_approval_status'] == 'approved')
                    const ListTile(
                      dense: true,
                      leading: Icon(Icons.folder_shared_rounded, color: Colors.green),
                      title: Text('مستندات الهوية'),
                      subtitle: Text('اكتمل رفع مستندات الهوية؛ قرار قبول المندوب يعود للمطعم'),
                    ),
                  ListTile(dense: true, leading: const Icon(Icons.phone), title: const Text('رقم الهاتف'), subtitle: SelectableText(a['phone']?.toString() ?? 'غير متوفر')),
                  ListTile(dense: true, leading: const Icon(Icons.email_outlined), title: const Text('البريد الإلكتروني'), subtitle: SelectableText(a['email']?.toString() ?? 'غير متوفر')),
                  _courierDocumentPreview('الهوية من الأمام', a['id_front_url']?.toString()),
                  _courierDocumentPreview('الهوية من الخلف', a['id_back_url']?.toString()),
                  _courierDocumentPreview('سيلفي المندوب مع البطاقة', a['selfie_url']?.toString()),
                  if (canReview) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: OutlinedButton.icon(
                        onPressed: _busy ? null : () => _reviewCourierApplication(a['application_id'].toString(), 'rejected'),
                        icon: const Icon(Icons.close, color: Colors.red), label: const Text('رفض الطلب'),
                      )),
                      const SizedBox(width: 8),
                      Expanded(child: FilledButton.icon(
                        onPressed: _busy ? null : () => _reviewCourierApplication(a['application_id'].toString(), 'accepted'),
                        icon: const Icon(Icons.check), label: const Text('قبول المندوب'),
                      )),
                    ]),
                  ],
                ],
              ),
            );
          }),
        ]);
      },
    );
  }


  Widget _cashierManagementTab(String restaurantId) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: SareeBackend.restaurantCashierApplications(restaurantId),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const LoadingPage();
        if (snap.hasError) return Center(child: Text('تعذر تحميل طلبات الكاشيرين: ${SareeBackend.arabicError(snap.error)}'));
        final requests = snap.data ?? [];
        final pending = requests.where((r) => r['status'] == 'pending').toList();
        final accepted = requests.where((r) => r['status'] == 'accepted').toList();
        return ListView(padding: const EdgeInsets.all(12), children: [
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('إدارة الكاشيرين', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            const Text('هنا تظهر طلبات الموظفين الذين يريدون العمل ككاشير في مطعمك. قبول الطلب يربط حسابه بالمطعم تلقائياً.'),
            const SizedBox(height: 10),
            Wrap(spacing: 8, children: [
              Chip(label: Text('طلبات معلقة: ${pending.length}')),
              Chip(label: Text('كاشيرون مقبولون: ${accepted.length}')),
            ]),
          ]))),
          if (requests.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('لا توجد طلبات كاشير حتى الآن. اطلب من الموظف إنشاء حساب عميل ثم إرسال طلب الانضمام من القائمة الرئيسية.'))),
          ...requests.map((r) {
            final status = r['status']?.toString() ?? 'pending';
            final isPending = status == 'pending';
            final statusLabel = status == 'accepted' ? 'مقبول ويستطيع الدخول ككاشير' : status == 'rejected' ? 'مرفوض' : 'بانتظار مراجعة المطعم';
            return Card(child: ExpansionTile(
              leading: CircleAvatar(child: Icon(Icons.point_of_sale_rounded, color: status == 'accepted' ? const Color(0xFF047857) : status == 'rejected' ? Colors.red : Colors.orange)),
              title: Text(r['full_name']?.toString().trim().isNotEmpty == true ? r['full_name'].toString() : 'كاشير جديد', style: const TextStyle(fontWeight: FontWeight.w900)),
              subtitle: Text('${r['phone'] ?? 'بدون هاتف'} • $statusLabel'),
              children: [
                ListTile(dense: true, leading: const Icon(Icons.phone), title: const Text('رقم الهاتف'), subtitle: SelectableText(r['phone']?.toString() ?? 'غير مسجل')),
                if (isPending) Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 12), child: Row(children: [
                  Expanded(child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _run(() async {
                      await SareeBackend.reviewCashierApplication(applicationId: r['id'].toString(), decision: 'rejected');
                    }),
                    icon: const Icon(Icons.close_rounded, color: Colors.red), label: const Text('رفض'),
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: FilledButton.icon(
                    onPressed: _busy ? null : () => _run(() async {
                      await SareeBackend.reviewCashierApplication(applicationId: r['id'].toString(), decision: 'accepted');
                    }),
                    icon: const Icon(Icons.check_rounded), label: const Text('قبول وربط'),
                  )),
                ])),
              ],
            ));
          }),
          const SizedBox(height: 18),
          OutlinedButton.icon(onPressed: () => setState(() {}), icon: const Icon(Icons.refresh), label: const Text('تحديث الطلبات')),
        ]);
      },
    );
  }

  Widget _courierTeamTab(String restaurantId) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: SareeBackend.restaurantCourierTeam(restaurantId),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const LoadingPage();
        if (snap.hasError) return Center(child: Text('تعذر تحميل فريق المندوبين: ${SareeBackend.arabicError(snap.error)}'));
        final couriers = snap.data ?? [];
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: SareeBackend.restaurantCourierApplications(restaurantId),
          builder: (context, docsSnap) {
            if (docsSnap.connectionState != ConnectionState.done) return const LoadingPage();
            if (docsSnap.hasError) return Center(child: Text('تعذر تحميل مستندات المندوبين: ${SareeBackend.arabicError(docsSnap.error)}'));
            final accepted = (docsSnap.data ?? []).where((a) => a['status'] == 'accepted').toList();
            return ListView(padding: const EdgeInsets.only(bottom: 16), children: [
              _courierApplicationsSection(restaurantId),
              const Divider(height: 24),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 14), child: Text('فريق المندوبين المقبولين', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900))),
              const Padding(padding: EdgeInsets.fromLTRB(14, 6, 14, 8), child: Text('افتح بطاقة أي مندوب لعرض بياناته وصور الهوية والسيلفي المرفقة بطلب الانضمام.', style: TextStyle(color: Color(0xFF536B61), height: 1.4))),
              if (couriers.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('لم يتم قبول أي مندوب في فريق المطعم بعد', textAlign: TextAlign.center))),
              ...couriers.map((courier) {
                final active = courier['is_active'] == true;
                final available = courier['is_available'] == true;
                final name = courier['full_name']?.toString().trim().isNotEmpty == true ? courier['full_name'].toString() : 'مندوب توصيل';
                final phone = courier['phone']?.toString() ?? 'بدون رقم هاتف';
                final status = !active ? 'موقوف' : available ? 'متاح الآن' : 'غير متصل أو لا يشارك موقعه';
                final application = accepted.where((a) => a['courier_id']?.toString() == courier['courier_id']?.toString()).firstOrNull;
                return Card(child: ExpansionTile(
                  leading: CircleAvatar(backgroundColor: active ? const Color(0xFFFFF8E7) : const Color(0xFFE8E1CE), child: Icon(Icons.delivery_dining_rounded, color: active ? const Color(0xFF047857) : const Color(0xFF647A70))),
                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text('$phone • $status'),
                  trailing: active ? IconButton(tooltip: 'إزالة من الفريق', onPressed: _busy ? null : () => _removeCourier(restaurantId, courier), icon: const Icon(Icons.person_remove_alt_1_rounded, color: Colors.red)) : const Icon(Icons.pause_circle_outline_rounded, color: Color(0xFF647A70)),
                  childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                  children: [
                    ListTile(dense: true, leading: const Icon(Icons.email_outlined), title: const Text('البريد الإلكتروني'), subtitle: SelectableText(application?['email']?.toString() ?? 'غير متوفر')),
                    ListTile(dense: true, leading: const Icon(Icons.verified_user_outlined), title: const Text('حالة اعتماد الإدارة'), subtitle: Text(application?['platform_approval_status']?.toString() ?? 'غير متوفر')),
                    _courierDocumentPreview('الهوية من الأمام', application?['id_front_url']?.toString()),
                    _courierDocumentPreview('الهوية من الخلف', application?['id_back_url']?.toString()),
                    _courierDocumentPreview('سيلفي المندوب مع البطاقة', application?['selfie_url']?.toString()),
                    _courierDocumentPreview('إثبات السكن', application?['residence_url']?.toString()),
                  ],
                ));
              }),
            ]);
          },
        );
      },
    );
  }

  Widget _restaurantOrderDetails(Map<String, dynamic> order) {
    final lat = (order['delivery_latitude'] as num?)?.toDouble();
    final lng = (order['delivery_longitude'] as num?)?.toDouble();
    final validLocation = lat != null && lng != null && lat.abs() <= 90 && lng.abs() <= 180;
    final subtotal = (order['subtotal_yer'] as num?)?.toInt() ?? 0;
    final deliveryFee = (order['delivery_fee_yer'] as num?)?.toInt() ?? 0;
    final total = (order['total_yer'] as num?)?.toInt() ?? subtotal + deliveryFee;
    final status = (order['status'] ?? '').toString().trim().toLowerCase();
    final ready = status == 'ready_for_pickup';
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF065F46),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ready ? const Color(0xFFFFD60A) : const Color(0xFFD5E3D8), width: ready ? 1.5 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.receipt_long_rounded, color: ready ? const Color(0xFFFFD60A) : Colors.white70),
          const SizedBox(width: 8),
          const Expanded(child: Text('تفاصيل الطلب كاملة', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900))),
          if (ready) const Chip(
            visualDensity: VisualDensity.compact,
            label: Text('جاهز للاستلام', style: TextStyle(fontWeight: FontWeight.w800)),
            backgroundColor: Color(0xFFFFD60A),
            labelStyle: TextStyle(color: Color(0xFF123B2F)),
            side: BorderSide.none,
          ),
        ]),
        const Divider(height: 18),
        _orderInfoRow(Icons.person_outline_rounded, 'اسم العميل', order['customer_name']?.toString() ?? 'غير مسجل'),
        _orderInfoRow(Icons.phone_outlined, 'رقم الهاتف', order['customer_phone']?.toString() ?? 'غير مسجل'),
        _orderInfoRow(Icons.location_on_outlined, 'عنوان التوصيل', order['delivery_address']?.toString() ?? 'غير مسجل'),
        if ((order['notes'] ?? '').toString().trim().isNotEmpty)
          _orderInfoRow(Icons.notes_rounded, 'ملاحظات العميل', order['notes'].toString()),
        const SizedBox(height: 10),
        const Text('الأصناف المطلوبة والكميات', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFFFD60A))),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: SareeBackend.courierOrderItems(order['id'].toString()),
          builder: (context, itemsSnap) {
            if (itemsSnap.connectionState != ConnectionState.done) {
              return const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: LinearProgressIndicator());
            }
            if (itemsSnap.hasError) {
              return Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text('تعذر تحميل الأصناف: ${SareeBackend.arabicError(itemsSnap.error)}'));
            }
            final items = itemsSnap.data ?? [];
            if (items.isEmpty) return const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Text('لا توجد أصناف مسجلة لهذا الطلب'));
            return Column(children: items.map((item) {
              final quantity = (item['quantity'] as num?)?.toInt() ?? 0;
              final unitPrice = (item['unit_price_yer'] as num?)?.toInt() ?? 0;
              final lineTotal = (item['line_total_yer'] as num?)?.toInt() ?? unitPrice * quantity;
              return Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.restaurant_menu_rounded, size: 18, color: Color(0xFFFFD60A)),
                  const SizedBox(width: 8),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(item['item_name']?.toString() ?? 'صنف', style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text('$quantity × $unitPrice ريال', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                  ])),
                  Text('$lineTotal ريال', style: const TextStyle(fontWeight: FontWeight.w900)),
                ]),
              );
            }).toList());
          },
        ),
        const Divider(height: 22),
        _orderInfoRow(Icons.shopping_basket_outlined, 'قيمة الأصناف', '$subtotal ريال'),
        _orderInfoRow(Icons.delivery_dining_rounded, 'رسوم التوصيل', '$deliveryFee ريال'),
        Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(color: const Color(0xFF064E3B), borderRadius: BorderRadius.circular(12)),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('الإجمالي المطلوب من العميل', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
            Text('$total ريال يمني', style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFFFD60A), fontSize: 16)),
          ]),
        ),
        const SizedBox(height: 8),
        _orderInfoRow(Icons.payments_outlined, 'طريقة الدفع', 'نقدًا عند الاستلام'),
        if (validLocation)
          OutlinedButton.icon(
            onPressed: () => launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng'), mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.map_outlined),
            label: const Text('فتح موقع العميل على الخريطة'),
          ),
      ]),
    );
  }

  Widget _orderInfoRow(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 18, color: const Color(0xFFFFD60A)),
      const SizedBox(width: 8),
      SizedBox(width: 105, child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12))),
      Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
    ]),
  );

  Future<void> _editPromotion(String restaurantId, [Map<String, dynamic>? promotion]) async {

    List<Map<String, dynamic>> menuItems;
    try {
      menuItems = await SareeBackend.manageMenu(restaurantId);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تحميل أصناف المطعم: ${SareeBackend.arabicError(error)}')));
      return;
    }
    final selectedMenuItemIds = <String>{};
    final legacyItemId = promotion?['menu_item_id']?.toString();
    if (legacyItemId != null && legacyItemId.isNotEmpty) selectedMenuItemIds.add(legacyItemId);
    final oldLinks = promotion?['promotion_menu_items'];
    if (oldLinks is List) {
      for (final link in oldLinks.whereType<Map>()) {
        final linkedId = link['menu_item_id']?.toString();
        if (linkedId != null && linkedId.isNotEmpty) selectedMenuItemIds.add(linkedId);
      }
    }
    final title = TextEditingController(text: promotion?['title']?.toString() ?? '');
    final description = TextEditingController(text: promotion?['description']?.toString() ?? '');
    final code = TextEditingController(text: promotion?['code']?.toString() ?? '');
    final value = TextEditingController(text: promotion?['discount_value']?.toString() ?? '');
    final minimum = TextEditingController(text: promotion?['minimum_order_yer']?.toString() ?? '0');
    String discountType = promotion?['discount_type']?.toString() ?? 'percentage';
    bool active = promotion?['is_active'] != false;
    DateTime? endsAt = DateTime.tryParse(promotion?['ends_at']?.toString() ?? '');
    final startsAt = DateTime.tryParse(promotion?['starts_at']?.toString() ?? '') ?? DateTime.now();
    final form = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) => AlertDialog(
        title: Text(promotion == null ? 'إضافة عرض أو تخفيض' : 'تعديل العرض'),
        content: SizedBox(width: 440, child: Form(key: form, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(controller: title, decoration: const InputDecoration(labelText: 'عنوان العرض'), validator: (v) => (v ?? '').trim().isEmpty ? 'أدخل عنوان العرض' : null),
          const SizedBox(height: 8),
          TextFormField(controller: description, maxLines: 2, decoration: const InputDecoration(labelText: 'تفاصيل العرض')),
          const SizedBox(height: 8),
          const Align(alignment: Alignment.centerRight, child: Text('أصناف العرض (يمكن اختيار عدة أصناف)', style: TextStyle(fontWeight: FontWeight.w800))),
          const SizedBox(height: 6),
          Container(
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(border: Border.all(color: const Color(0xFFC9D8CC)), borderRadius: BorderRadius.circular(12)),
            child: ListView(
              shrinkWrap: true,
              children: [
                const Padding(padding: EdgeInsets.all(10), child: Text('اترك الاختيارات فارغة إذا كان العرض يشمل المطعم كاملًا.', style: TextStyle(fontSize: 12, color: Colors.white70))),
                ...menuItems.map((meal) {
                  final itemId = meal['id'].toString();
                  return CheckboxListTile(
                    dense: true,
                    value: selectedMenuItemIds.contains(itemId),
                    title: Text(meal['name']?.toString() ?? 'صنف'),
                    onChanged: (checked) => setLocal(() {
                      if (checked == true) { selectedMenuItemIds.add(itemId); }
                      else { selectedMenuItemIds.remove(itemId); }
                    }),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: discountType,
            decoration: const InputDecoration(labelText: 'نوع التخفيض'),
            items: const [
              DropdownMenuItem(value: 'percentage', child: Text('نسبة مئوية ٪')),
              DropdownMenuItem(value: 'fixed', child: Text('مبلغ ثابت بالريال')),
            ],
            onChanged: (v) => setLocal(() => discountType = v ?? 'percentage'),
          ),
          const SizedBox(height: 8),
          TextFormField(controller: value, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: discountType == 'percentage' ? 'نسبة الخصم (1 إلى 100)' : 'قيمة الخصم بالريال'), validator: (v) {
            final n = int.tryParse(v ?? '') ?? 0;
            if (n <= 0 || (discountType == 'percentage' && n > 100)) return 'أدخل قيمة تخفيض صحيحة';
            return null;
          }),
          const SizedBox(height: 8),
          TextFormField(controller: code, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'كود العرض (اختياري)')),
          const SizedBox(height: 8),
          TextFormField(controller: minimum, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الحد الأدنى للطلب بالريال (0 = بدون حد)'), validator: (v) => (int.tryParse(v ?? '') ?? -1) < 0 ? 'أدخل مبلغًا صحيحًا' : null),
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerRight, child: TextButton.icon(
            onPressed: () async {
              final picked = await showDatePicker(
                context: ctx,
                initialDate: endsAt != null && endsAt!.isAfter(DateTime.now()) ? endsAt! : DateTime.now().add(const Duration(days: 7)),
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 730)),
              );
              if (picked != null) setLocal(() => endsAt = DateTime(picked.year, picked.month, picked.day, 23, 59));
            },
            icon: const Icon(Icons.event_outlined),
            label: Text(endsAt == null ? 'بدون تاريخ انتهاء' : 'ينتهي في ${endsAt!.year}-${endsAt!.month.toString().padLeft(2, '0')}-${endsAt!.day.toString().padLeft(2, '0')}'),
          )),
          if (endsAt != null) Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => setLocal(() => endsAt = null), child: const Text('إزالة تاريخ الانتهاء'))),
          SwitchListTile(value: active, onChanged: (v) => setLocal(() => active = v), title: const Text('عرض نشط ويظهر للعملاء')),
        ])))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () { if (form.currentState!.validate()) Navigator.pop(ctx, true); }, child: const Text('حفظ العرض')),
        ],
      )),
    );
    if (saved == true) {
      await _run(() => SareeBackend.savePromotion(
        id: promotion?['id']?.toString(),
        restaurantId: restaurantId,
        title: title.text,
        description: description.text,
        code: code.text,
        discountType: discountType,
        discountValue: int.parse(value.text),
        minimumOrder: int.parse(minimum.text),
        menuItemIds: selectedMenuItemIds.toList(),
        startsAt: startsAt,
        endsAt: endsAt,
        active: active,
      ));
    }
    title.dispose(); description.dispose(); code.dispose(); value.dispose(); minimum.dispose();
  }

  Widget _promotionsTab(String restaurantId) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: SareeBackend.managePromotions(restaurantId),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const LoadingPage();
        if (snap.hasError) return Center(child: Text('تعذر تحميل العروض: ${SareeBackend.arabicError(snap.error)}'));
        final promotions = snap.data ?? [];
        return ListView(padding: const EdgeInsets.all(12), children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : () => _editPromotion(restaurantId),
              icon: const Icon(Icons.add_circle_outline_rounded),
              label: const Text('إضافة عرض جديد'),
            ),
          ),
          const SizedBox(height: 8),
          const Align(
            alignment: Alignment.centerRight,
            child: Text('عروض وتخفيضات المطعم', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFFFFD60A))),
          ),
          const Padding(padding: EdgeInsets.only(top: 6, bottom: 12), child: Text('العروض النشطة تظهر تلقائيًا للعملاء في الصفحة الرئيسية مع كود العرض وشروطه.', style: TextStyle(color: Color(0xFF536B61), height: 1.5))),
          if (promotions.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(22), child: Text('لم تضف عروضًا بعد. أنشئ أول تخفيض ليظهر لعملائك.', textAlign: TextAlign.center))),
          ...promotions.map((item) {
            final discount = item['discount_type'] == 'percentage'
                ? '${item['discount_value']}٪ خصم'
                : '${item['discount_value']} ريال خصم';
            return Card(child: ListTile(
              leading: CircleAvatar(backgroundColor: const Color(0xFFFFF8E7), child: Icon(Icons.local_offer_rounded, color: item['is_active'] == true ? const Color(0xFF047857) : const Color(0xFF647A70))),
              title: Text(item['title']?.toString() ?? 'عرض'),
              subtitle: Text('$discount • ${_promotionItemNames(item)} • ${item['code'] == null || item['code'].toString().isEmpty ? 'بدون كود' : 'الكود: ${item['code']}'} • ${item['is_active'] == true ? 'نشط' : 'متوقف'}'),
              trailing: PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'edit') _editPromotion(restaurantId, item);
                  if (v == 'toggle') _run(() => SareeBackend.savePromotion(
                    id: item['id'].toString(), restaurantId: restaurantId,
                    title: item['title'].toString(), description: item['description']?.toString() ?? '',
                    code: item['code']?.toString() ?? '', discountType: item['discount_type'].toString(),
                    discountValue: (item['discount_value'] as num).toInt(),
                    minimumOrder: (item['minimum_order_yer'] as num? ?? 0).toInt(),
                    menuItemIds: (item['promotion_menu_items'] is List)
                      ? (item['promotion_menu_items'] as List).whereType<Map>().map((link) => link['menu_item_id'].toString()).toList()
                      : (item['menu_item_id'] == null ? <String>[] : [item['menu_item_id'].toString()]),
                    startsAt: DateTime.tryParse(item['starts_at']?.toString() ?? '') ?? DateTime.now(),
                    endsAt: DateTime.tryParse(item['ends_at']?.toString() ?? ''),
                    active: item['is_active'] != true,
                  ));
                  if (v == 'delete') _run(() => SareeBackend.deletePromotion(item['id'].toString(), restaurantId));
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('تعديل')),
                  PopupMenuItem(value: 'toggle', child: Text('تفعيل / إيقاف')),
                  PopupMenuItem(value: 'delete', child: Text('حذف')),
                ],
              ),
            ));
          }),
        ]);
      },
    );
  }

  Future<void> _importMenuBulk(String restaurantId) async {
    final controller = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة منيو كامل دفعة واحدة'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('اكتب كل صنف في سطر مستقل بهذا الترتيب: الاسم | السعر | الوصف | القسم. الوصف والقسم اختياريان.', style: TextStyle(height: 1.6)),
              const SizedBox(height: 10),
              const Text('مثال:\nبرجر لحم | 1800 | لحم وجبن | البرجر\nبيتزا خضار | 2200 | خضار وجبن | البيتزا\nعصير مانجو | 700 | عصير طازج | المشروبات', style: TextStyle(color: Color(0xFFFFD60A), fontSize: 12, height: 1.7)),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                minLines: 8,
                maxLines: 12,
                textDirection: TextDirection.rtl,
                decoration: const InputDecoration(
                  hintText: 'الصنف | السعر | الوصف | القسم',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton.icon(onPressed: () => Navigator.pop(ctx, true), icon: const Icon(Icons.upload_rounded), label: const Text('استيراد الأصناف')),
        ],
      ),
    );
    if (accepted == true) {
      final rows = <Map<String, dynamic>>[];
      final lines = controller.text.split(RegExp(r'\r?\n'));
      String? problem;
      for (var index = 0; index < lines.length; index++) {
        final line = lines[index].trim();
        if (line.isEmpty) continue;
        final parts = line.split('|').map((part) => part.trim()).toList();
        final name = parts.isNotEmpty ? parts[0] : '';
        final price = parts.length > 1 ? int.tryParse(parts[1].replaceAll(',', '')) : null;
        if (name.isEmpty || price == null || price <= 0 || parts.length > 4) {
          problem = 'راجع السطر رقم ${index + 1}: يجب كتابة الاسم ثم السعر، ويمكن إضافة الوصف والقسم.';
          break;
        }
        rows.add({
          'name': name,
          'price_yer': price,
          'description': parts.length > 2 ? parts[2] : '',
          'category': parts.length > 3 ? parts[3] : '',
        });
      }
      if (problem != null || rows.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem ?? 'أدخل صنفًا واحدًا على الأقل')));
      } else {
        await _run(() async {
          final imported = await SareeBackend.importMenuItemsBulk(restaurantId: restaurantId, items: rows);
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تمت إضافة $imported صنفًا إلى المنيو بنجاح')));
        });
      }
    }
    controller.dispose();
  }

  Future<void> _editMeal(String restaurantId, [Map<String,dynamic>? item]) async {
    final name = TextEditingController(text: item?['name']?.toString() ?? '');
    final description = TextEditingController(text: item?['description']?.toString() ?? '');
    final price = TextEditingController(text: item?['price_yer']?.toString() ?? '');
    final image = TextEditingController(text: item?['image_url']?.toString() ?? '');
    final selectedPhotos = <XFile>[];
    final existingPhotos = item == null ? <String>[] : _mealPhotoUrls(item);
    bool available = item?['is_available'] != false;
    final form = GlobalKey<FormState>();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) => AlertDialog(
      title: Text(item == null ? 'إضافة وجبة' : 'تعديل الوجبة'),
      content: Form(key: form, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: name, decoration: const InputDecoration(labelText: 'اسم الوجبة'), validator: (v) => v == null || v.trim().isEmpty ? 'أدخل اسم الوجبة' : null),
        const SizedBox(height: 8),
        TextFormField(controller: description, maxLines: 2, decoration: const InputDecoration(labelText: 'الوصف')),
        const SizedBox(height: 8),
        TextFormField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'السعر بالريال'), validator: (v) => (int.tryParse(v ?? '') ?? 0) <= 0 ? 'أدخل سعرًا صحيحًا' : null),
        const SizedBox(height: 8),
        TextFormField(controller: image, decoration: const InputDecoration(labelText: 'رابط صورة الوجبة (اختياري)')),
        const SizedBox(height: 6),
        Align(alignment: Alignment.centerRight, child: TextButton.icon(
          onPressed: () async {
            final picked = await ImagePicker().pickMultiImage(imageQuality: 84, maxWidth: 1600, limit: 8);
            if (picked.isNotEmpty) setLocal(() { selectedPhotos..clear()..addAll(picked.take(8)); });
          },
          icon: const Icon(Icons.photo_library_outlined),
          label: Text(selectedPhotos.isEmpty ? 'اختيار عدة صور للوجبة (حتى 8 صور)' : 'تم اختيار ${selectedPhotos.length} صور للوجبة'),
        )),
        if (existingPhotos.isNotEmpty || selectedPhotos.isNotEmpty)
          SizedBox(height: 76, child: ListView(scrollDirection: Axis.horizontal, children: [
            ...existingPhotos.map((url) => Padding(padding: const EdgeInsets.all(4), child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(url, width: 68, height: 68, fit: BoxFit.cover)))),
            ...selectedPhotos.map((photo) => Padding(padding: const EdgeInsets.all(4), child: FutureBuilder<Uint8List>(future: photo.readAsBytes(), builder: (_, snap) => snap.hasData ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(snap.data!, width: 68, height: 68, fit: BoxFit.cover)) : const SizedBox(width: 68, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))))),
          ])),
        SwitchListTile(value: available, onChanged: (v) => setLocal(() => available = v), title: const Text('متاحة للطلب')),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(onPressed: () { if(form.currentState!.validate()) Navigator.pop(ctx, true); }, child: const Text('حفظ'))],
    )));
    if(ok == true) await _run(() async {
      final imageUrls = <String>[];
      if (selectedPhotos.isNotEmpty) {
        for (final photo in selectedPhotos) {
          final extension = photo.name.contains('.') ? photo.name.split('.').last.toLowerCase() : 'jpg';
          final contentType = extension == 'png' ? 'image/png' : extension == 'webp' ? 'image/webp' : 'image/jpeg';
          imageUrls.add(await SareeBackend.uploadMenuPhoto(
            restaurantId: restaurantId,
            bytes: await photo.readAsBytes(),
            extension: extension,
            contentType: contentType,
          ));
        }
      } else if (existingPhotos.isNotEmpty) {
        imageUrls.addAll(existingPhotos);
      } else if (image.text.trim().isNotEmpty) {
        imageUrls.add(image.text.trim());
      }
      final imageUrl = imageUrls.isEmpty ? null : jsonEncode(imageUrls);
      await SareeBackend.saveMenuItem(
        id: item?['id']?.toString(), restaurantId: restaurantId, name: name.text,
        description: description.text, price: int.parse(price.text),
        imageUrl: imageUrl, available: available,
      );
    });
    name.dispose(); description.dispose(); price.dispose(); image.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('إدارة المطعم'), actions: [IconButton(tooltip: 'خيارات الحساب وتسجيل الخروج', onPressed: () => showRestaurantSignOutOptions(context), icon: const Icon(Icons.logout))]),
    body: FutureBuilder<List<Map<String,dynamic>>>(
      future: SareeBackend.myRestaurants(),
      builder: (context, rs) {
        if(rs.connectionState != ConnectionState.done) return const LoadingPage();
        if(rs.hasError) return Center(child: Text('تعذر تحميل المطعم: ${SareeBackend.arabicError(rs.error)}'));
        final restaurants = rs.data ?? [];
        if(restaurants.isEmpty) return const Center(child: Text('لم يتم ربط حسابك بمطعم. اطلب من الإدارة ربط الحساب.'));
        final restaurant = restaurants.first;
        final rid = restaurant['id'].toString();
        return Column(children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 10, 12, 2),
            child: FoodPhotoBanner(
              title: 'وجباتك تستحق الظهور',
              subtitle: 'تابع الطلبات وأدر قائمة مطعمك بسهولة',
              height: 132,
            ),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 4), child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [Color(0xFF123B2F), Color(0xFF064E3B)]),
              borderRadius: BorderRadius.circular(22),
              boxShadow: const [BoxShadow(color: Color(0x1F171717), blurRadius: 16, offset: Offset(0, 7))],
            ),
            child: Row(children: [
              Container(width: 48, height: 48, decoration: BoxDecoration(color: const Color(0xFFFFD60A), borderRadius: BorderRadius.circular(15)), child: const Icon(Icons.storefront_rounded, color: Color(0xFF123B2F), size: 27)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(restaurant['name'].toString(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
                const SizedBox(height: 3),
                const Text('إدارة الطلبات والوجبات وفريق التوصيل', style: TextStyle(fontSize: 11, color: Colors.white70)),
              ])),
              const Icon(Icons.verified_rounded, color: Color(0xFFFFD60A), size: 22),
            ]),
          )),
          Expanded(child: IndexedStack(index: _tab, children: [
            FutureBuilder<List<Map<String,dynamic>>>(
              future: SareeBackend.manageMenu(rid),
              builder: (context, snap) {
                if(snap.connectionState != ConnectionState.done) return const LoadingPage();
                if(snap.hasError) return Center(child: Text('تعذر تحميل الوجبات: ${SareeBackend.arabicError(snap.error)}'));
                final items = snap.data ?? [];
                return ListView(padding: const EdgeInsets.all(12), children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('قائمة الوجبات', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                    FilledButton.icon(onPressed: () => _editMeal(rid), icon: const Icon(Icons.add), label: const Text('وجبة جديدة')),
                  ]),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : () => _importMenuBulk(rid),
                      icon: const Icon(Icons.playlist_add_rounded),
                      label: const Text('إضافة منيو كامل دفعة واحدة'),
                    ),
                  ),
                  if(items.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('لم تضف وجبات بعد. أضف أول وجبة ليراها العملاء.')),
                  ...items.map((item) => Card(child: ListTile(
                    leading: ClipRRect(borderRadius: BorderRadius.circular(10), child: SizedBox(width: 54, height: 54, child: RotatingFoodImage(urls: _mealPhotoUrls(item).isEmpty ? [_mealPhotoUrl(item)] : _mealPhotoUrls(item)))),
                    title: Text(item['name'].toString(), style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 15, fontWeight: FontWeight.w900)),
                    subtitle: Text('${item['price_yer']} ريال • ${item['is_available'] == true ? 'متاحة' : 'متوقفة'}', style: const TextStyle(color: Color(0xFFDCE9DE))),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) {
                        if(v == 'edit') _editMeal(rid, item);
                        if(v == 'toggle') _run(() => SareeBackend.saveMenuItem(id: item['id'].toString(), restaurantId: rid, name: item['name'].toString(), description: item['description']?.toString() ?? '', price: (item['price_yer'] as num).toInt(), imageUrl: item['image_url']?.toString(), available: item['is_available'] != true));
                        if(v == 'delete') _run(() => SareeBackend.deleteMenuItem(item['id'].toString()));
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('تعديل')),
                        PopupMenuItem(value: 'toggle', child: Text('تغيير التوفر')),
                        PopupMenuItem(value: 'delete', child: Text('حذف')),
                      ],
                    ),
                  ))),
                ]);
              },
            ),
            Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                child: Row(children: [
                  Expanded(child: TextField(
                    controller: _orderSearchController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: 'ابحث برقم الطلب',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(tooltip: 'مسح البحث', onPressed: () => setState(() => _orderSearchController.clear()), icon: const Icon(Icons.close)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  )),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(tooltip: 'تصدير سجل الطلبات PDF', onPressed: _busy ? null : () => _exportRestaurantOrdersPdf(rid), icon: const Icon(Icons.picture_as_pdf_rounded)),
                  if (_archivedOrderIds.isNotEmpty)
                    IconButton(tooltip: 'استعادة الطلبات المخفية', onPressed: _busy ? null : _restoreArchivedOrders, icon: const Icon(Icons.unarchive_outlined)),
                ]),
              ),
              Expanded(child: StreamBuilder<List<Map<String,dynamic>>>(
                stream: SareeBackend.restaurantOrdersStream(rid),
                builder: (context, snap) {
                  if (!snap.hasData && snap.connectionState == ConnectionState.waiting) return const LoadingPage();
                  if(snap.hasError) return Center(child: Text('تعذر تحميل الطلبات: ${SareeBackend.arabicError(snap.error)}'));
                  final allOrders = snap.data ?? [];
                  final query = _orderSearchController.text.trim();
                  final orders = allOrders.where((o) => !_archivedOrderIds.contains(o['id'].toString()) && (query.isEmpty || (o['order_number']?.toString() ?? '').contains(query))).toList();
                  if(allOrders.isEmpty) return const Center(child: Text('لا توجد طلبات حتى الآن'));
                  if(orders.isEmpty) return Center(child: Text(query.isEmpty ? 'لا توجد طلبات ظاهرة. يمكنك استعادة الطلبات المخفية.' : 'لا توجد نتيجة لرقم الطلب $query'));
                  return ListView(padding: const EdgeInsets.all(12), children: orders.map((o) {
                    final status = (o['status'] ?? '').toString().trim().toLowerCase();
                    final courierValue = o['courier_id'];
                    final hasCourier = courierValue != null && courierValue.toString().trim().isNotEmpty;
                    final isReadyForPickup = status == 'ready_for_pickup';
                    final next = status == 'pending' ? 'accepted' : status == 'accepted' ? 'preparing' : status == 'preparing' ? 'ready_for_pickup' : null;
                    final label = next == 'accepted' ? 'قبول الطلب' : next == 'preparing' ? 'بدء التحضير' : 'جاهز للاستلام';
                    return Card(clipBehavior: Clip.antiAlias, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      ListTile(
                        title: Text('طلب #${o['order_number']} • ${o['customer_name']}'),
                        subtitle: Text('${o['delivery_address']}\n${o['total_yer']} ريال • $status'),
                        isThreeLine: true,
                      ),
                      if (next != null)
                        Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 10), child: SizedBox(width: double.infinity, child: FilledButton(onPressed: _busy ? null : () => _run(() => SareeBackend.transition(o['id'].toString(), next)), child: Text(label))))
                      else if (isReadyForPickup && !hasCourier)
                        Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 10), child: SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _busy ? null : () => _assignCourier(rid, o), icon: const Icon(Icons.delivery_dining_rounded), label: const Text('اختيار مندوب'))))
                      else if (hasCourier)
                        const Padding(padding: EdgeInsets.fromLTRB(12, 0, 12, 10), child: Chip(label: Text('تم تعيين مندوب'))),
                      _restaurantOrderDetails(o),
                    ]));
                  }).toList());
                },
              )),
            ]),
            _courierTeamTab(rid),
            _cashierManagementTab(rid),
            _promotionsTab(rid),
            DeliveryFeeSettingsTab(
              restaurantId: rid,
              initialFee: (restaurant['delivery_fee_yer'] as num?)?.toInt() ?? 100,
            ),
            RestaurantBrandingTab(restaurantId: rid, initialCoverUrl: restaurant['cover_image_url']?.toString()),
            RestaurantAccountSettingsTab(
              restaurantId: rid,
              initialName: restaurant['name']?.toString() ?? '',
              initialPhone: restaurant['phone']?.toString() ?? '',
            ),
          ])),
        ]);
      },
    ),
    bottomNavigationBar: NavigationBar(selectedIndex: _tab, onDestinationSelected: (v) => setState(() => _tab = v), destinations: const [
      NavigationDestination(icon: Icon(Icons.restaurant_menu_outlined), label: 'الوجبات'),
      NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'الطلبات'),
      NavigationDestination(icon: Icon(Icons.delivery_dining_outlined), label: 'المندوبون'),
      NavigationDestination(icon: Icon(Icons.point_of_sale_rounded), label: 'الكاشيرون'),
      NavigationDestination(icon: Icon(Icons.local_offer_outlined), label: 'العروض'),
      NavigationDestination(icon: Icon(Icons.payments_outlined), label: 'رسوم التوصيل'),
      NavigationDestination(icon: Icon(Icons.wallpaper_outlined), label: 'خلفية المطعم'),
      NavigationDestination(icon: Icon(Icons.manage_accounts_outlined), label: 'إعدادات الحساب'),
    ]),
  );
}


class DeliveryFeeSettingsTab extends StatefulWidget {
  const DeliveryFeeSettingsTab({
    super.key,
    required this.restaurantId,
    required this.initialFee,
  });

  final String restaurantId;
  final int initialFee;

  @override
  State<DeliveryFeeSettingsTab> createState() => _DeliveryFeeSettingsTabState();
}

class _DeliveryFeeSettingsTabState extends State<DeliveryFeeSettingsTab> {
  late final TextEditingController _fee;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _fee = TextEditingController(text: widget.initialFee.toString());
  }

  @override
  void didUpdateWidget(covariant DeliveryFeeSettingsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.restaurantId != widget.restaurantId ||
        oldWidget.initialFee != widget.initialFee) {
      _fee.text = widget.initialFee.toString();
    }
  }

  @override
  void dispose() {
    _fee.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = int.tryParse(_fee.text.trim());
    if (amount == null || amount < 0 || amount > 1000000) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('أدخل رسومًا صحيحة من 0 إلى 1,000,000 ريال'),
      ));
      return;
    }
    setState(() => _saving = true);
    try {
      await SareeBackend.updateRestaurantDeliveryFee(
        restaurantId: widget.restaurantId,
        feeYer: amount,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تم حفظ رسوم التوصيل بنجاح، وستُطبق على الطلبات الجديدة'),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر حفظ الرسوم: ${SareeBackend.arabicError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Card(child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Icon(Icons.delivery_dining_rounded, size: 52, color: Color(0xFFFFD60A)),
          const SizedBox(height: 12),
          const Text('تحديد رسوم توصيل المطعم',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          const Text(
            'حدد المبلغ الذي يناسب مطعمك. سيظهر للعميل بوضوح عند إتمام الطلب، ويُحفظ مع الطلب حتى لا تتغير رسوم الطلبات السابقة إذا عدّلت السعر لاحقًا.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, height: 1.6),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _fee,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
              labelText: 'رسوم التوصيل بالريال اليمني',
              suffixText: 'ريال',
              prefixIcon: Icon(Icons.payments_outlined),
            ),
          ),
          const SizedBox(height: 8),
          const Text('يمكنك كتابة 0 إذا كان التوصيل مجانيًا.',
            style: TextStyle(color: Color(0xFFFFD60A), fontSize: 12)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_rounded),
            label: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ رسوم التوصيل'),
          ),
        ]),
      )),
    ],
  );
}

class CourierRestaurantJoinPage extends StatefulWidget {
  const CourierRestaurantJoinPage({super.key, required this.status, this.note});
  final String status;
  final String? note;
  @override State<CourierRestaurantJoinPage> createState() => _CourierRestaurantJoinPageState();
}

class _CourierRestaurantJoinPageState extends State<CourierRestaurantJoinPage> {
  bool _busy = false;
  Set<String> _selected = {};
  late Future<List<Map<String, dynamic>>> _restaurants;
  late Future<List<Map<String, dynamic>>> _applications;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _restaurants = SareeBackend.restaurants();
    _applications = SareeBackend.courierMyRestaurantApplications();
  }

  Future<void> _submit() async {
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اختر مطعماً واحداً على الأقل')));
      return;
    }
    setState(() => _busy = true);
    try {
      await SareeBackend.courierApplyToRestaurants(_selected.toList());
      if (!mounted) return;
      setState(() {
        _selected.clear();
        _load();
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال طلبات الانضمام إلى المطاعم المختارة')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(SareeBackend.arabicError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _statusLabel(String value) => switch (value) {
    'accepted' => 'تم قبولك',
    'rejected' => 'تم رفض الطلب',
    _ => 'بانتظار رد المطعم',
  };

  Color _statusColor(String value) => value == 'accepted'
      ? const Color(0xFF16834A)
      : value == 'rejected' ? const Color(0xFF047857) : const Color(0xFF9A7B00);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('اختيار المطاعم للعمل معها'),
      actions: [IconButton(tooltip: 'خيارات تسجيل الخروج', onPressed: () => showAccountSignOutOptions(context), icon: const Icon(Icons.logout))],
    ),
    body: ListView(padding: const EdgeInsets.all(14), children: [
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [Icon(Icons.verified_user_outlined, color: Color(0xFF16834A)), SizedBox(width: 8), Expanded(child: Text('تم استلام مستندات هويتك', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)))]),
        const SizedBox(height: 8),
        Text(widget.status == 'approved'
          ? 'اختر المطاعم التي ترغب في العمل معها. سيراجع كل مطعم طلبك وبياناتك.'
          : 'يمكنك إرسال طلباتك للمطاعم الآن. سيظل تفعيل استقبال الطلبات مرتبطاً باعتماد الإدارة لهويتك.'),
        if (widget.status != 'approved') ...[
          const SizedBox(height: 10),
          const Chip(avatar: Icon(Icons.hourglass_top_rounded), label: Text('توثيق الحساب بانتظار مراجعة الإدارة')),
        ],
        if (widget.note?.trim().isNotEmpty == true) Padding(padding: const EdgeInsets.only(top: 8), child: Text(widget.note!, style: const TextStyle(color: Colors.red))),
      ]))),
      const SizedBox(height: 12),
      const Text('اختر المطاعم التي تريد العمل معها', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      FutureBuilder<List<Map<String, dynamic>>>(
        future: _restaurants,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const LoadingPage();
          if (snap.hasError) return Text('تعذر تحميل المطاعم: ${SareeBackend.arabicError(snap.error)}');
          final rows = snap.data ?? [];
          if (rows.isEmpty) return const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('لا توجد مطاعم متاحة حالياً.')));
          return Column(children: rows.map((r) {
            final id = r['id'].toString();
            return Card(child: CheckboxListTile(
              value: _selected.contains(id),
              onChanged: _busy ? null : (v) => setState(() => v == true ? _selected.add(id) : _selected.remove(id)),
              title: Text(r['name']?.toString() ?? 'مطعم', style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(r['address']?.toString() ?? 'العنوان غير متوفر'),
              secondary: const CircleAvatar(child: Icon(Icons.restaurant_rounded)),
            ));
          }).toList());
        },
      ),
      FilledButton.icon(
        onPressed: _busy ? null : _submit,
        icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send_rounded),
        label: const Text('إرسال طلبات الانضمام'),
      ),
      const SizedBox(height: 20),
      const Text('طلبات الانضمام التي أرسلتها', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
      FutureBuilder<List<Map<String, dynamic>>>(
        future: _applications,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator());
          if (snap.hasError) return Text('تعذر تحميل الطلبات: ${SareeBackend.arabicError(snap.error)}');
          final rows = snap.data ?? [];
          if (rows.isEmpty) return const Padding(padding: EdgeInsets.all(12), child: Text('لم ترسل أي طلبات بعد.'));
          return Column(children: rows.map((a) {
            final status = a['status']?.toString() ?? 'pending';
            return Card(child: ListTile(
              leading: Icon(status == 'accepted' ? Icons.check_circle : status == 'rejected' ? Icons.cancel : Icons.hourglass_top, color: _statusColor(status)),
              title: Text(a['restaurant_name']?.toString() ?? 'مطعم'),
              subtitle: Text('${_statusLabel(status)} • ${a['review_note'] ?? ''}'),
              isThreeLine: (a['review_note']?.toString().isNotEmpty ?? false),
            ));
          }).toList());
        },
      ),
    ]),
  );
}


Widget _restaurantCourierDocumentPreview(String title, String? url) {
  if (url == null || url.isEmpty) {
    return Card(child: Padding(padding: const EdgeInsets.all(12), child: Text('$title: لم تُرفق الصورة')));
  }
  return Card(child: Padding(padding: const EdgeInsets.all(10), child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          url,
          height: 180,
          width: double.infinity,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const SizedBox(
            height: 100,
            child: Center(child: Text('تعذر عرض الصورة، حدّث الصفحة وحاول مجدداً')),
          ),
        ),
      ),
    ],
  )));
}

class RestaurantAccountSettingsTab extends StatefulWidget {
  const RestaurantAccountSettingsTab({
    super.key,
    required this.restaurantId,
    required this.initialName,
    required this.initialPhone,
  });
  final String restaurantId;
  final String initialName;
  final String initialPhone;

  @override
  State<RestaurantAccountSettingsTab> createState() => _RestaurantAccountSettingsTabState();
}

class _RestaurantAccountSettingsTabState extends State<RestaurantAccountSettingsTab> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName);
    _phone = TextEditingController(text: widget.initialPhone);
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await SareeBackend.updateRestaurantAccount(
        restaurantId: widget.restaurantId,
        name: _name.text,
        phone: _phone.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ بيانات المطعم بنجاح')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر حفظ بيانات المطعم: ${SareeBackend.arabicError(error)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const Text('بيانات حساب المطعم', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      const Text('يمكنك تعديل اسم المطعم ورقم التواصل المرتبط بصفحة المطعم.', style: TextStyle(color: Colors.white70, height: 1.5)),
      const SizedBox(height: 14),
      TextField(
        controller: _name,
        textDirection: TextDirection.rtl,
        decoration: const InputDecoration(labelText: 'اسم المطعم', prefixIcon: Icon(Icons.storefront_outlined)),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _phone,
        keyboardType: TextInputType.phone,
        textDirection: TextDirection.ltr,
        decoration: const InputDecoration(labelText: 'رقم هاتف المطعم', prefixIcon: Icon(Icons.phone_outlined), hintText: 'اختياري'),
      ),
      const SizedBox(height: 14),
      FilledButton.icon(
        onPressed: _busy ? null : _save,
        icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
        label: Text(_busy ? 'جارٍ الحفظ...' : 'حفظ التعديلات'),
      ),
      const Divider(height: 32),
      const Text('المندوبون الذين تمت الموافقة عليهم', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
      const SizedBox(height: 6),
      const Text('تظهر هنا بيانات المندوبين المقبولين وسجل تاريخ الموافقة. طلبات الرفض لا تظهر في حساب المطعم.', style: TextStyle(color: Colors.white70, height: 1.5)),
      FutureBuilder<List<Map<String, dynamic>>>(
        future: SareeBackend.restaurantCourierApplications(widget.restaurantId),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Padding(padding: EdgeInsets.all(14), child: LinearProgressIndicator());
          }
          if (snap.hasError) {
            return Padding(padding: const EdgeInsets.all(12), child: Text('تعذر تحميل بيانات المندوبين: ${SareeBackend.arabicError(snap.error)}'));
          }
          final accepted = (snap.data ?? []).where((entry) => entry['status'] == 'accepted').toList();
          if (accepted.isEmpty) {
            return const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('لا يوجد مندوبون تمت الموافقة عليهم حتى الآن.', textAlign: TextAlign.center)));
          }
          return Column(children: accepted.map((entry) {
            final date = DateTime.tryParse(entry['created_at']?.toString() ?? '')?.toLocal();
            final dateLabel = date == null ? 'التاريخ غير متاح' : '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
            return Card(
              child: ExpansionTile(
                leading: const CircleAvatar(child: Icon(Icons.verified_user_rounded, color: Colors.green)),
                title: Text(entry['full_name']?.toString().trim().isNotEmpty == true ? entry['full_name'].toString() : 'مندوب توصيل'),
                subtitle: Text('${entry['phone'] ?? 'لا يوجد رقم هاتف'} • تمت الموافقة على الطلب: $dateLabel'),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                children: [
                  ListTile(dense: true, leading: const Icon(Icons.phone_outlined), title: const Text('رقم الهاتف'), subtitle: SelectableText(entry['phone']?.toString() ?? 'غير متوفر')),
                  ListTile(dense: true, leading: const Icon(Icons.email_outlined), title: const Text('البريد الإلكتروني'), subtitle: SelectableText(entry['email']?.toString() ?? 'غير متوفر')),
                  _restaurantCourierDocumentPreview('صورة الهوية – الوجه الأمامي', entry['id_front_url']?.toString()),
                  _restaurantCourierDocumentPreview('صورة الهوية – الوجه الخلفي', entry['id_back_url']?.toString()),
                  _restaurantCourierDocumentPreview('صورة المندوب مع البطاقة', entry['selfie_url']?.toString()),
                  _restaurantCourierDocumentPreview('إثبات محل الإقامة (إن وُجد)', entry['residence_url']?.toString()),
                ],
              ),
            );
          }).toList());
        },
      ),
    ],
  );
}

class RestaurantBrandingTab extends StatefulWidget {
  const RestaurantBrandingTab({super.key, required this.restaurantId, this.initialCoverUrl});
  final String restaurantId;
  final String? initialCoverUrl;
  @override State<RestaurantBrandingTab> createState() => _RestaurantBrandingTabState();
}
class _RestaurantBrandingTabState extends State<RestaurantBrandingTab> {
  bool _busy = false;
  late String? _coverUrl;
  @override void initState() { super.initState(); _coverUrl = widget.initialCoverUrl; }
  @override void didUpdateWidget(covariant RestaurantBrandingTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialCoverUrl != widget.initialCoverUrl) _coverUrl = widget.initialCoverUrl;
  }
  Future<void> _chooseCover() async {
    if (_busy) return;
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 84, maxWidth: 2000);
    if (file == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await file.readAsBytes();
      final extension = file.name.contains('.') ? file.name.split('.').last.toLowerCase() : 'jpg';
      final contentType = switch (extension) { 'png' => 'image/png', 'webp' => 'image/webp', _ => 'image/jpeg' };
      final url = await SareeBackend.uploadRestaurantCover(restaurantId: widget.restaurantId, bytes: bytes, extension: extension, contentType: contentType);
      await SareeBackend.updateRestaurantCover(restaurantId: widget.restaurantId, imageUrl: url);
      if (!mounted) return;
      setState(() => _coverUrl = url);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تحديث خلفية المطعم وستظهر للعملاء')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر حفظ الخلفية: ${SareeBackend.arabicError(error)}')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
  Future<void> _removeCover() async {
    if (_busy || _coverUrl == null || _coverUrl!.isEmpty) return;
    setState(() => _busy = true);
    try {
      await SareeBackend.updateRestaurantCover(restaurantId: widget.restaurantId, imageUrl: null);
      if (!mounted) return;
      setState(() => _coverUrl = null);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت إزالة خلفية المطعم')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر إزالة الخلفية: ${SareeBackend.arabicError(error)}')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
  @override Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
    const Text('خلفية صفحة المطعم', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
    const SizedBox(height: 8),
    const Text('اختر صورة عريضة تمثل مطعمك. ستظهر أعلى صفحة مطعمك عند تصفح العملاء للوجبات.', style: TextStyle(color: Colors.white70, height: 1.6)),
    const SizedBox(height: 16),
    ClipRRect(borderRadius: BorderRadius.circular(20), child: SizedBox(height: 190, width: double.infinity,
      child: _coverUrl == null || _coverUrl!.isEmpty
        ? const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF123B2F), Color(0xFF064E3B)])), child: Center(child: Icon(Icons.wallpaper_rounded, size: 54, color: Color(0xFFFFD60A))))
        : Image.network(_coverUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_outlined, size: 48))),
    )),
    const SizedBox(height: 14),
    FilledButton.icon(onPressed: _busy ? null : _chooseCover,
      icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.photo_library_outlined),
      label: Text(_busy ? 'جارٍ الحفظ...' : 'اختيار خلفية من الهاتف')),
    if (_coverUrl != null && _coverUrl!.isNotEmpty)
      TextButton.icon(onPressed: _busy ? null : _removeCover, icon: const Icon(Icons.delete_outline_rounded), label: const Text('إزالة الخلفية')),
  ]);
}

class CourierPortal extends StatefulWidget {
  const CourierPortal({super.key});
  @override State<CourierPortal> createState() => _CourierPortalState();
}

class _CourierPortalState extends State<CourierPortal> {
  bool _busy = false;
  bool _sharing = false;
  Position? _lastPosition;
  late Future<List<Map<String, dynamic>>> _ordersFuture;
  StreamSubscription<Position>? _positionSub;
  StreamSubscription<List<Map<String, dynamic>>>? _assignedOrdersSubscription;
  bool _ordersStreamReady = false;
  final Set<String> _knownAssignedOrders = {};

  Future<List<Map<String, dynamic>>> _loadOrders() => SareeBackend.courierOrders();

  @override
  void initState() {
    super.initState();
    _ordersFuture = _loadOrders();
    _assignedOrdersSubscription = SareeBackend.courierOrdersStream().listen((rows) {
      final assigned = rows.where((row) => (row['status'] ?? '').toString().trim().toLowerCase() == 'assigned').toList();
      final newAssignments = _ordersStreamReady
          ? assigned.where((row) => !_knownAssignedOrders.contains(row['id'].toString())).toList()
          : <Map<String, dynamic>>[];
      _knownAssignedOrders.addAll(assigned.map((row) => row['id'].toString()));
      _ordersStreamReady = true;
      if (!mounted) return;
      if (newAssignments.isNotEmpty) {
        final number = newAssignments.first['order_number']?.toString() ?? '';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم إسناد طلب جديد${number.isEmpty ? '' : ' رقم #$number'} إليك. العنوان والموقع داخل تفاصيل المهمة.')));
      }
      _refreshOrders();
    }, onError: (Object error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تحديث مهامك تلقائيًا: ${SareeBackend.arabicError(error)}')));
    });
  }

  Future<void> _refreshOrders() async {
    final future = _loadOrders();
    if (mounted) setState(() => _ordersFuture = future);
    await future;
  }

  Future<void> _startSharing() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if(!enabled) throw Exception('فعّل خدمة الموقع GPS أولاً');
    var permission = await Geolocator.checkPermission();
    if(permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if(permission == LocationPermission.denied || permission == LocationPermission.deniedForever) throw Exception('اسمح للتطبيق بالوصول إلى الموقع من إعدادات الهاتف');
    await _positionSub?.cancel();
    const settings = LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 15);
    _positionSub = Geolocator.getPositionStream(locationSettings: settings).listen((p) async {
      if (mounted) setState(() => _lastPosition = p);
      try { await SareeBackend.updateCourierLocation(p.latitude, p.longitude); }
      catch(e) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تحديث الموقع: ${SareeBackend.arabicError(e)}'))); }
    });
    final now = await Geolocator.getCurrentPosition();
    _lastPosition = now;
    await SareeBackend.updateCourierLocation(now.latitude, now.longitude);
    if(mounted) setState(() => _sharing = true);
  }

  Future<void> _stopSharing() async {
    await _positionSub?.cancel();
    _positionSub = null;
    if(mounted) setState(() => _sharing = false);
  }

  @override
  void dispose() { _positionSub?.cancel(); _assignedOrdersSubscription?.cancel(); super.dispose(); }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) setState(() => _ordersFuture = _loadOrders());
    } catch(e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(SareeBackend.arabicError(e))));
    } finally {
      if(mounted) setState(() => _busy = false);
    }
  }

  List<double>? _deliveryCoordinates(Map<String, dynamic> order) {
    final rawLat = order['delivery_latitude'];
    final rawLng = order['delivery_longitude'];
    final lat = rawLat is num ? rawLat.toDouble() : double.tryParse(rawLat?.toString() ?? '');
    final lng = rawLng is num ? rawLng.toDouble() : double.tryParse(rawLng?.toString() ?? '');
    if (lat != null && lng != null && lat.abs() <= 90 && lng.abs() <= 180) return [lat, lng];

    final address = (order['delivery_address'] ?? '').toString();
    final patterns = [
      RegExp(r'[?&]q=(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)', caseSensitive: false),
      RegExp(r'(-?\d{1,2}\.\d+)\s*[,،]\s*(-?\d{1,3}\.\d+)'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(address);
      if (match == null) continue;
      final parsedLat = double.tryParse(match.group(1)!);
      final parsedLng = double.tryParse(match.group(2)!);
      if (parsedLat != null && parsedLng != null && parsedLat.abs() <= 90 && parsedLng.abs() <= 180) {
        return [parsedLat, parsedLng];
      }
    }
    return null;
  }

  Widget _courierOrderDetails(Map<String, dynamic> order) {
    final coordinates = _deliveryCoordinates(order);
    final lat = coordinates?[0];
    final lng = coordinates?[1];
    final hasLocation = lat != null && lng != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ListTile(dense: true, leading: const Icon(Icons.person_outline), title: Text(order['customer_name']?.toString().trim().isNotEmpty == true ? order['customer_name'].toString() : 'العميل'), subtitle: Text(order['customer_phone']?.toString() ?? 'لا يوجد رقم هاتف')),
      ListTile(dense: true, leading: const Icon(Icons.location_on_outlined), title: const Text('عنوان التوصيل'), subtitle: Text(order['delivery_address']?.toString().trim().isNotEmpty == true ? order['delivery_address'].toString() : 'لم يحدد العميل عنوان التوصيل')),
      if ((order['notes'] ?? '').toString().trim().isNotEmpty) ListTile(dense: true, leading: const Icon(Icons.notes_rounded), title: const Text('ملاحظات العميل'), subtitle: Text(order['notes'].toString())),
      ListTile(dense: true, leading: const Icon(Icons.payments_outlined), title: Text('الإجمالي: ${order['total_yer'] ?? 0} ريال'), subtitle: Text('طريقة الدفع: ${order['payment_method'] ?? 'نقدًا عند الاستلام'}')),
      FutureBuilder<List<Map<String, dynamic>>>(
        future: SareeBackend.courierOrderItems(order['id'].toString()),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator());
          if (snap.hasError) return Padding(padding: const EdgeInsets.all(12), child: Text('تعذر تحميل أصناف الطلب: ${SareeBackend.arabicError(snap.error)}'));
          final items = snap.data ?? [];
          return Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('تفاصيل الأصناف', style: TextStyle(fontWeight: FontWeight.w900)),
            if (items.isEmpty) const Padding(padding: EdgeInsets.only(top: 6), child: Text('لا توجد تفاصيل أصناف مسجلة لهذا الطلب')),
            ...items.map((item) => Padding(padding: const EdgeInsets.only(top: 6), child: Row(children: [
              Expanded(child: Text('${item['item_name']} × ${item['quantity']}')),
              Text('${item['line_total_yer']} ريال', style: const TextStyle(fontWeight: FontWeight.w700)),
            ]))),
          ]));
        },
      ),
      if (hasLocation) Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.map_outlined), title: Text('موقع العميل على الخريطة')),
        SelectableText('الإحداثيات: ${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}'),
        if (_lastPosition != null) SizedBox(height: 230, child: ClipRRect(borderRadius: BorderRadius.circular(14), child: FlutterMap(
          options: MapOptions(initialCenter: LatLng((_lastPosition!.latitude + lat) / 2, (_lastPosition!.longitude + lng) / 2), initialZoom: 13),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.saree.delivery.saree'),
            PolylineLayer(polylines: [Polyline(points: [LatLng(_lastPosition!.latitude, _lastPosition!.longitude), LatLng(lat, lng)], strokeWidth: 5, color: Colors.blueAccent)]),
            MarkerLayer(markers: [
              Marker(point: LatLng(_lastPosition!.latitude, _lastPosition!.longitude), width: 48, height: 48, child: const Icon(Icons.delivery_dining_rounded, color: Color(0xFF047857), size: 42)),
              Marker(point: LatLng(lat, lng), width: 48, height: 48, child: const Icon(Icons.location_pin, color: Colors.green, size: 42)),
            ]),
          ],
        ))),
        if (_lastPosition == null) const Padding(padding: EdgeInsets.all(8), child: Text('فعّل مشاركة الموقع ليظهر خط الطريق الأزرق من موقعك إلى العميل داخل التطبيق.')),
      ])) else const Padding(padding: EdgeInsets.all(12), child: Text('لم يرسل العميل موقعًا جغرافيًا؛ استخدم عنوان التوصيل ورقم الهاتف للتواصل معه.')),
    ]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('طلبات المندوب'), actions: [
      IconButton(tooltip: 'إشعارات التكليف', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerNotificationsPage())), icon: const Icon(Icons.notifications_active_outlined)),
      IconButton(tooltip: 'تحديث الطلبات', onPressed: _busy ? null : _refreshOrders, icon: const Icon(Icons.refresh_rounded)),
      IconButton(tooltip: 'خيارات تسجيل الخروج', onPressed: () => showAccountSignOutOptions(context), icon: const Icon(Icons.logout)),
    ]),
    body: FutureBuilder<List<Map<String,dynamic>>>(
      future: _ordersFuture,
      builder: (context, snap) {
        if(snap.connectionState != ConnectionState.done) return const LoadingPage();
        if(snap.hasError) return Center(child: Text('تعذر تحميل الطلبات: ${SareeBackend.arabicError(snap.error)}'));
        final active = (snap.data ?? []).where((o) {
          final status = (o['status'] ?? '').toString().trim().toLowerCase();
          return status == 'assigned' || status == 'picked_up';
        }).toList();
        return ListView(padding: const EdgeInsets.all(12), children: [
          Card(child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.storefront_outlined)),
            title: const Text('المطاعم وطلبات الانضمام', style: TextStyle(fontWeight: FontWeight.w900)),
            subtitle: const Text('اختر المطاعم التي تريد العمل معها وتابع ردودها'),
            trailing: const Icon(Icons.chevron_left_rounded),
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => const CourierRestaurantJoinPage(status: 'approved'),
            )),
          )),
          Card(child: SwitchListTile(
            value: _sharing,
            onChanged: (v) => _run(() => v ? _startSharing() : _stopSharing()),
            title: const Text('مشاركة موقعي مع العميل'),
            subtitle: Text(_sharing ? 'الموقع يتحدث أثناء فتح التطبيق' : 'فعّلها بعد استلام الطلب ليتمكن العميل من رؤية موقعك'),
            secondary: const Icon(Icons.my_location_rounded),
          )),
          const Padding(padding: EdgeInsets.all(8), child: Text('مهامك الحالية', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold))),
          if(active.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('لا توجد لديك توصيلات نشطة')),
          ...active.map((o) {
            final status = (o['status'] ?? '').toString().trim().toLowerCase();
            final next = status == 'assigned' ? 'picked_up' : 'delivered';
            final label = status == 'assigned' ? 'تأكيد استلام الطلب' : 'تأكيد التسليم';
            return Card(clipBehavior: Clip.antiAlias, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ListTile(title: Text('طلب #${o['order_number']}'), subtitle: Text(status == 'assigned' ? 'تم إسناده إليك - بانتظار الاستلام' : 'تم استلام الطلب')),
              _courierOrderDetails(o),
              Padding(padding: const EdgeInsets.all(12), child: FilledButton.icon(
                onPressed: _busy ? null : () => _run(() => SareeBackend.transition(o['id'].toString(), next)),
                icon: Icon(status == 'assigned' ? Icons.inventory_2_rounded : Icons.check_circle_outline),
                label: Text(label),
              )),
            ]));
          }),

        ]);
      },
    ),
  );
}

class AdminPortal extends StatefulWidget {
  const AdminPortal({super.key});
  @override State<AdminPortal> createState() => _AdminPortalState();
}

class _AdminPortalState extends State<AdminPortal> {
  int _tab = 0;
  Future<void> _refresh() async { if (mounted) setState(() {}); }

  Future<void> _createRestaurant() async {
    final name = TextEditingController();
    final address = TextEditingController();
    final phone = TextEditingController();
    final fee = TextEditingController(text: '1000');
    final form = GlobalKey<FormState>();
    final ok = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('إضافة مطعم'),
      content: Form(key: form, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: name, decoration: const InputDecoration(labelText: 'اسم المطعم'), validator: (v) => v == null || v.trim().isEmpty ? 'أدخل اسم المطعم' : null),
        const SizedBox(height: 10),
        TextFormField(controller: address, decoration: const InputDecoration(labelText: 'العنوان'), validator: (v) => v == null || v.trim().isEmpty ? 'أدخل العنوان' : null),
        const SizedBox(height: 10),
        TextFormField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'الهاتف')),
        const SizedBox(height: 10),
        TextFormField(controller: fee, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'رسوم التوصيل بالريال'), validator: (v) => int.tryParse(v ?? '') == null ? 'أدخل رقمًا صحيحًا' : null),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () { if (form.currentState!.validate()) Navigator.pop(dialogContext, true); }, child: const Text('حفظ')),
      ],
    ));
    if (ok == true) {
      try {
        await SareeBackend.createRestaurant(name: name.text, address: address.text, phone: phone.text, deliveryFee: int.parse(fee.text));
        await _refresh();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت إضافة المطعم. يبقى غير منشور حتى تفعيله.')));
      } catch(e) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(SareeBackend.arabicError(e)))); }
    }
    name.dispose(); address.dispose(); phone.dispose(); fee.dispose();
  }

  Future<void> _assignManager(String restaurantId) async {
    final profiles = await SareeBackend.adminProfiles();
    final candidates = profiles.where((p) => p['role'] == 'restaurant_owner').toList();
    if (!mounted) return;
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يوجد حساب بدور صاحب مطعم. غيّر دور الحساب أولاً من تبويب الحسابات.')));
      return;
    }
    String selected = candidates.first['id'].toString();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) => AlertDialog(
      title: const Text('ربط صاحب المطعم'),
      content: DropdownButtonFormField<String>(
        value: selected,
        isExpanded: true,
        items: candidates.map((p) => DropdownMenuItem(value: p['id'].toString(), child: Text('${p['full_name']} • ${p['phone'] ?? ''}', overflow: TextOverflow.ellipsis))).toList(),
        onChanged: (v) { if (v != null) setLocal(() => selected = v); },
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ربط'))],
    )));
    if (ok == true) {
      await SareeBackend.addRestaurantMember(restaurantId, selected);
      await _refresh();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم ربط صاحب المطعم')));
    }
  }

  Future<void> _reviewCourierDocuments(Map<String, dynamic> profile) async {
    try {
      final docs = await SareeBackend.adminCourierVerificationDocuments(profile['id'].toString());
      if (!mounted) return;
      final note = TextEditingController();
      final decision = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
        title: Text('توثيق المندوب: ${profile['full_name'] ?? ''}'),
        content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          ...docs.map((doc) => Padding(padding: const EdgeInsets.only(bottom: 14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(doc['label'].toString(), style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(doc['signed_url'].toString(),
              height: 190, width: double.infinity, fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Text('تعذر عرض الصورة؛ حاول تحديث المستندات.'))),
          ]))),
          TextField(controller: note, maxLines: 2, decoration: const InputDecoration(labelText: 'ملاحظة أو سبب الرفض (اختياري)')),
        ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: const Text('إغلاق')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'rejected'), child: const Text('رفض التوثيق', style: TextStyle(color: Colors.red))),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'approved'), child: const Text('اعتماد المندوب')),
        ],
      ));
      if (decision == 'approved' || decision == 'rejected') {
        await SareeBackend.adminReviewUser(profile['id'].toString(), decision!, note.text);
        await _refresh();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(decision == 'approved' ? 'تم اعتماد المندوب' : 'تم رفض التوثيق')));
      }
      note.dispose();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تحميل مستندات المندوب: ${SareeBackend.arabicError(e)}')));
    }
  }

  Future<void> _changeRole(Map<String, dynamic> profile) async {
    const roles = {'customer':'عميل','restaurant_owner':'صاحب مطعم','courier':'مندوب','admin':'مدير'};
    String role = profile['role'].toString();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) => AlertDialog(
      title: Text('صلاحيات ${profile['full_name']}'),
      content: DropdownButtonFormField<String>(
        value: role,
        items: roles.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
        onChanged: (v) { if(v != null) setLocal(() => role = v); },
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ الصلاحية'))],
    )));
    if (ok == true && role != profile['role']) {
      await SareeBackend.setUserRole(profile['id'].toString(), role);
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('لوحة إدارة سريع'),
      actions: [IconButton(tooltip: 'تحديث', onPressed: _refresh, icon: const Icon(Icons.refresh_rounded)), IconButton(tooltip: 'خيارات تسجيل الخروج', onPressed: () => showAccountSignOutOptions(context), icon: const Icon(Icons.logout_rounded))],
    ),
    body: IndexedStack(index: _tab, children: [
      FutureBuilder<List<Map<String, dynamic>>>(
        future: SareeBackend.adminRestaurants(),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const LoadingPage();
          if (snap.hasError) return Center(child: Text('تعذر تحميل المطاعم: ${SareeBackend.arabicError(snap.error)}'));
          final rows = snap.data ?? [];
          return ListView(padding: const EdgeInsets.all(14), children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('إدارة المطاعم', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF123B2F))),
              FilledButton.icon(onPressed: _createRestaurant, icon: const Icon(Icons.add), label: const Text('إضافة')),
            ]),
            const SizedBox(height: 8),
            if (rows.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(22), child: Text('لم تتم إضافة مطاعم بعد. أضف مطعمًا للبدء.'))),
            ...rows.map((r) => Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const CircleAvatar(backgroundColor: Color(0xFFE5F3EA), child: Icon(Icons.restaurant_rounded)),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF123B2F))),
                  Text(r['address']?.toString() ?? '', style: const TextStyle(color: Color(0xFF536B61), fontSize: 12)),
                ])),
                Switch(value: r['is_active'] == true, onChanged: (v) async {
                  try { await SareeBackend.setRestaurantActive(r['id'].toString(), v); await _refresh(); }
                  catch(e) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(SareeBackend.arabicError(e)))); }
                }),
              ]),
              const Divider(),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('التوصيل: ${r['delivery_fee_yer']} ريال', style: const TextStyle(fontWeight: FontWeight.w700)),
                TextButton.icon(onPressed: () => _assignManager(r['id'].toString()), icon: const Icon(Icons.person_add_alt_1), label: const Text('ربط مدير')),
              ]),
            ])))),
          ]);
        },
      ),
      FutureBuilder<List<Map<String, dynamic>>>(
        future: SareeBackend.adminProfiles(),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const LoadingPage();
          if (snap.hasError) return Center(child: Text('تعذر تحميل الحسابات: ${SareeBackend.arabicError(snap.error)}'));
          final profiles = snap.data ?? [];
          const labels = {'customer':'عميل','restaurant_owner':'صاحب مطعم','courier':'مندوب','admin':'مدير'};
          return ListView(padding: const EdgeInsets.all(14), children: [
            const Text('الحسابات والصلاحيات', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF123B2F))),
            const SizedBox(height: 8),
            ...profiles.map((p) {
              final approvalLabels = {'approved': 'معتمد', 'pending': 'بانتظار اعتماد الإدارة', 'rejected': 'مرفوض'};
              final approvalLabel = approvalLabels[p['approval_status']?.toString()] ?? '';
              return Card(child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
              title: Text(p['full_name']?.toString().isNotEmpty == true ? p['full_name'].toString() : 'مستخدم'),
              subtitle: Text('${p['phone'] ?? 'لا يوجد هاتف'} • ${labels[p['role']] ?? p['role']} • $approvalLabel'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (p['role'] == 'courier') IconButton(
                  tooltip: 'مراجعة إثباتات المندوب',
                  onPressed: () => _reviewCourierDocuments(p),
                  icon: const Icon(Icons.verified_user_outlined),
                ),
                IconButton(tooltip: 'تعديل الصلاحية', onPressed: () => _changeRole(p), icon: const Icon(Icons.manage_accounts_rounded)),
              ]),
            ));
            }),
          ]);
        },
      ),
      AdminReportsPage(),
      const AdminMenuManagementPage(),
    ]),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _tab,
      onDestinationSelected: (v) => setState(() => _tab = v),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: 'المطاعم'),
        NavigationDestination(icon: Icon(Icons.people_alt_outlined), selectedIcon: Icon(Icons.people_alt), label: 'الحسابات'),
        NavigationDestination(icon: Icon(Icons.analytics_outlined), selectedIcon: Icon(Icons.analytics_rounded), label: 'التقارير'),
        NavigationDestination(icon: Icon(Icons.fastfood_outlined), selectedIcon: Icon(Icons.fastfood_rounded), label: 'الوجبات'),
      ],
    ),
  );
}


Future<void> _showSareeReviewDialog(BuildContext context, Map<String, dynamic> order) async {
  int foodRating = 5;
  int courierRating = 5;
  final comment = TextEditingController();
  Widget stars(int value, ValueChanged<int> onChanged) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: List.generate(5, (i) => IconButton(
      onPressed: () => onChanged(i + 1),
      icon: Icon(i < value ? Icons.star_rounded : Icons.star_border_rounded,
        color: const Color(0xFFFFD60A), size: 30),
    )),
  );
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) => AlertDialog(
      title: const Text('قيّم طلبك'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('كيف كان الطعام؟'),
        stars(foodRating, (v) => setLocal(() => foodRating = v)),
        const Divider(),
        const Text('كيف كان التوصيل والمندوب؟'),
        stars(courierRating, (v) => setLocal(() => courierRating = v)),
        TextField(controller: comment, maxLines: 3, decoration: const InputDecoration(labelText: 'ملاحظاتك (اختياري)')),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إرسال التقييم')),
      ],
    )),
  );
  if (ok == true) {
    try {
      await SareeBackend.submitReview(
        orderId: order['id'].toString(),
        restaurantId: order['restaurant_id'].toString(),
        rating: foodRating,
        courierRating: courierRating,
        comment: comment.text,
      );
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('شكراً لك، تم إرسال تقييم الطعام والتوصيل')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر إرسال التقييم: $e')));
    }
  }
  comment.dispose();
}

class CustomerSearchPage extends StatefulWidget {
  const CustomerSearchPage({super.key, this.initialQuery = ''});
  final String initialQuery;
  @override State<CustomerSearchPage> createState() => _CustomerSearchPageState();
}
class _CustomerSearchPageState extends State<CustomerSearchPage> {
  late final TextEditingController _query;
  Future<List<Map<String,dynamic>>>? _results;
  Future<List<Map<String,dynamic>>>? _categories;
  @override void initState() {
    super.initState();
    _query = TextEditingController(text: widget.initialQuery);
    _categories = SareeBackend.categories();
    if (_query.text.trim().isNotEmpty) _search();
  }
  @override void dispose() { _query.dispose(); super.dispose(); }
  void _search() => setState(() => _results = SareeBackend.searchCatalog(_query.text));
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ابحث عن وجبتك')),
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(14), child: TextField(
        controller: _query,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _search(),
        decoration: InputDecoration(
          hintText: 'ابحث عن مطعم أو وجبة...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(onPressed: _search, icon: const Icon(Icons.arrow_forward_rounded)),
        ),
      )),
      SizedBox(height: 48, child: FutureBuilder<List<Map<String,dynamic>>>(
        future: _categories,
        builder: (context,snap) => ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
          if (snap.hasData) ...snap.data!.map((cat) => Padding(
            padding: const EdgeInsetsDirectional.only(end: 7),
            child: ActionChip(label: Text(cat['name'].toString()), onPressed: () {
              _query.text = cat['name'].toString();
              _search();
            }),
          )),
        ]),
      )),
      Expanded(child: _results == null
        ? const Center(child: Text('اكتب اسم مطعم أو وجبة لبدء البحث'))
        : FutureBuilder<List<Map<String,dynamic>>>(
          future: _results,
          builder: (context,snap) {
            if (snap.connectionState != ConnectionState.done) return const LoadingPage();
            if (snap.hasError) return Center(child: Text('تعذر البحث: ${SareeBackend.arabicError(snap.error)}'));
            final rows = snap.data ?? [];
            if (rows.isEmpty) return const Center(child: Text('لا توجد نتائج مطابقة'));
            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: rows.length,
              itemBuilder: (context,index) {
                final row = rows[index];
                final isRestaurant = row['_kind'] == 'restaurant';
                final restaurant = isRestaurant ? row : Map<String,dynamic>.from(row['restaurants'] as Map);
                return Card(child: ListTile(
                  leading: CircleAvatar(backgroundColor: const Color(0xFFE5F3EA), child: Icon(isRestaurant ? Icons.restaurant_rounded : Icons.fastfood_rounded)),
                  title: Text(isRestaurant ? row['name'].toString() : row['name'].toString()),
                  subtitle: Text(isRestaurant ? (row['description'] ?? 'مطعم') .toString() : '${row['price_yer']} ريال • ${restaurant['name']}'),
                  trailing: const Icon(Icons.chevron_left_rounded),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RestaurantMenuPage(restaurant: restaurant))),
                ));
              },
            );
          },
        ),
      ),
    ]),
  );
}

class CustomerFavoritesPage extends StatefulWidget {
  const CustomerFavoritesPage({super.key});
  @override State<CustomerFavoritesPage> createState() => _CustomerFavoritesPageState();
}
class _CustomerFavoritesPageState extends State<CustomerFavoritesPage> {
  late Future<List<Map<String,dynamic>>> _future;
  @override void initState() { super.initState(); _future = SareeBackend.favoriteRestaurants(); }
  Future<void> _refresh() async { setState(() => _future = SareeBackend.favoriteRestaurants()); await _future; }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('مطاعمي المفضلة'), actions: [IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh))]),
    body: FutureBuilder<List<Map<String,dynamic>>>(
      future: _future,
      builder: (context,snap) {
        if (snap.connectionState != ConnectionState.done) return const LoadingPage();
        if (snap.hasError) return Center(child: Text('تعذر تحميل المفضلة: ${SareeBackend.arabicError(snap.error)}'));
        final rows = snap.data ?? [];
        if (rows.isEmpty) return const Center(child: Text('لم تضف مطاعم إلى المفضلة بعد'));
        return ListView(children: rows.map((r) => Card(child: ListTile(
          leading: const Icon(Icons.favorite_rounded, color: Color(0xFF047857)),
          title: Text(r['name'].toString()),
          subtitle: Text(r['address']?.toString() ?? ''),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RestaurantMenuPage(restaurant: r))),
          trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async {
            await SareeBackend.toggleFavorite(r['id'].toString());
            await _refresh();
          }),
        ))).toList());
      },
    ),
  );
}

class CustomerNotificationsPage extends StatefulWidget {
  const CustomerNotificationsPage({super.key});
  @override State<CustomerNotificationsPage> createState() => _CustomerNotificationsPageState();
}
class _CustomerNotificationsPageState extends State<CustomerNotificationsPage> {
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('الإشعارات')),
    body: StreamBuilder<List<Map<String,dynamic>>>(
      stream: SareeBackend.notificationsStream(),
      builder: (context,snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) return const LoadingPage();
        if (snap.hasError) return Center(child: Text('تعذر تحميل الإشعارات: ${SareeBackend.arabicError(snap.error)}'));
        final rows = snap.data ?? [];
        if (rows.isEmpty) return const Center(child: Text('لا توجد إشعارات حالياً'));
        return ListView(children: rows.map((n) => Card(child: ListTile(
          leading: CircleAvatar(backgroundColor: n['read_at'] == null ? const Color(0xFFE5F3EA) : Colors.grey.shade200, child: const Icon(Icons.notifications_active_outlined)),
          title: Text(n['title'].toString(), style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text('${n['body']}\\n${n['created_at']}'),
          isThreeLine: true,
          onTap: () async {
            if (n['read_at'] == null) await SareeBackend.markNotificationRead(n['id'].toString());
          },
        ))).toList());
      },
    ),
  );
}

class CustomerSupportPage extends StatefulWidget {
  const CustomerSupportPage({super.key});
  @override State<CustomerSupportPage> createState() => _CustomerSupportPageState();
}
class _CustomerSupportPageState extends State<CustomerSupportPage> {
  late Future<List<Map<String,dynamic>>> _future;
  @override void initState() { super.initState(); _future = SareeBackend.mySupportTickets(); }
  Future<void> _refresh() async { setState(() => _future = SareeBackend.mySupportTickets()); await _future; }
  Future<void> _newTicket() async {
    final subject = TextEditingController();
    final message = TextEditingController();
    final form = GlobalKey<FormState>();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('إرسال طلب مساعدة'),
      content: Form(key: form, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: subject, decoration: const InputDecoration(labelText: 'موضوع المشكلة'), validator: (v) => v == null || v.trim().length < 3 ? 'اكتب موضوعاً واضحاً' : null),
        const SizedBox(height: 10),
        TextFormField(controller: message, minLines: 3, maxLines: 5, decoration: const InputDecoration(labelText: 'اشرح المشكلة'), validator: (v) => v == null || v.trim().length < 5 ? 'اكتب تفاصيل أكثر' : null),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx,false), child: const Text('إلغاء')), FilledButton(onPressed: () { if(form.currentState!.validate()) Navigator.pop(ctx,true); }, child: const Text('إرسال'))],
    ));
    if (ok == true) {
      try {
        await SareeBackend.createSupportTicket(subject: subject.text, message: message.text);
        await _refresh();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال طلبك للدعم')));
      } catch(e) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر إرسال الطلب: $e'))); }
    }
    subject.dispose(); message.dispose();
  }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('الدعم والمساعدة'), actions: [IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh))]),
    floatingActionButton: FloatingActionButton.extended(onPressed: _newTicket, icon: const Icon(Icons.add_comment_outlined), label: const Text('طلب مساعدة')),
    body: ListView(padding: const EdgeInsets.all(12), children: [
      const Card(child: Padding(padding: EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('كيف نساعدك؟', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
        SizedBox(height: 8),
        Text('أرسل تفاصيل المشكلة أو استفسارك، وسيتابع فريق الدعم طلبك من لوحة الإدارة.'),
        Divider(),
        Text('الأسئلة الشائعة', style: TextStyle(fontWeight: FontWeight.w800)),
        ExpansionTile(title: Text('كيف أطلب وجبة؟'), children: [Padding(padding: EdgeInsets.all(12), child: Text('اختر المطعم والوجبات، أضفها إلى السلة، ثم أكد عنوانك. الدفع نقداً عند الاستلام.'))]),
        ExpansionTile(title: Text('كيف أتابع طلبي؟'), children: [Padding(padding: EdgeInsets.all(12), child: Text('افتح صفحة طلباتي ثم اختر الطلب لمشاهدة آخر تحديث لحالته.'))]),
        ExpansionTile(title: Text('كيف أغيّر عنوان التوصيل؟'), children: [Padding(padding: EdgeInsets.all(12), child: Text('من حسابي أضف عنواناً أو اختر عنواناً افتراضياً قبل الطلب.'))]),
      ]))),
      FutureBuilder<List<Map<String,dynamic>>>(
        future: _future,
        builder: (context,snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return Text('تعذر تحميل طلبات الدعم: ${SareeBackend.arabicError(snap.error)}');
          final rows = snap.data ?? [];
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(padding: EdgeInsets.all(8), child: Text('طلبات المساعدة السابقة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
            if (rows.isEmpty) const Text('لم ترسل أي طلب مساعدة بعد'),
            ...rows.map((t) => Card(child: ListTile(
              leading: const Icon(Icons.support_agent_rounded),
              title: Text(t['subject'].toString()),
              subtitle: Text('${t['message']}\nالحالة: ${t['status']}\nرد الدعم: ${t['admin_reply']?.toString().isEmpty == true ? 'بانتظار الرد' : t['admin_reply']}'),
              isThreeLine: true,
            ))),
          ]);
        },
      ),
    ]),
  );
}

class AdminReportsPage extends StatelessWidget {
  const AdminReportsPage({super.key});
  @override Widget build(BuildContext context) => FutureBuilder<List<Map<String,dynamic>>>(
    future: SareeBackend.adminOrders(),
    builder: (context,snap) {
      if (snap.connectionState != ConnectionState.done) return const LoadingPage();
      if (snap.hasError) return Center(child: Text('تعذر تحميل التقارير: ${SareeBackend.arabicError(snap.error)}'));
      final orders = snap.data ?? [];
      final delivered = orders.where((o) => o['status'] == 'delivered').toList();
      final pending = orders.where((o) => o['status'] == 'pending').length;
      final cancelled = orders.where((o) => o['status'] == 'cancelled').length;
      final revenue = delivered.fold<int>(0, (sum,o) => sum + ((o['total_yer'] as num?)?.toInt() ?? 0));
      return ListView(padding: const EdgeInsets.all(14), children: [
        const Text('تقارير الأداء', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: 2, childAspectRatio: 1.45, children: [
          _reportCard('إجمالي الطلبات', orders.length.toString(), Icons.receipt_long_rounded),
          _reportCard('طلبات قيد الانتظار', pending.toString(), Icons.hourglass_top_rounded),
          _reportCard('طلبات مكتملة', delivered.length.toString(), Icons.check_circle_outline_rounded),
          _reportCard('طلبات ملغاة', cancelled.toString(), Icons.cancel_outlined),
          _reportCard('قيمة الطلبات المكتملة', '$revenue ريال', Icons.payments_outlined),
        ]),
        const SizedBox(height: 18),
        const Text('أحدث الطلبات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        ...orders.take(40).map((o) => Card(child: ListTile(
          title: Text('طلب #${o['order_number']} • ${o['customer_name']}'),
          subtitle: Text('${(o['restaurants'] as Map?)?['name'] ?? 'مطعم'} • ${o['status']} • ${o['total_yer']} ريال'),
        ))),
        const SizedBox(height: 18),
        const AdminSupportInbox(),
      ]);
    },
  );
  Widget _reportCard(String label, String value, IconData icon) => Card(child: Padding(padding: const EdgeInsets.all(13), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
    Icon(icon, color: const Color(0xFF047857)),
    Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
    Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF536B61))),
  ])));
}

class AdminSupportInbox extends StatefulWidget {
  const AdminSupportInbox({super.key});
  @override State<AdminSupportInbox> createState() => _AdminSupportInboxState();
}
class _AdminSupportInboxState extends State<AdminSupportInbox> {
  late Future<List<Map<String,dynamic>>> _future;
  @override void initState() { super.initState(); _future = SareeBackend.adminSupportTickets(); }
  Future<void> _refresh() async { setState(() => _future = SareeBackend.adminSupportTickets()); await _future; }
  Future<void> _reply(Map<String,dynamic> ticket) async {
    final reply = TextEditingController(text: ticket['admin_reply']?.toString() ?? '');
    String status = ticket['status'].toString();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx,setLocal) => AlertDialog(
      title: Text('طلب: ${ticket['subject']}'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(ticket['message'].toString()),
        const SizedBox(height: 12),
        TextField(controller: reply, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'رد الإدارة')),
        DropdownButtonFormField<String>(value: status, decoration: const InputDecoration(labelText: 'حالة الطلب'), items: const [
          DropdownMenuItem(value: 'open', child: Text('مفتوح')),
          DropdownMenuItem(value: 'in_progress', child: Text('قيد المعالجة')),
          DropdownMenuItem(value: 'resolved', child: Text('تم الحل')),
          DropdownMenuItem(value: 'closed', child: Text('مغلق')),
        ], onChanged: (v) { if(v != null) setLocal(() => status = v); }),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx,false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx,true), child: const Text('حفظ الرد'))],
    )));
    if (ok == true) {
      try { await SareeBackend.replySupportTicket(ticket['id'].toString(), reply.text, status); await _refresh(); }
      catch(e) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر حفظ الرد: $e'))); }
    }
    reply.dispose();
  }
  @override Widget build(BuildContext context) => FutureBuilder<List<Map<String,dynamic>>>(
    future: _future,
    builder: (context,snap) {
      if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      if (snap.hasError) return Text('تعذر تحميل طلبات الدعم: ${SareeBackend.arabicError(snap.error)}');
      final rows = snap.data ?? [];
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('صندوق الدعم', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        if (rows.isEmpty) const Text('لا توجد طلبات دعم حالياً'),
        ...rows.map((t) => Card(child: ListTile(
          title: Text(t['subject'].toString()),
          subtitle: Text('${(t['profiles'] as Map?)?['full_name'] ?? 'عميل'} • ${t['status']}'),
          trailing: IconButton(icon: const Icon(Icons.reply_rounded), onPressed: () => _reply(t)),
        ))),
      ]);
    },
  );
}


class AdminMenuManagementPage extends StatefulWidget {
  const AdminMenuManagementPage({super.key});
  @override State<AdminMenuManagementPage> createState() => _AdminMenuManagementPageState();
}
class _AdminMenuManagementPageState extends State<AdminMenuManagementPage> {
  String? _restaurantId;
  Future<List<Map<String,dynamic>>>? _restaurants;
  Future<List<Map<String,dynamic>>>? _menu;
  bool _busy = false;
  @override void initState() { super.initState(); _restaurants = SareeBackend.adminRestaurants(); }
  void _select(String? id) {
    setState(() {
      _restaurantId = id;
      _menu = id == null ? null : SareeBackend.manageMenu(id);
    });
  }
  Future<void> _refresh() async {
    setState(() {
      _restaurants = SareeBackend.adminRestaurants();
      _menu = _restaurantId == null ? null : SareeBackend.manageMenu(_restaurantId!);
    });
  }
  Future<void> _edit(Map<String,dynamic>? item) async {
    final restaurantId = _restaurantId;
    if (restaurantId == null) return;
    final name = TextEditingController(text: item?['name']?.toString() ?? '');
    final description = TextEditingController(text: item?['description']?.toString() ?? '');
    final price = TextEditingController(text: item?['price_yer']?.toString() ?? '');
    final image = TextEditingController(text: item?['image_url']?.toString() ?? '');
    bool available = item?['is_available'] == true;
    final form = GlobalKey<FormState>();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx,setLocal) => AlertDialog(
      title: Text(item == null ? 'إضافة وجبة للمطعم' : 'تعديل الوجبة'),
      content: Form(key: form, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: name, decoration: const InputDecoration(labelText: 'اسم الوجبة'), validator: (v) => v == null || v.trim().isEmpty ? 'أدخل اسم الوجبة' : null),
        const SizedBox(height: 8),
        TextFormField(controller: description, maxLines: 2, decoration: const InputDecoration(labelText: 'الوصف')),
        const SizedBox(height: 8),
        TextFormField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'السعر بالريال اليمني'), validator: (v) => (int.tryParse(v ?? '') ?? 0) <= 0 ? 'أدخل سعراً صحيحاً' : null),
        const SizedBox(height: 8),
        TextFormField(controller: image, decoration: const InputDecoration(labelText: 'رابط الصورة (اختياري)')),
        SwitchListTile(value: available, onChanged: (v) => setLocal(() => available = v), title: const Text('متاحة للطلب')),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx,false), child: const Text('إلغاء')), FilledButton(onPressed: () { if(form.currentState!.validate()) Navigator.pop(ctx,true); }, child: const Text('حفظ'))],
    )));
    if (ok == true) {
      setState(() => _busy = true);
      try {
        await SareeBackend.saveMenuItem(id: item?['id']?.toString(), restaurantId: restaurantId, name: name.text, description: description.text, price: int.parse(price.text), imageUrl: image.text, available: available);
        await _refresh();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ الوجبة')));
      } catch(e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر حفظ الوجبة: $e')));
      } finally { if(mounted) setState(() => _busy = false); }
    }
    name.dispose(); description.dispose(); price.dispose(); image.dispose();
  }
  @override Widget build(BuildContext context) => FutureBuilder<List<Map<String,dynamic>>>(
    future: _restaurants,
    builder: (context,rs) {
      if (rs.connectionState != ConnectionState.done) return const LoadingPage();
      if (rs.hasError) return Center(child: Text('تعذر تحميل المطاعم: ${SareeBackend.arabicError(rs.error)}'));
      final restaurants = rs.data ?? [];
      if (restaurants.isEmpty) return const Center(child: Text('أضف مطعماً أولاً من تبويب المطاعم'));
      _restaurantId ??= restaurants.first['id'].toString();
      _menu ??= SareeBackend.manageMenu(_restaurantId!);
      return Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: Row(children: [
          Expanded(child: DropdownButtonFormField<String>(
            value: _restaurantId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'اختر المطعم'),
            items: restaurants.map((r) => DropdownMenuItem(value: r['id'].toString(), child: Text(r['name'].toString(), overflow: TextOverflow.ellipsis))).toList(),
            onChanged: _select,
          )),
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
        ])),
        Expanded(child: FutureBuilder<List<Map<String,dynamic>>>(
          future: _menu,
          builder: (context,snap) {
            if (snap.connectionState != ConnectionState.done) return const LoadingPage();
            if (snap.hasError) return Center(child: Text('تعذر تحميل الوجبات: ${SareeBackend.arabicError(snap.error)}'));
            final items = snap.data ?? [];
            return ListView(padding: const EdgeInsets.all(12), children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('قائمة الوجبات', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                FilledButton.icon(onPressed: _busy ? null : () => _edit(null), icon: const Icon(Icons.add), label: const Text('إضافة وجبة')),
              ]),
              if (items.isEmpty) const Padding(padding: EdgeInsets.all(18), child: Text('لا توجد وجبات. أضف الوجبات وأسعارها الحقيقية قبل إتاحتها للعملاء.')),
              ...items.map((item) => Card(child: ListTile(
                title: Text(item['name'].toString()),
                subtitle: Text('${item['price_yer']} ريال • ${item['is_available'] == true ? 'متاحة' : 'متوقفة'}'),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'edit') await _edit(item);
                    if (v == 'toggle') {
                      await SareeBackend.saveMenuItem(id: item['id'].toString(), restaurantId: _restaurantId!, name: item['name'].toString(), description: item['description']?.toString() ?? '', price: (item['price_yer'] as num).toInt(), imageUrl: item['image_url']?.toString(), available: item['is_available'] != true);
                      await _refresh();
                    }
                    if (v == 'delete') {
                      await SareeBackend.deleteMenuItem(item['id'].toString());
                      await _refresh();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('تعديل')),
                    PopupMenuItem(value: 'toggle', child: Text('تغيير التوفر')),
                    PopupMenuItem(value: 'delete', child: Text('حذف')),
                  ],
                ),
              ))),
            ]);
          },
        )),
      ]);
    },
  );
}


class CashierJoinPage extends StatefulWidget {
  const CashierJoinPage({super.key});
  @override
  State<CashierJoinPage> createState() => _CashierJoinPageState();
}

class _CashierJoinPageState extends State<CashierJoinPage> {
  bool _busy = false;
  int _reload = 0;

  Future<Map<String, dynamic>> _load() async {
    final results = await Future.wait([
      SareeBackend.restaurants(),
      SareeBackend.myCashierApplications(),
    ]);
    return {'restaurants': results[0], 'applications': results[1]};
  }

  Future<void> _apply(String restaurantId) async {
    setState(() => _busy = true);
    try {
      await SareeBackend.submitCashierApplication(restaurantId);
      if (!mounted) return;
      setState(() => _reload++);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال طلب الانضمام إلى المطعم. انتظر موافقة صاحب المطعم.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر إرسال الطلب: ${SareeBackend.arabicError(e)}')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('الانضمام ككاشير')),
    body: FutureBuilder<Map<String, dynamic>>(
      key: ValueKey(_reload),
      future: _load(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const LoadingPage();
        if (snap.hasError) return Center(child: Text('تعذر تحميل المطاعم والطلبات: ${SareeBackend.arabicError(snap.error)}'));
        final restaurants = List<Map<String, dynamic>>.from(snap.data?['restaurants'] ?? []);
        final applications = List<Map<String, dynamic>>.from(snap.data?['applications'] ?? []);
        final byRestaurant = <String, Map<String, dynamic>>{};
        for (final application in applications) {
          byRestaurant.putIfAbsent(application['restaurant_id'].toString(), () => application);
        }
        return ListView(padding: const EdgeInsets.all(16), children: [
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.point_of_sale_rounded, size: 42, color: Color(0xFF047857)),
            const SizedBox(height: 8),
            const Text('اربط حسابك بمطعمك', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            const Text('اختر المطعم الذي تعمل لديه وأرسل طلب انضمام. لن تتمكن من رؤية طلبات المطعم إلا بعد موافقة صاحبه.'),
          ]))),
          const SizedBox(height: 10),
          if (restaurants.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('لا توجد مطاعم متاحة للانضمام حالياً.'))),
          ...restaurants.map((r) {
            final id = r['id'].toString();
            final application = byRestaurant[id];
            final status = application?['status']?.toString();
            return Card(child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.storefront_rounded)),
              title: Text(r['name']?.toString() ?? 'مطعم', style: const TextStyle(fontWeight: FontWeight.w900)),
              subtitle: Text(r['address']?.toString() ?? 'رداع'),
              trailing: status == 'accepted'
                ? const Icon(Icons.verified_rounded, color: Color(0xFF047857))
                : status == 'pending'
                  ? const Chip(label: Text('قيد المراجعة'))
                  : FilledButton(
                      onPressed: _busy ? null : () => _apply(id),
                      child: Text(status == 'rejected' ? 'إعادة الطلب' : 'انضمام'),
                    ),
              onTap: status == 'accepted' ? () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => CashierPortal(restaurant: r))) : null,
            ));
          }),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: () => setState(() => _reload++), icon: const Icon(Icons.refresh), label: const Text('تحديث حالة الطلب')),
        ]);
      },
    ),
  );
}

class CashierPortal extends StatelessWidget {
  const CashierPortal({super.key, required this.restaurant});
  final Map<String, dynamic> restaurant;

  @override
  Widget build(BuildContext context) {
    final restaurantId = restaurant['id'].toString();
    return Scaffold(
      appBar: AppBar(
        title: Text('كاشير • ${restaurant['name'] ?? 'المطعم'}'),
        actions: [IconButton(tooltip: 'تسجيل الخروج', onPressed: () => showAccountSignOutOptions(context), icon: const Icon(Icons.logout_rounded))],
      ),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: Card(child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.point_of_sale_rounded)),
          title: Text(restaurant['name']?.toString() ?? 'المطعم', style: const TextStyle(fontWeight: FontWeight.w900)),
          subtitle: const Text('حساب كاشير مرتبط بهذا المطعم'),
        ))),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Align(alignment: Alignment.centerRight, child: Text('طلبات المطعم', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)))),
        Expanded(child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: SareeBackend.restaurantOrdersStream(restaurantId),
          builder: (context, snap) {
            if (!snap.hasData && snap.connectionState == ConnectionState.waiting) return const LoadingPage();
            if (snap.hasError) return Center(child: Text('تعذر تحميل الطلبات: ${SareeBackend.arabicError(snap.error)}'));
            final orders = snap.data ?? [];
            if (orders.isEmpty) return const Center(child: Text('لا توجد طلبات حالياً'));
            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: orders.length,
              itemBuilder: (context, index) {
                final order = orders[index];
                final status = order['status']?.toString() ?? '';
                final next = status == 'pending' ? 'accepted' : status == 'accepted' ? 'preparing' : status == 'preparing' ? 'ready_for_pickup' : null;
                final label = next == 'accepted' ? 'قبول الطلب' : next == 'preparing' ? 'بدء التحضير' : 'جاهز للاستلام';
                return Card(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  ListTile(
                    leading: const Icon(Icons.receipt_long_rounded, color: Color(0xFF047857)),
                    title: Text('طلب #${order['order_number']} • ${order['customer_name'] ?? 'عميل'}', style: const TextStyle(fontWeight: FontWeight.w900)),
                    subtitle: Text('${order['customer_phone'] ?? ''}\n${order['delivery_address'] ?? ''}\nالإجمالي: ${order['total_yer'] ?? 0} ريال • $status'),
                    isThreeLine: true,
                  ),
                  if (next != null) Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 12), child: FilledButton(
                    onPressed: () async {
                      try {
                        await SareeBackend.cashierSetOrderStatus(order['id'].toString(), next);
                        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تحديث حالة الطلب')));
                      } catch (e) {
                        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(SareeBackend.arabicError(e))));
                      }
                    },
                    child: Text(label),
                  )),
                  if (status == 'ready_for_pickup') const Padding(padding: EdgeInsets.fromLTRB(12, 0, 12, 12), child: Chip(label: Text('الطلب جاهز لاستلام المندوب'))),
                ]));
              },
            );
          },
        )),
      ]),
    );
  }
}
