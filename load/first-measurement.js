import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend } from 'k6/metrics';

// The address of the deployed application comes from outside: the script holds no address of its own.
const BASE_URL = __ENV.ILP_BASE_URL;

// The first requests after a pause are counted apart: they show the cold start, not the usual speed.
const firstHealth = new Trend('first_health_after_pause', true);
const firstLanguages = new Trend('first_languages_after_pause', true);

export const options = {
    // The waking requests may wait up to 420 seconds together, and k6 gives the whole setup only 60 unless told otherwise.
    setupTimeout: '450s',
    scenarios: {
        readers: {
            executor: 'constant-vus',
            vus: 5,
            duration: '30s',
        },
    },
    thresholds: {
        // Only the requests of the measurement itself count: the waking requests in setup() are left out.
        'http_req_failed{scenario:readers}': ['rate<0.01'],
        'http_req_duration{scenario:readers,name:languages}': ['p(95)<1000'],
        'http_req_duration{scenario:readers,name:health}': ['p(95)<1000'],
        // An answer with the right status and the wrong content is a failure too.
        'checks{scenario:readers}': ['rate==1'],
        // These two make k6 print the numbers of the measurement apart from the waking requests.
        'http_reqs{scenario:readers}': ['count>0'],
        'http_req_duration{scenario:readers}': ['p(95)<1000'],
    },
};

// The free service sleeps after 15 minutes without requests, and after a restart nothing in it is warm yet.
export function setup() {
    if (!BASE_URL) {
        throw new Error('Set ILP_BASE_URL to the address of the deployed application');
    }
    const health = http.get(`${BASE_URL}/actuator/health`, { timeout: '180s', tags: { name: 'wake-up' } });
    if (health.status !== 200) {
        throw new Error(`The application did not wake up: status ${health.status}`);
    }
    firstHealth.add(health.timings.duration);

    // The first request that reads the database opens the connections; three more let the application settle.
    for (let i = 0; i < 4; i++) {
        const languages = http.get(`${BASE_URL}/api/v1/languages`, { timeout: '60s', tags: { name: 'wake-up' } });
        if (languages.status !== 200) {
            throw new Error(`The list of languages did not answer: status ${languages.status}`);
        }
        if (i === 0) {
            firstLanguages.add(languages.timings.duration);
        }
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
