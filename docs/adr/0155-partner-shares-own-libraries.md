# ADR-0155 — A partner share shows the owner's own libraries, not what the owner put in others'

* **Status**: Accepted — 2026-10-21 (photolib-design#509). The owner kept the decision: a partner share shows the
  assets of the owner's own libraries only, and what the owner put in another's library is shared as that library is
  (photolib-design#539).
* **Requirements**: R-SEC-2. **Design**:
  sharing §1, §4,
  security §5,
  [ADR-0038](0038-authorization-policy.md), [ADR-0091](0091-sync-rpc.md).

## Context

photolibd had two partner rules. The policy's partner path (ADR-0038) let a partner view every asset the owner owns
in the share's window, in whatever library; the `partner/{owner}` stream (ADR-0091) sent only those of the owner's own
libraries. An asset Bob put in Carol's library was visible to Bob's partner Ann, but no stream kept it current on her
device, whose garbage collection followed the policy and kept it after she left Carol's library.

## Decision

A partner share shows the assets of the owner's own libraries: those taken since the share's date, and private
libraries whole. What the owner put in someone else's library is shared as that library is. This amends ADR-0038's
partner path: `photolib_authz`'s `PARTNER` and the stream are one rule (the authz matrix: con's share shows sam nothing
he put in Ann's L1). A device keeps a partner's asset only in a library the partner's stream sent one of
(`partner_library`, schema 11, `whole` for private ones).

## Consequences

* Bob's contributions to Carol's library reach Ann only through Carol's sharing.
* A replica upgraded to schema 11 syncs its partners' streams again from scratch, once, to learn their libraries.

## Options considered

* **The stream sends the owner's assets in any library**: asset tombstones are scoped by library, so it would read the
  tombstones of every library the owner ever put something in, and a partner holds keys only of the owner's private
  libraries (S4), not of others'.
