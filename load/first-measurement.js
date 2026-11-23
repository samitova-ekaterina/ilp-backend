import http from 'k6/http';
import { check, sleep } from 'k6';

// The address of the deployed application comes from outside: the script holds no address of its own.
const BASE_URL = __ENV.ILP_BASE_URL;

export const options = {
    scenarios: {
        readers: {
            executor: 'constant-vus',
            vus: 5,
            duration: '30s',
        },
    },
    thresholds: {
        // Only the requests of the measurement itself count: the waking request in setup() is left out.
        'http_req_failed{scenario:readers}': ['rate<0.01'],
        'http_req_duration{scenario:readers,name:languages}': ['p(95)<1000'],
        'http_req_duration{scenario:readers,name:health}': ['p(95)<1000'],
    },
};

// The free service sleeps after 15 minutes without requests: the first request wakes it and may take a minute.
export function setup() {
    if (!BASE_URL) {
        throw new Error('Set ILP_BASE_URL to the address of the deployed application');
    }
    const response = http.get(`${BASE_URL}/actuator/health`, { timeout: '180s', tags: { name: 'wake-up' } });
    if (response.status !== 200) {
        throw new Error(`The application did not wake up: status ${response.status}`);
    }
}

export default function () {
    const languages = http.get(`${BASE_URL}/api/v1/languages`, { tags: { name: 'languages' } });
    check(languages, {
        'the list of languages answers 200': (r) => r.status === 200,
        'the list of languages is not empty': (r) => r.status === 200 && r.json().length > 0,
    });

    const health = http.get(`${BASE_URL}/actuator/health`, { tags: { name: 'health' } });
    check(health, {
        'the health check answers 200': (r) => r.status === 200,
    });

    // A reader does not click without a pause: one second between two rounds of requests.
    sleep(1);
}
