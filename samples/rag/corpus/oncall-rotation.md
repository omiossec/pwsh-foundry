# Contoso On-Call Rotation and Incident Response

Production services at Contoso are covered around the clock by an on-call rotation managed in **Contoso PagerHub**.

## Rotation schedule

Rotations run for **seven days**, beginning **Wednesday at 10:00 CET** and ending the following Wednesday at the same time. Each rotation has a primary and a secondary responder drawn from different teams so that a single team absence cannot leave a gap.

A handover meeting is held every **Wednesday at 09:30 CET**, thirty minutes before the switch. The outgoing primary walks through open incidents, any deferred alerts, and known fragile areas. Attendance is mandatory for the outgoing and incoming primary.

## Acknowledgement and escalation

The primary responder must acknowledge a page within **8 minutes**. If the page is not acknowledged, PagerHub automatically notifies the secondary responder. If the secondary does not acknowledge within a further **15 minutes**, the incident escalates to the duty engineering manager.

Escalation is never a failure. Responders are explicitly encouraged to escalate early when an incident is outside their area, and no responder is measured on how often they escalate.

## Severity levels

- **Sev-1**: complete loss of a customer-facing service, or any confirmed data loss. Requires an incident commander and a public status page update within 30 minutes.
- **Sev-2**: significant degradation affecting a subset of customers, with no data loss. Status page update required within two hours.
- **Sev-3**: internal-only impact or a degraded non-critical component. Handled during business hours.

Only the incident commander may declare or downgrade a Sev-1. The on-call primary may raise a Sev-2 or Sev-3 without approval.

## Compensation

On-call duty is compensated at **280 EUR per completed week**, paid regardless of how many pages were received. A responder who is paged and works more than four hours outside normal working hours is entitled to a compensating rest day, requested through their line manager.

## Post-incident review

Every Sev-1 and Sev-2 requires a written post-incident review within **five working days**. Reviews are blameless: they record the timeline, the contributing factors, and the follow-up actions, and they never name an individual as a cause. Follow-up actions are tracked to completion by the owning team.
