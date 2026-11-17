import http from 'k6/http';
import { check, sleep } from 'k6';

// Run only against a staging project with a dedicated test account.
// Required: SUPABASE_URL, SUPABASE_ANON_KEY, USER_JWT, RESTAURANT_ID, MENU_ITEM_ID.
// Optional: VUS (default 10), ITERATIONS (default 1).
export const options = {
  scenarios: {
    simultaneous_orders: {
      executor: 'shared-iterations',
      vus: Number(__ENV.VUS || 10),
      iterations: Number(__ENV.ITERATIONS || 10),
      maxDuration: '90s',
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.05'],
    http_req_duration: ['p(95)<2500'],
  },
};

export default function () {
  const url = `${__ENV.SUPABASE_URL}/rest/v1/rpc/create_order_with_gps`;
  const payload = JSON.stringify({
    p_restaurant_id: __ENV.RESTAURANT_ID,
    p_customer_name: `Load Test ${__VU}-${__ITER}`,
    p_customer_phone: `700${String(__VU).padStart(3, '0')}${String(__ITER).padStart(2, '0')}`,
    p_delivery_address: 'عنوان اختبار الأداء - رداع',
    p_items: [{ menu_item_id: __ENV.MENU_ITEM_ID, quantity: 1 }],
    p_delivery_latitude: null,
    p_delivery_longitude: null,
    p_notes: 'K6 STAGING LOAD TEST - delete test orders after validation',
  });
  const response = http.post(url, payload, {
    headers: {
      'Content-Type': 'application/json',
      apikey: __ENV.SUPABASE_ANON_KEY,
      Authorization: `Bearer ${__ENV.USER_JWT}`,
    },
  });
  check(response, {
    'order RPC returned success': (r) => r.status === 200 && !!r.body,
  });
  sleep(0.2);
}
