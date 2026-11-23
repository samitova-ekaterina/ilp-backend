import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend } from 'k6/metrics';

// The address of the deployed application comes from outside: the script holds no address of its own.
const BASE_URL = __ENV.ILP_BASE_URL;

// The first requests of a run are counted apart: right after a start of the application they show the cold start.
const firstHealth = new Trend('first_health_of_the_run', true);
const firstLanguages = new Trend('first_languages_of_the_run', true);

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

// A body that is not JSON is wrong content, not a reason to stop the script with a parsing error.
function bodyOf(response) {
    try {
        const body = response.json();
        return body === undefined ? null : body;
    } catch (e) {
        return null;
    }
}

// The waking requests and the measurement judge the content of an answer by the same two rules.
function saysUp(response) {
    const body = bodyOf(response);
    return response.status === 200 && body !== null && body.status === 'UP';
}

function listsLanguages(response) {
    const body = bodyOf(response);
    return (
        response.status === 200 &&
        Array.isArray(body) &&
        body.length > 0 &&
        body.every((language) => language !== null && typeof language.code === 'string' && typeof language.name === 'string')
    );
}

// The free service sleeps after 15 minutes without requests, and after a restart nothing in it is warm yet.
export function setup() {
    if (!BASE_URL) {
        throw new Error('Set ILP_BASE_URL to the address of the deployed application');
    }
    const health = http.get(`${BASE_URL}/actuator/health`, { timeout: '180s', tags: { name: 'wake-up' } });
    if (!saysUp(health)) {
        throw new Error(`The application did not wake up: status ${health.status}, and the health check must say UP`);
    }
    firstHealth.add(health.timings.duration);

    // The first request that reads the database opens the connections; three more let the application settle.
    for (let i = 0; i < 4; i++) {
        const languages = http.get(`${BASE_URL}/api/v1/languages`, { timeout: '60s', tags: { name: 'wake-up' } });
        if (!listsLanguages(languages)) {
            throw new Error(`The list of languages did not answer with languages: status ${languages.status}`);
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
        'the list of languages holds languages with a code and a name': listsLanguages,
    });

    const health = http.get(`${BASE_URL}/actuator/health`, { tags: { name: 'health' } });
    check(health, {
        'the health check answers 200': (r) => r.status === 200,
        'the health check says UP': saysUp,
    });

    // A reader does not click without a pause: one second between two rounds of requests.
    sleep(1);
}
