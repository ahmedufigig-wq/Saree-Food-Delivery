import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

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
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE50914), brightness: Brightness.dark, secondary: const Color(0xFFFFC400), surface: const Color(0xFF242020)),
      scaffoldBackgroundColor: Colors.transparent,
      iconTheme: const IconThemeData(color: Color(0xFFFFC400), size: 23),
      appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0, scrolledUnderElevation: 0, backgroundColor: Color(0xFF20191A), foregroundColor: Colors.white, titleTextStyle: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
      cardTheme: CardThemeData(color: const Color(0xFF292223), elevation: 2, shadowColor: Color(0x66000000), margin: const EdgeInsets.symmetric(vertical: 7, horizontal: 2), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFF493438)))),
      inputDecorationTheme: InputDecorationTheme(
        labelStyle: const TextStyle(color: Color(0xFFE8DADD)),
        hintStyle: const TextStyle(color: Color(0xFFB9A9AC)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Color(0xFF594147))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Color(0xFF594147))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Color(0xFFFFC400), width: 1.6)),
        filled: true, fillColor: const Color(0xFF302629), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      ),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE50914), foregroundColor: Colors.white, minimumSize: const Size.fromHeight(52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
      navigationBarTheme: const NavigationBarThemeData(backgroundColor: Color(0xFF20191A), indicatorColor: Color(0xFF650008), labelTextStyle: WidgetStatePropertyAll(TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12))),
      dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF292223), surfaceTintColor: Colors.transparent),
      snackBarTheme: const SnackBarThemeData(backgroundColor: Color(0xFF352629), contentTextStyle: TextStyle(color: Colors.white)),
    ),
    builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: SareeFoodBackdrop(child: child ?? const SizedBox.shrink())),
    home: const BrandSplashGate(),
  );
}

class SareeFoodBackdrop extends StatelessWidget {
  const SareeFoodBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
    const DecoratedBox(decoration: BoxDecoration(
      gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [Color(0xFF171717), Color(0xFF241719), Color(0xFF171717)]),
    )),
    const Positioned(top: 115, right: 12, child: Opacity(opacity: .055, child: Icon(Icons.lunch_dining_rounded, size: 112, color: Color(0xFFFFC400)))),
    const Positioned(top: 330, left: -18, child: Opacity(opacity: .045, child: Icon(Icons.local_pizza_rounded, size: 145, color: Color(0xFFE50914)))),
    const Positioned(bottom: 125, right: -15, child: Opacity(opacity: .05, child: Icon(Icons.ramen_dining_rounded, size: 132, color: Color(0xFFFFC400)))),
    const Positioned(bottom: 18, left: 75, child: Opacity(opacity: .04, child: Icon(Icons.local_cafe_rounded, size: 92, color: Color(0xFFE50914)))),
    Positioned.fill(child: child),
  ]);
}

class FoodPhotoBanner extends StatelessWidget {
  const FoodPhotoBanner({
    super.key,
    required this.title,
    required this.subtitle,
    this.height = 190,
  });

  final String title;
  final String subtitle;
  final double height;

