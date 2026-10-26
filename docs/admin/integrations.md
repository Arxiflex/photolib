# Integrations: events, webhooks and frames

Home Assistant, photo frames, kiosks and scripts follow libraries with an [API key](users.md#api-keys) through the
events API, signed webhooks and a random photo ([ADR-0263](../adr/0263-webhooks-events-and-wasm-plugins.md)).

## Events

An event says that an asset was created (uploaded, imported or found by a scan), trashed, restored or deleted: its
`eventId`, `type`, `recordedAt`, `libraryId` and `assetId`, never a name, date, place or file. Only standard libraries
have events; private libraries have none. An account reads the events of the assets it may view now, but locked ones,
and the deletions in the libraries it may view; photolibd keeps them for 7 days. Poll with a key that has `view`,
passing the answer's `nextAfter` as `after` the next time (empty starts at the oldest event kept):

```sh
curl -H 'Authorization: Bearer plk_…' -H 'Content-Type: application/json' \
  http://127.0.0.1:8080/photolib.api.v1.EventService/ListEvents -d '{"after": ""}'
```

## Webhooks

`webhooks: true` in the [configuration](configuration.md) turns webhooks on; they are off by default and
`outbound: none` turns them off ([privacy manifest](privacy.md)). An account signed in, never an API key, registers up
to 10 URLs with `WebhookService.CreateWebhook` and gets each one's secret, `whsec_…`, once; creating and deleting a
webhook are audited.

Within a minute of an event, photolibd POSTs it to each of its account's webhooks as JSON, one event per request, in
order and at least once, signed as [Standard Webhooks](https://www.standardwebhooks.com/) sign: `webhook-id` is the
event id, `webhook-timestamp` the Unix time and `webhook-signature` `v1,` and the base64 HMAC-SHA256 of
`<id>.<timestamp>.<body>` under the base64-decoded secret. Check it with any Standard Webhooks library, refuse old
timestamps and drop a `webhook-id` already seen. A delivery fails on a status other than 2xx, a redirect or no answer
within 10 seconds; photolibd tries the same event again the next minute, and `ListWebhooks` shows `failingSince` and
`lastStatus` (0 without an answer).

A URL may name a host on the LAN or the internet, never a loopback, `0.0.0.0/8`, link-local, broadcast or multicast
address, which photolibd checks on every address the name resolves to: reach a receiver on photolibd's own machine by
its LAN address. An HTTPS receiver needs a certificate the system trusts.

## Random photo

`GET /media/random/{role}` (`thumb_s`, `thumb_m` or `preview`) answers with that rendition of a random photo the key's
or session's account may view in a standard library, neither locked, archived nor trashed, and its id in
`Photolib-Asset`; nothing caches it. RSS feeds and embeds of albums will come with public links.
