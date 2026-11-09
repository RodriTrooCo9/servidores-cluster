import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://backend-api.aplicaciones.svc.cluster.local:8000/api/v1/data';

export const options = {
  stages: [
    { duration: '30s', target: 30 },  // Ramp-up a 30 VUs
    { duration: '1m',  target: 90 },  // Crecimiento a 90 VUs
    { duration: '2m',  target: 150 }, // Carga sostenida a 150 VUs (50 VUs por nodo con parallelism: 3)
    { duration: '30s', target: 0 },   // Ramp-down
  ],
  thresholds: {
    http_req_failed: ['rate<0.01'],    // Fallos menores al 1%
    http_req_duration: ['p(95)<500'],  // 95% de peticiones bajo 500ms
  },
};

export default function () {
  const res = http.get(BASE_URL);
  check(res, {
    'HTTP 200': (r) => r.status === 200,
  });
  sleep(1);
}
