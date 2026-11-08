import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFF6B35)),
      scaffoldBackgroundColor: const Color(0xFFFFFBF8),
      appBarTheme: const AppBarTheme(centerTitle: true),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      ),
    ),
    home: const SareeGate(),
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
        Icon(Icons.cloud_off, size: 64, color: Colors.deepOrange),
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
          const CircleAvatar(radius: 42, child: Icon(Icons.delivery_dining, size: 48)),
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
        title: const Text('سريع - رداع'),
        actions: [
          IconButton(tooltip: 'طلباتي', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerOrdersPage())), icon: const Icon(Icons.receipt_long)),
          Stack(children: [
            IconButton(tooltip: 'السلة', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartPage())), icon: const Icon(Icons.shopping_bag_outlined)),
            if (cart.count > 0) Positioned(right: 5, top: 4, child: CircleAvatar(radius: 9, child: Text(cart.count.toString(), style: const TextStyle(fontSize: 10)))),
          ]),
          IconButton(tooltip: 'خروج', onPressed: () => SareeBackend.signOut(), icon: const Icon(Icons.logout)),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: SareeBackend.restaurants(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const LoadingPage();
          if (snapshot.hasError) return Center(child: Text('تعذر تحميل المطاعم: ${snapshot.error}'));
          final restaurants = snapshot.data ?? [];
          if (restaurants.isEmpty) return const Center(child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('لا توجد مطاعم مفعّلة حاليًا. ستظهر المطاعم هنا بعد إضافتها واعتمادها من الإدارة.', textAlign: TextAlign.center),
          ));
          return ListView(padding: const EdgeInsets.all(16), children: [
            const Card(child: ListTile(leading: Icon(Icons.location_on), title: Text('منطقة الخدمة'), subtitle: Text('رداع - اليمن'))),
            const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Text('المطاعم المتاحة', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold))),
            ...restaurants.map((r) => Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.restaurant)),
                title: Text(r['name']?.toString() ?? 'مطعم'),
                subtitle: Text('${r['description'] ?? ''}\nرسوم التوصيل: ${r['delivery_fee_yer']} ريال'),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_left),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RestaurantMenuPage(restaurant: r))),
              ),
            )),
          ]);
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
        return ListView(padding: const EdgeInsets.all(16), children: menu.map((item) => Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.fastfood)),
            title: Text(item['name'].toString()),
            subtitle: Text('${item['description'] ?? ''}\n${item['price_yer']} ريال يمني'),
            isThreeLine: true,
            trailing: IconButton(
              icon: const Icon(Icons.add_circle, color: Colors.deepOrange),
              onPressed: () {
                context.read<CartController>().add(item, restaurant['id'].toString());
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أضيفت الوجبة إلى السلة')));
              },
            ),
          ),
        )).toList());
      },
    ),
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
            onTap: () => showDialog(context: context, builder: (_) => AlertDialog(
              title: Text('طلب #${order['order_number']}'),
              content: Text('الحالة: ${statusLabel(order['status'].toString())}\nالعنوان: ${order['delivery_address']}\nالإجمالي: ${order['total_yer']} ريال'),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق'))],
            )),
          ),
        )).toList());
      },
    ),
  );
}

class RestaurantPortal extends StatefulWidget {
  const RestaurantPortal({super.key});
  @override State<RestaurantPortal> createState() => _RestaurantPortalState();
}

class _RestaurantPortalState extends State<RestaurantPortal> {
  bool _busy = false;
  Future<void> _advance(String id, String next) async {
    setState(() => _busy = true);
    try { await SareeBackend.transition(id, next); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()))); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('طلبات المطعم'), actions: [IconButton(onPressed: () => SareeBackend.signOut(), icon: const Icon(Icons.logout))]),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: SareeBackend.restaurantOrders(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const LoadingPage();
        if (snapshot.hasError) return Center(child: Text('تعذر تحميل طلبات المطعم: ${snapshot.error}'));
        final orders = snapshot.data ?? [];
        if (orders.isEmpty) return const Center(child: Text('لا توجد طلبات. تأكد من ربط حسابك بالمطعم من الإدارة.'));
        return ListView(padding: const EdgeInsets.all(12), children: orders.map((o) {
          final status = o['status'].toString();
          final next = status == 'pending' ? 'accepted' : status == 'accepted' ? 'preparing' : status == 'preparing' ? 'ready_for_pickup' : null;
          final label = next == 'accepted' ? 'قبول الطلب' : next == 'preparing' ? 'بدء التحضير' : next == 'ready_for_pickup' ? 'جاهز للاستلام' : null;
          return Card(child: ListTile(
            title: Text('طلب #${o['order_number']} - ${o['customer_name']}'),
            subtitle: Text('الحالة: $status\n${o['delivery_address']}\n${o['total_yer']} ريال'),
            isThreeLine: true,
            trailing: next == null ? null : FilledButton(onPressed: _busy ? null : () => _advance(o['id'].toString(), next), child: Text(label!)),
          ));
        }).toList());
      },
    ),
  );
}

class CourierPortal extends StatefulWidget {
  const CourierPortal({super.key});
  @override State<CourierPortal> createState() => _CourierPortalState();
}

class _CourierPortalState extends State<CourierPortal> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('طلبات المندوب'), actions: [IconButton(onPressed: () => SareeBackend.signOut(), icon: const Icon(Icons.logout))]),
    body: FutureBuilder<List<List<Map<String, dynamic>>>>(
      future: Future.wait([SareeBackend.availableCourierOrders(), SareeBackend.courierOrders()]),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const LoadingPage();
        if (snapshot.hasError) return Center(child: Text('تعذر تحميل الطلبات: ${snapshot.error}'));
        final available = snapshot.data![0];
        final active = snapshot.data![1].where((o) => o['status'] == 'assigned' || o['status'] == 'picked_up').toList();
        return ListView(padding: const EdgeInsets.all(12), children: [
          const Padding(padding: EdgeInsets.all(8), child: Text('مهامك الحالية', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold))),
          if (active.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('لا توجد لديك توصيلات نشطة')),
          ...active.map((o) {
            final status = o['status'].toString();
            final next = status == 'assigned' ? 'picked_up' : 'delivered';
            final label = status == 'assigned' ? 'تأكيد استلام الطلب' : 'تأكيد التسليم';
            return Card(child: ListTile(
              title: Text('طلب #${o['order_number']}'),
              subtitle: Text('${o['delivery_address']}\nالحالة: $status'),
              isThreeLine: true,
              trailing: FilledButton(onPressed: _busy ? null : () => _run(() => SareeBackend.transition(o['id'].toString(), next)), child: Text(label)),
            ));
          }),
          const Padding(padding: EdgeInsets.all(8), child: Text('طلبات جاهزة للاستلام', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold))),
          if (available.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('لا توجد طلبات جاهزة حاليًا')),
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

class AdminPortal extends StatelessWidget {
  const AdminPortal({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('إدارة سريع'), actions: [IconButton(onPressed: () => SareeBackend.signOut(), icon: const Icon(Icons.logout))]),
    body: const Center(child: Padding(
      padding: EdgeInsets.all(24),
      child: Text('تم تسجيل الدخول كمدير. إدارة المطاعم والحسابات تحتاج استكمال لوحة الإدارة وربط إجراءات اعتماد المطاعم وتعيين الأدوار.', textAlign: TextAlign.center),
    )),
  );
}
