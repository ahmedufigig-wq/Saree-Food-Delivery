import 'dart:async';
import 'dart:io';

import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../services/saree_backend.dart';
import 'courier_tracking_policy.dart';

/// Owns the courier's foreground location stream and its server availability flag.
class CourierLocationService {
  StreamSubscription<Position>? _subscription;

  bool get isRunning => _subscription != null;

  Future<void> _requireActiveOrder() async {
    final orders = await SareeBackend.courierOrders();
    if (!CourierTrackingPolicy.canShare(orders)) {
      throw StateError('لا يمكن مشاركة الموقع قبل إسناد طلب توصيل نشط إليك');
    }
  }

  Future<void> start({
    required void Function(Position position) onPosition,
    required void Function(Object error) onUploadError,
    required void Function(Object error) onStreamError,
  }) async {
    if (_subscription != null) return;

    await _requireActiveOrder();

    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('فعّل خدمة الموقع GPS أولاً');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      throw StateError('اسمح للتطبيق بالوصول إلى الموقع أثناء استخدامه');
    }

    // Android 13+ requires runtime notification consent for a visible notification.
    // The foreground location service is started while the courier app is visible.
    if (Platform.isAndroid) {
      var notification = await Permission.notification.status;
      if (!notification.isGranted) {
        notification = await Permission.notification.request();
      }
      if (!notification.isGranted) {
        throw StateError('اسمح بإشعارات سريع لعرض تنبيه مشاركة الموقع أثناء التوصيل');
      }
    }

    // Recheck after permission prompts so a cancelled/reassigned order cannot start tracking.
    await _requireActiveOrder();

    final initialPosition = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
    await SareeBackend.updateCourierLocation(
      initialPosition.latitude,
      initialPosition.longitude,
    );
    onPosition(initialPosition);

    final LocationSettings settings = Platform.isAndroid
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 15,
            intervalDuration: const Duration(seconds: 15),
            foregroundNotificationConfig: ForegroundNotificationConfig(
              notificationTitle: 'سريع - مشاركة موقع المندوب',
              notificationText: 'يتم تحديث موقعك للعميل أثناء مهمة توصيل نشطة',
              notificationChannelName: 'تتبع التوصيل',
              notificationIcon: AndroidResource(
                name: 'ic_launcher',
                defType: 'mipmap',
              ),
              setOngoing: true,
            ),
          )
        : const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 15,
          );

    try {
      _subscription = Geolocator.getPositionStream(
        locationSettings: settings,
      ).listen(
        (position) {
          onPosition(position);
          unawaited(_publish(position, onUploadError));
        },
        onError: (Object error) {
          onStreamError(error);
          unawaited(stop().catchError(onUploadError));
        },
      );
    } catch (_) {
      await SareeBackend.stopCourierLocation();
      rethrow;
    }
  }

  Future<void> _publish(
    Position position,
    void Function(Object error) onUploadError,
  ) async {
    try {
      await SareeBackend.updateCourierLocation(
        position.latitude,
        position.longitude,
      );
    } catch (error) {
      onUploadError(error);
    }
  }

  Future<void> stop() async {
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    await SareeBackend.stopCourierLocation();
  }
}
