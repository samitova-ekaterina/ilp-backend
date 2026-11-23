# Load measurement

This is the first measurement of the deployed application under a small load. Its purpose is to have the tool, a script and a first number in place before real features appear; later measurements are added to the table at the end.

The tool is [k6](https://k6.io) 2.4.0. It is started through Docker, so nothing is installed on the computer.

## What is measured

The script [`load/first-measurement.js`](../load/first-measurement.js): five users at once for 30 seconds. Each of them asks for the list of languages (a request that reads the database), then for the health check, then waits a second and starts again.

Before the measurement the script sends waking requests: one for the health check and four for the list of languages. The free service on Render stops after 15 minutes without requests, and after any restart nothing in the application is warm yet. These requests are not counted in the result. The time of the first request of each kind is reported apart, as the first requests of the run: they show a cold start only when the application has just started or woken up, otherwise they show the usual speed.

## Limits

The run fails when a limit is broken.

| What | Limit | Where it comes from |
|---|---|---|
| Share of failed requests | below 1 % | A working value for the first measurement |
| Response time of 95 % of the requests | below 1 second | A working value. The Business Analysis block allows 2.5 seconds to show a page; a request to the server is only a part of that time |
| Checks of the content of the responses | all pass | A response with the right status and the wrong content is a failure too: the list of languages must not be empty, and the health check must say `UP` |

## How to repeat

Docker must be running. In the root of the repository, in PowerShell:

```
docker run --rm -e ILP_BASE_URL=https://ilp-backend-7jv7.onrender.com -v "${PWD}\load:/scripts:ro" grafana/k6:2.4.0 run /scripts/first-measurement.js
```

On Linux or macOS the path is written as `"$PWD/load:/scripts:ro"`. The address of the application is passed in `ILP_BASE_URL`; the script holds no address of its own.

## Results

All measurements so far: Render free plan (512 MB, 0.1 CPU) and Neon free plan, both in Frankfurt; the requests are sent from a home computer in Vilnius, so the time includes the way through the internet and back.

The numbers are those of the measurement only: k6 prints them in the lines marked `scenario:readers`, and the waking requests are not in them.

Requests per second are the requests of the measurement divided by the 30 seconds set in the script. The real period is a little longer, because a round of requests that began before the 30 seconds were over is allowed to finish; a round takes a little over a second, so the number in the table is a few per cent too high. k6 prints a lower number of its own (8.3 for the measurement at 15:15), because it divides by the whole run together with the waking requests.

| Date | State of the application | Requests | Requests per second | Response time: median | Response time: 95 % | Failed requests | First requests of the run | Limits |
|---|---|---|---|---|---|---|---|---|
| 23.11.2026, 11:01 | commit `89e364d`, in use for several minutes | 250 | 8.3 | list of languages 99 ms, health check 96 ms | list of languages 216 ms, health check 195 ms | 0 of 250 | not counted apart yet | kept |
| 23.11.2026, 15:10 | commit `05ed763`, five minutes after its deployment went live | 156 | 5.2 | list of languages 76 ms, health check 75 ms | list of languages 11.3 s, health check 295 ms | 0 of 156 | not counted apart yet; the script woke the service with the health check only | broken: response time of the list of languages |
| 23.11.2026, 15:15 | the same commit, ten minutes after its deployment went live; the script with the waking requests | 264 | 8.8 | list of languages 66 ms, health check 65 ms | list of languages 158 ms, health check 108 ms | 0 of 264 | health check 87 ms, list of languages 84 ms: no slow first request in this run | kept |

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
- A slow first request has been seen once, with five requests at once. A single first request after a restart has not been measured.
- The first request after 15 minutes without requests has not been measured either. Render says that a free service needs [about a minute](https://render.com/docs/free) to start again.
