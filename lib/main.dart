import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'services/saree_backend.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SareeBackend.initialize();
  runApp(ChangeNotifierProvider(
    create: (_) => CartController(),
    child: const SareeApp(),
  ));
}

class CartLine {
  CartLine({required this.id, required this.name, required this.price, required this.quantity});
  final String id;
  final String name;
  final int price;
  int quantity;
  int get total => price * quantity;
}

class CartController extends ChangeNotifier {
  final List<CartLine> _items = [];
  String? restaurantId;
  List<CartLine> get items => List.unmodifiable(_items);
  int get subtotal => _items.fold(0, (sum, item) => sum + item.total);
  int get count => _items.fold(0, (sum, item) => sum + item.quantity);

  void add(Map<String, dynamic> item, String ownerRestaurantId) {
    if (restaurantId != null && restaurantId != ownerRestaurantId) _items.clear();
    restaurantId = ownerRestaurantId;
    final id = item['id'].toString();
    final index = _items.indexWhere((line) => line.id == id);
    if (index >= 0) {
      _items[index].quantity++;
    } else {
      _items.add(CartLine(
        id: id,
        name: item['name'].toString(),
        price: (item['price_yer'] as num).toInt(),
        quantity: 1,
      ));
    }
    notifyListeners();
  }

  void change(CartLine item, int delta) {
    item.quantity += delta;
    if (item.quantity <= 0) _items.remove(item);
    if (_items.isEmpty) restaurantId = null;
    notifyListeners();
  }

  void clear() {
    _items.clear();
    restaurantId = null;
    notifyListeners();
  }
}

class SareeApp extends StatelessWidget {
  const SareeApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'سريع',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFF7A1A), brightness: Brightness.light, secondary: const Color(0xFF14243A)),
      scaffoldBackgroundColor: const Color(0xFFF5F7FA),
      iconTheme: const IconThemeData(color: Color(0xFFFF7A1A), size: 23),
      appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0, scrolledUnderElevation: 1, backgroundColor: Color(0xFFF5F7FA), foregroundColor: Color(0xFF14243A), titleTextStyle: TextStyle(color: Color(0xFF14243A), fontSize: 19, fontWeight: FontWeight.w800)),
      cardTheme: CardThemeData(color: Colors.white, elevation: 1, shadowColor: Color(0x1420232B), margin: const EdgeInsets.symmetric(vertical: 7, horizontal: 2), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFFE7ECF2)))),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Color(0xFFDCE3EC))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Color(0xFFDCE3EC))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Color(0xFFFF7A1A), width: 1.6)),
        filled: true, fillColor: Colors.white, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      ),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF7A1A), foregroundColor: Colors.white, minimumSize: const Size.fromHeight(52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
      navigationBarTheme: const NavigationBarThemeData(backgroundColor: Colors.white, indicatorColor: Color(0xFFFFE7D2), labelTextStyle: WidgetStatePropertyAll(TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
    ),
    builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child ?? const SizedBox.shrink()),
    home: const BrandSplashGate(),
  );
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 88});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size, height: size,
    decoration: BoxDecoration(
      gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFF9A32), Color(0xFFFF7A1A), Color(0xFF14243A)]),
      borderRadius: BorderRadius.circular(size * .30),
      border: Border.all(color: Colors.white, width: 2),
      boxShadow: const [BoxShadow(color: Color(0x30B91F2B), blurRadius: 20, offset: Offset(0, 8))],
    ),
    child: Stack(alignment: Alignment.center, children: [
      Positioned(left: size * .09, top: size * .32, child: Icon(Icons.bolt_rounded, color: Colors.white70, size: size * .23)),
      Icon(Icons.delivery_dining_rounded, color: Colors.white, size: size * .67),
      Positioned(bottom: size * .09, right: size * .12, child: Container(width: size * .19, height: size * .19, decoration: BoxDecoration(color: const Color(0xFFFFC247), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)))),
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
                colors: [Color(0xFFFF8A36), Color(0xFFFF642D), Color(0xFF14243A)],
                stops: [0, .58, 1],
              ),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 142,
                    height: 142,
                    decoration: BoxDecoration(
                      color: const Color(0xFF14243A),
                      borderRadius: BorderRadius.circular(42),
                      border: Border.all(color: Colors.white.withValues(alpha: .85), width: 3),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .22), blurRadius: 28, offset: const Offset(0, 12))],
                    ),
                    child: const BrandMark(size: 112),
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
            if (profile.hasError) return ErrorPage(message: profile.error.toString());
            final role = profile.data?['role']?.toString() ?? 'customer';
            if (role == 'restaurant_owner') return const RestaurantPortal();
            if (role == 'courier') return const CourierPortal();
            if (role == 'admin') return const AdminPortal();
            return const CustomerHome();
          },
        );
      },
    );
  }
}

