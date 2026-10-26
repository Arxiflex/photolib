"""Stdlib-only reference implementations of the primitives crypto suite v1 builds on.

Slow and not constant-time: they exist to generate and check known-answer vectors, never to protect real data.
Each one is checked against its published vectors by `vectors.py` (standards.json).
"""
import hashlib
import hmac
import struct

M32, M64 = 0xFFFFFFFF, (1 << 64) - 1


class Reject(Exception):
    """A reader refused its input; the message is the error code of the specification."""


def sha256(data):
    return hashlib.sha256(data).digest()


def hkdf_extract(salt, ikm, hash_name="sha256"):
    return hmac.new(salt, ikm, hash_name).digest()


def hkdf_expand(prk, info, length, hash_name="sha256"):
    out, block, counter = b"", b"", 0
    while len(out) < length:
        counter += 1
        block = hmac.new(prk, block + info + bytes([counter]), hash_name).digest()
        out += block
    return out[:length]


def hkdf(ikm, info, length=32, salt=b""):
    return hkdf_expand(hkdf_extract(salt, ikm), info, length)


# --- ChaCha20-Poly1305 (RFC 8439) and XChaCha20-Poly1305 (draft-irtf-cfrg-xchacha-03)

def _rounds(s):
    def qr(a, b, c, d):
        s[a] = (s[a] + s[b]) & M32
        x = s[d] ^ s[a]
        s[d] = ((x << 16) | (x >> 16)) & M32
        s[c] = (s[c] + s[d]) & M32
        x = s[b] ^ s[c]
        s[b] = ((x << 12) | (x >> 20)) & M32
        s[a] = (s[a] + s[b]) & M32
        x = s[d] ^ s[a]
        s[d] = ((x << 8) | (x >> 24)) & M32
        s[c] = (s[c] + s[d]) & M32
        x = s[b] ^ s[c]
        s[b] = ((x << 7) | (x >> 25)) & M32

    for _ in range(10):
        qr(0, 4, 8, 12), qr(1, 5, 9, 13), qr(2, 6, 10, 14), qr(3, 7, 11, 15)
        qr(0, 5, 10, 15), qr(1, 6, 11, 12), qr(2, 7, 8, 13), qr(3, 4, 9, 14)


SIGMA = struct.unpack("<4I", b"expand 32-byte k")


def _chacha_block(key, counter, nonce):
    init = [*SIGMA, *struct.unpack("<8I", key), counter, *struct.unpack("<3I", nonce)]
    s = init[:]
    _rounds(s)
    return struct.pack("<16I", *((a + b) & M32 for a, b in zip(s, init)))


