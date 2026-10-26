//! OPAQUE-3DH (docs/dev/crypto-v1.md#opaque) for the client and the server, with opaque-ke: OPRF ristretto255-SHA512,
//! the KSF Argon2id with the account's m and t over a zero salt, context `photolib/v1/opaque`, default identities.
//! Each side's two steps take the same randomness, so that the second rebuilds the state of the first.

use crate::keys::{argon2_params, argon2id_into, nfc};
use crate::proto::kernel::v1::{
    CallError, OpaqueClientResponse, OpaqueLoginRequest, OpaqueRegisterRequest, OpaqueServerLoginRequest,
    OpaqueServerRegisterRequest, OpaqueServerResponse,
};
use crate::{Randomness, invalid_request, reject};
use curve25519_dalek::constants::RISTRETTO_BASEPOINT_COMPRESSED;
use opaque_ke::errors::InternalError;
use opaque_ke::generic_array::{ArrayLength, GenericArray};
use opaque_ke::rand::{CryptoRng, RngCore};
use opaque_ke::{
    ClientLogin, ClientLoginFinishParameters, ClientRegistration, ClientRegistrationFinishParameters,
    CredentialFinalization, CredentialRequest, CredentialResponse, Identifiers, RegistrationRequest,
    RegistrationResponse, Ristretto255, ServerLogin, ServerLoginParameters, ServerRegistration, ServerSetup, TripleDh,
};
use zeroize::{Zeroize, Zeroizing};

const CONTEXT: &[u8] = b"photolib/v1/opaque";

struct Suite;

impl opaque_ke::CipherSuite for Suite {
    type OprfCs = Ristretto255;
    type KeyExchange = TripleDh<Ristretto255, sha512::Sha512>;
    type Ksf = Ksf;
}

/// Argon2id with the account's m and t, `p = 1` and `S = Z(16)`.
#[derive(Default)]
struct Ksf((u32, u32));

impl opaque_ke::ksf::Ksf for Ksf {
    fn hash<L: ArrayLength<u8>>(&self, input: GenericArray<u8, L>) -> Result<GenericArray<u8, L>, InternalError> {
        let mut output = GenericArray::default();
        argon2id_into(&input, &[0; 16], self.0, &mut output).map_err(|_| InternalError::KsfError)?;
        Ok(output)
    }
}

impl RngCore for Randomness {
    fn next_u32(&mut self) -> u32 {
        u32::from_le_bytes(self.word())
    }

    fn next_u64(&mut self) -> u64 {
        u64::from_le_bytes(self.word())
    }

    fn fill_bytes(&mut self, out: &mut [u8]) {
        self.fill(out);
    }

    fn try_fill_bytes(&mut self, out: &mut [u8]) -> Result<(), opaque_ke::rand::Error> {
        self.fill(out);
        Ok(())
    }
}

impl CryptoRng for Randomness {}

/// Draws 64 bytes for a blinding scalar, then the rest.
pub fn register(mut r: OpaqueRegisterRequest) -> Result<OpaqueClientResponse, CallError> {
    let password = nfc(&mut r.password);
    let ksf = Ksf(argon2_params(&r.params)?);
    let mut randomness = Randomness::take(&mut r.randomness, 96, 0)?;
    let start = ClientRegistration::<Suite>::start(&mut randomness, password.as_bytes())
        .map_err(|_| invalid_request("password"))?;
    if r.response.is_empty() {
        return Ok(OpaqueClientResponse {
            message: start.message.serialize().to_vec(),
            ..Default::default()
        });
    }
    let response = RegistrationResponse::deserialize(&r.response).map_err(|_| invalid_request("response"))?;
    let parameters = ClientRegistrationFinishParameters::new(Identifiers::default(), Some(&ksf));
    let finish = (start.state)
        .finish(&mut randomness, password.as_bytes(), response, parameters)
        .map_err(|_| invalid_request("response"))?;
    Ok(OpaqueClientResponse {
        message: finish.message.serialize().to_vec(),
        export_key: finish.export_key.to_vec(),
        ..Default::default()
    })
}

