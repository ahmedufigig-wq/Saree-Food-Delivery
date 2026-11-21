import 'package:flutter_test/flutter_test.dart';
import 'package:saree/features/courier/courier_tracking_policy.dart';

void main() {
  group('CourierTrackingPolicy', () {
    test('allows sharing only for assigned and picked-up orders', () {
      expect(CourierTrackingPolicy.canShareStatus('assigned'), isTrue);
      expect(CourierTrackingPolicy.canShareStatus('picked_up'), isTrue);
      expect(CourierTrackingPolicy.canShareStatus('pending'), isFalse);
      expect(CourierTrackingPolicy.canShareStatus('preparing'), isFalse);
      expect(CourierTrackingPolicy.canShareStatus('delivered'), isFalse);
      expect(CourierTrackingPolicy.canShareStatus('cancelled'), isFalse);
    });

    test('normalizes status text', () {
      expect(CourierTrackingPolicy.canShareStatus(' ASSIGNED '), isTrue);
      expect(CourierTrackingPolicy.canShareStatus('Picked_Up'), isTrue);
    });

    test('requires at least one active order', () {
      expect(CourierTrackingPolicy.canShare([
        {'status': 'pending'},
        {'status': 'delivered'},
      ]), isFalse);
      expect(CourierTrackingPolicy.canShare([
        {'status': 'pending'},
        {'status': 'picked_up'},
      ]), isTrue);
    });
  });
}
