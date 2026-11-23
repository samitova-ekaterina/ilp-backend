# Load measurement

This is the first measurement of the deployed application under a small load. Its purpose is to have the tool, a script and a first number in place before real features appear; later measurements are added to the table at the end.

The tool is [k6](https://k6.io) 2.4.0. It is started through Docker, so nothing is installed on the computer.

## What is measured

The script [`load/first-measurement.js`](../load/first-measurement.js): five users at once for 30 seconds. Each of them asks for the list of languages (a request that reads the database), then for the health check, then waits a second and starts again.

Before the measurement the script sends waking requests: one for the health check and four for the list of languages. The free service on Render stops after 15 minutes without requests, and after any restart nothing in the application is warm yet. These requests are not counted in the result, but their content is checked by the same rules as in the measurement: a wrong answer stops the run before the measurement begins. The time of the first request of each kind is reported apart, as the first requests of the run: they show a cold start only when the application has just started or woken up, otherwise they show the usual speed.

## Limits

The run fails when a limit is broken.

| What | Limit | Where it comes from |
|---|---|---|
| Share of failed requests | below 1 % | A working value for the first measurement |
| Response time of 95 % of the requests | below 1 second | A working value. The Business Analysis block allows 2.5 seconds to show a page; a request to the server is only a part of that time |
| Checks of the content of the responses | all pass | A response with the right status and the wrong content is a failure too: the list of languages must be a list that is not empty, in which every language has a code and a name, and the health check must say `UP`. The exact languages are checked by the integration test of the list, not here |

## How to repeat

Docker must be running. In the root of the repository, in PowerShell:

```
docker run --rm -e ILP_BASE_URL=https://ilp-backend-7jv7.onrender.com -v "${PWD}\load:/scripts:ro" grafana/k6:2.4.0 run /scripts/first-measurement.js
```

On Linux or macOS the path is written as `"$PWD/load:/scripts:ro"`. The address of the application is passed in `ILP_BASE_URL`; the script holds no address of its own.

## Results

All measurements so far: Render free plan (512 MB, 0.1 CPU) and Neon free plan, both in Frankfurt; the requests are sent from a home computer in Vilnius, so the time includes the way through the internet and back.

The numbers are those of the measurement only: k6 prints them in the lines marked `scenario:readers`, and the waking requests are not in them.

Requests per second are the requests of the measurement divided by the 30 seconds set in the script. The real period is a little longer, because a round of requests that began before the 30 seconds were over is allowed to finish; a round takes a little over a second, so the number in the table is a few per cent too high. k6 prints a lower number of its own (8.3 for the measurement at 15:15, 1.6 for the one at 16:02), because it divides by the whole run together with the waking requests.

| Date | State of the application | Requests | Requests per second | Response time: median | Response time: 95 % | Failed requests | First requests of the run | Limits |
|---|---|---|---|---|---|---|---|---|
| 23.11.2026, 11:01 | commit `89e364d`, in use for several minutes | 250 | 8.3 | list of languages 99 ms, health check 96 ms | list of languages 216 ms, health check 195 ms | 0 of 250 | not counted apart yet | kept |
| 23.11.2026, 15:10 | commit `05ed763`, five minutes after its deployment went live | 156 | 5.2 | list of languages 76 ms, health check 75 ms | list of languages 11.3 s, health check 295 ms | 0 of 156 | not counted apart yet; the script woke the service with the health check only | broken: response time of the list of languages |
| 23.11.2026, 15:15 | the same commit, ten minutes after its deployment went live; the script with the waking requests | 264 | 8.8 | list of languages 66 ms, health check 65 ms | list of languages 158 ms, health check 108 ms | 0 of 264 | health check 87 ms, list of languages 84 ms: no slow first request in this run | kept |
| 23.11.2026, 16:02 | commit `f168faa`, 34 minutes after its deployment went live; no requests from our side since then | 254 | 8.5 | list of languages 76 ms, health check 76 ms | list of languages 258 ms, health check 197 ms | 0 of 254 | health check 1 min 58 s, list of languages 8.2 s | kept |

## What the second measurement showed

Observed:

- In the measurement at 15:10 the first five requests for the list of languages, sent at once, took about 11.5 seconds each. All later requests of that run were as fast as usual.
- The list of events of the service on Render shows that the deployment of commit `05ed763` started at 15:02 and went live at 15:05, and that the next deployment started at 15:25; no other event stands between them in the list. So the measurement at 15:10 began five minutes after a new copy of the application had started.
- In the measurement at 15:15 the first requests of the run took 87 ms and 84 ms.

Assumed, not checked:

- That those five requests were the first ones to read the database in the new copy of the application. The script of that time woke the service with the health check only, but the request log of the platform was not read, so requests from elsewhere are not excluded.
- The cause of the 11.5 seconds. The likely one is a cold start: the code of the request ran for the first time, five requests at once shared the tenth of a processor that the free plan gives, and connections to the database were still being opened. None of these parts was measured apart.

What was done and what stays open:

- The script now sends the waking requests described above, so the measurement shows the usual speed, and the first requests of the run are reported apart.
- At that moment a single first request after a start and the first request after 15 minutes without requests had not been measured. The measurement at 16:02 gave both numbers.

## What the measurement at 16:02 showed

Observed:

- The first request of the run, for the health check, was answered in 1 minute 58 seconds.
- The first request for the list of languages, sent alone right after it, took 8.2 seconds; three more such requests followed before the measurement.
- The measurement itself kept all limits: 254 requests, none failed, 95 % of the responses within 258 ms.
- The list of events of the service on Render shows that the deployment of commit `f168faa` went live at 15:28. No requests were sent from our side between that moment and the run.

Assumed, not checked:

- That the service had been stopped for lack of requests and that the 1 minute 58 seconds is the time of its start. No event about the stop was looked up, and requests from elsewhere are not excluded. Render says that a free service needs [about a minute](https://render.com/docs/free) to start again; here it was twice as long.
- What the 8.2 seconds consist of: the same likely parts as in the second measurement, none measured apart.

What follows:

- Whoever opens the application after a pause waits about two minutes for the first answer and several seconds more for the first data from the database. After that the application is as fast as usual.
- This has been measured once. Whether to warm the application at start-up, and what to tell the people who will open it, is decided before the submission to the experts.