class SetupRequiredPage extends StatelessWidget {
  const SetupRequiredPage({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(child: Padding(
      padding: EdgeInsets.all(28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.cloud_off, size: 64, color: const Color(0xFFFF7A1A)),
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
        FilledButton(onPressed: () => SareeBackend.signOut(), child: const Text('تسجيل الخروج')),
      ]),
    )),
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
  bool _register = false;
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _name.dispose(); _phone.dispose(); _email.dispose(); _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() { _busy = true; _message = null; });
    try {
      if (_register) {
        await SareeBackend.signUp(
          email: _email.text,
          password: _password.text,
          fullName: _name.text,
          phone: _phone.text,
        );
        if (mounted) setState(() => _message = 'تم إنشاء الحساب. إذا طُلب منك تأكيد البريد، افتح رسالة التأكيد ثم سجّل الدخول.');
      } else {
        await SareeBackend.signIn(_email.text, _password.text);
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } catch (e) {
      if (mounted) setState(() => _message = e.toString());
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
          const BrandMark(size: 86),
          const SizedBox(height: 14),
          const Text('سريع', textAlign: TextAlign.center, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
          const Text('طعامك يصل إليك', textAlign: TextAlign.center),
          const SizedBox(height: 28),
          Text(_register ? 'إنشاء حساب جديد' : 'تسجيل الدخول', textAlign: TextAlign.center, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
          const SizedBox(height: 18),
          if (_register) ...[
            TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'الاسم الكامل'), validator: (v) => (v == null || v.trim().length < 2) ? 'أدخل اسمك' : null),
            const SizedBox(height: 12),
            TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف'), validator: (v) => (v == null || v.trim().length < 7) ? 'أدخل رقم هاتف صحيحاً' : null),
            const SizedBox(height: 12),
          ],
          TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'البريد الإلكتروني'), validator: (v) => (v == null || !v.contains('@')) ? 'أدخل بريدًا إلكترونيًا صحيحًا' : null),
          const SizedBox(height: 12),
          TextFormField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة المرور'), validator: (v) => (v == null || v.length < 6) ? 'كلمة المرور 6 أحرف على الأقل' : null),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(_message!, style: TextStyle(color: _message!.startsWith('تم') ? Colors.green : Colors.red)),
          ],
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(_register ? 'إنشاء الحساب' : 'دخول'),
          ),
          TextButton(
            onPressed: _busy ? null : () => setState(() { _register = !_register; _message = null; }),
            child: Text(_register ? 'لديك حساب؟ سجل الدخول' : 'ليس لديك حساب؟ أنشئ حسابًا'),
          ),
        ])),
      ),
    ))),
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
          Text('سريع', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF14243A))),
        ]),
        actions: [
          IconButton(tooltip: 'طلباتي', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerOrdersPage())), icon: const Icon(Icons.receipt_long_rounded)),
          Stack(children: [
            IconButton(tooltip: 'السلة', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartPage())), icon: const Icon(Icons.shopping_bag_outlined)),
            if (cart.count > 0) Positioned(right: 5, top: 4, child: CircleAvatar(radius: 9, backgroundColor: const Color(0xFFFF7A1A), child: Text(cart.count.toString(), style: const TextStyle(fontSize: 10, color: Colors.white)))),
          ]),
          IconButton(tooltip: 'خروج', onPressed: () => SareeBackend.signOut(), icon: const Icon(Icons.logout_rounded)),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: SareeBackend.restaurants(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const LoadingPage();
          if (snapshot.hasError) return Center(child: Text('تعذر تحميل المطاعم: ${snapshot.error}'));
          final restaurants = snapshot.data ?? [];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [Color(0xFF14243A), Color(0xFF284766)]),
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Row(children: [
                    Icon(Icons.location_on_rounded, color: Color(0xFFFF9A32), size: 18),
                    SizedBox(width: 6),
                    Text('التوصيل إلى', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  ]),
                  const SizedBox(height: 5),
                  const Text('رداع، اليمن', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
                  const SizedBox(height: 18),
                  const Text('ماذا تشتهي اليوم؟', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 24)),
                  const SizedBox(height: 6),
                  const Text('وجبتك المفضلة تصلك حتى باب بيتك', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 17),
                  Row(children: [
                    const Icon(Icons.delivery_dining_rounded, color: Color(0xFFFF9A32), size: 24),
                    const SizedBox(width: 8),
                    const Text('اطلب بسهولة • تابع طلبك • استمتع', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                  ]),
                ]),
              ),
              const SizedBox(height: 22),
              const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('المطاعم المتاحة', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF14243A))),
                Icon(Icons.tune_rounded, color: Color(0xFFFF7A1A)),
              ]),
              const SizedBox(height: 10),
              if (restaurants.isEmpty)
                const Card(child: Padding(
                  padding: EdgeInsets.all(22),
                  child: Column(children: [
                    Icon(Icons.restaurant_menu_rounded, size: 46, color: Color(0xFFFF7A1A)),
                    SizedBox(height: 10),
                    Text('لا توجد مطاعم مفعّلة حاليًا', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF14243A))),
                    SizedBox(height: 5),
                    Text('ستظهر المطاعم هنا بعد إضافتها واعتمادها من الإدارة.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF748094))),
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
                        Container(
                          width: 82, height: 82,
                          decoration: BoxDecoration(color: const Color(0xFFFFF0E3), borderRadius: BorderRadius.circular(18)),
                          child: const Icon(Icons.restaurant_rounded, size: 38, color: Color(0xFFFF7A1A)),
                        ),
                        const SizedBox(width: 13),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(r['name']?.toString() ?? 'مطعم', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF14243A))),
                          const SizedBox(height: 5),
                          Text(r['description']?.toString() ?? 'وجبات شهية بانتظارك', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF748094), fontSize: 12)),
                          const SizedBox(height: 8),
                          Row(children: [
                            const Icon(Icons.delivery_dining_rounded, size: 16, color: Color(0xFFFF7A1A)),
                            const SizedBox(width: 4),
                            Text('رسوم التوصيل: ${r['delivery_fee_yer'] ?? '—'} ريال', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF14243A))),
                          ]),
                        ])),
                        const Icon(Icons.chevron_left_rounded, color: Color(0xFF8994A3)),
                      ]),
                    ),
                  ),
                )),
            ],
          );
        },
      ),
    );
  }
}

