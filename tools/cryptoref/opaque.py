"""OPRF (RFC 9497, ristretto255-SHA512, mode 0) and OPAQUE-3DH (RFC 9807) with every random input passed in, so a
whole registration and login can be replayed as a known-answer vector. Reference only, like prims."""
import hashlib
import hmac

from prims import BASE, L, Reject, _mul, hkdf_expand, hkdf_extract, ristretto_decode, ristretto_encode, \
    ristretto_from_uniform

CONTEXT_STRING = b"OPRFV1-\x00-ristretto255-SHA512"
NH = 64


def _i2osp(n, size):
    return n.to_bytes(size, "big")


def _expand_xmd(msg, dst, length):
    dst_prime = dst + _i2osp(len(dst), 1)
    b0 = hashlib.sha512(b"\0" * 128 + msg + _i2osp(length, 2) + b"\0" + dst_prime).digest()
    out = bi = hashlib.sha512(b0 + b"\x01" + dst_prime).digest()
    for i in range(2, -(-length // 64) + 1):
        bi = hashlib.sha512(bytes(a ^ b for a, b in zip(b0, bi)) + _i2osp(i, 1) + dst_prime).digest()
        out += bi
    return out[:length]


def _hash_to_scalar(msg, dst):
    return int.from_bytes(_expand_xmd(msg, dst, 64), "little") % L


def _element(b):
    point = ristretto_decode(b)
    if point is None or ristretto_encode(point) == bytes(32):
        raise Reject("bad_public_key")
    return point


def derive_key_pair(seed, info):
    derive_input = seed + _i2osp(len(info), 2) + info
    for counter in range(256):
        sk = _hash_to_scalar(derive_input + _i2osp(counter, 1), b"DeriveKeyPair" + CONTEXT_STRING)
        if sk:
            return sk, ristretto_encode(_mul(sk, BASE))
    raise Reject("derive_key_pair")


def blind(data, blind_scalar):
    point = ristretto_from_uniform(_expand_xmd(data, b"HashToGroup-" + CONTEXT_STRING, 64))
    return ristretto_encode(_mul(blind_scalar, point))


def blind_evaluate(sk, blinded):
    return ristretto_encode(_mul(sk, _element(blinded)))


def finalize(data, blind_scalar, evaluated):
    unblinded = ristretto_encode(_mul(pow(blind_scalar, -1, L), _element(evaluated)))
    return hashlib.sha512(_i2osp(len(data), 2) + data + _i2osp(len(unblinded), 2) + unblinded + b"Finalize").digest()


def _expand(prk, info, length=NH):
    return hkdf_expand(prk, info, length, "sha512")


def _mac(key, msg):
    return hmac.new(key, msg, "sha512").digest()


def _dh_pair(seed):
    return derive_key_pair(seed, b"OPAQUE-DeriveDiffieHellmanKeyPair")


def _dh(sk, pk):
    return ristretto_encode(_mul(sk, _element(pk)))


def _randomized_password(password, blind_scalar, evaluated, ksf):
    output = finalize(password, blind_scalar, evaluated)
    return hkdf_extract(b"", output + ksf(output), "sha512")


def _envelope_keys(randomized_password, nonce, server_pk):
    sk, pk = _dh_pair(_expand(randomized_password, nonce + b"PrivateKey", 32))
    auth_tag = _mac(_expand(randomized_password, nonce + b"AuthKey"),
                    nonce + server_pk + _i2osp(32, 2) + server_pk + _i2osp(32, 2) + pk)
    return sk, pk, auth_tag, _expand(randomized_password, nonce + b"ExportKey")


def _oprf_key(oprf_seed, credential_identifier):
    return derive_key_pair(_expand(oprf_seed, credential_identifier + b"OprfKey", 32), b"OPAQUE-DeriveKeyPair")[0]


def register(password, credential_identifier, oprf_seed, server_pk, blind_scalar, envelope_nonce, ksf):
    """Registration with default identities (the public keys). Returns the three messages and the export key."""
    request = blind(password, blind_scalar)
    response = blind_evaluate(_oprf_key(oprf_seed, credential_identifier), request) + server_pk
    rwd = _randomized_password(password, blind_scalar, response[:32], ksf)
    _, client_pk, auth_tag, export_key = _envelope_keys(rwd, envelope_nonce, server_pk)
    record = client_pk + _expand(rwd, b"MaskingKey") + envelope_nonce + auth_tag
    return {"registration_request": request, "registration_response": response, "registration_record": record,
            "export_key": export_key}


def _preamble(context, client_pk, ke1, server_pk, credential_response, server_nonce, server_keyshare):
    return (b"OPAQUEv1-" + _i2osp(len(context), 2) + context + _i2osp(32, 2) + client_pk + ke1 + _i2osp(32, 2) +
            server_pk + credential_response + server_nonce + server_keyshare)


def _derive_keys(ikm, preamble):
    def derive_secret(secret, label, transcript):
        label = b"OPAQUE-" + label
        return _expand(secret, _i2osp(NH, 2) + _i2osp(len(label), 1) + label + _i2osp(len(transcript), 1) + transcript)

    prk = hkdf_extract(b"", ikm, "sha512")
    transcript = hashlib.sha512(preamble).digest()
    handshake = derive_secret(prk, b"HandshakeSecret", transcript)
    return (derive_secret(handshake, b"ServerMAC", b""), derive_secret(handshake, b"ClientMAC", b""),
            derive_secret(prk, b"SessionKey", transcript), transcript)


def login(password, record, credential_identifier, oprf_seed, server_sk, server_pk, context, ksf, r):
    """One login, client and server interleaved. `r` holds the random inputs: blind, client_nonce,
    client_keyshare_seed, masking_nonce, server_nonce, server_keyshare_seed."""
    client_pk, masking_key, envelope = record[:32], record[32:96], record[96:]
    request = blind(password, r["blind"])
    client_esk, client_epk = _dh_pair(r["client_keyshare_seed"])
    ke1 = request + r["client_nonce"] + client_epk

    pad = _expand(masking_key, r["masking_nonce"] + b"CredentialResponsePad", 32 + 96)
    credential_response = (blind_evaluate(_oprf_key(oprf_seed, credential_identifier), request) + r["masking_nonce"] +
                           bytes(a ^ b for a, b in zip(pad, server_pk + envelope)))
    server_esk, server_epk = _dh_pair(r["server_keyshare_seed"])
    preamble = _preamble(context, client_pk, ke1, server_pk, credential_response, r["server_nonce"], server_epk)
    km2, km3, session_key, transcript = _derive_keys(
        _dh(server_esk, client_epk) + _dh(server_sk, client_epk) + _dh(server_esk, client_pk), preamble)
    server_mac = _mac(km2, transcript)
    ke2 = credential_response + r["server_nonce"] + server_epk + server_mac

    rwd = _randomized_password(password, r["blind"], ke2[:32], ksf)
    pad = _expand(_expand(rwd, b"MaskingKey"), ke2[32:64] + b"CredentialResponsePad", 32 + 96)
    unmasked = bytes(a ^ b for a, b in zip(pad, ke2[64:192]))
    seen_server_pk, nonce, auth_tag = unmasked[:32], unmasked[32:64], unmasked[64:]
    client_sk, client_pk2, expected_tag, export_key = _envelope_keys(rwd, nonce, seen_server_pk)
    if not hmac.compare_digest(auth_tag, expected_tag):
        raise Reject("envelope_recovery")
    server_nonce, server_keyshare = ke2[192:224], ke2[224:256]
    preamble = _preamble(context, client_pk2, ke1, seen_server_pk, ke2[:192], server_nonce, server_keyshare)
    km2, km3, client_session_key, transcript = _derive_keys(
        _dh(client_esk, server_keyshare) + _dh(client_esk, seen_server_pk) + _dh(client_sk, server_keyshare), preamble)
    if not hmac.compare_digest(ke2[256:], _mac(km2, transcript)):
        raise Reject("server_authentication")
    ke3 = _mac(km3, hashlib.sha512(preamble + ke2[256:]).digest())
    if not hmac.compare_digest(ke3, _mac(km3, hashlib.sha512(preamble + server_mac).digest())):
        raise Reject("client_authentication")
    assert client_session_key == session_key
    return {"KE1": ke1, "KE2": ke2, "KE3": ke3, "session_key": session_key, "export_key": export_key}
