import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saree/features/cart/cart_controller.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('CartController', () {
    test('adds a dish and calculates quantity and subtotal', () async {
      final cart = await CartController.create();
      final dish = {'id': 'meal-1', 'name': 'وجبة اختبار'};

      cart.add(dish, 'restaurant-1', price: 1200);
      expect(cart.count, 1);
      expect(cart.subtotal, 1200);

      cart.add(dish, 'restaurant-1', price: 1200);
      await cart.flush();
      expect(cart.count, 2);
      expect(cart.subtotal, 2400);
    });

    test('switching restaurants clears previous restaurant items', () async {
      final cart = await CartController.create();
      cart.add({'id': 'meal-1', 'name': 'الأولى'}, 'restaurant-1', price: 1000);
      cart.add({'id': 'meal-2', 'name': 'الثانية'}, 'restaurant-2', price: 1500);
      await cart.flush();

      expect(cart.count, 1);
      expect(cart.subtotal, 1500);
      expect(cart.restaurantId, 'restaurant-2');
    });

    test('decrementing last item empties cart and resets restaurant', () async {
      final cart = await CartController.create();
      cart.add({'id': 'meal-1', 'name': 'وجبة'}, 'restaurant-1', price: 500);
      cart.change(cart.items.single, -1);
      await cart.flush();

      expect(cart.items, isEmpty);
      expect(cart.count, 0);
      expect(cart.restaurantId, isNull);
    });
  });
}