class RestaurantMenuPage extends StatelessWidget {
  const RestaurantMenuPage({super.key, required this.restaurant});
  final Map<String, dynamic> restaurant;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(restaurant['name'].toString())),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: SareeBackend.menu(restaurant['id'].toString()),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const LoadingPage();
        if (snapshot.hasError) return Center(child: Text('تعذر تحميل القائمة: ${snapshot.error}'));
        final menu = snapshot.data ?? [];
        if (menu.isEmpty) return const Center(child: Text('لم يضف المطعم وجباته بعد'));
        return ListView(padding: const EdgeInsets.all(16), children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: const Color(0xFF14243A), borderRadius: BorderRadius.circular(22)),
            child: Row(children: [
              const Icon(Icons.restaurant_menu_rounded, color: Color(0xFFFF9A32), size: 32),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(restaurant['name'].toString(), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                const Text('اختر وجبتك المفضلة', style: TextStyle(color: Colors.white70)),
              ])),
            ]),
          ),
          const SizedBox(height: 16),
          ...menu.map((item) => Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MealDetailsPage(item: item, restaurantId: restaurant['id'].toString()))),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Container(width: 76, height: 76, decoration: BoxDecoration(color: const Color(0xFFFFF0E3), borderRadius: BorderRadius.circular(17)), child: const Icon(Icons.lunch_dining_rounded, size: 38, color: Color(0xFFFF7A1A))),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(item['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Color(0xFF14243A))),
                    const SizedBox(height: 4),
                    Text(item['description']?.toString() ?? 'وجبة شهية', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF748094), fontSize: 12)),
                    const SizedBox(height: 7),
                    Text('${item['price_yer']} ريال يمني', style: const TextStyle(color: Color(0xFFFF7A1A), fontWeight: FontWeight.w900)),
                  ])),
                  const Icon(Icons.chevron_left_rounded, color: Color(0xFF8994A3)),
                ]),
              ),
            ),
          )),
        ]);
      },
    ),
  );
}

