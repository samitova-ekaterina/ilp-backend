# API conventions

These rules apply to every request the server accepts. They are checked in code review; the error format is produced by one handler, `GlobalExceptionHandler`.

## Addresses

- Every address starts with `/api/v1`.
- A resource is named by a plural noun in lower case; words are joined by a hyphen: `/api/v1/languages`, `/api/v1/study-groups`.
- One item is addressed by its identifier: `/api/v1/materials/15`.
- An action that is not one of the five methods below is named by a noun: approving an exercise is `POST /api/v1/exercises/15/approval`.

## Methods

| Method | Meaning |
|---|---|
| `GET` | Reads; changes nothing |
| `POST` | Creates |
| `PUT` | Replaces an item as a whole |
| `PATCH` | Changes a part of an item |
| `DELETE` | Deletes |

## Status codes

| Code | When |
|---|---|
| 200 | Read or changed successfully |
| 201 | Created; the `Location` header holds the address of the new item |
| 204 | Done, there is nothing to return |
| 400 | The input did not pass validation or the request cannot be read |
| 401 | The user is not signed in |
| 403 | The user is signed in but has no right to do this |
| 404 | There is no such address or item |
| 409 | The request contradicts the current state |
| 415 | The type of the sent data is not supported |
| 500 | An unexpected error on the server |

An error is never returned with the code 200.

## Data

- Requests and responses are JSON.
- Field names are written in camel case: `createdAt`.
- Dates and times are strings in the ISO 8601 format, in UTC: `2026-11-21T12:00:00Z`.
- A long list is returned in pages: `?page=0&size=20&sort=createdAt,desc`. Reference lists, such as languages, are short and are returned as a whole.

## Request number

- The server gives every request a number and returns it in the `X-Request-Id` header of every response, successful or not.
- The number is always created by the server; a value sent by the client in this header is ignored.
- Every log line written while the request is processed carries this number.

## Errors

Every error has the same body, in the format of RFC 9457 (Problem Details for HTTP APIs), with the content type `application/problem+json`:

```json
{
  "title": "Not Found",
  "status": 404,
  "detail": "The requested address does not exist.",
  "instance": "/api/v1/nothing",
  "code": "common.not-found",
  "requestId": "d02b0360-f645-4e34-8808-b8d091ecf263"
}
```

| Field | Meaning |
|---|---|
| `title`, `status`, `detail`, `instance` | The standard fields of RFC 9457. The field `type` is not sent: by the standard this means a general error without a description page of its own |
| `code` | The permanent name of the error. The front end uses it to show a message in the language of the user; the server does not translate messages |
| `requestId` | The number of the request, the same as in the `X-Request-Id` header. A user can quote it when reporting a problem |

The names of errors are kept in one place, the enum `ErrorCode`. The response never contains a stack trace, a class name or the text of a database query: these go to the log only.
