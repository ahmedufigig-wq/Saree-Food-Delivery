import 'package:supabase_flutter/supabase_flutter.dart';

class SareeBackend {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  // SUPABASE_ANON_KEY accepts the Supabase publishable key (recommended)
  // or the legacy anon key. Never put a service_role/secret key in the app.
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isConfigured =>
      supabaseUrl.startsWith('https://') && supabaseAnonKey.isNotEmpty;

  static SupabaseClient get client => Supabase.instance.client;
  static User? get user => isConfigured ? client.auth.currentUser : null;

  static Future<void> initialize() async {
    if (isConfigured) {
      await Supabase.initialize(
        url: supabaseUrl,
        publishableKey: supabaseAnonKey,
        authOptions: const FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
        ),
      );
    }
  }

  static Future<void> signIn(String email, String password) async {
    await client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  static Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
    required String phone,
  }) async {
    await client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {
        'full_name': fullName.trim(),
        'phone': phone.trim(),
      },
    );
  }


  static Future<void> updateMyProfile({
    required String fullName,
    required String phone,
  }) async {
    await client.from('profiles').update({
      'full_name': fullName.trim(),
      'phone': phone.trim().isEmpty ? null : phone.trim(),
    }).eq('id', user!.id);
  }

  static Future<List<Map<String, dynamic>>> myAddresses() async {
    final rows = await client
        .from('customer_addresses')
        .select()
        .eq('customer_id', user!.id)
        .order('is_default', ascending: false)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<void> saveAddress({
    String? id,
    required String label,
    required String addressText,
    required String area,
    required bool isDefault,
  }) async {
    final values = {
      'customer_id': user!.id,
      'label': label.trim(),
      'address_text': addressText.trim(),
      'area': area.trim(),
      'is_default': isDefault,
    };
    if (isDefault) {
      await client.from('customer_addresses')
          .update({'is_default': false})
          .eq('customer_id', user!.id);
    }
    if (id == null) {
      await client.from('customer_addresses').insert(values);
    } else {
      values.remove('customer_id');
      await client.from('customer_addresses').update(values).eq('id', id);
    }
  }

  static Future<void> deleteAddress(String id) async {
    await client.from('customer_addresses')
        .delete().eq('id', id).eq('customer_id', user!.id);
  }

  static Future<void> setDefaultAddress(String id) async {
    await client.from('customer_addresses')
        .update({'is_default': false}).eq('customer_id', user!.id);
    await client.from('customer_addresses')
        .update({'is_default': true})
        .eq('id', id).eq('customer_id', user!.id);
  }

  static Future<void> signOut() => client.auth.signOut();

  static Future<Map<String, dynamic>> profile() async {
    final current = user;
    if (current == null) throw Exception('يرجى تسجيل الدخول');
    final row = await client
        .from('profiles')
        .select('id, full_name, phone, role, created_at')
        .eq('id', current.id)
        .single();
    return Map<String, dynamic>.from(row);
  }

  static Future<List<Map<String, dynamic>>> restaurants() async {
    final rows = await client
        .from('restaurants')
        .select()
        .eq('is_active', true)
        .order('name');
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<List<Map<String, dynamic>>> menu(String restaurantId) async {
    // Return all listed dishes so customers can browse the restaurant's full menu.
    // Availability is checked separately before allowing an order.
    final rows = await client
        .from('menu_items')
        .select('*, menu_categories(name, sort_order)')
        .eq('restaurant_id', restaurantId)
        .order('name');
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<String> createOrder({
    required String restaurantId,
    required String customerName,
    required String customerPhone,
    required String address,
    required List<Map<String, dynamic>> items,
    String notes = '',
  }) async {
    final result = await client.rpc('create_order', params: {
      'p_restaurant_id': restaurantId,
      'p_customer_name': customerName,
      'p_customer_phone': customerPhone,
      'p_delivery_address': address,
      'p_items': items,
      'p_notes': notes,
    });
    return result.toString();
  }

  static Stream<List<Map<String, dynamic>>> customerOrders() {
    final id = user!.id;
    return client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('customer_id', id)
        .order('created_at', ascending: false);
  }


  static Stream<List<Map<String, dynamic>>> trackOrder(String orderId) {
    return client.from('orders').stream(primaryKey: ['id']).eq('id', orderId);
  }

  static Future<List<Map<String, dynamic>>> restaurantOrders() async {
    final id = user!.id;
    final memberships = await client
        .from('restaurant_members')
        .select('restaurant_id')
        .eq('user_id', id);
    final ids = List<Map<String, dynamic>>.from(memberships)
        .map((row) => row['restaurant_id'].toString())
        .toList();
    if (ids.isEmpty) return [];
    final rows = await client
        .from('orders')
        .select()
        .inFilter('restaurant_id', ids)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<List<Map<String, dynamic>>> courierOrders() async {
    final rows = await client
        .from('orders')
        .select()
        .eq('courier_id', user!.id)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<List<Map<String, dynamic>>> availableCourierOrders() async {
    final rows = await client
        .from('orders')
        .select()
        .eq('status', 'ready_for_pickup')
        .isFilter('courier_id', null)
        .order('created_at');
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<void> transition(
    String orderId,
    String status, {
    String? reason,
  }) async {
    await client.rpc('transition_order', params: {
      'p_order_id': orderId,
      'p_next_status': status,
      'p_cancellation_reason': reason,
    });
  }

  static Future<List<Map<String, dynamic>>> adminRestaurants() async {
    final rows = await client.from('restaurants').select().order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<void> createRestaurant({
    required String name,
    required String address,
    required String phone,
    required int deliveryFee,
  }) async {
    await client.from('restaurants').insert({
      'name': name.trim(),
      'address': address.trim(),
      'phone': phone.trim().isEmpty ? null : phone.trim(),
      'delivery_fee_yer': deliveryFee,
      'is_active': false,
    });
  }

  static Future<void> setRestaurantActive(String id, bool active) async {
    await client.from('restaurants').update({'is_active': active}).eq('id', id);
  }

  static Future<List<Map<String, dynamic>>> adminProfiles() async {
    final rows = await client.from('profiles').select('id, full_name, phone, role, created_at').order('created_at', ascending: false).limit(200);
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<void> setUserRole(String id, String role) async {
    await client.rpc('admin_set_user_role', params: {'p_user_id': id, 'p_role': role});
  }

  static Future<void> addRestaurantMember(String restaurantId, String userId) async {
    await client.from('restaurant_members').upsert({
      'restaurant_id': restaurantId,
      'user_id': userId,
      'member_role': 'manager',
    });
  }

  static Future<void> removeRestaurantMember(String restaurantId, String userId) async {
    await client.from('restaurant_members').delete().eq('restaurant_id', restaurantId).eq('user_id', userId);
  }


  static Future<List<Map<String, dynamic>>> myRestaurants() async {
    final memberships = await client.from('restaurant_members').select('restaurant_id').eq('user_id', user!.id);
    final ids = List<Map<String, dynamic>>.from(memberships).map((r) => r['restaurant_id'].toString()).toList();
    if (ids.isEmpty) return [];
    final rows = await client.from('restaurants').select().inFilter('id', ids).order('name');
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<List<Map<String, dynamic>>> manageMenu(String restaurantId) async {
    final rows = await client.from('menu_items').select().eq('restaurant_id', restaurantId).order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<void> saveMenuItem({String? id, required String restaurantId, required String name, required String description, required int price, String? imageUrl, required bool available}) async {
    final values = {
      'restaurant_id': restaurantId,
      'name': name.trim(),
      'description': description.trim(),
      'price_yer': price,
      'image_url': imageUrl?.trim().isEmpty == true ? null : imageUrl?.trim(),
      'is_available': available,
    };
    if (id == null) {
      await client.from('menu_items').insert(values);
    } else {
      await client.from('menu_items').update(values..remove('restaurant_id')).eq('id', id);
    }
  }

  static Future<void> deleteMenuItem(String id) async {
    await client.from('menu_items').delete().eq('id', id);
  }

  static Future<void> updateCourierLocation(double latitude, double longitude) async {
    await client.from('courier_locations').upsert({
      'courier_id': user!.id,
      'latitude': latitude,
      'longitude': longitude,
      'is_available': true,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  static Stream<List<Map<String, dynamic>>> courierLocation(String courierId) {
    return client.from('courier_locations').stream(primaryKey: ['courier_id']).eq('courier_id', courierId);
  }

  static Future<List<Map<String, dynamic>>> searchCatalog(String query) async {
    final term = query.trim();
    if (term.isEmpty) return [];
    final safe = term.replaceAll('%', r'\%').replaceAll('_', r'\_');
    final categories = await client.from('menu_categories').select('id').eq('is_active', true).ilike('name', '%$safe%').limit(30);
    final categoryIds = List<Map<String,dynamic>>.from(categories).map((row) => row['id'].toString()).toList();
    final restaurantRows = await client.from('restaurants').select().eq('is_active', true).ilike('name', '%$safe%').limit(20);
    final mealRows = await client.from('menu_items').select('*, restaurants!inner(id,name,is_active)').eq('is_available', true).eq('restaurants.is_active', true).ilike('name', '%$safe%').limit(30);
    final categoryMeals = categoryIds.isEmpty
      ? <Map<String,dynamic>>[]
      : List<Map<String,dynamic>>.from(await client.from('menu_items').select('*, restaurants!inner(id,name,is_active)').eq('is_available', true).eq('restaurants.is_active', true).inFilter('category_id', categoryIds).limit(30));
    final rows = <Map<String, dynamic>>[];
    for (final row in List<Map<String, dynamic>>.from(restaurantRows)) {
      rows.add({...row, '_kind': 'restaurant'});
    }
    final seenMeals = <String>{};
    for (final row in [...List<Map<String, dynamic>>.from(mealRows), ...categoryMeals]) {
      if (seenMeals.add(row['id'].toString())) rows.add({...row, '_kind': 'meal'});
    }
    return rows;
  }

  static Future<List<Map<String, dynamic>>> categories() async {
    final rows = await client.from('menu_categories').select('id,name,sort_order,restaurant_id').eq('is_active', true).order('sort_order').limit(40);
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<List<Map<String, dynamic>>> favoriteRestaurants() async {
    final rows = await client.from('favorites').select('restaurant_id, restaurants(*)').eq('customer_id', user!.id).order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows).map((row) {
      final restaurant = row['restaurants'];
      return restaurant is Map<String, dynamic> ? restaurant : Map<String, dynamic>.from(restaurant as Map);
    }).toList();
  }

  static Future<bool> isFavorite(String restaurantId) async {
    final rows = await client.from('favorites').select('restaurant_id').eq('customer_id', user!.id).eq('restaurant_id', restaurantId).limit(1);
    return rows.isNotEmpty;
  }

  static Future<void> toggleFavorite(String restaurantId) async {
    final rows = await client.from('favorites').select('restaurant_id').eq('customer_id', user!.id).eq('restaurant_id', restaurantId).limit(1);
    if (rows.isNotEmpty) {
      await client.from('favorites').delete().eq('customer_id', user!.id).eq('restaurant_id', restaurantId);
    } else {
      await client.from('favorites').insert({'customer_id': user!.id, 'restaurant_id': restaurantId});
    }
  }

  static Future<List<Map<String, dynamic>>> myNotifications() async {
    final rows = await client.from('notifications').select().eq('user_id', user!.id).order('created_at', ascending: false).limit(100);
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<void> markNotificationRead(String id) async {
    await client.from('notifications').update({'read_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id).eq('user_id', user!.id);
  }

  static Future<void> submitReview({required String orderId, required String restaurantId, required int rating, required String comment}) async {
    await client.from('reviews').upsert({
      'order_id': orderId,
      'customer_id': user!.id,
      'restaurant_id': restaurantId,
      'rating': rating,
      'comment': comment.trim(),
    }, onConflict: 'order_id');
  }

  static Future<List<Map<String, dynamic>>> mySupportTickets() async {
    final rows = await client.from('support_tickets').select().eq('user_id', user!.id).order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<void> createSupportTicket({required String subject, required String message}) async {
    await client.from('support_tickets').insert({
      'user_id': user!.id,
      'subject': subject.trim(),
      'message': message.trim(),
    });
  }

  static Future<List<Map<String, dynamic>>> adminOrders() async {
    final rows = await client.from('orders').select('*, restaurants(name)').order('created_at', ascending: false).limit(500);
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<List<Map<String, dynamic>>> adminSupportTickets() async {
    final rows = await client.from('support_tickets').select('*, profiles(full_name,phone)').order('created_at', ascending: false).limit(200);
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<void> replySupportTicket(String id, String reply, String status) async {
    await client.from('support_tickets').update({
      'admin_reply': reply.trim(),
      'status': status,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  static Future<void> claimOrder(String orderId) async {
    await client.rpc(
      'claim_delivery_order',
      params: {'p_order_id': orderId},
    );
  }
}
