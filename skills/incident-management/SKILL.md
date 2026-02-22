---
name: incident-management
description: SRE incident response, blameless postmortems, SLOs/error budgets, and on-call best practices
---

# Incident Management

## Overview

Incident management is the structured process of detecting, responding to, mitigating, and learning from service disruptions. Effective incident management reduces Mean Time To Recovery (MTTR), minimizes customer impact, and transforms failures into organizational learning.

## Incident Severity Levels

| Level | Name | Description | Response Time | Communication |
|-------|------|-------------|---------------|---------------|
| SEV1 | Critical | Service fully down, data loss, security breach | < 5 minutes | Page on-call, exec notification |
| SEV2 | Major | Significant degradation, major feature broken | < 15 minutes | Page on-call, team notification |
| SEV3 | Minor | Minor feature broken, workaround exists | < 1 hour | Team notification, ticket |
| SEV4 | Low | Cosmetic issue, no user impact | Next business day | Ticket only |

## SRE Incident Response Lifecycle

### 1. Detection

```
Sources:
├── Automated Monitoring
│   ├── SLO burn rate alerts (error budget consumption)
│   ├── Synthetic monitoring (uptime checks)
│   ├── Anomaly detection (baseline deviation)
│   └── Infrastructure alerts (resource exhaustion)
├── Customer Reports
│   ├── Support tickets
│   ├── Social media mentions
│   └── Status page reports
└── Internal Reports
    ├── Engineer observation
    └── Deployment pipeline failure
```

**Goal**: Detect incidents within 5 minutes of customer impact starting.

### 2. Triage

Rapid assessment to determine:
- **Severity**: How many users affected? What is the business impact?
- **Scope**: Single service? Region? Global?
- **Ownership**: Which team owns the affected service?
- **Urgency**: Is it getting worse? Is there data loss?

```markdown
## Triage Checklist
- [ ] What is broken? (specific symptom)
- [ ] When did it start? (correlate with deployments, config changes)
- [ ] How many users affected? (% of traffic, specific segments)
- [ ] Is there data loss or security exposure?
- [ ] Is it getting worse or stable?
- [ ] Has anything changed recently? (deploy, config, dependency)
```

### 3. Mitigation

Focus on **stopping the bleeding**, not finding root cause.

```markdown
## Mitigation Decision Tree

Is there a recent deployment?
├── YES → Can we rollback safely?
│   ├── YES → Rollback immediately
│   └── NO → Feature flag the change
└── NO → Is a dependency down?
    ├── YES → Enable circuit breaker / fallback
    └── NO → Scale up? Restart? Failover?

ALWAYS: Communicate current status to stakeholders
```

Common mitigation actions:
- **Rollback** the most recent deployment
- **Feature flag** to disable problematic feature
- **Scale up** to handle increased load
- **Failover** to another region/provider
- **Rate limit** to protect the system
- **Restart** if a process is in a bad state
- **DNS redirect** to a static error page

### 4. Resolution

Full fix applied; service restored to normal operation.

```markdown
## Resolution Confirmation
- [ ] All monitoring metrics back to normal
- [ ] Customer-facing functionality verified
- [ ] Error rates returned to baseline
- [ ] No data loss or data inconsistency identified
- [ ] Temporary mitigations removed (if any)
- [ ] Status page updated to "Resolved"
```

## Incident Command Roles

### Incident Commander (IC)

**Responsibilities**:
- Own the incident from declaration to resolution
- Coordinate responders and delegate tasks
- Make decisions on mitigation approach
- Manage communication cadence
- Declare incident resolved

**What the IC does NOT do**: Debug code, make changes to production, or investigate root cause.

### Communications Lead

**Responsibilities**:
- Post status page updates at regular intervals
- Notify stakeholders (support, sales, execs)
- Draft customer-facing communications
- Maintain internal timeline of events