  // صورة طعام فوتوغرافية حقيقية للواجهة العامة، وليست رسماً توضيحياً.
  static const String photoUrl =
      'https://rs-menus-api.roocdn.com/images/6c489085-92dc-488d-ad81-c77bec5c5189/image.jpeg?fit=crop&height=630&width=1200';

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(24),
    child: SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(fit: StackFit.expand, children: [
        Image.network(
          photoUrl,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stack) => const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [Color(0xFF171717), Color(0xFF8B0008)],
              ),
            ),
            child: Center(
              child: Icon(Icons.restaurant_menu_rounded, size: 58, color: Color(0xFFFFC400)),
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.center,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Color(0xE6000000)],
              stops: [0.12, 1],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(title, style: const TextStyle(
                color: Colors.white, fontSize: 23, fontWeight: FontWeight.w900,
                shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
              )),
              const SizedBox(height: 5),
              Text(subtitle, style: const TextStyle(
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
    width: size, height: size,
    decoration: BoxDecoration(
      gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFC400), Color(0xFFE50914), Color(0xFF171717)]),
      borderRadius: BorderRadius.circular(size * .30),
      border: Border.all(color: Colors.white, width: 2),
      boxShadow: const [BoxShadow(color: Color(0x30B91F2B), blurRadius: 20, offset: Offset(0, 8))],
    ),
    child: Stack(alignment: Alignment.center, children: [
      Positioned(left: size * .07, top: size * .27, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: size * .28, height: size * .035, decoration: BoxDecoration(color: const Color(0xFFFFC400), borderRadius: BorderRadius.circular(8))),
        SizedBox(height: size * .055),
        Container(width: size * .20, height: size * .035, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8))),
      ])),
      Icon(Icons.location_on_rounded, color: Colors.white, size: size * .76),
      Positioned(top: size * .30, child: Icon(Icons.restaurant_rounded, color: const Color(0xFFE50914), size: size * .29)),
      Positioned(top: size * .10, right: size * .13, child: Icon(Icons.bolt_rounded, color: const Color(0xFFFFC400), size: size * .23)),
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
                colors: [Color(0xFFE50914), Color(0xFFA9000A), Color(0xFF171717)],
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
                      color: const Color(0xFF171717),
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
            final role = profile.data?['role']?.toString() ?? 'customer';
            final approval = profile.data?['approval_status']?.toString() ?? 'approved';
            if (approval != 'approved' && role != 'admin') return PendingApprovalPage(status: approval, note: profile.data?['approval_note']?.toString());
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
          Icon(rejected ? Icons.cancel_outlined : Icons.hourglass_top_rounded, size: 68, color: rejected ? Colors.red : const Color(0xFFFFA000)),
          const SizedBox(height: 16),
          Text(rejected ? 'لم تتم الموافقة على الحساب' : 'حسابك قيد المراجعة', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Text(note?.isNotEmpty == true ? note! : rejected ? 'يرجى التواصل مع إدارة سريع لمعرفة التفاصيل.' : 'سيتم تفعيل حسابك بعد مراجعة الإدارة واعتماد بياناتك.', textAlign: TextAlign.center),
          const SizedBox(height: 20),
          FilledButton(onPressed: () => SareeBackend.signOut(), child: const Text('تسجيل الخروج')),
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
        return Container(padding:const EdgeInsets.all(22),decoration:BoxDecoration(gradient:const LinearGradient(colors:[Color(0xFFE50914),Color(0xFFFF8A00)]),borderRadius:BorderRadius.circular(22)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
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
        Icon(Icons.cloud_off, size: 64, color: const Color(0xFFE50914)),
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
  String _requestedRole = 'customer';
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
          requestedRole: _requestedRole,
        );
        if (mounted) setState(() => _message = _requestedRole == 'customer' ? 'تم إنشاء الحساب. إذا طُلب تأكيد البريد، افتح رسالة التأكيد ثم سجّل الدخول.' : 'تم إرسال طلب التسجيل. سيظل الحساب معلقًا حتى اعتماد الإدارة.');
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
            DropdownButtonFormField<String>(
              initialValue: _requestedRole,
              decoration: const InputDecoration(labelText: 'نوع الحساب'),
              items: const [
                DropdownMenuItem(value: 'customer', child: Text('عميل')),
                DropdownMenuItem(value: 'courier', child: Text('مندوب توصيل — يتطلب اعتماد الإدارة')),
                DropdownMenuItem(value: 'restaurant_owner', child: Text('صاحب مطعم — يتطلب اعتماد الإدارة')),
              ],
              onChanged: (value) => setState(() => _requestedRole = value ?? 'customer'),
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'الاسم الكامل'), validator: (v) => (v == null || v.trim().length < 2) ? 'أدخل اسمك' : null),
            const SizedBox(height: 12),
            TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف'), validator: (v) => (v == null || v.trim().length < 7) ? 'أدخل رقم هاتف صحيحاً' : null),
            const SizedBox(height: 12),
          ],
          TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'البريد الإلكتروني أو رقم الهاتف للمندوب'), validator: (v) { final value = (v ?? '').trim(); return value.isEmpty || (!value.contains('@') && value.replaceAll(RegExp(r'[^0-9]'), '').length < 7) ? 'أدخل بريدًا صحيحًا أو رقم هاتف المندوب' : null; }),
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
          Text('سريع', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF171717))),
        ]),
        actions: [
          IconButton(tooltip: 'البحث', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerSearchPage())), icon: const Icon(Icons.search_rounded)),
          Stack(children: [
            IconButton(tooltip: 'السلة', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartPage())), icon: const Icon(Icons.shopping_bag_outlined)),
            if (cart.count > 0) Positioned(right: 5, top: 4, child: CircleAvatar(radius: 9, backgroundColor: const Color(0xFFE50914), child: Text(cart.count.toString(), style: const TextStyle(fontSize: 10, color: Colors.white)))),
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
                _ => null,
              };
              if (page != null) Navigator.push(context, MaterialPageRoute(builder: (_) => page));
              if (value == 'logout') SareeBackend.signOut();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'notifications', child: ListTile(dense: true, leading: Icon(Icons.notifications_none), title: Text('الإشعارات'))),
              PopupMenuItem(value: 'favorites', child: ListTile(dense: true, leading: Icon(Icons.favorite_border), title: Text('المفضلة'))),
              PopupMenuItem(value: 'orders', child: ListTile(dense: true, leading: Icon(Icons.receipt_long), title: Text('طلباتي'))),
              PopupMenuItem(value: 'account', child: ListTile(dense: true, leading: Icon(Icons.person_outline), title: Text('حسابي والعناوين'))),
              PopupMenuItem(value: 'wallet', child: ListTile(dense: true, leading: Icon(Icons.account_balance_wallet_outlined), title: Text('محفظتي'))),
              PopupMenuItem(value: 'support', child: ListTile(dense: true, leading: Icon(Icons.support_agent), title: Text('الدعم والمساعدة'))),
              PopupMenuItem(value: 'logout', child: ListTile(dense: true, leading: Icon(Icons.logout), title: Text('تسجيل الخروج'))),
            ],
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: SareeBackend.restaurants(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const LoadingPage();
          if (snapshot.hasError) return Center(child: Text('تعذر تحميل المطاعم: ${SareeBackend.arabicError(snapshot.error)}'));
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
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE7ECF2))),
                  child: const Row(children: [
                    Icon(Icons.search_rounded, color: Color(0xFFE50914)),
                    SizedBox(width: 10),
                    Expanded(child: Text('ابحث عن مطعمك أو وجبتك المفضلة', style: TextStyle(color: Color(0xFF8994A3)))),
                    Icon(Icons.tune_rounded, color: Color(0xFF8994A3), size: 20),
                  ]),
                ),
              ),
              const SizedBox(height: 18),
              FutureBuilder<List<Map<String,dynamic>>>(
                future: SareeBackend.activePromotions(),
                builder: (context, promoSnap) {
                  final promos = promoSnap.data ?? [];
                  if (promos.isEmpty) return const SizedBox.shrink();
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('عروض سريع', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 9),
                    SizedBox(height: 116, child: ListView(scrollDirection: Axis.horizontal, children: promos.map((promo) => Container(
                      width: 270, margin: const EdgeInsetsDirectional.only(end: 10), padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), gradient: const LinearGradient(colors: [Color(0xFFE50914), Color(0xFF8B0008)])),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(promo['title'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17)),
                        const SizedBox(height: 5),
                        Expanded(child: Text(promo['description']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70))),
                        if ((promo['code']?.toString() ?? '').isNotEmpty) Text('كود العرض: ${promo['code']}', style: const TextStyle(color: Color(0xFFFFC400), fontWeight: FontWeight.w900)),
                      ]),
                    )).toList())),
                    const SizedBox(height: 18),
                  ]);
                },
              ),
              const Text('تصفح حسب القسم', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF171717))),
              const SizedBox(height: 8),
              FutureBuilder<List<Map<String,dynamic>>>(
                future: SareeBackend.categories(),
                builder: (context, categorySnap) {
                  if (!categorySnap.hasData || categorySnap.data!.isEmpty) return const SizedBox.shrink();
                  final seen = <String>{};
                  final unique = categorySnap.data!.where((cat) => seen.add(cat['name'].toString())).toList();
                  return SizedBox(height: 44, child: ListView(scrollDirection: Axis.horizontal, children: unique.map((cat) => Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ActionChip(
                      avatar: const Icon(Icons.restaurant_menu_rounded, size: 17),
                      label: Text(cat['name'].toString()),
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerSearchPage(initialQuery: cat['name'].toString()))),
                    ),
                  )).toList()));
                },
              ),
              const SizedBox(height: 20),
              const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('المطاعم المتاحة', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF171717))),
                Icon(Icons.tune_rounded, color: Color(0xFFE50914)),
              ]),
              const SizedBox(height: 10),
              if (restaurants.isEmpty)
                const Card(child: Padding(
                  padding: EdgeInsets.all(22),
                  child: Column(children: [
                    Icon(Icons.restaurant_menu_rounded, size: 46, color: Color(0xFFE50914)),
                    SizedBox(height: 10),
                    Text('لا توجد مطاعم مفعّلة حاليًا', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF171717))),
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
                          child: const Icon(Icons.restaurant_rounded, size: 38, color: Color(0xFFE50914)),
                        ),
                        const SizedBox(width: 13),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(r['name']?.toString() ?? 'مطعم', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF171717))),
                          const SizedBox(height: 5),
                          Text(r['description']?.toString() ?? 'وجبات شهية بانتظارك', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF748094), fontSize: 12)),
                          const SizedBox(height: 8),
                          Row(children: [
                            const Icon(Icons.delivery_dining_rounded, size: 16, color: Color(0xFFE50914)),
                            const SizedBox(width: 4),
                            Text('رسوم التوصيل: ${r['delivery_fee_yer'] ?? '—'} ريال', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF171717))),
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
                      CircleAvatar(radius: 25, backgroundColor: Color(0xFFFFE6E6), child: Icon(Icons.person_rounded, color: Color(0xFFE50914), size: 28)),
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
                    Text('البريد الإلكتروني: ${SareeBackend.user?.email ?? '—'}', style: const TextStyle(color: Color(0xFF748094))),
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
                Icon(Icons.location_off_outlined, size: 38, color: Color(0xFFE50914)),
                SizedBox(height: 8),
                Text('لم تحفظ عنوان توصيل بعد', style: TextStyle(fontWeight: FontWeight.w800)),
                Text('أضف عنوان المنزل أو العمل لتسهيل طلباتك القادمة.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF748094))),
              ]),
            ));
            return Column(children: rows.map((row) => Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFFFE6E6),
                  child: Icon(row['label'] == 'العمل' ? Icons.work_outline : Icons.home_outlined, color: const Color(0xFFE50914)),
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
            await SareeBackend.signOut();
            if (context.mounted) Navigator.of(context).popUntil((route) => route.isFirst);
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
      title: Text(restaurant['name'].toString()),
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
            icon: Icon(snap.data == true ? Icons.favorite : Icons.favorite_border, color: const Color(0xFFE50914)),
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
        return ListView(padding: const EdgeInsets.all(16), children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: const Color(0xFF171717), borderRadius: BorderRadius.circular(22)),
            child: Row(children: [
              const Icon(Icons.restaurant_menu_rounded, color: Color(0xFFFFC400), size: 32),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(restaurant['name'].toString(), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                const Text('تصفح أقسام المنيو واختر وجبتك', style: TextStyle(color: Colors.white70)),
              ])),
            ]),
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<Map<String,dynamic>>>(
            future: SareeBackend.restaurantReviews(restaurant['id'].toString()),
            builder: (context, reviewSnap) {
              final reviews = reviewSnap.data ?? [];
              if (reviews.isEmpty) return const SizedBox.shrink();
              final average = reviews.map((r) => (r['rating'] as num).toDouble()).reduce((a,b) => a+b) / reviews.length;
              return Card(child: ListTile(
                leading: const Icon(Icons.star_rounded, color: Color(0xFFFFC400), size: 30),
                title: Text(average.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.w900)),
                subtitle: Text('${reviews.length} تقييم من العملاء'),
                trailing: TextButton(onPressed: () => showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
                  const Text('تقييمات العملاء', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                  ...reviews.map((r) => ListTile(
                    leading: const Icon(Icons.star_rounded, color: Color(0xFFFFC400)),
                    title: Text('${r['rating']}/5 • ${(r['profiles'] is Map ? r['profiles']['full_name'] : null) ?? 'عميل'}'),
                    subtitle: Text(r['comment']?.toString() ?? ''),
                  )),
                ]))), child: const Text('عرض التقييمات')),
              ));
            },
          ),
          const SizedBox(height: 16),
          ...orderedCategories.expand((category) => [
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
              child: Text(category, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Color(0xFF171717))),
            ),
            ...grouped[category]!.map((item) {
              final available = item['is_available'] == true && (item['price_yer'] as num? ?? 0) > 0;
              final imageUrl = item['image_url']?.toString() ?? '';
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
                          child: imageUrl.startsWith('http')
                              ? Image.network(imageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFFFFF0E3), child: Icon(Icons.restaurant_rounded, size: 36, color: Color(0xFFE50914))))
                              : const ColoredBox(color: Color(0xFFFFF0E3), child: Icon(Icons.restaurant_rounded, size: 36, color: Color(0xFFE50914))),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(item['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Color(0xFF171717))),
                        const SizedBox(height: 4),
                        Text(item['description']?.toString() ?? 'وجبة شهية', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF748094), fontSize: 12)),
                        const SizedBox(height: 7),
                        Text(available ? '${item['price_yer']} ريال يمني' : 'السعر والتوفر يحددهما المطعم', style: TextStyle(color: available ? const Color(0xFFE50914) : const Color(0xFF8A6670), fontWeight: FontWeight.w900, fontSize: 12)),
                      ])),
                      Icon(available ? Icons.chevron_left_rounded : Icons.info_outline_rounded, color: const Color(0xFF8994A3)),
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

