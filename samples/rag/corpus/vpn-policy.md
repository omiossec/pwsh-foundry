# Contoso Remote Access and VPN Policy

This policy governs all remote connections into the Contoso corporate network. It applies to employees, contractors, and vendor staff.

## Approved client

The only approved VPN client is **Contoso SecureLink 4.2**. Earlier releases of SecureLink were retired on 1 March and will be refused by the gateway. Personal VPN products, browser-based proxies, and third-party tunnelling tools are not permitted on managed devices.

SecureLink is distributed through the Contoso Software Portal. Manual installation from any other source is a policy violation and must be reported to the Service Desk.

## Authentication

All remote sessions require multi-factor authentication through the **Contoso Authenticator** app. Hardware tokens are issued only to staff in the Payments and Treasury groups, who must use them instead of the app.

A remote session expires after **12 hours**, after which the user must re-authenticate in full. Session extension is not available, and the gateway will not renew a session silently.

## Split tunnelling

Split tunnelling is **prohibited on all managed devices**. While SecureLink is connected, all traffic including personal browsing is routed through the Contoso gateway and is subject to inspection and logging.

The single exception is real-time conferencing traffic, which is allowed to egress directly to reduce latency. This exception is applied automatically by the client and cannot be enabled by the user.

## Contractor and vendor access

External staff connect using a **SecureLink Guest** profile. Guest profiles are limited to a maximum of **30 days** and must be renewed by the sponsoring manager. A guest profile grants access only to the systems named in the access request; broad network access is never granted to a guest profile.

Sponsoring managers receive a renewal reminder seven days before expiry. Profiles that are not renewed are disabled automatically at midnight on the expiry date.

## Gateway regions

Contoso operates VPN gateways in three regions: Dublin, Singapore, and Toronto. Users are assigned to the gateway nearest their registered office location. Cross-region connection is blocked by default and requires an exception approved by the Network Security team.
