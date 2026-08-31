# Contoso Production Deployment Standards

All production deployments run through the **Contoso Forge** pipeline. Manual deployment to production is not permitted, and direct write access to production infrastructure is withdrawn from all engineering accounts.

## Deployment windows

Production deployments are allowed Monday to Friday between 08:00 and 14:00 CET.

Deployments are **blocked after 14:00 CET on Friday** and all weekend, so that a regression is never left unattended over a weekend. Weekend deployment requires an approved emergency change record.

An annual change freeze runs from **18 December to 5 January** inclusive. During the freeze only Sev-1 remediation may be deployed, and each deployment needs Vice President approval.

## Approvals

Every production release requires **two approvals** from engineers other than the change author. At least one approver must belong to the team that owns the service being changed. Forge rejects a release whose only approver is the author.

## Canary and rollout

Releases roll out in stages. A new build first goes to a **canary receiving 5% of traffic for a minimum of 30 minutes**. Forge watches error rate and p99 latency during this window and halts the rollout automatically if either exceeds the service's defined budget.

If the canary is healthy, traffic increases to 50% for a further 15 minutes, and then to 100%. An engineer may pause a rollout at any stage, but only the service owner may skip a stage.

## Rollback

Every service must be able to roll back to the previous release within **12 minutes**. This target is verified quarterly in a scheduled rollback drill, and a service that fails its drill is blocked from further releases until the problem is fixed.

Rollback is always preferred to a forward fix during an active incident.

## Artifact signing

Build artifacts are signed with a **Forge Seal** signature at build time. The production cluster refuses any artifact without a valid Forge Seal, and seals cannot be created outside the pipeline. Seals expire after **90 days**, so an artifact that has not been deployed within that period must be rebuilt.
