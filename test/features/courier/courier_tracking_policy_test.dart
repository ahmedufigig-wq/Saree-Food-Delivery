import 'package:flutter_test/flutter_test.dart';
import 'package:saree/features/courier/courier_tracking_policy.dart';

void main() {
  group('CourierTrackingPolicy', () {
    test('allows only assigned and picked_up statuses', () {
      expect(CourierTrackingPolicy.canShareStatus('assigned'), isTrue);
      expect(CourierTrackingPolicy.canShareStatus('picked_up'), isTrue);
      expect(CourierTrackingPolicy.canShareStatus('pending'), isFalse);
      expect(CourierTrackingPolicy.canShareStatus('accepted'), isFalse);
      expect(CourierTrackingPolicy.canShareStatus('preparing'), isFalse);
      expect(CourierTrackingPolicy.canShareStatus('delivered'), isFalse);
      expect(CourierTrackingPolicy.canShareStatus('cancelled'), isFalse);
    });

    test('normalizes status values', () {
      expect(CourierTrackingPolicy.canShareStatus(' PICKED_UP '), isTrue);
      expect(CourierTrackingPolicy.canShareStatus(null), isFalse);
    });

    test('requires at least one active courier order', () {
      expect(
        CourierTrackingPolicy.canShare([
          {'status': 'delivered'},
          {'status': 'assigned'},
        ]),
        isTrue,
      );
      expect(
        CourierTrackingPolicy.canShare([
          {'status': 'pending'},
          {'status': 'cancelled'},
        ]),
        isFalse,
      );
      expect(CourierTrackingPolicy.canShare(const []), isFalse);
    });
  });
}
