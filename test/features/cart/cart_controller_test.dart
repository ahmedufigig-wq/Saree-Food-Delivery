import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saree/features/cart/cart_controller.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Map<String, dynamic> item(String id, String name) => {
        'id': id,
        'name': name,
      };

  test('restores restaurant, items, quantities and saved prices', () async {
    final cart = await CartController.create();
    cart.add(item('meal-1', 'كبسة دجاج'), 'restaurant-1', price: 1800);
    cart.add(item('meal-1', 'كبسة دجاج'), 'restaurant-1', price: 1800);
    cart.add(item('meal-2', 'عصير'), 'restaurant-1', price: 500);
    await cart.flush();

    final restored = await CartController.create();
    expect(restored.restaurantId, 'restaurant-1');
    expect(restored.items, hasLength(2));
    expect(restored.items.first.quantity, 2);
    expect(restored.items.first.price, 1800);
    expect(restored.subtotal, 4100);
  });

  test('switching restaurants replaces the previous restaurant cart', () async {
    final cart = await CartController.create();
    cart.add(item('meal-1', 'كبسة'), 'restaurant-1', price: 1000);
    cart.add(item('meal-2', 'بيتزا'), 'restaurant-2', price: 2000);
    await cart.flush();

    final restored = await CartController.create();
    expect(restored.restaurantId, 'restaurant-2');
    expect(restored.items, hasLength(1));
    expect(restored.items.single.id, 'meal-2');
  });

  test('quantity changes persist and remove an item at zero', () async {
    final cart = await CartController.create();
    cart.add(item('meal-1', 'كبسة'), 'restaurant-1', price: 1000);
    final line = cart.items.single;

    cart.change(line, 2);
    await cart.flush();
    expect((await CartController.create()).items.single.quantity, 3);

    cart.change(line, -3);
    await cart.flush();
    final restored = await CartController.create();
    expect(restored.items, isEmpty);
    expect(restored.restaurantId, isNull);
  });

  test('clear removes the persisted cart after successful checkout', () async {
    final cart = await CartController.create();
    cart.add(item('meal-1', 'كبسة'), 'restaurant-1', price: 1000);
    await cart.flush();

    await cart.clear();
    final restored = await CartController.create();
    expect(restored.items, isEmpty);
    expect(restored.restaurantId, isNull);
  });

  test('corrupt saved data is discarded safely', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('saree.cart.v1', '{not-json');

    final cart = await CartController.create();
    expect(cart.items, isEmpty);
    expect(cart.restaurantId, isNull);
    expect(preferences.getString('saree.cart.v1'), isNull);
  });
}
