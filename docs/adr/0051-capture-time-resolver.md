# ADR-0051 — Capture-time resolver: host-supplied claims and zones, a compiled file-name registry, explained results

* **Status**: Accepted — 2026-10-16, refined 2026-10-17. The owner answered the provisional choices of M1-07 in
  photolib-design#346:
  the compiled registry is confirmed and the confidence rules deferred ("do not fully understand"); for zones, and
  for zone data ("read 1"), the owner asked for flexible defaults and a solution robust to phones that save UTC or
  local time and to files without GPS. Read literally, that kept measured offsets first and added the host's default
  zone and the zero-delta rule below. Asked again in
  #377 (2026-10-17), the
  owner confirmed it with one refinement, the GPS zone's wall clock over a measured offset it disagrees with, and kept
  the host's default zone.
* **Requirements**: F-09, R-REL-1. **Design**:
  import §4–§5,
  research §5.

## Context

Doc 13 §4 fixes the claim model, the precedence table, the zone tiers and the plausibility checks of
`ResolveCaptureTime`, and §5 the 56-rule file-name catalogue. It leaves open how a pure, stateless kernel call gets
what only the host has (QuickTime and Takeout dates, the zone at a GPS position, the device's zone journal, the
current time), how the registry ships, how confidences combine into the bands of the media corpus' golden records,
and whether a GPS polygon or a measured offset wins when both exist.

## Decision

We will take everything outside the file's head as request fields: claims the host read, named by source
(`quicktime:creationdate`, `quicktime:mvhd`, `takeout:photoTakenTime`, or the file's own when the host read more
than the head), the zone at the GPS position, the device's zone and a default zone the host chose (the import run's,
a rule for the device or camera, or the library's: the owner's home zone), each as an IANA name with its table of
offsets, and `resolved_at`. Unknown sources are rejected; the kernel holds every prior. A zone the host does not give
stays unknown: never the server's zone, nor UTC for want of one.

We will compile the registry into the kernel as a table of RE2-style patterns with named groups (`regex-lite`),
instead of doc 13 §5.1's YAML file. The most specific matching rule (the longest match, the lower id on a tie) dates
a name; generic rules F52–F56 apply only when no vendor rule matches. Rule changes still bump the vectors.

We will rate claims in per mille: the prior of doc 13 §4.2, ×0.6 for a receive, save or transfer date, ×0.5 for an
epoch in a name, ×0.7 for a name that contradicts the file's own capture time. Agreeing claims combine by noisy-OR;
bounds and folder dates alone stay at most 0.60. The result is at most 0.80 ("medium") unless the wall clock comes
from the file or the host and its zone was measured, ×0.85 when a strong claim disagrees and ×0.5 when the time is
after a receive date. F53's prior is 0.45 (research: 0.50) and `xmp:CreateDate` with an offset is a strong XMP date,
as the corpus records them.

We will place the wall clock with the first of: the offset written with it, the GPS time's delta, another UTC claim's
delta (a Pixel name, Takeout, a phone's `mvhd`), the host's GPS zone, the device's zone, the default zone. Measured
offsets come before the GPS zone, which only says where the camera was, not what its clock was set to, so they fix
the instant. Where the GPS zone has another offset at that instant (a camera left on home time, or a stale fix), the
wall clock shown is the GPS zone's (`GPS_ZONE`), the winning claim keeps the camera's, and the result is flagged
`NEEDS_REVIEW` and `ZONE_MISMATCH`, where the user may keep the camera's zone. A zero delta,
though, is often one clock read twice (a phone that writes its local clock into `mvhd`, a geotagger that copies the
wall clock into the GPS time): it counts only where the first zone the host gave agrees. The default zone is
`DEFAULT_ZONE`, an assumption; when it gives a UTC-only time its wall clock, the result is flagged `ASSUMED_ZONE`.
A GPS time before the capture is a stale fix, not a conflict.

Every response lists every claim with its event and verdict, and the rule that chose the winner.

## Consequences

* Server, apps and viewer resolve identically; hosts need a zone lookup, a device zone journal and a default zone of
  their own.
* The corpus matches its golden capture times but one record whose name has the same shape as another's with a
  different rule id (F02 or F08); the corpus test lists it. Its Paris-positioned files with other offsets show Paris'
  wall clock, flagged `zone_mismatch`.
* Rule updates need a kernel release, not a data push. `regex-lite` and `prost-types` join the kernel (MIT or
  Apache-2.0).
* Follow-ups: `user` and `source_user` claims (M3-05), Takeout edits (M4-02), group inheritance, sibling and mtime
  evidence, localized screenshot prefixes.

## Options considered

* **A YAML registry parsed at run time**: data-only updates, but a YAML parser in every binary for 56 rules.
* **GPS polygon before measured offsets** (doc 13 §4.4's numbering): wrong whenever a camera keeps its home time
  abroad. The owner chose the GPS zone for the wall clock only, the measured offset keeping the instant.
* **A zero delta as a measurement**: a phone that writes its local clock into `mvhd` would get +00:00 and an instant
  off by its offset, with high confidence.
* **No default zone** (the provisional choice): floating wall clocks had no instant and UTC-only videos no wall clock
  until each host added its own.
* **Polygons in the kernel** (tzf-rs): about 4 MB per call or a stateful API; the host already has the places pack.
* **Plain noisy-OR without caps**: a file name with a Takeout time, or a floating wall clock, would look as sure as
  an EXIF offset.
