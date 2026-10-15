# Postmortem: <short title>

*Blameless. The goal is to fix systems, not people.*

| | |
|---|---|
| **Date** | YYYY-MM-DD |
| **Duration** | HH:MM (detection → resolution) |
| **Severity** | SEV1 / SEV2 / SEV3 |
| **Environment** | dev / prod |
| **Error budget consumed** | e.g. 12% of the 30-day budget |
| **Author** | |

## Summary

Two or three sentences: what broke, who or what was affected, how it was fixed.

## Impact

What users experienced (errors, latency, failed thumbnails), with numbers from Grafana or k6.

## Timeline (UTC)

| Time | Event |
|---|---|
| 12:00 | Change merged / failure injected |
| 12:03 | Alert `…` fired |
| 12:05 | Investigation started (runbook: …) |
| 12:12 | Root cause identified |
| 12:15 | Mitigated (rollback / scale / …) |
| 12:20 | Resolved and verified |

## Root cause

The *system* reason it happened. Use "5 whys" if it helps.

## What went well

- e.g. readiness probes pulled broken pods out of the ALB automatically

## What went badly

- e.g. the alert took 6 minutes to fire; the runbook was missing a step

## Action items

| Action | Type (prevent / detect / mitigate) | Owner | Link |
|---|---|---|---|
| Add a test for … | prevent | | PR #… |
| Tune alert window … | detect | | |