class MealDetailsPage extends StatelessWidget {
  const MealDetailsPage({super.key, required this.item, required this.restaurantId});
  final Map<String, dynamic> item;
  final String restaurantId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('تفاصيل الوجبة')),
    body: Builder(builder: (context) {
      final available = item['is_available'] == true && (item['price_yer'] as num? ?? 0) > 0;
      final imageUrl = item['image_url']?.toString() ?? '';
      return ListView(padding: const EdgeInsets.all(18), children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: SizedBox(
            height: 230,
            child: imageUrl.startsWith('http')
                ? Image.network(imageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFFFFF0E3), child: Icon(Icons.restaurant_rounded, size: 90, color: Color(0xFFE50914))))
                : const ColoredBox(color: Color(0xFFFFF0E3), child: Icon(Icons.restaurant_rounded, size: 90, color: Color(0xFFE50914))),
          ),
        ),
        const SizedBox(height: 20),
        Text(item['name'].toString(), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF171717))),
        const SizedBox(height: 8),
        Text(item['description']?.toString() ?? 'وجبة شهية محضرة بعناية.', style: const TextStyle(fontSize: 14, height: 1.7, color: Color(0xFF748094))),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE7ECF2))),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('السعر', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF748094))),
            Text(available ? '${item['price_yer']} ريال يمني' : 'يُحدد من المطعم', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Color(0xFFE50914))),
          ]),
        ),
        const SizedBox(height: 24),
        if (available)
          FilledButton.icon(
            onPressed: () {
              context.read<CartController>().add(item, restaurantId);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أضيفت الوجبة إلى السلة')));
            },
            icon: const Icon(Icons.add_shopping_cart_rounded),
            label: const Text('أضف إلى السلة'),
          )
        else
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('هذا الصنف معروض في المنيو، وسيصبح متاحاً للطلب بعد تأكيد السعر والتوفر من المطعم.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF8A6670), fontWeight: FontWeight.w700)),
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
      cart.clear();
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
          initialValue: _selectedAddressId,
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
            trailing: order['status'] == 'delivered' ? IconButton(tooltip: 'قيّم المطعم', onPressed: () => _showSareeReviewDialog(context, order), icon: const Icon(Icons.star_rate_rounded, color: Color(0xFFFFB300))) : null,
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
            decoration: BoxDecoration(color: const Color(0xFF171717), borderRadius: BorderRadius.circular(22)),
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
                backgroundColor: active ? const Color(0xFFFFE6E6) : const Color(0xFFE7ECF2),
                child: Icon(done ? Icons.check_rounded : entry.value.$3, color: active ? const Color(0xFFE50914) : const Color(0xFF8994A3)),
              ),
              title: Text(entry.value.$2, style: TextStyle(fontWeight: active ? FontWeight.w900 : FontWeight.w500, color: active ? const Color(0xFF171717) : const Color(0xFF8994A3))),
            );
          }),
          Card(child: ListTile(leading: const Icon(Icons.location_on_rounded), title: const Text('عنوان التوصيل'), subtitle: Text(current['delivery_address']?.toString() ?? ''))),
          if (current['courier_id'] != null && (status == 'assigned' || status == 'picked_up'))
            CourierLiveMap(courierId: current['courier_id'].toString()),
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
          const Padding(padding: EdgeInsets.only(top: 10), child: Text('تتحدث حالة الطلب تلقائيًا. عند مشاركة المندوب لموقعه مع السماح بإذن GPS أثناء استخدام التطبيق، ستظهر حركته هنا على الخريطة.', style: TextStyle(color: Color(0xFF748094), height: 1.5))),
        ]);
      },
    ),
  );
}


