/// Defines when a courier is allowed to share a live delivery location.
class CourierTrackingPolicy {
  static const Set<String> activeStatuses = {'assigned', 'picked_up'};

  static bool canShareStatus(Object? rawStatus) {
    final status = rawStatus?.toString().trim().toLowerCase() ?? '';
    return activeStatuses.contains(status);
  }

  static bool canShare(Iterable<Map<String, dynamic>> orders) {
    return orders.any((order) => canShareStatus(order['status']));
  }
}
