import http from 'k6/http';
import { check } from 'k6';
import { Rate, Trend } from 'k6/metrics';

// SAFETY: Run ONLY against a staging Supabase project and a test restaurant.
// This script creates one real test order per virtual user.
const failures = new Rate('order_create_failures');
const createDuration = new Trend('order_create_duration');

export const options = {
  scenarios: {
    ten_customers_at_once: {
      executor: 'per-vu-iterations',
      vus: 10,
      iterations: 1,
      maxDuration: '60s',
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.01'],
    order_create_failures: ['rate<0.01'],
    order_create_duration: ['p(95)<3000'],
  },
};

const baseUrl = (__ENV.SUPABASE_URL || '').replace(/\/$/, '');
const anonKey = __ENV.SUPABASE_ANON_KEY || '';
const accessToken = __ENV.TEST_CUSTOMER_ACCESS_TOKEN || '';
const restaurantId = __ENV.TEST_RESTAURANT_ID || '';
const menuItemId = __ENV.TEST_MENU_ITEM_ID || '';

export function setup() {
  if (!baseUrl.startsWith('https://') || !anonKey || !accessToken ||
      !restaurantId || !menuItemId) {
    throw new Error(
      'Set SUPABASE_URL, SUPABASE_ANON_KEY, TEST_CUSTOMER_ACCESS_TOKEN, ' +
      'TEST_RESTAURANT_ID and TEST_MENU_ITEM_ID. Use staging only.'
    );
  }
}

export default function () {
  const payload = {
    p_restaurant_id: restaurantId,
    p_customer_name: 'عميل اختبار الضغط',
    p_customer_phone: '777000000',
    p_delivery_address: 'عنوان تجريبي لا يستخدم للتوصيل الفعلي - رداع',
    p_items: [{ menu_item_id: menuItemId, quantity: 1 }],
    p_delivery_latitude: null,
    p_delivery_longitude: null,
    p_notes: 'اختبار ضغط آلي - لا يتم التوصيل',
  };

  const response = http.post(
    baseUrl + '/rest/v1/rpc/create_order_with_gps',
    JSON.stringify(payload),
    {
      headers: {
        apikey: anonKey,
        Authorization: 'Bearer ' + accessToken,
        'Content-Type': 'application/json',
      },
      tags: { endpoint: 'create_order_with_gps' },
    }
  );

  const ok = check(response, {
    'order RPC returns HTTP 200': (r) => r.status === 200,
    'order RPC returns an order id': (r) =>
      typeof r.body === 'string' && r.body.length > 10,
  });
  failures.add(!ok);
  createDuration.add(response.timings.duration);
}
