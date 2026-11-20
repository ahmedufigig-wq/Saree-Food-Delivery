import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CartLine {
  CartLine({
    required this.id,
    required this.name,
    required this.price,
    required this.quantity,
  });

  final String id;
  final String name;
  final int price;
  int quantity;

  int get total => price * quantity;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'price': price,
        'quantity': quantity,
      };
}

class CartController extends ChangeNotifier {
  CartController._(this._preferences);

  static const String _storageKey = 'saree.cart.v1';

  final SharedPreferences _preferences;
  final List<CartLine> _items = [];
  Future<void> _writeQueue = Future<void>.value();
  Object? _lastPersistenceError;

  String? restaurantId;

  List<CartLine> get items => List.unmodifiable(_items);
  int get subtotal => _items.fold(0, (sum, item) => sum + item.total);
  int get count => _items.fold(0, (sum, item) => sum + item.quantity);
  Object? get persistenceError => _lastPersistenceError;

  /// Restores the cart before the customer UI is displayed.
  static Future<CartController> create({
    SharedPreferences? preferences,
  }) async {
    final prefs = preferences ?? await SharedPreferences.getInstance();
    final controller = CartController._(prefs);
    await controller._restore();
    return controller;
  }

  Future<void> _restore() async {
    final saved = _preferences.getString(_storageKey);
    if (saved == null || saved.isEmpty) return;

    try {
      final decoded = jsonDecode(saved);
      if (decoded is! Map) {
        throw const FormatException('Cart payload must be an object');
      }

      final storedRestaurantId = decoded['restaurantId'];
      final storedItems = decoded['items'];
      if (storedRestaurantId is! String ||
          storedRestaurantId.trim().isEmpty ||
          storedItems is! List ||
          storedItems.isEmpty) {
        throw const FormatException('Cart payload is incomplete');
      }

      final restored = <CartLine>[];
      final seenIds = <String>{};
      for (final value in storedItems) {
        if (value is! Map) {
          throw const FormatException('Cart item must be an object');
        }
        final id = value['id'];
        final name = value['name'];
        final priceValue = value['price'];
        final quantityValue = value['quantity'];
        if (id is! String ||
            id.trim().isEmpty ||
            name is! String ||
            name.trim().isEmpty ||
            priceValue is! num ||
            quantityValue is! num) {
          throw const FormatException('Cart item has invalid fields');
        }

        final price = priceValue.toInt();
        final quantity = quantityValue.toInt();
        if (price < 0 ||
            quantity < 1 ||
            priceValue != price ||
            quantityValue != quantity ||
            !seenIds.add(id)) {
          throw const FormatException('Cart item values are invalid');
        }

        restored.add(CartLine(
          id: id,
          name: name,
          price: price,
          quantity: quantity,
        ));
      }

      restaurantId = storedRestaurantId;
      _items
        ..clear()
        ..addAll(restored);
    } catch (_) {
      // Never keep a partially decoded cart or repeatedly crash on bad local data.
      _items.clear();
      restaurantId = null;
      await _preferences.remove(_storageKey);
    }
  }

  void add(
    Map<String, dynamic> item,
    String ownerRestaurantId, {
    required int price,
  }) {
    final id = item['id']?.toString().trim() ?? '';
    final name = item['name']?.toString().trim() ?? '';
    final restaurant = ownerRestaurantId.trim();
    if (id.isEmpty || name.isEmpty || restaurant.isEmpty || price < 0) {
      throw ArgumentError('Cart item is missing a valid id, name, restaurant, or price.');
    }

    if (restaurantId != null && restaurantId != restaurant) {
      _items.clear();
    }
    restaurantId = restaurant;

    final index = _items.indexWhere((line) => line.id == id);
    if (index >= 0) {
      _items[index].quantity++;
    } else {
      _items.add(CartLine(
        id: id,
        name: name,
        price: price,
        quantity: 1,
      ));
    }
    _persist();
    notifyListeners();
  }

  void change(CartLine item, int delta) {
    if (delta == 0) return;
    final index = _items.indexWhere((line) => line.id == item.id);
    if (index < 0) return;

    final nextQuantity = _items[index].quantity + delta;
    if (nextQuantity <= 0) {
      _items.removeAt(index);
    } else {
      _items[index].quantity = nextQuantity;
    }
    if (_items.isEmpty) restaurantId = null;

    _persist();
    notifyListeners();
  }

  /// Clears memory and waits until the removal is written to local storage.
  Future<void> clear() async {
    _items.clear();
    restaurantId = null;
    final write = _enqueueWrite(null);
    notifyListeners();
    await write;
  }

  /// Useful at lifecycle boundaries and in tests to wait for queued writes.
  Future<void> flush() async {
    await _writeQueue;
    final error = _lastPersistenceError;
    if (error != null) {
      throw StateError('Unable to persist the cart: $error');
    }
  }

  void _persist() {
    if (_items.isEmpty || restaurantId == null) {
      _enqueueWrite(null);
      return;
    }
    final snapshot = jsonEncode({
      'version': 1,
      'restaurantId': restaurantId,
      'items': _items.map((item) => item.toJson()).toList(),
    });
    _enqueueWrite(snapshot);
  }

  Future<void> _enqueueWrite(String? snapshot) {
    _writeQueue = _writeQueue.catchError((Object _) {}).then((_) async {
      try {
        if (snapshot == null) {
          await _preferences.remove(_storageKey);
        } else {
          await _preferences.setString(_storageKey, snapshot);
        }
        _lastPersistenceError = null;
      } catch (error) {
        _lastPersistenceError = error;
      }
    });
    return _writeQueue;
  }
}
