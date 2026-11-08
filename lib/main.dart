import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

void main() => runApp(MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => CartProvider()),
    ChangeNotifierProvider(create: (_) => RestaurantProvider()),
    ChangeNotifierProvider(create: (_) => OrderProvider()),
  ],
  child: const SareeApp(),
));

class FoodItem {
  const FoodItem({required this.id, required this.name, required this.price});
  final String id, name;
  final int price;
}

class RestaurantModel {
  const RestaurantModel({required this.id, required this.name, required this.rating, required this.deliveryMinutes, required this.menu});
  final String id, name;
  final double rating;
  final int deliveryMinutes;
  final List<FoodItem> menu;
}

class CartItem {
  CartItem({required this.food, this.quantity = 1});
  final FoodItem food;
  int quantity;
  int get subtotal => food.price * quantity;
}

class CartProvider extends ChangeNotifier {
  final List<CartItem> _items = [];
  String? _restaurantId;
  List<CartItem> get items => List.unmodifiable(_items);
  int get count => _items.fold(0, (sum, item) => sum + item.quantity);
  int get subtotal => _items.fold(0, (sum, item) => sum + item.subtotal);
  int get delivery => _items.isEmpty ? 0 : 1000;
  int get total => subtotal + delivery;

  void add(FoodItem food, String restaurantId) {
    if (_restaurantId != null && _restaurantId != restaurantId) _items.clear();
    _restaurantId = restaurantId;
    final index = _items.indexWhere((item) => item.food.id == food.id);
    if (index >= 0) _items[index].quantity++; else _items.add(CartItem(food: food));
    notifyListeners();
  }

  void change(CartItem item, int delta) {
    item.quantity += delta;
    if (item.quantity <= 0) _items.remove(item);
    if (_items.isEmpty) _restaurantId = null;
    notifyListeners();
  }

  void clear() { _items.clear(); _restaurantId = null; notifyListeners(); }
}

class RestaurantProvider extends ChangeNotifier {
  final List<RestaurantModel> _restaurants = const [
    RestaurantModel(id: 'taste', name: 'مطعم الذوق', rating: 4.7, deliveryMinutes: 30, menu: [
      FoodItem(id: 'taste-chicken', name: 'وجبة دجاج', price: 3500),
      FoodItem(id: 'taste-burger', name: 'برجر لحم', price: 3000),
      FoodItem(id: 'taste-grill', name: 'وجبة مشويات', price: 5000),
    ]),
    RestaurantModel(id: 'radaa', name: 'مطعم رداع الشعبي', rating: 4.6, deliveryMinutes: 35, menu: [
      FoodItem(id: 'radaa-mandi', name: 'مندي دجاج', price: 4000),
      FoodItem(id: 'radaa-saltah', name: 'سلتة يمنية', price: 2500),
      FoodItem(id: 'radaa-fahsa', name: 'فحسة', price: 3000),
    ]),
  ];

  List<RestaurantModel> search(String query) {
    if (query.trim().isEmpty) return List.unmodifiable(_restaurants);
    return _restaurants.where((r) => r.name.contains(query.trim()) || r.menu.any((f) => f.name.contains(query.trim()))).toList();
  }
}

enum OrderStatus { sent, accepted, preparing, delivering, delivered, cancelled }

class OrderModel {
  OrderModel({required this.id, required this.items, required this.address, required this.total, this.status = OrderStatus.sent, DateTime? createdAt}) : createdAt = createdAt ?? DateTime.now();
  final String id;
  final List<CartItem> items;
  final String address;
  final int total;
  OrderStatus status;
  final DateTime createdAt;
}

class OrderProvider extends ChangeNotifier {
  final List<OrderModel> _orders = [];
  List<OrderModel> get orders => List.unmodifiable(_orders);

  OrderModel createOrder({required List<CartItem> items, required String address, required int total}) {
    final order = OrderModel(
      id: 'SR' + DateTime.now().millisecondsSinceEpoch.toString(),
      items: items.map((item) => CartItem(food: item.food, quantity: item.quantity)).toList(),
      address: address,
      total: total,
    );
    _orders.insert(0, order);
    notifyListeners();
    return order;
  }

  void advanceStatus(String id) {
    final order = _orders.firstWhere((order) => order.id == id);
    if (order.status.index < OrderStatus.delivered.index) {
      order.status = OrderStatus.values[order.status.index + 1];
      notifyListeners();
    }
  }

  void cancel(String id) {
    final order = _orders.firstWhere((order) => order.id == id);
    if (order.status.index < OrderStatus.preparing.index) {
      order.status = OrderStatus.cancelled;
      notifyListeners();
    }
  }
}

String orderStatusText(OrderStatus status) {
  switch (status) {
    case OrderStatus.sent: return 'تم إرسال الطلب';
    case OrderStatus.accepted: return 'قبل المطعم الطلب';
    case OrderStatus.preparing: return 'جاري تحضير الطلب';
    case OrderStatus.delivering: return 'المندوب في الطريق';
    case OrderStatus.delivered: return 'تم التوصيل';
    case OrderStatus.cancelled: return 'تم إلغاء الطلب';
  }
}