def chacha20(key, counter, nonce, data):
    stream = b"".join(_chacha_block(key, counter + i, nonce) for i in range((len(data) + 63) // 64))
    n = len(data)
    return (int.from_bytes(data, "little") ^ int.from_bytes(stream[:n], "little")).to_bytes(n, "little")


def poly1305(key, msg):
    r = int.from_bytes(key[:16], "little") & 0x0FFFFFFC0FFFFFFC0FFFFFFC0FFFFFFF
    p, acc = (1 << 130) - 5, 0
    for i in range(0, len(msg), 16):
        acc = (acc + int.from_bytes(msg[i:i + 16] + b"\x01", "little")) * r % p
    return ((acc + int.from_bytes(key[16:], "little")) & ((1 << 128) - 1)).to_bytes(16, "little")


def _tag(key, nonce, aad, ct):
    pad = lambda b: b"\0" * (-len(b) % 16)
    otk = _chacha_block(key, 0, nonce)[:32]
    return poly1305(otk, aad + pad(aad) + ct + pad(ct) + struct.pack("<QQ", len(aad), len(ct)))


def aead_seal(key, nonce, plaintext, aad):
    ct = chacha20(key, 1, nonce, plaintext)
    return ct + _tag(key, nonce, aad, ct)


def aead_open(key, nonce, sealed, aad):
    ct, tag = sealed[:-16], sealed[-16:]
    if len(sealed) < 16 or not hmac.compare_digest(_tag(key, nonce, aad, ct), tag):
        raise Reject("auth_failed")
    return chacha20(key, 1, nonce, ct)


def _hchacha20(key, nonce16):
    s = [*SIGMA, *struct.unpack("<8I", key), *struct.unpack("<4I", nonce16)]
    _rounds(s)
    return struct.pack("<8I", *s[0:4], *s[12:16])


def xaead_seal(key, nonce24, plaintext, aad):
    return aead_seal(_hchacha20(key, nonce24[:16]), b"\0" * 4 + nonce24[16:], plaintext, aad)


def xaead_open(key, nonce24, sealed, aad):
    return aead_open(_hchacha20(key, nonce24[:16]), b"\0" * 4 + nonce24[16:], sealed, aad)


# --- Curve25519: X25519 (RFC 7748), Ed25519 (RFC 8032) and ristretto255 (RFC 9496) share the field arithmetic

P = 2**255 - 19
L = 2**252 + 27742317777372353535851937790883648493
D = -121665 * pow(121666, P - 2, P) % P
SQRT_M1 = pow(2, (P - 1) // 4, P)


def x25519(scalar, u):
    k = int.from_bytes(scalar, "little") & ~7 & ~(1 << 255) | (1 << 254)
    x1 = int.from_bytes(u, "little") & ((1 << 255) - 1)
    x2, z2, x3, z3, swap = 1, 0, x1, 1, 0
    for t in reversed(range(255)):
        bit = (k >> t) & 1
        if swap ^ bit:
            x2, x3, z2, z3 = x3, x2, z3, z2
        swap = bit
        a, b, c, d = x2 + z2, x2 - z2, x3 + z3, x3 - z3
        aa, bb, da, cb = a * a, b * b, d * a, c * b
        e = aa - bb
        x3, z3 = (da + cb) ** 2 % P, x1 * (da - cb) ** 2 % P
        x2, z2 = aa * bb % P, e * (aa + 121665 * e) % P
    if swap:
        x2, z2 = x3, z3
    return (x2 * pow(z2, P - 2, P) % P).to_bytes(32, "little")


X25519_BASE = (9).to_bytes(32, "little")
IDENTITY = (0, 1, 1, 0)


def _add(p, q):
    a = (p[1] - p[0]) * (q[1] - q[0]) % P
    b = (p[1] + p[0]) * (q[1] + q[0]) % P
    c = 2 * p[3] * q[3] * D % P
    d = 2 * p[2] * q[2] % P
    e, f, g, h = b - a, d - c, d + c, b + a
    return (e * f % P, g * h % P, f * g % P, e * h % P)


def _mul(s, p):
    q = IDENTITY
    while s:
        if s & 1:
            q = _add(q, p)
        p, s = _add(p, p), s >> 1
    return q


def _recover_x(y, sign):
    if y >= P:
        return None
    x2 = (y * y - 1) * pow(D * y * y + 1, P - 2, P) % P
    x = pow(x2, (P + 3) // 8, P)
    if (x * x - x2) % P:
        x = x * SQRT_M1 % P
    if (x * x - x2) % P or (x == 0 and sign):
        return None
    return P - x if x & 1 != sign else x


_GY = 4 * pow(5, P - 2, P) % P
_GX = _recover_x(_GY, 0)
BASE = (_GX, _GY, 1, _GX * _GY % P)


def _same(p, q):
    return (p[0] * q[2] - q[0] * p[2]) % P == 0 and (p[1] * q[2] - q[1] * p[2]) % P == 0


def _ed_encode(p):
    zi = pow(p[2], P - 2, P)
    x, y = p[0] * zi % P, p[1] * zi % P
    return (y | (x & 1) << 255).to_bytes(32, "little")


def _ed_decode(b):
    y = int.from_bytes(b, "little")
    x = _recover_x(y & ((1 << 255) - 1), y >> 255)
    return None if x is None else (x, y & ((1 << 255) - 1), 1, x * (y & ((1 << 255) - 1)) % P)


def _ed_secret(seed):
    h = hashlib.sha512(seed).digest()
    return int.from_bytes(h[:32], "little") & ~7 & ~(1 << 255) | (1 << 254), h[32:]


def ed25519_public(seed):
    return _ed_encode(_mul(_ed_secret(seed)[0], BASE))


def ed25519_sign(seed, msg):
    a, prefix = _ed_secret(seed)
    pub = _ed_encode(_mul(a, BASE))
    r = int.from_bytes(hashlib.sha512(prefix + msg).digest(), "little") % L
    big_r = _ed_encode(_mul(r, BASE))
    k = int.from_bytes(hashlib.sha512(big_r + pub + msg).digest(), "little") % L
    return big_r + ((r + k * a) % L).to_bytes(32, "little")


def ed25519_verify(pub, msg, sig):
    """RFC 8032 verification, strict as ed25519-dalek's verify_strict: canonical encodings, S < L, and no small-order
    public key or R (they let one signature verify for every message)."""
    a, r = _ed_decode(pub), _ed_decode(sig[:32])
    if len(sig) != 64 or a is None or r is None or _ed_encode(a) != pub or _ed_encode(r) != sig[:32]:
        return False
    if _same(_mul(8, a), IDENTITY) or _same(_mul(8, r), IDENTITY):
        return False
    s = int.from_bytes(sig[32:], "little")
    k = int.from_bytes(hashlib.sha512(sig[:32] + pub + msg).digest(), "little") % L
    return s < L and _same(_mul(s, BASE), _add(r, _mul(k, a)))


def _is_neg(x):
    return x % P & 1


def _sqrt_ratio_m1(u, v):
    v3 = v * v * v % P
    r = u * v3 * pow(u * v3 * v3 * v % P, (P - 5) // 8, P) % P
    check = v * r * r % P
    correct, flipped, flipped_i = check == u % P, check == -u % P, check == -u * SQRT_M1 % P
    if flipped or flipped_i:
        r = r * SQRT_M1 % P
    return correct or flipped, P - r if _is_neg(r) else r


SQRT_AD_MINUS_ONE = 25063068953384623474111414158702152701244531502492656460079210482610430750235
INVSQRT_A_MINUS_D = 54469307008909316920995813868745141605393597292927456921205312896311721017578


def ristretto_decode(b):
    s = int.from_bytes(b, "little")
    if len(b) != 32 or s >= P or s & 1:
        return None
    ss = s * s % P
    u1, u2 = (1 - ss) % P, (1 + ss) % P
    v = (-(D * u1 * u1) - u2 * u2) % P
    ok, invsqrt = _sqrt_ratio_m1(1, v * u2 * u2 % P)
    den_x = invsqrt * u2 % P
    den_y = invsqrt * den_x * v % P
    x = 2 * s * den_x % P
    x = P - x if _is_neg(x) else x
    y = u1 * den_y % P
    t = x * y % P
    return (x, y, 1, t) if ok and not _is_neg(t) and y else None


def ristretto_encode(p):
    x0, y0, z0, t0 = p
    u1 = (z0 + y0) * (z0 - y0) % P
    u2 = x0 * y0 % P
    _, invsqrt = _sqrt_ratio_m1(1, u1 * u2 * u2 % P)
    den1, den2 = invsqrt * u1 % P, invsqrt * u2 % P
    z_inv = den1 * den2 * t0 % P
    if _is_neg(t0 * z_inv):
        x, y, den_inv = y0 * SQRT_M1 % P, x0 * SQRT_M1 % P, den1 * INVSQRT_A_MINUS_D % P
    else:
        x, y, den_inv = x0, y0, den2
    if _is_neg(x * z_inv):
        y = -y % P
    s = den_inv * (z0 - y) % P
    return (P - s if _is_neg(s) else s).to_bytes(32, "little")


def _elligator(t):
    r = SQRT_M1 * t * t % P
    u = (r + 1) * (1 - D * D) % P
    v = (-1 - r * D) * (r + D) % P
    ok, s = _sqrt_ratio_m1(u, v)
    st = s * t % P
    if not ok:
        s = -(P - st if _is_neg(st) else st) % P
    c = -1 if ok else r
    n = (c * (r - 1) * (D - 1) ** 2 - v) % P
    w0, w1, w2, w3 = 2 * s * v % P, n * SQRT_AD_MINUS_ONE % P, (1 - s * s) % P, (1 + s * s) % P
    return (w0 * w3 % P, w2 * w1 % P, w1 * w3 % P, w0 * w2 % P)


def ristretto_from_uniform(b):
    mask = (1 << 255) - 1
    return _add(*(_elligator(int.from_bytes(half, "little") & mask) for half in (b[:32], b[32:])))


def ristretto_same(p, q):
    return (p[0] * q[1] - p[1] * q[0]) % P == 0 or (p[1] * q[1] - p[0] * q[0]) % P == 0


# --- ML-KEM-768 (FIPS 203)

Q, K_MLKEM = 3329, 3


def _br7(i):
    return int(f"{i:07b}"[::-1], 2)


ZETAS = [pow(17, _br7(i), Q) for i in range(128)]
GAMMAS = [pow(17, 2 * _br7(i) + 1, Q) for i in range(128)]


def _ntt(f):
    f, k, n = list(f), 1, 128
    while n >= 2:
        for start in range(0, 256, 2 * n):
            z, k = ZETAS[k], k + 1
            for j in range(start, start + n):
                t = z * f[j + n] % Q
                f[j + n], f[j] = (f[j] - t) % Q, (f[j] + t) % Q
        n //= 2
    return f


def _intt(f):
    f, k, n = list(f), 127, 2
    while n <= 128:
        for start in range(0, 256, 2 * n):
            z, k = ZETAS[k], k - 1
            for j in range(start, start + n):
                t = f[j]
                f[j], f[j + n] = (t + f[j + n]) % Q, z * (f[j + n] - t) % Q
        n *= 2
    return [x * 3303 % Q for x in f]


def _mul_ntt(f, g):
    h = [0] * 256
    for i in range(128):
        a0, a1, b0, b1 = f[2 * i], f[2 * i + 1], g[2 * i], g[2 * i + 1]
        h[2 * i], h[2 * i + 1] = (a0 * b0 + a1 * b1 * GAMMAS[i]) % Q, (a0 * b1 + a1 * b0) % Q
    return h


def _padd(*fs):
    return [sum(c) % Q for c in zip(*fs)]


def _sample_ntt(seed):
    n = 840
    while True:
        stream, f = hashlib.shake_128(seed).digest(n), []
        for i in range(0, n - 2, 3):
            d1 = stream[i] + 256 * (stream[i + 1] % 16)
            d2 = stream[i + 1] // 16 + 16 * stream[i + 2]
            f += [d for d in (d1, d2) if d < Q]
            if len(f) >= 256:
                return f[:256]
        n *= 2


def _cbd2(b):
    bits = int.from_bytes(b, "little")
    return [((bits >> 4 * i & 1) + (bits >> 4 * i + 1 & 1) - (bits >> 4 * i + 2 & 1) - (bits >> 4 * i + 3 & 1)) % Q
            for i in range(256)]


def _prf(s, n):
    return _cbd2(hashlib.shake_256(s + bytes([n])).digest(128))


def _encode(d, f):
    return sum(x << (d * i) for i, x in enumerate(f)).to_bytes(32 * d, "little")


def _decode(d, b):
    v = int.from_bytes(b, "little")
    return [(v >> (d * i)) & ((1 << d) - 1) for i in range(256)]


def _compress(d, f):
    return [((x << (d + 1)) + Q) // (2 * Q) % (1 << d) for x in f]


def _decompress(d, f):
    return [(Q * y + (1 << (d - 1))) >> d for y in f]


def _matrix(rho, transpose):
    return [[_sample_ntt(rho + (bytes([i, j]) if transpose else bytes([j, i]))) for j in range(3)] for i in range(3)]


def mlkem_keygen(d, z):
    g = hashlib.sha3_512(d + bytes([K_MLKEM])).digest()
    rho, sigma = g[:32], g[32:]
    a = _matrix(rho, False)
    s = [_ntt(_prf(sigma, i)) for i in range(3)]
    e = [_ntt(_prf(sigma, 3 + i)) for i in range(3)]
    t = [_padd(*(_mul_ntt(a[i][j], s[j]) for j in range(3)), e[i]) for i in range(3)]
    ek = b"".join(_encode(12, x) for x in t) + rho
    return ek, b"".join(_encode(12, x) for x in s) + ek + hashlib.sha3_256(ek).digest() + z


def _pke_encrypt(ek, m, r):
    t = [_decode(12, ek[384 * i:384 * (i + 1)]) for i in range(3)]
    a = _matrix(ek[1152:], True)
    y = [_ntt(_prf(r, i)) for i in range(3)]
    u = [_padd(_intt(_padd(*(_mul_ntt(a[i][j], y[j]) for j in range(3)))), _prf(r, 3 + i)) for i in range(3)]
    v = _padd(_intt(_padd(*(_mul_ntt(t[j], y[j]) for j in range(3)))), _prf(r, 6), _decompress(1, _decode(1, m)))
    return b"".join(_encode(10, _compress(10, x)) for x in u) + _encode(4, _compress(4, v))


def mlkem_encaps(ek, m):
    if any(_encode(12, [x % Q for x in _decode(12, part)]) != part for part in (ek[:384], ek[384:768], ek[768:1152])):
        raise Reject("bad_public_key")
    g = hashlib.sha3_512(m + hashlib.sha3_256(ek).digest()).digest()
    return g[:32], _pke_encrypt(ek, m, g[32:])


def mlkem_decaps(dk, c):
    ek, h, z = dk[1152:2336], dk[2336:2368], dk[2368:]
    u = [_ntt(_decompress(10, _decode(10, c[320 * i:320 * (i + 1)]))) for i in range(3)]
    s = [_decode(12, dk[384 * i:384 * (i + 1)]) for i in range(3)]
    su = _intt(_padd(*(_mul_ntt(s[i], u[i]) for i in range(3))))
    w = _padd(_decompress(4, _decode(4, c[960:])), [-x % Q for x in su])
    m = _encode(1, _compress(1, w))
    g = hashlib.sha3_512(m + h).digest()
    return g[:32] if _pke_encrypt(ek, m, g[32:]) == c else hashlib.shake_256(z + c).digest(32)


# --- X-Wing (draft-connolly-cfrg-xwing-kem-11): ML-KEM-768 + X25519 with the SHA3-256 combiner

XWING_LABEL = bytes.fromhex("5c2e2f2f5e5c")


def _xwing_expand(sk):
    x = hashlib.shake_256(sk).digest(96)
    ek, dk = mlkem_keygen(x[:32], x[32:64])
    return dk, x[64:], ek + x25519(x[64:], X25519_BASE)


def xwing_public(sk):
    return _xwing_expand(sk)[2]


def xwing_encaps(pk, eseed):
    pk_x = pk[1184:]
    ct_x = x25519(eseed[32:], X25519_BASE)
    ss_m, ct_m = mlkem_encaps(pk[:1184], eseed[:32])
    return hashlib.sha3_256(ss_m + x25519(eseed[32:], pk_x) + ct_x + pk_x + XWING_LABEL).digest(), ct_m + ct_x


def xwing_decaps(sk, ct):
    dk, sk_x, pk = _xwing_expand(sk)
    ss_m = mlkem_decaps(dk, ct[:1088])
    return hashlib.sha3_256(ss_m + x25519(sk_x, ct[1088:]) + ct[1088:] + pk[1184:] + XWING_LABEL).digest()


# --- HPKE (RFC 9180) base mode, single shot, KDF HKDF-SHA256 (0x0001), AEAD ChaCha20-Poly1305 (0x0003), with KEM
# X-Wing (0x647a, draft-ietf-hpke-pq-05 appendix A.5) for PLH or DHKEM(X25519, HKDF-SHA256) (0x0020) for journal entries

XWING_KEM, X25519_KEM = 0x647A, 0x0020


def _labeled_extract(salt, label, ikm, suite):
    return hkdf_extract(salt, b"HPKE-v1" + suite + label + ikm)


def _labeled_expand(prk, label, info, length, suite):
    return hkdf_expand(prk, struct.pack(">H", length) + b"HPKE-v1" + suite + label + info, length)


DHKEM_SUITE = b"KEM" + struct.pack(">H", X25519_KEM)


def dhkem_key_pair(ikm):
    """DeriveKeyPair (RFC 9180 7.1.3) for X25519: (private key, public key)."""
    sk = _labeled_expand(_labeled_extract(b"", b"dkp_prk", ikm, DHKEM_SUITE), b"sk", b"", 32, DHKEM_SUITE)
    return sk, x25519(sk, X25519_BASE)


def _dhkem_shared(dh, enc, pk_r):
    if dh == bytes(32):
        raise Reject("auth_failed")
    prk = _labeled_extract(b"", b"eae_prk", dh, DHKEM_SUITE)
    return _labeled_expand(prk, b"shared_secret", enc + pk_r, 32, DHKEM_SUITE)


def dhkem_encaps(pk_r, ikm_e):
    sk_e, enc = dhkem_key_pair(ikm_e)
    return _dhkem_shared(x25519(sk_e, pk_r), enc, pk_r), enc


def dhkem_decaps(sk_r, enc):
    return _dhkem_shared(x25519(sk_r, enc), enc, x25519(sk_r, X25519_BASE))


KEMS = {XWING_KEM: (xwing_encaps, xwing_decaps), X25519_KEM: (dhkem_encaps, dhkem_decaps)}


def _suite(kem):
    return b"HPKE" + struct.pack(">HHH", kem, 0x0001, 0x0003)


def hpke_schedule(shared_secret, info, kem=XWING_KEM):
    suite = _suite(kem)
    context = b"\0" + _labeled_extract(b"", b"psk_id_hash", b"", suite) + \
        _labeled_extract(b"", b"info_hash", info, suite)
    secret = _labeled_extract(shared_secret, b"secret", b"", suite)
    return (_labeled_expand(secret, b"key", context, 32, suite),
            _labeled_expand(secret, b"base_nonce", context, 12, suite),
            _labeled_expand(secret, b"exp", context, 32, suite))


def hpke_export(exporter_secret, context, length, kem=XWING_KEM):
    return _labeled_expand(exporter_secret, b"sec", context, length, _suite(kem))


def hpke_seal(pk, eseed, info, aad, plaintext, kem=XWING_KEM):
    shared, enc = KEMS[kem][0](pk, eseed)
    key, nonce, _ = hpke_schedule(shared, info, kem)
    return enc, aead_seal(key, nonce, plaintext, aad)


def hpke_open(sk, enc, info, aad, sealed, kem=XWING_KEM):
    key, nonce, _ = hpke_schedule(KEMS[kem][1](sk, enc), info, kem)
    return aead_open(key, nonce, sealed, aad)


# --- Argon2id v1.3 (RFC 9106)

def _blake2b_long(data, length):
    prefix = struct.pack("<I", length)
    if length <= 64:
        return hashlib.blake2b(prefix + data, digest_size=length).digest()
    v = hashlib.blake2b(prefix + data).digest()
    out = v[:32]
    while length - len(out) > 64:
        v = hashlib.blake2b(v).digest()
        out += v[:32]
    return out + hashlib.blake2b(v, digest_size=length - len(out)).digest()


def _gb(v, a, b, c, d):
    va, vb, vc, vd = v[a], v[b], v[c], v[d]
    va = (va + vb + 2 * (va & M32) * (vb & M32)) & M64
    vd ^= va
    vd = (vd >> 32 | vd << 32) & M64
    vc = (vc + vd + 2 * (vc & M32) * (vd & M32)) & M64
    vb ^= vc
    vb = (vb >> 24 | vb << 40) & M64
    va = (va + vb + 2 * (va & M32) * (vb & M32)) & M64
    vd ^= va
    vd = (vd >> 16 | vd << 48) & M64
    vc = (vc + vd + 2 * (vc & M32) * (vd & M32)) & M64
    vb ^= vc
    vb = (vb >> 63 | vb << 1) & M64
    v[a], v[b], v[c], v[d] = va, vb, vc, vd


def _permute(v, idx):
    for a, b, c, d in ((0, 4, 8, 12), (1, 5, 9, 13), (2, 6, 10, 14), (3, 7, 11, 15),
                       (0, 5, 10, 15), (1, 6, 11, 12), (2, 7, 8, 13), (3, 4, 9, 14)):
        _gb(v, idx[a], idx[b], idx[c], idx[d])


_ROWS = [list(range(16 * i, 16 * i + 16)) for i in range(8)]
_COLS = [[2 * i + 16 * j + k for j in range(8) for k in (0, 1)] for i in range(8)]


def _compress_block(x, y):
    r = [a ^ b for a, b in zip(x, y)]
    q = r[:]
    for idx in _ROWS + _COLS:
        _permute(q, idx)
    return [a ^ b for a, b in zip(q, r)]


def _words(b):
    return list(struct.unpack("<128Q", b))


def argon2id(password, salt, m_kib, t, p, length=32, secret=b"", ad=b""):
    le = lambda n: struct.pack("<I", n)
    h0 = hashlib.blake2b(b"".join(map(le, (p, length, m_kib, t, 0x13, 2))) + le(len(password)) + password +
                         le(len(salt)) + salt + le(len(secret)) + secret + le(len(ad)) + ad).digest()
    lane = 4 * p * (m_kib // (4 * p)) // p
    seg = lane // 4
    mem = [[None] * lane for _ in range(p)]
    for i in range(p):
        for j in (0, 1):
            mem[i][j] = _words(_blake2b_long(h0 + le(j) + le(i), 1024))
    zero = [0] * 128
    for r in range(t):
        for sl in range(4):
            for ln in range(p):
                independent = r == 0 and sl < 2
                inp = [r, ln, sl, lane * p, t, 2] + [0] * 122
                addresses = None
                first = 2 if r == 0 and sl == 0 else 0
                for i in range(first, seg):
                    j = sl * seg + i
                    prev = mem[ln][j - 1]
                    if independent:
                        if i % 128 == 0 or addresses is None:
                            inp[6] += 1
                            addresses = _compress_block(zero, _compress_block(zero, inp))
                        rand = addresses[i % 128]
                    else:
                        rand = prev[0]
                    ref_lane = ln if r == 0 and sl == 0 else (rand >> 32) % p
                    same = ref_lane == ln
                    if r == 0:
                        area = sl * seg + i - 1 if same else sl * seg - (i == 0)
                    else:
                        area = lane - seg + i - 1 if same else lane - seg - (i == 0)
                    x = (rand & M32) ** 2 >> 32
                    start = 0 if r == 0 or sl == 3 else (sl + 1) * seg
                    block = _compress_block(prev, mem[ref_lane][(start + area - 1 - (area * x >> 32)) % lane])
                    mem[ln][j] = block if r == 0 else [a ^ b for a, b in zip(block, mem[ln][j])]
    final = mem[0][lane - 1]
    for i in range(1, p):
        final = [a ^ b for a, b in zip(final, mem[i][lane - 1])]
    return _blake2b_long(struct.pack("<128Q", *final), length)
