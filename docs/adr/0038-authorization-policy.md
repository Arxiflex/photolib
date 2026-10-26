# ADR-0038 — Authorization: one policy crate, a rule per procedure, one SQL scope for single and list reads

* **Status**: Accepted — 2026-10-17. The owner answered M2-03's provisional choices in
  photolib-design#330:
  confirmed that shared paths hide locked assets, now with matrix rows for covers, memories, search, the map and face
  crops; that a library's owner acts as an editor without Share; that viewer accounts never change anything; the
  grants' id lists, required expiry and own assets; and that only an album's owner shares or deletes it. Changed: the
  trash shows to whoever may delete, private libraries are shared whole with partners, per-user state needs only View,
  comments and likes need no Contribute, and adding an asset to an album needs Share on it.
* **Requirements**: R-SEC-1, R-SEC-2. **Design**: 12 §4, 06 §10, 03 §6,
  18 §17.

## Context

Competitors leak because every endpoint checks permissions itself: single and bulk paths diverge, sync and static
files bypass the checks, search ignores grants (lessons learned §2.9 in the design repository). The design asks for
one module computing `can(principal, action, resource)` over six access paths (owner, library member, album member,
partner filter, link token, processing grant) that also generates the scoped SQL of every list. The baseline schema
already holds every relation those paths read.

## Decision

* **`photolib-authz`** is that module: a `Principal` (anonymous, an active account with its role, a verified link,
  a grant's worker), an `Action` (view, download, contribute, edit, delete, share, manage users, process for one
  grant purpose) and a `Resource` (the server, a library, album or asset, a sync stream of design 05 §3, an upload,
  and what else shows an asset: an album's item or cover, a memory's asset, a face's crop, a search hit, a map pin).
* **One SQL per principal, action and kind.** `scope` pushes `SELECT id …`, a `UNION ALL` of the access paths;
  lists and sync streams keep `id IN (scope)`, and `can` asks the same scope about one id. A list cannot show what a
  single read refuses. PostgreSQL pushes the id into every branch, so a check reads by primary key; a test keeps it so.
* **What each path allows.** Owners everything. A library's owner acts as an editor over what others put into it,
  without Share (family libraries, 1.x, revisit this with their equal rights); library members view and download,
  contributors also upload, editors also edit and delete. Album owners and members see the album's items; members
  contribute or edit by role; sharing and deleting stay with the owner until M3-11 adds co-owners. Adding an asset to
  an album needs Share on the asset (its owner now, co-owners later), so that no partner or member puts someone
  else's asset into an album and publishes it by link. A partner sees the owner's assets taken since the share's
  date, leaving out standard-library ones without a known date, while private libraries are shared whole: the server
  cannot read their dates and S4 wraps the whole LibraryKey to the partner, so a date filter would be cosmetic. A
  link shows its album while neither revoked nor expired, and originals only when it allows downloads. A grant
  processes only its owner's assets in its scope (`{"libraries": […], "albums": […], "assets": […]}`; the client
  turns a date range into assets), for its purposes, until its required expiry or revocation.
* **Shared paths hide what the owner locked or trashed**, and whoever may delete an asset also sees it in the trash and
  may restore it (`Delete`), so a library's owner or editor can undo deleting another member's asset. Album covers,
  memories, face crops, search hits and map pins show an asset only to whoever may view it; links show covers, never
  faces, memories, search hits or locations (design 12 §3). **Viewer accounts** never upload, edit or delete,
  whatever their member roles; per-user state (favourite, seen, hidden from memories) needs only View, and comments
  and likes need View and an album that allows comments, not Contribute (design 12 §2). **Administrators** manage
  accounts and see no one's content (design 18 §17). Only accounts sync.
* **A rule per procedure.** `rpc::ROUTES` names each procedure's `Rule` (`Anyone` or `Server(action)`). An
  interceptor admits every unary and streaming call before its handler runs, refuses a procedure without a rule
  (`permission_denied`, `route.no_rule`) and hands the principal to the handler. Credentials inside a request (the
  setup token, later passwords) are authentication and stay with their handler; no handler checks permissions. The
  health probes (`/healthz`, `/readyz`) stay public as ADR-0021 decided; they carry no account data.
* **Enforced by tests and review.** A test keeps `ROUTES` equal to the `rpc`s in `proto/`; the policy matrix
  (`photolib-authz/tests/matrix.rs`) checks every principal, action, resource and stream and that `scope` lists what
  `can` allows; the API matrix (`rpc/authz.rs`) checks every procedure against every kind of caller. The pull request
  checklist asks for both.

## Consequences

* A new procedure without a rule fails the gate and is refused at runtime; a new access path is one SQL branch and a
  matrix column.
* Content handlers must read through `can` and `scope`, and sync streams filter their rows with `scope` (M2-14).
* Partner filters beyond the date (people, media types) need columns (M3-12), whose UI disables the date filter for
  private libraries and says why; filtered private sharing needs per-file keys.
* Comments and likes (M3-11) bring the album's setting that allows them and an action viewer accounts have.
* Grants exist only for private libraries, so server-side date ranges never apply. When they are built (M6), their
  asset scope comes from the grant's per-file key rows (indexed, one per file; design 06 §7 G3), the id lists stay
  only as the description the UI shows, and a database check keeps the expiry at most 24 h after creation.
* Devices act as their account until M2-02 binds sessions to devices; scoped API keys (M2-06) extend the rules.

## Options considered

* **Checks in each handler**: the failure this decision exists to prevent.
* **PostgreSQL row-level security** with the principal in a session setting: per-connection state in a pooled
  connection, rules split between SQL policies and Rust, harder to test per action.
* **An in-memory `can` over loaded facts beside separate list SQL**: two implementations that can disagree.
* **A policy engine** (OPA, Cedar, OpenFGA): another dependency or service for a few relational rules.