class MealDetailsPage extends StatelessWidget {
  const MealDetailsPage({super.key, required this.item, required this.restaurantId});
  final Map<String, dynamic> item;
  final String restaurantId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('تفاصيل الوجبة')),
    body: ListView(padding: const EdgeInsets.all(18), children: [
      Container(
        height: 210,
        decoration: BoxDecoration(
          gradient: const LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [Color(0xFFFFE7D2), Color(0xFFFFF7EF)]),
          borderRadius: BorderRadius.circular(26),
        ),
        child: const Icon(Icons.lunch_dining_rounded, size: 100, color: Color(0xFFFF7A1A)),
      ),
      const SizedBox(height: 20),
      Text(item['name'].toString(), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF14243A))),
      const SizedBox(height: 8),
      Text(item['description']?.toString() ?? 'وجبة شهية محضرة بعناية.', style: const TextStyle(fontSize: 14, height: 1.7, color: Color(0xFF748094))),
      const SizedBox(height: 18),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE7ECF2))),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('السعر', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF748094))),
          Text('${item['price_yer']} ريال يمني', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Color(0xFFFF7A1A))),
        ]),
      ),
      const SizedBox(height: 24),
      FilledButton.icon(
        onPressed: () {
          context.read<CartController>().add(item, restaurantId);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أضيفت الوجبة إلى السلة')));
        },
        icon: const Icon(Icons.add_shopping_cart_rounded),
        label: const Text('أضف إلى السلة'),
      ),
    ]),
  );
}

