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
    final rows = await client
        .from('menu_items')
        .select()
        .eq('restaurant_id', restaurantId)
        .eq('is_available', true)
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

  static Future<void> claimOrder(String orderId) async {
    await client.rpc(
      'claim_delivery_order',
      params: {'p_order_id': orderId},
    );
  }
}
