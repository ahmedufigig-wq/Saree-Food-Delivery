import 'package:flutter_test/flutter_test.dart';
import 'package:saree/main.dart';

void main() {
  group('CartController', () {
    test('adds a dish and calculates quantity and subtotal', () {
      final cart = CartController();
      cart.add({'id': 'meal-1', 'name': 'وجبة اختبار', 'price_yer': 1200}, 'restaurant-1');
      expect(cart.count, 1);
      expect(cart.subtotal, 1200);
      cart.add({'id': 'meal-1', 'name': 'وجبة اختبار', 'price_yer': 1200}, 'restaurant-1');
      expect(cart.count, 2);
      expect(cart.subtotal, 2400);
    });

    test('switching restaurants clears previous restaurant items', () {
      final cart = CartController();
      cart.add({'id': 'meal-1', 'name': 'الأولى', 'price_yer': 1000}, 'restaurant-1');
      cart.add({'id': 'meal-2', 'name': 'الثانية', 'price_yer': 1500}, 'restaurant-2');
      expect(cart.count, 1);
      expect(cart.subtotal, 1500);
      expect(cart.restaurantId, 'restaurant-2');
    });

    test('decrementing last item empties cart and resets restaurant', () {
      final cart = CartController();
      cart.add({'id': 'meal-1', 'name': 'وجبة', 'price_yer': 500}, 'restaurant-1');
      cart.change(cart.items.single, -1);
      expect(cart.items, isEmpty);
      expect(cart.count, 0);
      expect(cart.restaurantId, isNull);
    });
  });
}
