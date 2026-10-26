# Reaching photolibd from the apps

How the apps and the viewer connect to a server behind a reverse proxy, a private certificate authority or mutual
TLS. In the apps, *Settings › Server › Add a server* takes the addresses, a private CA, a client certificate, a proxy
and headers. The decisions are [ADR-0032](../adr/0032-one-network-stack.md) and
[ADR-0125](../adr/0125-sign-in-from-the-app.md).

## One configuration per server

Each server the app knows has one network configuration, and every request to it uses it: API calls, thumbnails,
video and uploads. A setting that works for the library therefore also works for playback and backup.

* **Addresses**: a server may have several (LAN, WAN, VPN), one a line. The app asks each for its server information
  and uses the fastest one that answers as the same instance, and asks again once that one stops answering and
  whenever the device joins or leaves a network (Wi-Fi, mobile data, a VPN; no location permission), so it never talks
  to another machine that happens to own the same address on a foreign network.
* **Private CA**: the app trusts the PEM certificate of your private certificate authority for this server, in
  addition to the system's roots.
* **Client certificates (mutual TLS)**: the app presents a PKCS#12 bundle (certificate chain and key, a `.p12` or
  `.pfx` file you choose, opened with its password) to the reverse proxy, for example nginx with
  `ssl_verify_client on` or Caddy with `client_auth`. The app keeps it with the server, sealed in its store (ADR-0209).
* **Self-signed certificates**: on first contact the user confirms the certificate's SHA-256 fingerprint; the app
  then trusts exactly that certificate and refuses the server if its key changes.
* An **HTTP proxy** applies to every request, and **custom headers** (a Cloudflare Access token, proxy
  authentication) to every HTTPS request; a plain-HTTP address gets none, since any machine on its network could
  answer.
* **Plain HTTP**: the apps send their session over plain HTTP only to an address of the local networks, as photolibd
  counts them (loopback, private and link-local, IPv6 unique-local), judged by the address the server's name resolves
  to; anywhere else they say the server needs HTTPS. In a browser, which does not say where a name resolves, only an
  address or `localhost` counts.
* The apps follow no redirects, which could carry these headers or the client certificate elsewhere: a server that
  redirects to a single-sign-on login page counts as unreachable.
* **Video players** that cannot use the app's connection read through a proxy inside the app, on `127.0.0.1`, so
  playback uses the same certificates.

In a browser, the web app and the viewer use the browser's own connection: install a private CA or a client
certificate in the browser or the operating system.

## On the same network

*Add a server* lists the servers on the device's network under *Servers on this network*: the app asks over multicast
DNS (DNS-SD `_photolib._tcp.local`) from a port of its own, and photolibd answers with its port, instance, base path
and `public_url` (`discovery` in the [configuration](configuration.md)). A tap adds the server with its address on this
network and its public one; it needs no location permission. Browsers send no such question, and the iOS app does not
yet.

## Pairing a device

*Pair a device* in the admin console shows a link and its QR code: the server's first address with its other
addresses, the SHA-256 of the self-signed certificate the administrator's app trusts and the server's instance in the
fragment, which reaches no server's log. Pasted into *Add a server*, it adds every address at once, trusts that
certificate without asking, and refuses a server that answers as another instance. A password setup link from
*Accounts* carries the same, so a new account's first sign-in needs no typed URL either.

## The connection check

*Settings › Server › Check the connection*, also offered wherever the app says the server does not answer, runs these
steps against each address, in order, and names the one that fails with its cause, the next step and a fix: trust the
certificate (after comparing its fingerprint), sign in again, try again, or copy the details for the administrator.

1. **Finding the server's address**: the name resolves (DNS).
2. **Reaching the server**: a TCP connection opens; refused and timed out are told apart.
3. **Secure connection and certificate**: the TLS handshake; an expired certificate, a self-signed one not trusted
   yet, one that changed since it was trusted, or one from an unknown authority.
4. **Photolib on the server**: photolibd answers, not a proxy's error page or a Wi-Fi sign-in page, as the instance the
   app knows, and still serves this version of the app.
5. **Your sign-in**: the server takes the device's session.
6. **Large uploads through proxies**: one upload piece (8 MiB) to `POST /healthz`, which a proxy capping requests
   below it refuses (413); skipped on a metered network.
7. **Your network**: whether it is metered, such as mobile data.
8. **Your device's clock**: within five minutes of the server's (`Date` of its answer).

In a browser the browser resolves, connects and checks certificates itself: the first three steps do not run.

## Reverse-proxy limits

* Uploads are sent in pieces of at most 8 MiB, so a request cap such as Cloudflare's 100 MB never stops a backup, and
  each piece is sent within a 60 s proxy timeout from about 1.2 Mbit/s. A smaller cap answered with 413 (nginx allows
  1 MiB unless `client_max_body_size` says otherwise) makes the app halve its pieces. A lost connection resumes
  where the server's copy ends.
* A proxy's error page (502 Bad Gateway, 504 Gateway Timeout, 413, or a 401 from proxy authentication), a timeout or a
  certificate failure never logs you out: the app treats the server as unreachable and works offline. Only photolibd
  itself ends a session, with an explicit revocation, or you, with *Sign out*.

The decision behind this is [ADR-0032](../adr/0032-one-network-stack.md).