class CourierLiveMap extends StatelessWidget {
  const CourierLiveMap({super.key, required this.courierId});
  final String courierId;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Map<String,dynamic>>>(
    stream: SareeBackend.courierLocation(courierId),
    builder: (context, snap) {
      if(snap.hasError) return const Card(child: ListTile(title: Text('تعذر تحميل موقع المندوب')));
      if(snap.data == null || snap.data!.isEmpty) return const Card(child: ListTile(leading: Icon(Icons.location_searching), title: Text('بانتظار مشاركة المندوب لموقعه')));
      final row = snap.data!.first;
      final point = LatLng((row['latitude'] as num).toDouble(), (row['longitude'] as num).toDouble());
      return Card(clipBehavior: Clip.antiAlias, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const ListTile(leading: Icon(Icons.map_rounded), title: Text('موقع المندوب المباشر'), subtitle: Text('تتحدث الخريطة عند وصول تحديث جديد')),
        SizedBox(height: 230, child: FlutterMap(
          options: MapOptions(initialCenter: point, initialZoom: 15),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.saree.delivery.saree'),
            MarkerLayer(markers: [Marker(point: point, width: 52, height: 52, child: const Icon(Icons.delivery_dining_rounded, color: Color(0xFFE50914), size: 44))]),
          ],
        )),
        Padding(padding: const EdgeInsets.all(10), child: Text('آخر تحديث: ${row['updated_at'] ?? ''}', style: const TextStyle(fontSize: 11, color: Color(0xFF748094)))),
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
            initialValue: selected,
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

  Future<void> _addCourier(String restaurantId) async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final password = TextEditingController();
    final form = GlobalKey<FormState>();
    final accepted = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('إنشاء حساب مندوب جديد'),
      content: SizedBox(width: 420, child: Form(key: form, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: name, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'اسم المندوب', prefixIcon: Icon(Icons.person_outline_rounded)), validator: (v) => (v ?? '').trim().length < 2 ? 'أدخل اسم المندوب' : null),
        const SizedBox(height: 12),
        TextFormField(controller: phone, keyboardType: TextInputType.phone, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'رقم الهاتف', prefixIcon: Icon(Icons.phone_android_rounded)), validator: (v) => (v ?? '').replaceAll(RegExp(r'[^0-9]'), '').length < 7 ? 'أدخل رقم هاتف صحيحًا' : null),
        const SizedBox(height: 12),
        TextFormField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة مرور المندوب (8 أحرف على الأقل)', prefixIcon: Icon(Icons.lock_outline_rounded)), validator: (v) => (v ?? '').length < 8 ? 'كلمة المرور يجب ألا تقل عن 8 أحرف' : null),
        const SizedBox(height: 8),
        const Text('سيُنشأ الحساب ويرتبط بهذا المطعم، ويظل بانتظار موافقة الإدارة قبل استقبال الطلبات.', style: TextStyle(color: Color(0xFFFFC400), height: 1.5)),
      ])))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(onPressed: () { if (form.currentState!.validate()) Navigator.pop(ctx, true); }, child: const Text('إنشاء الحساب'))],
    ));
    if (accepted == true) {
      await _run(() async {
        await SareeBackend.createRestaurantCourierAccount(restaurantId: restaurantId, fullName: name.text, phone: phone.text, password: password.text);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إنشاء الحساب وربطه بالمطعم. بانتظار موافقة الإدارة.')));
      });
    }
    name.dispose(); phone.dispose(); password.dispose();
  }

  Future<void> _removeCourier(String restaurantId, Map<String, dynamic> courier) async {
    final accepted = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('إزالة المندوب من الفريق؟'),
      content: Text('سيتم إيقاف ربط ' + (courier['full_name'] ?? 'المندوب').toString() + ' بهذا المطعم. لن تتأثر حساباته أو طلباته السابقة.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إزالة'))],
    ));
    if (accepted == true) await _run(() => SareeBackend.removeRestaurantCourier(restaurantId, courier['courier_id'].toString()));
  }

  Widget _courierTeamTab(String restaurantId) {
    return FutureBuilder<List<Map<String, dynamic>>>(future: SareeBackend.restaurantCourierTeam(restaurantId), builder: (context, snap) {
      if (snap.connectionState != ConnectionState.done) return const LoadingPage();
      if (snap.hasError) return Center(child: Text('تعذر تحميل فريق المندوبين: ' + SareeBackend.arabicError(snap.error)));
      final couriers = snap.data ?? [];
      return ListView(padding: const EdgeInsets.all(14), children: [
        Row(children: [const Expanded(child: Text('مندوبو المطعم', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900))), FilledButton.icon(onPressed: _busy ? null : () => _addCourier(restaurantId), icon: const Icon(Icons.person_add_alt_1_rounded), label: const Text('إضافة مندوب'))]),
        const SizedBox(height: 8),
        const Text('أنشئ حساب المندوب مباشرة بالاسم ورقم الهاتف وكلمة المرور. سيُربط بهذا المطعم، ولن يستقبل الطلبات حتى توافق الإدارة.', style: TextStyle(color: Color(0xFFFFC400), height: 1.5)),
        const SizedBox(height: 12),
        if (couriers.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(20), child: Column(children: [Icon(Icons.delivery_dining_rounded, size: 42, color: Color(0xFF8994A3)), SizedBox(height: 8), Text('لم تضف أي مندوب إلى فريق المطعم بعد', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700))]))),
        ...couriers.map((courier) {
          final active = courier['is_active'] == true;
          final available = courier['is_available'] == true;
          final name = courier['full_name']?.toString().trim().isNotEmpty == true ? courier['full_name'].toString() : 'مندوب توصيل';
          final phone = courier['phone']?.toString() ?? 'بدون رقم هاتف';
          final status = !active ? 'بانتظار موافقة الإدارة أو موقوف' : available ? 'متاح الآن' : 'غير متصل أو لا يشارك موقعه';
          return Card(child: ListTile(leading: CircleAvatar(backgroundColor: active ? const Color(0xFFFFF0E3) : const Color(0xFFE7ECF2), child: Icon(Icons.delivery_dining_rounded, color: active ? const Color(0xFFE50914) : const Color(0xFF8994A3))), title: Text(name, style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text('$phone • $status'), trailing: active ? IconButton(tooltip: 'إزالة من الفريق', onPressed: _busy ? null : () => _removeCourier(restaurantId, courier), icon: const Icon(Icons.person_remove_alt_1_rounded, color: Colors.red)) : const Icon(Icons.pause_circle_outline_rounded, color: Color(0xFF8994A3))));
        }),
      ]);
    });
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
        color: const Color(0xFF211B1C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ready ? const Color(0xFFFFC400) : const Color(0xFF493438), width: ready ? 1.5 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.receipt_long_rounded, color: ready ? const Color(0xFFFFC400) : Colors.white70),
          const SizedBox(width: 8),
          const Expanded(child: Text('تفاصيل الطلب كاملة', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900))),
          if (ready) const Chip(
            visualDensity: VisualDensity.compact,
            label: Text('جاهز للاستلام', style: TextStyle(fontWeight: FontWeight.w800)),
            backgroundColor: Color(0xFFFFC400),
            labelStyle: TextStyle(color: Color(0xFF171717)),
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
        const Text('الأصناف المطلوبة والكميات', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFFFC400))),
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
                  const Icon(Icons.restaurant_menu_rounded, size: 18, color: Color(0xFFFFC400)),
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
          decoration: BoxDecoration(color: const Color(0xFF650008), borderRadius: BorderRadius.circular(12)),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('الإجمالي المطلوب من العميل', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
            Text('$total ريال يمني', style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFFFC400), fontSize: 16)),
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
      Icon(icon, size: 18, color: const Color(0xFFFFC400)),
      const SizedBox(width: 8),
      SizedBox(width: 105, child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12))),
      Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
    ]),
  );

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
              gradient: const LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [Color(0xFF171717), Color(0xFF650008)]),
              borderRadius: BorderRadius.circular(22),
              boxShadow: const [BoxShadow(color: Color(0x1F171717), blurRadius: 16, offset: Offset(0, 7))],
            ),
            child: Row(children: [
              Container(width: 48, height: 48, decoration: BoxDecoration(color: const Color(0xFFFFC400), borderRadius: BorderRadius.circular(15)), child: const Icon(Icons.storefront_rounded, color: Color(0xFF171717), size: 27)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(restaurant['name'].toString(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
                const SizedBox(height: 3),
                const Text('إدارة الطلبات والوجبات وفريق التوصيل', style: TextStyle(fontSize: 11, color: Colors.white70)),
              ])),
              const Icon(Icons.verified_rounded, color: Color(0xFFFFC400), size: 22),
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
            StreamBuilder<List<Map<String,dynamic>>>(
              stream: SareeBackend.restaurantOrdersStream(rid),
              builder: (context, snap) {
                if (!snap.hasData && snap.connectionState == ConnectionState.waiting) return const LoadingPage();
                if(snap.hasError) return Center(child: Text('تعذر تحميل الطلبات: ${SareeBackend.arabicError(snap.error)}'));
                final orders = snap.data ?? [];
                if(orders.isEmpty) return const Center(child: Text('لا توجد طلبات حتى الآن'));
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
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _busy ? null : () => _run(() => SareeBackend.transition(o['id'].toString(), next)),
                            child: Text(label),
                          ),
                        ),
                      )
                    else if (isReadyForPickup && !hasCourier)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _busy ? null : () => _assignCourier(rid, o),
                            icon: const Icon(Icons.delivery_dining_rounded),
                            label: const Text('اختيار مندوب'),
                          ),
                        ),
                      )
                    else if (hasCourier)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(12, 0, 12, 10),
                        child: Chip(label: Text('تم تعيين مندوب')),
                      ),
                    // Keep the complete order information directly beneath the action button.
                    _restaurantOrderDetails(o),
                  ]));
                }).toList());
              },
            ),
            _courierTeamTab(rid),
          ])),
        ]);
      },
    ),
    bottomNavigationBar: NavigationBar(selectedIndex: _tab, onDestinationSelected: (v) => setState(() => _tab = v), destinations: const [
      NavigationDestination(icon: Icon(Icons.restaurant_menu_outlined), label: 'الوجبات'),
      NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'الطلبات'),
      NavigationDestination(icon: Icon(Icons.delivery_dining_outlined), label: 'المندوبون'),
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
      try { await SareeBackend.updateCourierLocation(p.latitude, p.longitude); }
      catch(e) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تحديث الموقع: ${SareeBackend.arabicError(e)}'))); }
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
        TextButton.icon(onPressed: () => launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng'), mode: LaunchMode.externalApplication), icon: const Icon(Icons.open_in_new_rounded), label: const Text('فتح الاتجاهات في خرائط Google')),
        SizedBox(height: 210, child: ClipRRect(borderRadius: BorderRadius.circular(14), child: FlutterMap(
          options: MapOptions(initialCenter: LatLng(lat, lng), initialZoom: 15),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.saree.delivery.saree'),
            MarkerLayer(markers: [Marker(point: LatLng(lat, lng), width: 48, height: 48, child: const Icon(Icons.location_pin, color: Color(0xFFE50914), size: 44))]),
          ],
        ))),
      ])) else const Padding(padding: EdgeInsets.all(12), child: Text('لم يرسل العميل موقعًا جغرافيًا؛ استخدم عنوان التوصيل ورقم الهاتف للتواصل معه.')),
    ]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('طلبات المندوب'), actions: [
      IconButton(tooltip: 'إشعارات التكليف', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerNotificationsPage())), icon: const Icon(Icons.notifications_active_outlined)),
      IconButton(tooltip: 'تحديث الطلبات', onPressed: _busy ? null : _refreshOrders, icon: const Icon(Icons.refresh_rounded)),
      IconButton(onPressed: () => SareeBackend.signOut(), icon: const Icon(Icons.logout)),
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
          if (snap.hasError) return Center(child: Text('تعذر تحميل المطاعم: ${SareeBackend.arabicError(snap.error)}'));
          final rows = snap.data ?? [];
          return ListView(padding: const EdgeInsets.all(14), children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('إدارة المطاعم', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF171717))),
              FilledButton.icon(onPressed: _createRestaurant, icon: const Icon(Icons.add), label: const Text('إضافة')),
            ]),
            const SizedBox(height: 8),
            if (rows.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(22), child: Text('لم تتم إضافة مطاعم بعد. أضف مطعمًا للبدء.'))),
            ...rows.map((r) => Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const CircleAvatar(backgroundColor: Color(0xFFFFE6E6), child: Icon(Icons.restaurant_rounded)),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF171717))),
                  Text(r['address']?.toString() ?? '', style: const TextStyle(color: Color(0xFF748094), fontSize: 12)),
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
            const Text('الحسابات والصلاحيات', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF171717))),
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
  int rating = 5;
  final comment = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) => AlertDialog(
      title: const Text('قيّم تجربتك'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('كيف كانت تجربتك مع المطعم؟'),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(5, (i) => IconButton(
          onPressed: () => setLocal(() => rating = i + 1),
          icon: Icon(i < rating ? Icons.star_rounded : Icons.star_border_rounded, color: const Color(0xFFFFB300), size: 32),
        ))),
        TextField(controller: comment, maxLines: 3, decoration: const InputDecoration(labelText: 'اكتب تعليقك (اختياري)')),
      ]),
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
        rating: rating,
        comment: comment.text,
      );
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('شكراً لك، تم إرسال تقييمك')));
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
                  leading: CircleAvatar(backgroundColor: const Color(0xFFFFE6E6), child: Icon(isRestaurant ? Icons.restaurant_rounded : Icons.fastfood_rounded)),
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
          leading: const Icon(Icons.favorite_rounded, color: Color(0xFFE50914)),
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
  late Future<List<Map<String,dynamic>>> _future;
  @override void initState() { super.initState(); _future = SareeBackend.myNotifications(); }
  Future<void> _refresh() async { setState(() => _future = SareeBackend.myNotifications()); await _future; }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('الإشعارات'), actions: [IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh))]),
    body: FutureBuilder<List<Map<String,dynamic>>>(
      future: _future,
      builder: (context,snap) {
        if (snap.connectionState != ConnectionState.done) return const LoadingPage();
        if (snap.hasError) return Center(child: Text('تعذر تحميل الإشعارات: ${SareeBackend.arabicError(snap.error)}'));
        final rows = snap.data ?? [];
        if (rows.isEmpty) return const Center(child: Text('لا توجد إشعارات حالياً'));
        return ListView(children: rows.map((n) => Card(child: ListTile(
          leading: CircleAvatar(backgroundColor: n['read_at'] == null ? const Color(0xFFFFE6E6) : Colors.grey.shade200, child: const Icon(Icons.notifications_active_outlined)),
          title: Text(n['title'].toString(), style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text('${n['body']}\n${n['created_at']}'),
          isThreeLine: true,
          onTap: () async {
            if (n['read_at'] == null) await SareeBackend.markNotificationRead(n['id'].toString());
            await _refresh();
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
    Icon(icon, color: const Color(0xFFE50914)),
    Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
    Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF748094))),
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
        DropdownButtonFormField<String>(initialValue: status, decoration: const InputDecoration(labelText: 'حالة الطلب'), items: const [
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
            initialValue: _restaurantId,
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
