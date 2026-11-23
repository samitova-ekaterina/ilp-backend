# Load measurement

This is the first measurement of the deployed application under a small load. Its purpose is to have the tool, a script and a first number in place before real features appear; later measurements are added to the table at the end.

The tool is [k6](https://k6.io) 2.4.0. It is started through Docker, so nothing is installed on the computer.

## What is measured

The script [`load/first-measurement.js`](../load/first-measurement.js): five users at once for 30 seconds. Each of them asks for the list of languages (a request that reads the database), then for the health check, then waits a second and starts again.

Before the measurement one request wakes the service: the free service on Render stops after 15 minutes without requests. This request is not counted in the result.

## Limits

The run fails when a limit is broken.

| What | Limit | Where it comes from |
|---|---|---|
| Share of failed requests | below 1 % | A working value for the first measurement |
| Response time of 95 % of the requests | below 1 second | A working value. The Business Analysis block allows 2.5 seconds to show a page; a request to the server is only a part of that time |

## How to repeat

Docker must be running. In the root of the repository, in PowerShell:

```
docker run --rm -e ILP_BASE_URL=https://ilp-backend-7jv7.onrender.com -v "${PWD}\load:/scripts:ro" grafana/k6:2.4.0 run /scripts/first-measurement.js
```

On Linux or macOS the path is written as `"$PWD/load:/scripts:ro"`. The address of the application is passed in `ILP_BASE_URL`; the script holds no address of its own.

## Results

| Date | Version of the application | Requests | Requests per second | Response time: median | Response time: 95 % | Failed requests | Limits |
|---|---|---|---|---|---|---|---|
| 23.11.2026 | commit `89e364d`, Render free plan (512 MB, 0.1 CPU), Neon free plan, both in Frankfurt | 250 in 30 seconds | 8.1 | 98 ms | list of languages 216 ms, health check 195 ms | 0 of 250 | kept |

The requests were sent from a home computer in Vilnius, so the time includes the way through the internet to Frankfurt and back.