/// Draws 64 bytes for a blinding scalar, then the ephemeral key's seed and the nonce.
pub fn login(mut r: OpaqueLoginRequest) -> Result<OpaqueClientResponse, CallError> {
    let password = nfc(&mut r.password);
    let ksf = Ksf(argon2_params(&r.params)?);
    let mut randomness = Randomness::take(&mut r.randomness, 128, 0)?;
    let start =
        ClientLogin::<Suite>::start(&mut randomness, password.as_bytes()).map_err(|_| invalid_request("password"))?;
    if r.ke2.is_empty() {
        return Ok(OpaqueClientResponse {
            message: start.message.serialize().to_vec(),
            ..Default::default()
        });
    }
    let ke2 = CredentialResponse::deserialize(&r.ke2).map_err(|_| invalid_request("ke2"))?;
    let parameters = ClientLoginFinishParameters::new(Some(CONTEXT), Identifiers::default(), Some(&ksf));
    let finish = (start.state)
        .finish(&mut randomness, password.as_bytes(), ke2, parameters)
        .map_err(|_| reject("envelope_recovery"))?;
    Ok(OpaqueClientResponse {
        message: finish.message.serialize().to_vec(),
        session_key: finish.session_key.to_vec(),
        export_key: finish.export_key.to_vec(),
    })
}

/// The server's keys, zeroizing the request's copies.
fn setup(oprf_seed: &mut Vec<u8>, private_key: &mut Vec<u8>) -> Result<ServerSetup<Suite>, CallError> {
    let lengths = (oprf_seed.len(), private_key.len());
    // The last part is the public key of the fake record for unknown users, which logins here never need.
    let setup = Zeroizing::new([&oprf_seed[..], private_key, RISTRETTO_BASEPOINT_COMPRESSED.as_bytes()].concat());
    oprf_seed.zeroize();
    private_key.zeroize();
    match lengths {
        (64, 32) => ServerSetup::deserialize(&setup).map_err(|_| invalid_request("private_key")),
        (64, _) => Err(invalid_request("private_key")),
        _ => Err(invalid_request("oprf_seed")),
    }
}

pub fn server_register(mut r: OpaqueServerRegisterRequest) -> Result<OpaqueServerResponse, CallError> {
    let setup = setup(&mut r.oprf_seed, &mut r.private_key)?;
    let request = RegistrationRequest::deserialize(&r.request).map_err(|_| invalid_request("request"))?;
    let start = ServerRegistration::<Suite>::start(&setup, request, &r.credential_id)
        .map_err(|_| invalid_request("request"))?;
    Ok(OpaqueServerResponse {
        message: start.message.serialize().to_vec(),
        ..Default::default()
    })
}

/// Draws the masking nonce, the ephemeral key's seed and the nonce.
pub fn server_login(mut r: OpaqueServerLoginRequest) -> Result<OpaqueServerResponse, CallError> {
    let setup = setup(&mut r.oprf_seed, &mut r.private_key)?;
    let record = ServerRegistration::<Suite>::deserialize(&r.record).map_err(|_| invalid_request("record"))?;
    let ke1 = CredentialRequest::deserialize(&r.ke1).map_err(|_| invalid_request("ke1"))?;
    // opaque-ke first draws the masking key of a fake record, used only for unknown users.
    let mut randomness = Randomness::take(&mut r.randomness, 96, 64)?;
    let parameters = || ServerLoginParameters {
        context: Some(CONTEXT),
        identifiers: Identifiers::default(),
    };
    let start = ServerLogin::start(
        &mut randomness,
        &setup,
        Some(record),
        ke1,
        &r.credential_id,
        parameters(),
    )
    .map_err(|_| invalid_request("ke1"))?;
    if r.ke3.is_empty() {
        return Ok(OpaqueServerResponse {
            message: start.message.serialize().to_vec(),
            ..Default::default()
        });
    }
    let ke3 = CredentialFinalization::deserialize(&r.ke3).map_err(|_| invalid_request("ke3"))?;
    let finish = (start.state)
        .finish(ke3, parameters())
        .map_err(|_| reject("auth_failed"))?;
    Ok(OpaqueServerResponse {
        session_key: finish.session_key.to_vec(),
        ..Default::default()
    })
}