class SareeApp extends StatelessWidget {
  const SareeApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'سريع',
    theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFF6B35))),
    home: const Directionality(textDirection: TextDirection.rtl, child: HomePage()),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final restaurants = context.watch<RestaurantProvider>().search(query);
    final cart = context.watch<CartProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('سريع - توصيل الطعام في رداع'), actions: [
        IconButton(icon: const Icon(Icons.receipt_long), tooltip: 'طلباتي', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OrdersPage()))),
        Badge(label: Text(cart.count.toString()), isLabelVisible: cart.count > 0, child: IconButton(icon: const Icon(Icons.shopping_cart), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartPage())))),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Card(child: ListTile(leading: Icon(Icons.location_on), title: Text('منطقة التوصيل'), subtitle: Text('رداع، اليمن - اختر عنوانك عند تأكيد الطلب'))),
        const SizedBox(height: 12),
        TextField(onChanged: (value) => setState(() => query = value), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'ابحث عن مطعم أو وجبة', border: OutlineInputBorder())),
        const SizedBox(height: 16),
        const Text('المطاعم المتاحة', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        if (restaurants.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('لا توجد نتائج مطابقة'))),
        ...restaurants.map((r) => Card(child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.restaurant)),
          title: Text(r.name),
          subtitle: Text('⭐ ' + r.rating.toString() + ' • حوالي ' + r.deliveryMinutes.toString() + ' دقيقة'),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RestaurantPage(restaurant: r))),
        ))),
      ]),
    );
  }
}

class RestaurantPage extends StatelessWidget {
  const RestaurantPage({super.key, required this.restaurant});
  final RestaurantModel restaurant;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(restaurant.name)),
    body: ListView(padding: const EdgeInsets.all(16), children: restaurant.menu.map((food) => Card(child: ListTile(
      title: Text(food.name),
      subtitle: Text(food.price.toString() + ' ريال يمني'),
      trailing: IconButton(icon: const Icon(Icons.add_circle), onPressed: () {
        context.read<CartProvider>().add(food, restaurant.id);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تمت إضافة ' + food.name + ' إلى السلة')));
      }),
    ))).toList()),
  );
}

class CartPage extends StatelessWidget {
  const CartPage({super.key});
  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('سلة الطلب')),
      body: cart.items.isEmpty ? const Center(child: Text('السلة فارغة')) : Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Expanded(child: ListView(children: cart.items.map((item) => ListTile(
            title: Text(item.food.name),
            subtitle: Text(item.subtotal.toString() + ' ريال'),
            leading: IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => cart.change(item, -1)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [Text(item.quantity.toString()), IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => cart.change(item, 1))]),
          )).toList())),
          Align(alignment: Alignment.centerRight, child: Text('التوصيل: ' + cart.delivery.toString() + ' ريال\nالإجمالي: ' + cart.total.toString() + ' ريال', style: const TextStyle(fontWeight: FontWeight.bold))),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CheckoutPage())), child: const Text('متابعة الطلب')),
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
  final address = TextEditingController(text: 'رداع - حدد عنوانك بالتفصيل');
  @override void dispose() { address.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('تأكيد الطلب')),
    body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
      TextField(controller: address, decoration: const InputDecoration(labelText: 'عنوان التوصيل', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      const ListTile(leading: Icon(Icons.payments), title: Text('الدفع عند الاستلام')),
      ElevatedButton(onPressed: () {
        if (address.text.trim().isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى إدخال عنوان التوصيل'))); return; }
        final cart = context.read<CartProvider>();
        final order = context.read<OrderProvider>().createOrder(
          items: cart.items,
          address: address.text.trim(),
          total: cart.total,
        );
        cart.clear();
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => TrackingPage(orderId: order.id)),
          (_) => false,
        );
      }, child: const Text('تأكيد الطلب')),
    ])),
  );
}

class OrdersPage extends StatelessWidget {
  const OrdersPage({super.key});
  @override
  Widget build(BuildContext context) {
    final orders = context.watch<OrderProvider>().orders;
    return Scaffold(
      appBar: AppBar(title: const Text('طلباتي')),
      body: orders.isEmpty
          ? const Center(child: Text('لا توجد طلبات حتى الآن'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: orders.map((order) => Card(
                child: ListTile(
                  leading: const Icon(Icons.receipt_long),
                  title: Text('طلب ' + order.id),
                  subtitle: Text(orderStatusText(order.status) + ' • ' + order.total.toString() + ' ريال'),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TrackingPage(orderId: order.id))),
                ),
              )).toList(),
            ),
    );
  }
}

class TrackingPage extends StatelessWidget {
  const TrackingPage({super.key, required this.orderId});
  final String orderId;

  @override
  Widget build(BuildContext context) {
    final orders = context.watch<OrderProvider>().orders;
    final order = orders.firstWhere((item) => item.id == orderId);
    const steps = [
      OrderStatus.sent,
      OrderStatus.accepted,
      OrderStatus.preparing,
      OrderStatus.delivering,
      OrderStatus.delivered,
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('تتبع الطلب')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.delivery_dining, size: 80),
          Text('رقم الطلب: ' + order.id, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text('العنوان: ' + order.address),
          ...steps.map((step) {
            final done = order.status.index >= step.index && order.status != OrderStatus.cancelled;
            return ListTile(
              leading: Icon(done ? Icons.check_circle : Icons.radio_button_unchecked),
              title: Text(orderStatusText(step)),
            );
          }),
          if (order.status == OrderStatus.cancelled)
            const ListTile(leading: Icon(Icons.cancel), title: Text('تم إلغاء الطلب')),
          const SizedBox(height: 12),
          if (order.status != OrderStatus.delivered && order.status != OrderStatus.cancelled)
            ElevatedButton(
              onPressed: () => context.read<OrderProvider>().advanceStatus(order.id),
              child: const Text('تحديث حالة الطلب'),
            ),
          if (order.status.index < OrderStatus.preparing.index)
            OutlinedButton(
              onPressed: () => context.read<OrderProvider>().cancel(order.id),
              child: const Text('إلغاء الطلب'),
            ),
        ],
      ),
    );
  }
}