class CartPage extends StatelessWidget {
  const CartPage({super.key});
  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartController>();
    return Scaffold(
      appBar: AppBar(title: const Text('سلة الطلب')),
      body: cart.items.isEmpty ? const Center(child: Text('السلة فارغة')) : Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Expanded(child: ListView(children: cart.items.map((item) => ListTile(
            title: Text(item.name),
            subtitle: Text('${item.total} ريال'),
            leading: IconButton(onPressed: () => cart.change(item, -1), icon: const Icon(Icons.remove_circle_outline)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(item.quantity.toString()),
              IconButton(onPressed: () => cart.change(item, 1), icon: const Icon(Icons.add_circle_outline)),
            ]),
          )).toList())),
          Text('المجموع قبل التوصيل: ${cart.subtotal} ريال', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          FilledButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CheckoutPage())), child: const Text('إتمام الطلب')),
        ]),
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
  String? _error;

  @override
  void dispose() { _name.dispose(); _phone.dispose(); _address.dispose(); _notes.dispose(); super.dispose(); }

  Future<void> _send() async {
    if (_name.text.trim().length < 2 || _phone.text.trim().length < 7 || _address.text.trim().length < 5) {
      setState(() => _error = 'أكمل الاسم ورقم الهاتف والعنوان بالتفصيل');
      return;
    }
    final cart = context.read<CartController>();
    if (cart.items.isEmpty || cart.restaurantId == null) return;
    setState(() { _busy = true; _error = null; });
    try {
      final id = await SareeBackend.createOrder(
        restaurantId: cart.restaurantId!,
        customerName: _name.text,
        customerPhone: _phone.text,
        address: _address.text,
        notes: _notes.text,
        items: cart.items.map((line) => {'menu_item_id': line.id, 'quantity': line.quantity}).toList(),
      );
      cart.clear();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => OrderCreatedPage(orderId: id)), (route) => route.isFirst);
    } catch (e) {
      setState(() => _error = e.toString());
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
      TextField(controller: _address, maxLines: 2, decoration: const InputDecoration(labelText: 'عنوان التوصيل بالتفصيل')),
      const SizedBox(height: 12),
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
        if (snapshot.hasError) return Center(child: Text('تعذر تحميل الطلبات: ${snapshot.error}'));
        final orders = snapshot.data ?? [];
        if (orders.isEmpty) return const Center(child: Text('لا توجد طلبات حتى الآن'));
        return ListView(padding: const EdgeInsets.all(16), children: orders.map((order) => Card(
          child: ListTile(
            leading: const Icon(Icons.receipt_long),
            title: Text('طلب #${order['order_number']}'),
            subtitle: Text('${statusLabel(order['status'].toString())}\nالإجمالي: ${order['total_yer']} ريال'),
            isThreeLine: true,
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
            decoration: BoxDecoration(color: const Color(0xFF14243A), borderRadius: BorderRadius.circular(22)),
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
                backgroundColor: active ? const Color(0xFFFFE7D2) : const Color(0xFFE7ECF2),
                child: Icon(done ? Icons.check_rounded : entry.value.$3, color: active ? const Color(0xFFFF7A1A) : const Color(0xFF8994A3)),
              ),
              title: Text(entry.value.$2, style: TextStyle(fontWeight: active ? FontWeight.w900 : FontWeight.w500, color: active ? const Color(0xFF14243A) : const Color(0xFF8994A3))),
            );
          }),
          Card(child: ListTile(leading: const Icon(Icons.location_on_rounded), title: const Text('عنوان التوصيل'), subtitle: Text(current['delivery_address']?.toString() ?? ''))),
          if (status == 'pending')
            OutlinedButton.icon(
              onPressed: () async {
                try {
                  await SareeBackend.transition(current['id'].toString(), 'cancelled', reason: 'طلب العميل');
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إلغاء الطلب')));
                } catch(e) { if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()))); }
              },
              icon: const Icon(Icons.cancel_outlined), label: const Text('إلغاء الطلب'),
            ),
          const Padding(padding: EdgeInsets.only(top: 10), child: Text('تتحدث حالة الطلب تلقائيًا عند تغييرها. عرض موقع المندوب على خريطة مباشرة يحتاج إلى تفعيل GPS وإذن الموقع للمندوب، ولم يُفعّل بعد.', style: TextStyle(color: Color(0xFF748094), height: 1.5))),
        ]);
      },
    ),
  );
}

class RestaurantPortal extends StatefulWidget {
  const RestaurantPortal({super.key});
  @override State<RestaurantPortal> createState() => _RestaurantPortalState();
}