**Update Template**:
```markdown
## Incident Update - [TIMESTAMP]

**Status**: Investigating / Identified / Monitoring / Resolved
**Impact**: [Description of customer impact]
**Current Actions**: [What we're doing right now]
**Next Update**: [Time of next update, e.g., "in 30 minutes"]
```

### Subject Matter Expert (SME)

**Responsibilities**:
- Investigate the technical cause
- Propose and implement mitigation
- Execute changes under IC direction
- Provide technical status to IC

### Scribe (Optional)

- Records timeline of events, decisions, and actions
- Captures key data points for the postmortem
- Logs who did what and when

## Blameless Postmortems

### When to Write a Postmortem

- All SEV1 and SEV2 incidents
- Any incident with customer data exposure
- Incidents lasting > 1 hour
- Near-misses that could have been major

### Postmortem Template

```markdown
# Postmortem: [Incident Title]

**Date**: YYYY-MM-DD
**Duration**: X hours Y minutes
**Severity**: SEV-X
**Authors**: [Names]
**Status**: Draft / Reviewed / Complete

## Summary
[2-3 sentence summary of what happened and the impact]

## Impact
- **Duration**: HH:MM to HH:MM UTC
- **Users Affected**: X% of users in [region/segment]
- **Revenue Impact**: $X estimated
- **Support Tickets**: X filed
- **SLO Impact**: Error budget consumed: X%

## Timeline (All times UTC)

| Time | Event |
|------|-------|
| 14:00 | Deployment v2.3.1 rolled out to production |
| 14:05 | Error rate alert fires (5xx rate > 5%) |
| 14:07 | On-call engineer acknowledges alert |
| 14:10 | Incident declared SEV2, IC assigned |
| 14:15 | Root cause identified: DB connection pool exhaustion |
| 14:18 | Rollback initiated |
| 14:22 | Rollback complete, error rate declining |
| 14:30 | Metrics return to baseline, incident resolved |

## Root Cause Analysis

### What Happened
[Technical description of the failure chain]

### 5 Whys Analysis
1. **Why** did the API return 500 errors?
   - Database connection pool was exhausted
2. **Why** was the connection pool exhausted?
   - New query in v2.3.1 held connections for 30s+
3. **Why** did the query take 30s+?
   - Missing index on the `orders.customer_id` column
4. **Why** was the index missing?
   - Migration was written but not included in the release
5. **Why** was the missing migration not caught?
   - No pre-deploy check for pending migrations

### Contributing Factors
- Missing database index (primary cause)
- No connection pool exhaustion alert
- Load test environment has different data volume than production
- Migration checklist not enforced in CI

## What Went Well
- Alert fired within 5 minutes of impact
- IC was assigned quickly and communication was clear
- Rollback was smooth and took < 5 minutes

## What Went Poorly
- Took 15 minutes to identify root cause
- No staging environment has production-like data volume
- Connection pool metrics were not on the dashboard

## Action Items

| Priority | Action | Owner | Due Date | Status |
|----------|--------|-------|----------|--------|
| P0 | Add missing DB index | @alice | 2025-03-20 | Done |
| P0 | Add connection pool exhaustion alert | @bob | 2025-03-22 | In Progress |
| P1 | Add pre-deploy migration check to CI | @carol | 2025-04-01 | To Do |
| P1 | Load test with production-like data volume | @dave | 2025-04-15 | To Do |
| P2 | Add connection pool metrics to service dashboard | @bob | 2025-04-30 | To Do |

## Lessons Learned
[Key takeaways that apply beyond this specific incident]
```

### Facilitating a Blameless Postmortem

**Ground Rules**:
1. We examine what happened, not who is at fault
2. Everyone involved was doing their best with the information they had
3. Focus on systemic improvements, not individual actions
4. All perspectives are valuable and welcome
5. Action items must have clear owners and deadlines

