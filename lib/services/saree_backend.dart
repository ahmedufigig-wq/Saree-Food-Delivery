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

  // Convert backend and network errors to clear Arabic messages.
  static String arabicError(Object? error) {
    final raw = error?.toString() ?? '';
    final value = raw.toLowerCase();
    if (value.contains('email rate limit exceeded') ||
        value.contains('over_email_send_rate_limit')) {
      return 'خدمة إرسال رسائل التحقق وصلت إلى حدها المؤقت. لا تكرر المحاولة الآن؛ انتظر حتى يتجدد الحد أو استخدم الإدارة لإكمال التسجيل. يحتاج التطبيق إلى خدمة بريد مخصصة لإتاحة التسجيل للجميع.';
    }
    if (value.contains('too many requests') || value.contains('rate limit') ||
        value.contains('statuscode: 429')) {
      return 'عدد المحاولات كبير خلال وقت قصير. انتظر قليلًا ثم حاول مرة واحدة.';
    }
    if (value.contains('otp_expired') || value.contains('token has expired')) {
      return 'انتهت صلاحية رمز التحقق. اطلب رمزًا جديدًا ثم حاول مرة أخرى.';
    }
    if (value.contains('user not found') || value.contains('no rows')) {
      return 'لم نعثر على الحساب أو البيانات المطلوبة.';
    }
    if (value.contains('violates foreign key') || value.contains('foreign key')) {
      return 'تعذر إكمال العملية لارتباط البيانات بسجل آخر. حدّث الصفحة وحاول مجددًا.';
    }
    if (value.contains('email_address_not_authorized')) {
      return 'هذا البريد غير مسموح له باستقبال رسائل التسجيل حاليًا. يلزم إعداد خدمة بريد موثوقة للتطبيق.';
    }
    if (value.contains('user already registered') ||
        value.contains('already been registered') ||
        value.contains('user_already_exists')) {
      return 'هذا البريد مسجل بالفعل. سجّل الدخول بدل إنشاء حساب جديد.';
    }
    if (value.contains('invalid login credentials')) {
      return 'البريد الإلكتروني أو كلمة المرور غير صحيحة.';
    }
    if (value.contains('email not confirmed')) {
      return 'لم يتم تأكيد البريد الإلكتروني بعد. افتح رسالة التأكيد ثم حاول تسجيل الدخول.';
    }
    if (value.contains('password should be') || value.contains('weak_password')) {
      return 'كلمة المرور ضعيفة. استخدم كلمة مرور أقوى لا تقل عن 8 أحرف.';
    }
    if (value.contains('invalid email') || value.contains('email_address_invalid')) {
      return 'صيغة البريد الإلكتروني غير صحيحة.';
    }
    if (value.contains('network') || value.contains('socketexception') ||
        value.contains('failed host lookup') || value.contains('connection')) {
      return 'تعذر الاتصال بالإنترنت أو بالخادم. تحقق من اتصالك ثم أعد المحاولة.';
    }
    if (value.contains('jwt') || value.contains('not authenticated') ||
        value.contains('unauthorized')) {
      return 'انتهت جلسة الدخول. سجّل الدخول مرة أخرى.';
    }
    if (value.contains('permission denied') || value.contains('row-level security') ||
        value.contains('rls')) {
      return 'ليست لديك صلاحية لتنفيذ هذا الإجراء. تحقق من نوع حسابك واعتماده.';
    }
    if (value.contains('duplicate key') || value.contains('already exists')) {
      return 'هذه البيانات مسجلة من قبل.';
    }
    return 'حدث خطأ غير متوقع. حاول مرة أخرى، وإذا تكرر تواصل مع الدعم.';
  }

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

  static String _courierEmailFromPhone(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    return 'courier_${digits}@couriers.saree.app';
  }

  static Future<void> signIn(String emailOrPhone, String password) async {
    final input = emailOrPhone.trim();
    final email = input.contains('@') ? input : _courierEmailFromPhone(input);
    await client.auth.signInWithPassword(email: email, password: password);
  }

  static Future<void> createRestaurantCourierAccount({
    required String restaurantId,
    required String fullName,
    required String phone,
    required String password,
  }) async {
    final response = await client.functions.invoke(
      'restaurant-create-courier',
      body: {
        'restaurant_id': restaurantId,
        'full_name': fullName.trim(),
        'phone': phone.trim(),
        'password': password,
      },
    );
    if (response.status < 200 || response.status >= 300) {
      final data = response.data;
      final message = data is Map ? data['message'] ?? data['error'] : data;
      throw Exception(message?.toString() ?? 'تعذر إنشاء حساب المندوب');
    }
  }

  static Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
    required String phone,
    String requestedRole = 'customer',
  }) async {
    if (!['customer', 'courier', 'restaurant_owner'].contains(requestedRole)) {
      throw ArgumentError('نوع الحساب غير صالح');
    }
    await client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {
        'full_name': fullName.trim(),
        'phone': phone.trim(),
        'requested_role': requestedRole,
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
    double? latitude,
    double? longitude,
  }) async {
    final values = {
      'customer_id': user!.id,
      'label': label.trim(),
      'address_text': addressText.trim(),
      'area': area.trim(),
      'is_default': isDefault,
      'latitude': latitude,
      'longitude': longitude,
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
        .select('id, full_name, phone, role, approval_status, approval_note, created_at')
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
    double? deliveryLatitude,
    double? deliveryLongitude,
    String notes = '',
  }) async {
    final result = await client.rpc('create_order_with_gps', params: {
      'p_restaurant_id': restaurantId,
      'p_customer_name': customerName,
      'p_customer_phone': customerPhone,
      'p_delivery_address': address,
      'p_items': items,
      'p_delivery_latitude': deliveryLatitude,
      'p_delivery_longitude': deliveryLongitude,
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

  static Stream<List<Map<String, dynamic>>> restaurantOrdersStream(String restaurantId) {
    return client.from('orders').stream(primaryKey: ['id']).eq('restaurant_id', restaurantId).order('created_at', ascending: false);
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

  static Future<List<Map<String, dynamic>>> availableCouriersForRestaurant(String restaurantId) async {
    final rows = await client.rpc('available_couriers_for_restaurant', params: {
      'p_restaurant_id': restaurantId,
    });
    return List<Map<String, dynamic>>.from(rows as List);
  }

  static Future<List<Map<String, dynamic>>> restaurantCourierTeam(String restaurantId) async {
    final rows = await client.rpc('restaurant_courier_team', params: {
      'p_restaurant_id': restaurantId,
    });
    return List<Map<String, dynamic>>.from(rows as List);
  }

  static Future<void> addRestaurantCourier(String restaurantId, String phone) async {
    await client.rpc('restaurant_add_courier', params: {
      'p_restaurant_id': restaurantId,
      'p_phone': phone.trim(),
    });
  }

  static Future<void> removeRestaurantCourier(String restaurantId, String courierId) async {
    await client.rpc('restaurant_remove_courier', params: {
      'p_restaurant_id': restaurantId,
      'p_courier_id': courierId,
    });
  }

  static Future<void> assignCourierToOrder({
    required String orderId,
    required String courierId,
  }) async {
    await client.rpc('assign_order_courier', params: {
      'p_order_id': orderId,
      'p_courier_id': courierId,
    });
  }

  static Future<List<Map<String, dynamic>>> courierOrderItems(String orderId) async {
    final rows = await client
        .from('order_items')
        .select('item_name, quantity, unit_price_yer, line_total_yer')
        .eq('order_id', orderId)
        .order('item_name');
    return List<Map<String, dynamic>>.from(rows);
  }

  static Stream<List<Map<String, dynamic>>> courierOrdersStream() {
    return client.from('orders').stream(primaryKey: ['id']).eq('courier_id', user!.id).order('created_at', ascending: false);
  }

  static Future<List<Map<String, dynamic>>> courierOrders() async {
    final rows = await client
        .from('orders')
        .select()
        .eq('courier_id', user!.id)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  // Orders are assigned by each restaurant to one of its own couriers.
  // Couriers no longer browse or claim a global pool of unassigned orders.
  static Future<List<Map<String, dynamic>>> availableCourierOrders() async => [];

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
    final rows = await client.from('profiles').select('id, full_name, phone, role, approval_status, approval_note, created_at').order('created_at', ascending: false).limit(200);
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

  static Future<void> bulkSaveMenuItems({
    required String restaurantId,
    required List<Map<String, dynamic>> items,
  }) async {
    if (items.isEmpty) return;
    if (items.length > 100) throw ArgumentError('يمكن إضافة 100 وجبة كحد أقصى في الدفعة الواحدة.');
    final rows = items.map((item) => {
      'restaurant_id': restaurantId,
      'name': item['name'].toString().trim(),
      'description': (item['description'] ?? '').toString().trim(),
      'price_yer': item['price_yer'],
      'is_available': item['is_available'] == true,
    }).toList();
    await client.from('menu_items').insert(rows);
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

  static Future<List<Map<String, dynamic>>> activePromotions() async {
    final rows = await client.from('promotions').select().eq('is_active', true).lte('starts_at', DateTime.now().toUtc().toIso8601String()).order('starts_at', ascending: false).limit(10);
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<List<Map<String, dynamic>>> restaurantReviews(String restaurantId) async {
    final rows = await client.from('reviews').select('rating,comment,created_at,profiles(full_name)').eq('restaurant_id', restaurantId).eq('is_visible', true).order('created_at', ascending: false).limit(30);
    return List<Map<String, dynamic>>.from(rows);
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


  static Future<Map<String, dynamic>> walletBalance() async {
    final rows = await client.from('wallet_balances').select('balance_yer').eq('user_id', user!.id).maybeSingle();
    return Map<String, dynamic>.from(rows ?? {'balance_yer': 0});
  }

  static Future<List<Map<String, dynamic>>> walletTransactions() async {
    final rows = await client.from('wallet_transactions').select('id,amount_yer,kind,note,created_at').eq('user_id', user!.id).order('created_at', ascending: false).limit(100);
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<void> reviewUser(String userId, String decision, {String note = ''}) async {
    await client.rpc('admin_review_user', params: {
      'p_user_id': userId,
      'p_decision': decision,
      'p_note': note,
    });
  }

  static Future<void> claimOrder(String orderId) async {
    await client.rpc(
      'claim_delivery_order',
      params: {'p_order_id': orderId},
    );
  }
}
