# Load measurement

This is the first measurement of the deployed application under a small load. Its purpose is to have the tool, a script and a first number in place before real features appear; later measurements are added to the table at the end.

The tool is [k6](https://k6.io) 2.4.0. It is started through Docker, so nothing is installed on the computer.

## What is measured

The script [`load/first-measurement.js`](../load/first-measurement.js): five users at once for 30 seconds. Each of them asks for the list of languages (a request that reads the database), then for the health check, then waits a second and starts again.

Before the measurement the script sends waking requests: one for the health check and four for the list of languages. The free service on Render stops after 15 minutes without requests, and after any restart nothing in the application is warm yet. These requests are not counted in the result; the time of the first request of each kind is reported apart, as the cost of a cold start.

## Limits

The run fails when a limit is broken.

| What | Limit | Where it comes from |
|---|---|---|
| Share of failed requests | below 1 % | A working value for the first measurement |
| Response time of 95 % of the requests | below 1 second | A working value. The Business Analysis block allows 2.5 seconds to show a page; a request to the server is only a part of that time |
| Checks of the content of the responses | all pass | A response with the right status and the wrong content, such as an empty list of languages, is a failure too |

## How to repeat

Docker must be running. In the root of the repository, in PowerShell:

```
docker run --rm -e ILP_BASE_URL=https://ilp-backend-7jv7.onrender.com -v "${PWD}\load:/scripts:ro" grafana/k6:2.4.0 run /scripts/first-measurement.js
```

On Linux or macOS the path is written as `"$PWD/load:/scripts:ro"`. The address of the application is passed in `ILP_BASE_URL`; the script holds no address of its own.

## Results

All measurements so far: Render free plan (512 MB, 0.1 CPU) and Neon free plan, both in Frankfurt; the requests are sent from a home computer in Vilnius, so the time includes the way through the internet and back.

The numbers are those of the measurement only: k6 prints them in the lines marked `scenario:readers`, and the waking requests are not in them. Requests per second are the requests of the measurement divided by its 30 seconds.

| Date | State of the application | Requests | Requests per second | Response time: median | Response time: 95 % | Failed requests | First requests, before the measurement | Limits |
|---|---|---|---|---|---|---|---|---|
| 23.11.2026, 11:01 | commit `89e364d`, in use for several minutes | 250 | 8.3 | list of languages 99 ms, health check 96 ms | list of languages 216 ms, health check 195 ms | 0 of 250 | not counted apart yet | kept |
| 23.11.2026, 15:10 | commit `05ed763`, a few minutes after a restart by a new deployment | 156 | 5.2 | list of languages 76 ms, health check 75 ms | list of languages 11.3 s, health check 295 ms | 0 of 156 | not counted apart yet; the script woke the service with the health check only | broken: response time of the list of languages |
| 23.11.2026, 15:15 | the same commit, warm; the script with the waking requests | 264 | 8.8 | list of languages 66 ms, health check 65 ms | list of languages 158 ms, health check 108 ms | 0 of 264 | health check 87 ms, list of languages 84 ms: the application was already warm | kept |

## What the second measurement showed

In the measurement at 15:10 the first five requests for the list of languages, sent at once, took about 11.5 seconds each; all later requests were as fast as usual. The application had been restarted by a new deployment a few minutes earlier: its connections to the database were not open yet and its code was not warm, and the free plan gives it a tenth of a processor. The cause is an estimate made from outside; the request log of the platform was not read.

Two things follow from it:

- The script now sends the waking requests described above, so the measurement shows the usual speed and the cold start is reported apart.
- The cold start itself stays: on the free plan the first request that reads the database after a restart takes about 11.5 seconds, and after 15 minutes without requests the service also needs up to a minute to start. The first request after such a sleep has not been measured yet.