class _RestaurantPortalState extends State<RestaurantPortal> {
  int _tab = 0;
  bool _busy = false;
  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try { await action(); if(mounted) setState(() {}); }
    catch(e) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()))); }
    finally { if(mounted) setState(() => _busy = false); }
  }

  Future<void> _editMeal(String restaurantId, [Map<String,dynamic>? item]) async {
    final name = TextEditingController(text: item?['name']?.toString() ?? '');
    final description = TextEditingController(text: item?['description']?.toString() ?? '');
    final price = TextEditingController(text: item?['price_yer']?.toString() ?? '');
    final image = TextEditingController(text: item?['image_url']?.toString() ?? '');
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
        SwitchListTile(value: available, onChanged: (v) => setLocal(() => available = v), title: const Text('متاحة للطلب')),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(onPressed: () { if(form.currentState!.validate()) Navigator.pop(ctx, true); }, child: const Text('حفظ'))],
    )));
    if(ok == true) await _run(() => SareeBackend.saveMenuItem(id: item?['id']?.toString(), restaurantId: restaurantId, name: name.text, description: description.text, price: int.parse(price.text), imageUrl: image.text, available: available));
    name.dispose(); description.dispose(); price.dispose(); image.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('إدارة المطعم'), actions: [IconButton(onPressed: () => SareeBackend.signOut(), icon: const Icon(Icons.logout))]),
    body: FutureBuilder<List<Map<String,dynamic>>>(
      future: SareeBackend.myRestaurants(),
      builder: (context, rs) {
        if(rs.connectionState != ConnectionState.done) return const LoadingPage();
        if(rs.hasError) return Center(child: Text('تعذر تحميل المطعم: ${rs.error}'));
        final restaurants = rs.data ?? [];
        if(restaurants.isEmpty) return const Center(child: Text('لم يتم ربط حسابك بمطعم. اطلب من الإدارة ربط الحساب.'));
        final restaurant = restaurants.first;
        final rid = restaurant['id'].toString();
        return Column(children: [
          Padding(padding: const EdgeInsets.all(12), child: Row(children: [
            const Icon(Icons.storefront_rounded, color: Color(0xFFFF7A1A)),
            const SizedBox(width: 8),
            Expanded(child: Text(restaurant['name'].toString(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
          ])),
          Expanded(child: IndexedStack(index: _tab, children: [
            FutureBuilder<List<Map<String,dynamic>>>(
              future: SareeBackend.manageMenu(rid),
              builder: (context, snap) {
                if(snap.connectionState != ConnectionState.done) return const LoadingPage();
                if(snap.hasError) return Center(child: Text('تعذر تحميل الوجبات: ${snap.error}'));
                final items = snap.data ?? [];
                return ListView(padding: const EdgeInsets.all(12), children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('قائمة الوجبات', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                    FilledButton.icon(onPressed: () => _editMeal(rid), icon: const Icon(Icons.add), label: const Text('وجبة جديدة')),
                  ]),
                  if(items.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('لم تضف وجبات بعد. أضف أول وجبة ليراها العملاء.')),
                  ...items.map((item) => Card(child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.fastfood_rounded)),
                    title: Text(item['name'].toString()),
                    subtitle: Text('${item['price_yer']} ريال • ${item['is_available'] == true ? 'متاحة' : 'متوقفة'}'),
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
            FutureBuilder<List<Map<String,dynamic>>>(
              future: SareeBackend.restaurantOrders(),
              builder: (context, snap) {
                if(snap.connectionState != ConnectionState.done) return const LoadingPage();
                if(snap.hasError) return Center(child: Text('تعذر تحميل الطلبات: ${snap.error}'));
                final orders = snap.data ?? [];
                if(orders.isEmpty) return const Center(child: Text('لا توجد طلبات حتى الآن'));
                return ListView(padding: const EdgeInsets.all(12), children: orders.map((o) {
                  final status = o['status'].toString();
                  final next = status == 'pending' ? 'accepted' : status == 'accepted' ? 'preparing' : status == 'preparing' ? 'ready_for_pickup' : null;
                  final label = next == 'accepted' ? 'قبول الطلب' : next == 'preparing' ? 'بدء التحضير' : 'جاهز للاستلام';
                  return Card(child: ListTile(
                    title: Text('طلب #${o['order_number']} • ${o['customer_name']}'),
                    subtitle: Text('${o['delivery_address']}\n${o['total_yer']} ريال • $status'),
                    isThreeLine: true,
                    trailing: next == null ? null : FilledButton(onPressed: _busy ? null : () => _run(() => SareeBackend.transition(o['id'].toString(), next)), child: Text(label)),
                  ));
                }).toList());
              },
            ),
          ])),
        ]);
      },
    ),
    bottomNavigationBar: NavigationBar(selectedIndex: _tab, onDestinationSelected: (v) => setState(() => _tab = v), destinations: const [
      NavigationDestination(icon: Icon(Icons.restaurant_menu_outlined), label: 'الوجبات'),
      NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'الطلبات'),
    ]),
  );
}

class CourierPortal extends StatefulWidget {
  const CourierPortal({super.key});
  @override State<CourierPortal> createState() => _CourierPortalState();
}

class _CourierPortalState extends State<CourierPortal> {
  bool _busy = false;
  bool _sharing = false;
  StreamSubscription<Position>? _positionSub;

  Future<void> _startSharing() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if(!enabled) throw Exception('فعّل خدمة الموقع GPS أولاً');
    var permission = await Geolocator.checkPermission();
    if(permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if(permission == LocationPermission.denied || permission == LocationPermission.deniedForever) throw Exception('اسمح للتطبيق بالوصول إلى الموقع من إعدادات الهاتف');
    await _positionSub?.cancel();
    const settings = LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 15);
    _positionSub = Geolocator.getPositionStream(locationSettings: settings).listen((p) async {
      try { await SareeBackend.updateCourierLocation(p.latitude, p.longitude); }
      catch(e) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تحديث الموقع: $e'))); }
    });
    final now = await Geolocator.getCurrentPosition();
    await SareeBackend.updateCourierLocation(now.latitude, now.longitude);
    if(mounted) setState(() => _sharing = true);
  }

  Future<void> _stopSharing() async {
    await _positionSub?.cancel();
    _positionSub = null;
    if(mounted) setState(() => _sharing = false);
  }

  @override
  void dispose() { _positionSub?.cancel(); super.dispose(); }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try { await action(); if(mounted) setState(() {}); }
    catch(e) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()))); }
    finally { if(mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('طلبات المندوب'), actions: [IconButton(onPressed: () => SareeBackend.signOut(), icon: const Icon(Icons.logout))]),
    body: FutureBuilder<List<List<Map<String,dynamic>>>>(
      future: Future.wait([SareeBackend.availableCourierOrders(), SareeBackend.courierOrders()]),
      builder: (context, snap) {
        if(snap.connectionState != ConnectionState.done) return const LoadingPage();
        if(snap.hasError) return Center(child: Text('تعذر تحميل الطلبات: ${snap.error}'));
        final available = snap.data![0];
        final active = snap.data![1].where((o) => o['status'] == 'assigned' || o['status'] == 'picked_up').toList();
        return ListView(padding: const EdgeInsets.all(12), children: [
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
            final status = o['status'].toString();
            final next = status == 'assigned' ? 'picked_up' : 'delivered';
            final label = status == 'assigned' ? 'تأكيد استلام الطلب' : 'تأكيد التسليم';
            return Card(child: ListTile(
              title: Text('طلب #${o['order_number']}'),
              subtitle: Text('${o['customer_name']} • ${o['customer_phone']}\n${o['delivery_address']}\nالحالة: $status'),
              isThreeLine: true,
              trailing: FilledButton(onPressed: _busy ? null : () => _run(() => SareeBackend.transition(o['id'].toString(), next)), child: Text(label)),
            ));
          }),
          const Padding(padding: EdgeInsets.all(8), child: Text('طلبات جاهزة للاستلام', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold))),
          if(available.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('لا توجد طلبات جاهزة حاليًا')),
          ...available.map((o) => Card(child: ListTile(
            title: Text('طلب #${o['order_number']}'),
            subtitle: Text('${o['delivery_address']}\n${o['total_yer']} ريال'),
            isThreeLine: true,
            trailing: FilledButton(onPressed: _busy ? null : () => _run(() => SareeBackend.claimOrder(o['id'].toString())), child: const Text('استلام')),
          ))),
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
      } catch(e) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()))); }
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
        initialValue: selected,
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

  Future<void> _changeRole(Map<String, dynamic> profile) async {
    const roles = {'customer':'عميل','restaurant_owner':'صاحب مطعم','courier':'مندوب','admin':'مدير'};
    String role = profile['role'].toString();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) => AlertDialog(
      title: Text('صلاحيات ${profile['full_name']}'),
      content: DropdownButtonFormField<String>(
        initialValue: role,
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
      actions: [IconButton(tooltip: 'تحديث', onPressed: _refresh, icon: const Icon(Icons.refresh_rounded)), IconButton(tooltip: 'خروج', onPressed: () => SareeBackend.signOut(), icon: const Icon(Icons.logout_rounded))],
    ),
    body: IndexedStack(index: _tab, children: [
      FutureBuilder<List<Map<String, dynamic>>>(
        future: SareeBackend.adminRestaurants(),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const LoadingPage();
          if (snap.hasError) return Center(child: Text('تعذر تحميل المطاعم: ${snap.error}'));
          final rows = snap.data ?? [];
          return ListView(padding: const EdgeInsets.all(14), children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('إدارة المطاعم', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF14243A))),
              FilledButton.icon(onPressed: _createRestaurant, icon: const Icon(Icons.add), label: const Text('إضافة')),
            ]),
            const SizedBox(height: 8),
            if (rows.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(22), child: Text('لم تتم إضافة مطاعم بعد. أضف مطعمًا للبدء.'))),
            ...rows.map((r) => Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const CircleAvatar(backgroundColor: Color(0xFFFFE7D2), child: Icon(Icons.restaurant_rounded)),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF14243A))),
                  Text(r['address']?.toString() ?? '', style: const TextStyle(color: Color(0xFF748094), fontSize: 12)),
                ])),
                Switch(value: r['is_active'] == true, onChanged: (v) async {
                  try { await SareeBackend.setRestaurantActive(r['id'].toString(), v); await _refresh(); }
                  catch(e) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()))); }
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
          if (snap.hasError) return Center(child: Text('تعذر تحميل الحسابات: ${snap.error}'));
          final profiles = snap.data ?? [];
          const labels = {'customer':'عميل','restaurant_owner':'صاحب مطعم','courier':'مندوب','admin':'مدير'};
          return ListView(padding: const EdgeInsets.all(14), children: [
            const Text('الحسابات والصلاحيات', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF14243A))),
            const SizedBox(height: 8),
            ...profiles.map((p) => Card(child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
              title: Text(p['full_name']?.toString().isNotEmpty == true ? p['full_name'].toString() : 'مستخدم'),
              subtitle: Text('${p['phone'] ?? 'لا يوجد هاتف'} • ${labels[p['role']] ?? p['role']}'),
              trailing: IconButton(tooltip: 'تعديل الصلاحية', onPressed: () => _changeRole(p), icon: const Icon(Icons.manage_accounts_rounded)),
            ))),
          ]);
        },
      ),
    ]),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _tab,
      onDestinationSelected: (v) => setState(() => _tab = v),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: 'المطاعم'),
        NavigationDestination(icon: Icon(Icons.people_alt_outlined), selectedIcon: Icon(Icons.people_alt), label: 'الحسابات'),
      ],
    ),
  );
}