**Facilitator Guide**:
- Ask "how" questions, not "why did you" questions
- Redirect blame language: "The system allowed X" vs "Person Y did X"
- Ensure all contributors speak (not just the loudest voices)
- Focus on what would prevent recurrence, not what should have been done differently

## SLOs and Error Budgets

### SLO Definition Framework

```yaml
# SLO Document
service: payment-api
team: payments
tier: 1

slos:
  - name: Availability
    description: Payment API responds successfully
    sli: "Proportion of non-5xx responses"
    objective: 99.95%
    window: 30 days rolling
    error_budget: "21.6 minutes/month"

  - name: Latency
    description: Payment API responds within acceptable time
    sli: "Proportion of requests completing within 500ms"
    objective: 99.0%
    window: 30 days rolling
    error_budget: "432 minutes/month (at p99)"

  - name: Data Freshness
    description: Payment status reflects within 30 seconds
    sli: "Proportion of status updates propagated within 30s"
    objective: 99.9%
    window: 30 days rolling
```

### Error Budget Policy

```markdown
## Error Budget Policy

### Budget > 50% remaining
- Normal development velocity
- Feature work proceeds as planned
- Experiments and chaos testing allowed

### Budget 25-50% remaining
- Reduce risky deployments
- Prioritize reliability work
- Increase deployment testing

### Budget 10-25% remaining
- Feature freeze for this service
- Focus on reliability improvements
- Daily error budget review

### Budget < 10% remaining
- Emergency reliability mode
- All hands on reliability
- Postmortem for any further budget consumption
- Executive visibility
```

## Root Cause Analysis Techniques

### Fishbone (Ishikawa) Diagram

```
                    ┌─── People ────────── Process ──────── Technology ───┐
                    │   - Knowledge gap    - No migration   - Missing     │
                    │   - Onboarding       check             index        │
                    │                     - No load test    - No pool     │
                    │                       with prod data    monitoring  │
                    │                                                     │
EFFECT: ──────────────────── API 500 Errors ─────────────────────────────
                    │                                                     │
                    │   - Staging != prod  - Peak traffic   - Connection  │
                    │   - Data volume       during deploy    pool config  │
                    │     mismatch                                        │
                    └─── Environment ────── Timing ─────── Configuration ─┘
```

### Fault Tree Analysis

Start with the failure, work backward through AND/OR gates to identify all contributing factors.

### Timeline Reconstruction

Build a minute-by-minute timeline from multiple data sources (logs, metrics, chat history, deployment records) to understand the exact sequence of events.

## Runbook Design

### Structure

```markdown
# Runbook: [Service Name] - [Failure Mode]

## Alert That Triggers This Runbook
- Alert name: `ApiHighErrorRate`
- Dashboard: [link to dashboard]

## Quick Diagnosis
1. Check error rate: [Grafana link]
2. Check recent deployments: `kubectl rollout history deploy/api -n production`
3. Check dependency health: [status page links]

## Decision Tree

```
Is there a recent deployment (< 1 hour)?
├── YES
│   └── Rollback: `kubectl rollout undo deploy/api -n production`
└── NO
    └── Is a downstream dependency degraded?
        ├── YES
        │   └── Enable circuit breaker: [instructions]
        └── NO
            └── Escalate to service owner: [contact info]
```

## Rollback Procedure
1. `kubectl rollout undo deploy/api -n production`
2. Verify: `kubectl rollout status deploy/api -n production`
3. Check error rate returns to baseline within 5 minutes
4. If not resolved, escalate to [team/person]

## Escalation
- Primary on-call: [PagerDuty schedule link]
- Secondary: [name/contact]
- Engineering manager: [name/contact]
```

## On-Call Best Practices

### Rotation Structure

- **Rotation length**: 1 week (typical), handoff during business hours
- **Team size**: Minimum 4-5 people for sustainable rotation
- **Compensation**: On-call pay, time off after incident-heavy weeks
- **Handoff**: Written summary of active issues, upcoming risks

