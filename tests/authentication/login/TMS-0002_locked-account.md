---
id: TMS-0002
title: Login is blocked for a locked account
priority: high
type: functional
module: authentication
status: ready
execution_type: manual
size: S
targets: [onetest-ai/app-web]
requirements: [REQ-002]
tags: [smoke, login, negative]
---

# TMS-0002: Login Blocked for a Locked Account

**Module:** Authentication · **Priority:** High · **Type:** Functional / Smoke

## Preconditions
- App is accessible at `{{base_url}}`
- A locked user exists: email=`locked@example.com`, password=`Test1234!`

## Steps

| # | Action                                          | Expected Result                                  |
|---|-------------------------------------------------|--------------------------------------------------|
| 1 | Navigate to `{{base_url}}/login`                | Login page loads                                 |
| 2 | Fill Email with `locked@example.com`            | Email value is set                               |
| 3 | Fill Password with `Test1234!`                  | Password input is masked                         |
| 4 | Click "Sign In"                                 | Stays on `/login`; "Account locked" error shown  |

## Expected Final State
User remains unauthenticated on `{{base_url}}/login` with a visible "Account locked" message.
