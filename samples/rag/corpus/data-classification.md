# Contoso Data Classification Standard

Every dataset held by Contoso is assigned one of four tiers. The tier determines how the data may be stored, shared, and retained.

## Tiers

- **Tier-0 (Crown)**: payment card data, authentication secrets, and unreleased financial results. The most tightly controlled category.
- **Tier-1 (Restricted)**: personal data of customers and employees, contracts, and pricing that has not been published.
- **Tier-2 (Internal)**: ordinary business information such as project plans, internal documentation, and team metrics.
- **Tier-3 (Public)**: material approved for publication, including marketing content and published release notes.

When a dataset combines tiers, it inherits the most restrictive tier present.

## Storage and residency

Tier-0 data must never leave the **eu-west-contoso-1** region. Replication, backup, and disaster-recovery copies of Tier-0 data must also remain inside that region, and cross-region export is blocked at the platform level rather than by policy alone.

Tier-1 data may be replicated across Contoso regions but must not be stored on endpoint devices such as laptops or phones. Tier-2 and Tier-3 data have no residency restriction.

## Encryption

Tier-0 and Tier-1 data require encryption at rest and in transit, using customer-managed keys held in the Contoso Key Vault. Tier-2 requires encryption in transit only. Tier-3 has no encryption requirement.

Keys protecting Tier-0 data are rotated every **180 days**.

## Retention

- Tier-0: retained **7 years**, then destroyed under a witnessed destruction record.
- Tier-1: retained **5 years** after the end of the customer or employment relationship.
- Tier-2: retained **3 years**.
- Tier-3: no retention limit.

Retention periods are enforced automatically. A legal hold overrides all retention rules and suspends deletion until the hold is lifted by the Legal team.

## Access review

Access to Tier-0 and Tier-1 datasets is reviewed **quarterly** by the data owner. Any account that has not read a Tier-0 dataset for 60 days has its access removed automatically. Access reviews that are not completed within 14 days of issue are escalated to the Chief Information Security Officer.

## Sharing outside Contoso

Tier-0 data may never be shared externally. Tier-1 data may be shared only under a signed data processing agreement recorded by the Legal team. Tier-2 data may be shared with a standard non-disclosure agreement. Tier-3 data may be shared freely.