### On-Call Health Metrics

| Metric | Healthy | Unhealthy |
|--------|---------|-----------|
| Pages per week | < 2 | > 5 |
| False positive rate | < 10% | > 30% |
| Time to acknowledge | < 5 min | > 15 min |
| After-hours pages | < 1/week | > 3/week |
| Mean time to mitigate | < 30 min | > 2 hours |

### On-Call Checklist (Start of Rotation)

```markdown
- [ ] Verify PagerDuty/Opsgenie escalation policy is correct
- [ ] Review recent incidents and active issues
- [ ] Check known upcoming risks (deployments, maintenance windows)
- [ ] Verify VPN/access to production systems works
- [ ] Review and bookmark key dashboards and runbooks
- [ ] Confirm phone/laptop charged and accessible
```

## Status Page Communication

### Update Guidelines

| Phase | What to Say | Tone |
|-------|-------------|------|
| Investigating | "We are aware of issues with [service] and are investigating." | Calm, factual |
| Identified | "We have identified the cause and are working on a fix." | Reassuring |
| Monitoring | "A fix has been deployed. We are monitoring for stability." | Optimistic |
| Resolved | "The issue has been fully resolved. [Brief summary]." | Confident |

### Example Updates

```
[14:05 UTC] Investigating - We are aware that some users are experiencing
errors when processing payments. Our team is actively investigating.

[14:15 UTC] Identified - We have identified the cause as a database
performance issue following a recent update. We are rolling back the change.

[14:25 UTC] Monitoring - The rollback is complete and payment processing
is recovering. We are monitoring for full stability.

[14:45 UTC] Resolved - Payment processing has fully recovered. The issue
lasted approximately 40 minutes. We will publish a detailed postmortem
within 48 hours.
```

## Best Practices

1. **Declare incidents early** -- it is better to declare and cancel than to delay
2. **Separate mitigation from root cause** -- stop the bleeding first, investigate later
3. **Assign clear roles** -- IC, comms lead, SME reduce confusion
4. **Communicate proactively** -- silence during incidents creates anxiety
5. **Write postmortems within 48 hours** -- while memories are fresh
6. **Track action items to completion** -- postmortems without follow-through are waste
7. **Practice incident response** -- run tabletop exercises quarterly
8. **Measure MTTR, not MTBF** -- failures are inevitable; recovery speed matters
9. **Automate common mitigations** -- one-click rollback, circuit breakers, feature flags
10. **Invest in on-call health** -- burnout reduces incident response quality

## Anti-Patterns

1. **Blame culture** -- people hide mistakes instead of surfacing them early
2. **No defined severity levels** -- everything is treated as critical or nothing is
3. **Hero culture** -- relying on one person who "knows everything"
4. **Postmortems without action items** -- documentation without improvement
5. **Alert fatigue** -- too many alerts means real incidents get ignored
6. **No communication plan** -- customers find out from Twitter, not your status page
7. **Manual runbooks only** -- key procedures should be automated where possible
8. **No practice drills** -- the first time you use your incident process should not be a real incident

## Sources & References

- https://sre.google/sre-book/managing-incidents/ -- Google SRE: Managing Incidents
- https://sre.google/sre-book/postmortem-culture/ -- Google SRE: Postmortem Culture
- https://sre.google/workbook/alerting-on-slos/ -- SRE Workbook: Alerting on SLOs
- https://www.pagerduty.com/resources/learn/incident-response/ -- PagerDuty Incident Response Guide
- https://response.pagerduty.com/ -- PagerDuty Incident Response Operations Guide
- https://www.atlassian.com/incident-management/handbook -- Atlassian Incident Management Handbook
- https://firehydrant.com/blog/incident-severity-levels/ -- FireHydrant severity levels guide
- https://www.blameless.com/blog/blameless-postmortem-guide -- Blameless postmortem guide
