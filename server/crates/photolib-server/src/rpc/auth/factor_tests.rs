//! Second factors (M2-05, ADR-0088): TOTP, passkeys and recovery codes at sign-in, the instance's policy and the reset.

use std::time::{SystemTime, UNIX_EPOCH};

use axum::http::StatusCode;
use base64::{Engine, engine::general_purpose::STANDARD};
use opaque_ke::{ClientLogin, ClientLoginFinishParameters, CredentialResponse, Identifiers};
use rand_core::OsRng;
use serde_json::{Value, json};
use uuid::Uuid;

use super::tests::{Server, attempt, phone, server, set_password, signed_in, token};
use crate::{
    auth::{CONTEXT, Suite},
    rpc::account_keys::tests::Enrolment,
    testing::call,
    totp,
    webauthn::{
        UP, UV,
        tests::{Authenticator, b64, rp},
    },
};

fn now_step() -> u64 {
    let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap();
    now.as_secs() / 30
}

fn unbase32(text: &str) -> Vec<u8> {
    let bits: Vec<u8> = text
        .bytes()
        .flat_map(|c| {
            let value = match c {
                b'A'..=b'Z' => c - b'A',
                _ => c - b'2' + 26,
            };
            (0..5).rev().map(move |bit| value >> bit & 1)
        })
        .collect();
    let (bytes, _) = bits.as_chunks::<8>();
    bytes
        .iter()
        .map(|byte| byte.iter().fold(0, |value, bit| value << 1 | bit))
        .collect()
}

/// A six-digit code that is not `secret`'s within two steps of `step`.
fn wrong_code(secret: &[u8], step: u64) -> String {
    let right = [step - 1, step, step + 1, step + 2].map(|step| totp::code(secret, step));
    (0..5)
        .map(|n| format!("{n:06}"))
        .find(|code| !right.contains(code))
        .unwrap()
}

fn denied(status: StatusCode, code: &str, reason: &str) -> (StatusCode, Value) {
    (status, json!({ "code": code, "reason": reason }))
}

fn failed() -> (StatusCode, Value) {
    denied(StatusCode::FORBIDDEN, "permission_denied", "login.failed")
}

fn invalid(field: &str) -> (StatusCode, Value) {
    let error = json!({ "code": "invalid_argument", "reason": "field.invalid", "field": field });
    (StatusCode::BAD_REQUEST, error)
}

fn strings(value: &Value) -> Vec<String> {
    serde_json::from_value(value.clone()).unwrap_or_default()
}

fn options(response: &Value, field: &str) -> Value {
    serde_json::from_str(response[field].as_str().unwrap()).unwrap()
}

fn challenge(options: &Value) -> Vec<u8> {
    use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
    URL_SAFE_NO_PAD.decode(options["challenge"].as_str().unwrap()).unwrap()
}

/// Turns TOTP on for the account of `session`: its secret, and the recovery codes the setup returned.
async fn enable_totp(app: &axum::Router, session: &Value) -> (Vec<u8>, Vec<String>) {
    let (_, started) = call(app, "AuthService/StartTotpSetup", token(session), json!({})).await;
    let secret = unbase32(started["secret"].as_str().unwrap());
    let body = json!({ "setupId": started["setupId"], "code": totp::code(&secret, now_step()) });
    let (status, finished) = call(app, "AuthService/FinishTotpSetup", token(session), body).await;
    assert_eq!(status, StatusCode::OK, "{finished}");
    (secret, strings(&finished["recoveryCodes"]))
}

/// Adds a passkey named `name` to the account of `session`, and returns the authenticator that holds it.
async fn add_passkey(app: &axum::Router, session: &Value, name: &str) -> Authenticator {
    let passkey = Authenticator::new(&rp());
    let (_, started) = call(app, "AuthService/StartPasskeySetup", token(session), json!({})).await;
    let credential = passkey.create(&challenge(&options(&started, "optionsJson")));
    let body = json!({ "setupId": started["setupId"], "credentialJson": credential, "name": name });
    let (status, created) = call(app, "AuthService/FinishPasskeySetup", token(session), body).await;
    assert_eq!(status, StatusCode::OK, "{created}");
    passkey
}

/// Answers the second factor challenge of a password sign-in with `answer`.
async fn answer(app: &axum::Router, challenged: &Value, mut answer: Value) -> (StatusCode, Value) {
    answer["loginId"] = challenged["secondFactor"]["loginId"].clone();
    call(app, "AuthService/FinishSecondFactor", None, answer).await
}

async fn factors(app: &axum::Router, session: &Value) -> Value {
    let (status, listed) = call(app, "AuthService/ListSecondFactors", token(session), json!({})).await;
    assert_eq!(status, StatusCode::OK, "{listed}");
    listed
}

async fn audited(server: &Server, action: &str) -> i64 {
    sqlx::query_scalar("SELECT count(*) FROM audit_events WHERE action = $1")
        .bind(action)
        .fetch_one(&server.pool)
        .await
        .unwrap()
}

#[tokio::test]
async fn with_totp_a_password_sign_in_needs_a_code_that_counts_once_or_a_recovery_code() {
    let server = server().await;
    let app = &server.app;
    let (_, sessions) = signed_in(&server, "ann", &["phone"]).await;
    let session = &sessions[0];
    let (status, started) = call(app, "AuthService/StartTotpSetup", token(session), json!({})).await;
    assert_eq!(status, StatusCode::OK, "{started}");
    let secret = unbase32(started["secret"].as_str().unwrap());
    assert_eq!(secret.len(), 20);
    assert_eq!(started["uri"], totp::uri("Photolib", "ann@photos.example.com", &secret));
    let step = now_step();
    let finish = |code: String| {
        let body = json!({ "setupId": started["setupId"], "code": code });
        call(app, "AuthService/FinishTotpSetup", token(session), body)
    };
    assert_eq!(finish(wrong_code(&secret, step)).await, invalid("code"));
    let (status, finished) = finish(totp::code(&secret, step)).await;
    assert_eq!(status, StatusCode::OK, "a typo does not end the setup: {finished}");
    let codes = strings(&finished["recoveryCodes"]);
    assert_eq!(codes.len(), 10);
    let expired = denied(StatusCode::BAD_REQUEST, "failed_precondition", "setup.expired");
    assert_eq!(finish(totp::code(&secret, step)).await, expired);

    let challenged = attempt(app, "ann", "pw", phone()).await.unwrap();
    assert_eq!(challenged.get("session"), None, "the password alone opens no session");
    assert_eq!(
        challenged["secondFactor"]["factors"],
        json!(["SECOND_FACTOR_TOTP", "SECOND_FACTOR_RECOVERY_CODE"])
    );
    assert_eq!(challenged["secondFactor"].get("passkeyOptionsJson"), None);
    let code = |step| json!({ "totpCode": totp::code(&secret, step) });
    let replayed = answer(app, &challenged, code(step)).await;
    assert_eq!(replayed, failed(), "the setup's code counted already");
    let (status, opened) = answer(app, &challenged, code(step + 1)).await;
    assert_eq!(status, StatusCode::OK, "{opened}");
    let devices = call(app, "AuthService/ListDevices", token(&opened["session"]), json!({}));
    assert_eq!(devices.await.0, StatusCode::OK);

    let challenged = attempt(app, "ann", "pw", phone()).await.unwrap();
    let again = answer(app, &challenged, code(step + 1)).await;
    assert_eq!(again, failed(), "a code counts once");
    for _ in 0..4 {
        let guess = json!({ "recoveryCode": "aaaa-bbbb-cccc-dddd" });
        assert_eq!(answer(app, &challenged, guess).await, failed());
    }
    let right = json!({ "recoveryCode": codes[0] });
    let ended = answer(app, &challenged, right.clone()).await;
    assert_eq!(ended, failed(), "five wrong answers end the sign-in");
    let challenged = attempt(app, "ann", "pw", phone()).await.unwrap();
    assert_eq!(answer(app, &challenged, json!({})).await, failed(), "no answer");
    let typed = json!({ "recoveryCode": codes[0].to_uppercase().replace('-', " ") });
    assert_eq!(answer(app, &challenged, typed).await.0, StatusCode::OK);
    let challenged = attempt(app, "ann", "pw", phone()).await.unwrap();
    let reused = answer(app, &challenged, right).await;
    assert_eq!(reused, failed(), "a recovery code works once");
    let listed = factors(app, session).await;
    assert_eq!(listed, json!({ "totp": true, "recoveryCodesLeft": 9 }));
    assert_eq!(audited(&server, "recovery_code.use").await, 1);

    // Until a second factor answers, every sign-in counts towards the handle's lockout.
    for _ in 0..4 {
        assert!(attempt(app, "ann", "pw", phone()).await.is_ok());
    }
    let throttled = json!({
        "code": "resource_exhausted", "reason": "login.throttled", "retry_after_seconds": "30"
    });
    assert_eq!(attempt(app, "ann", "pw", phone()).await, Err(throttled));
}

/// A password sign-in that a second factor completes returns the password path then, as one without does at once.
#[tokio::test]
async fn a_second_factor_completes_a_password_sign_in_with_its_password_path() {
    let server = server().await;
    let (ann, sessions) = signed_in(&server, "ann", &["phone"]).await;
    let keys = Enrolment::new(ann);
    let created = call(
        &server.app,
        "KeyService/CreateKeys",
        token(&sessions[0]),
        keys.request(),
    );
    assert_eq!(created.await.0, StatusCode::OK);
    let (_, codes) = enable_totp(&server.app, &sessions[0]).await;
    let challenged = attempt(&server.app, "ann", "pw", phone()).await.unwrap();
    assert_eq!(challenged.get("passwordPath"), None, "not before the second factor");
    let (status, opened) = answer(&server.app, &challenged, json!({ "recoveryCode": codes[0] })).await;
    assert_eq!(status, StatusCode::OK, "{opened}");
    let wrap = STANDARD.encode(&keys.password);
    assert_eq!(opened["passwordPath"]["wrap"], wrap);
}

#[tokio::test]
async fn a_passkey_signs_in_alone_or_answers_a_password_sign_in() {
    let server = server().await;
    let app = &server.app;
    let (ann, sessions) = signed_in(&server, "ann", &["laptop"]).await;
    let session = &sessions[0];
    let mut passkey = Authenticator::new(&rp());
    let start = || call(app, "AuthService/StartPasskeySetup", token(session), json!({}));
    let finish = |started: &Value, credential: String, name: &str| {
        let body = json!({ "setupId": started["setupId"], "credentialJson": credential, "name": name });
        call(app, "AuthService/FinishPasskeySetup", token(session), body)
    };
    let (status, started) = start().await;
    assert_eq!(status, StatusCode::OK, "{started}");
    let created_with = options(&started, "optionsJson");
    let user = json!({ "id": b64(ann.as_bytes()), "name": "ann", "displayName": "ann" });
    assert_eq!(created_with["user"], user);
    assert_eq!(created_with["excludeCredentials"], json!([]));
    let created = passkey.create(&challenge(&created_with));
    assert_eq!(finish(&started, created.clone(), " ").await, invalid("name"));
    let (status, added) = finish(&started, created.clone(), " Ann's laptop ").await;
    assert_eq!(status, StatusCode::OK, "{added}");
    assert_eq!(added["passkey"]["name"], "Ann's laptop");
    let codes = strings(&added["recoveryCodes"]);
    assert_eq!(codes.len(), 10, "the first second factor comes with codes");
    let expired = denied(StatusCode::BAD_REQUEST, "failed_precondition", "setup.expired");
    assert_eq!(finish(&started, created, "again").await, expired);
    let (_, started) = start().await;
    let excluded = json!([{ "type": "public-key", "id": b64(&passkey.id) }]);
    assert_eq!(options(&started, "optionsJson")["excludeCredentials"], excluded);
    let mismatched = passkey.create(b"another challenge");
    assert_eq!(finish(&started, mismatched, "x").await, invalid("credential_json"));
    let (_, started) = start().await;
    let twice = passkey.create(&challenge(&options(&started, "optionsJson")));
    let exists = denied(StatusCode::CONFLICT, "already_exists", "passkey.exists");
    assert_eq!(finish(&started, twice, "twice").await, exists);

    let start_login = || async {
        let (status, login) = call(app, "AuthService/StartPasskeyLogin", None, json!({})).await;
        assert_eq!(status, StatusCode::OK, "{login}");
        let options = options(&login, "optionsJson");
        (login, options)
    };
    let finish_login = |login: &Value, credential: &str| {
        let body = json!({
            "loginId": login["loginId"], "credentialJson": credential, "device": phone()
        });
        call(app, "AuthService/FinishPasskeyLogin", None, body)
    };
    let (login, asked) = start_login().await;
    assert_eq!(
        (&asked["allowCredentials"], &asked["userVerification"]),
        (&json!([]), &json!("required"))
    );
    let signed = passkey.get(&challenge(&asked), ann.as_bytes());
    let (status, opened) = finish_login(&login, &signed).await;
    assert_eq!(status, StatusCode::OK, "{opened}");
    assert_eq!(opened["session"]["userId"], ann.to_string());
    let devices = call(app, "AuthService/ListDevices", token(&opened["session"]), json!({}));
    assert_eq!(devices.await.0, StatusCode::OK);
    assert_eq!(finish_login(&login, &signed).await, failed(), "a login id works once");
    let (again, _) = start_login().await;
    let replayed = finish_login(&again, &signed).await;
    assert_eq!(replayed, failed(), "an assertion answers its own challenge only");

    passkey.flags = UP;
    let (login, asked) = start_login().await;
    let unverified = passkey.get(&challenge(&asked), ann.as_bytes());
    let alone = finish_login(&login, &unverified).await;
    assert_eq!(alone, failed(), "alone, a passkey must verify its user");
    let challenged = attempt(app, "ann", "pw", phone()).await.unwrap();
    let second = &challenged["secondFactor"];
    let named = json!(["SECOND_FACTOR_PASSKEY", "SECOND_FACTOR_RECOVERY_CODE"]);
    assert_eq!(second["factors"], named);
    let asked = options(second, "passkeyOptionsJson");
    assert_eq!(
        (&asked["allowCredentials"], &asked["userVerification"]),
        (&excluded, &json!("preferred"))
    );
    let (bob, bob_sessions) = signed_in(&server, "bob", &["phone"]).await;
    let mut bobs = add_passkey(app, &bob_sessions[0], "Bob's phone").await;
    let not_ann = json!({ "passkeyCredentialJson": bobs.get(&challenge(&asked), bob.as_bytes()) });
    let refused = answer(app, &challenged, not_ann).await;
    assert_eq!(refused, failed(), "Bob's passkey does not answer for Ann");
    let ann_answers = json!({ "passkeyCredentialJson": passkey.get(&challenge(&asked), ann.as_bytes()) });
    let answered = answer(app, &challenged, ann_answers).await;
    assert_eq!(answered.0, StatusCode::OK, "a second factor needs presence only");

    let listed = factors(app, session).await;
    let passkeys = listed["passkeys"].as_array().unwrap();
    assert_eq!((passkeys.len(), &passkeys[0]["name"]), (1, &json!("Ann's laptop")));
    let times = (&passkeys[0]["createdAt"], &passkeys[0]["lastUsedAt"]);
    assert!(times.0.is_string() && times.1.is_string(), "{listed}");
    let delete = |id: &Value| {
        let body = json!({ "passkeyId": id });
        call(app, "AuthService/DeletePasskey", token(session), body)
    };
    let not_found = denied(StatusCode::NOT_FOUND, "not_found", "passkey.not_found");
    let bobs_id = &factors(app, &bob_sessions[0]).await["passkeys"][0]["passkeyId"];
    assert_eq!(delete(bobs_id).await, not_found, "nobody deletes another's passkey");
    let id = &passkeys[0]["passkeyId"];
    assert_eq!(delete(id).await, (StatusCode::OK, json!({})));
    assert_eq!(delete(id).await, not_found);
    assert_eq!(delete(&json!("x")).await, not_found);
    passkey.flags = UP | UV;
    let (login, asked) = start_login().await;
    let deleted = passkey.get(&challenge(&asked), ann.as_bytes());
    let gone = finish_login(&login, &deleted).await;
    assert_eq!(gone, failed(), "a deleted passkey signs nobody in");
    let created = audited(&server, "passkey.create").await;
    assert_eq!((created, audited(&server, "passkey.delete").await), (2, 1));

    sqlx::query("UPDATE users SET status = 'disabled' WHERE handle = 'bob'")
        .execute(&server.pool)
        .await
        .unwrap();
    let (login, asked) = start_login().await;
    let disabled = bobs.get(&challenge(&asked), bob.as_bytes());
    let refused = finish_login(&login, &disabled).await;
    assert_eq!(refused, failed(), "nor one of a disabled account");
}

#[tokio::test]
async fn without_a_public_url_there_are_no_passkeys_but_totp_works() {
    let server = server().await;
    let elsewhere = server.with_key(opaque_ke::ServerSetup::new(&mut OsRng));
    let (_, sessions) = signed_in(&server, "ann", &["phone"]).await;
    let session = token(&sessions[0]);
    let unavailable = denied(StatusCode::BAD_REQUEST, "failed_precondition", "passkey.unavailable");
    let login = call(&elsewhere, "AuthService/StartPasskeyLogin", None, json!({}));
    assert_eq!(login.await, unavailable);
    let setup = call(&elsewhere, "AuthService/StartPasskeySetup", session, json!({}));
    assert_eq!(setup.await, unavailable);
    let (_, started) = call(&elsewhere, "AuthService/StartTotpSetup", session, json!({})).await;
    let uri = started["uri"].as_str().unwrap();
    assert!(uri.starts_with("otpauth://totp/Photolib:ann?"), "{uri}");
    for (app, methods) in [
        (&server.app, json!(["AUTH_METHOD_OPAQUE", "AUTH_METHOD_PASSKEY"])),
        (&elsewhere, json!(["AUTH_METHOD_OPAQUE"])),
    ] {
        let (_, info) = call(app, "ServerInfoService/GetServerInfo", None, json!({})).await;
        assert_eq!(info["authMethods"], methods);
    }
}

#[tokio::test]
async fn while_the_instance_requires_a_second_factor_an_account_without_one_only_enrols() {
    let server = server().await;
    let app = &server.app;
    let admin = server.admin().await;
    let (_, sessions) = signed_in(&server, "ann", &["phone"]).await;
    let ann = &sessions[0];
    let require = |on: bool| {
        let settings = json!({ "requireTwoFactor": on, "trashRetentionDays": 60, "minFreeDiskPercent": 5 });
        call(
            app,
            "AdminService/UpdateSettings",
            token(&admin),
            json!({ "settings": settings }),
        )
    };
    let (status, updated) = require(true).await;
    assert_eq!(status, StatusCode::OK, "{updated}");
    let enrol = denied(StatusCode::FORBIDDEN, "permission_denied", "second_factor.required");
    let keys = |session: &Value| {
        let bearer = token(session).map(str::to_owned);
        async move { call(app, "ApiKeyService/ListApiKeys", bearer.as_deref(), json!({})).await }
    };
    assert_eq!(keys(ann).await, enrol, "from the next request on");
    let users = || call(app, "UserService/ListUsers", token(&admin), json!({}));
    assert_eq!(users().await, enrol, "administrators too");
    let devices = call(app, "AuthService/ListDevices", token(ann), json!({}));
    assert_eq!(devices.await.0, StatusCode::OK, "the auth service still answers");
    let signed = attempt(app, "ann", "pw", phone()).await.unwrap();
    assert_eq!(keys(&signed["session"]).await, enrol, "a new session must enrol too");
    enable_totp(app, ann).await;
    assert_eq!(keys(ann).await.0, StatusCode::OK);
    add_passkey(app, &admin, "Root's key").await;
    assert_eq!(users().await.0, StatusCode::OK);
    assert_eq!(require(false).await.0, StatusCode::OK);
    let (_, bob) = signed_in(&server, "bob", &["phone"]).await;
    assert_eq!(keys(&bob[0]).await.0, StatusCode::OK);
}

/// Makes the last proof of every session older than five minutes.
async fn stale(server: &Server) {
    sqlx::query("UPDATE sessions SET proved_at = now() - interval '5 minutes 1 second'")
        .execute(&server.pool)
        .await
        .unwrap();
}

fn step_up_required() -> (StatusCode, Value) {
    denied(StatusCode::FORBIDDEN, "permission_denied", "step_up.required")
}

#[tokio::test]
async fn removing_or_replacing_a_second_factor_needs_a_proof_within_five_minutes() {
    let server = server().await;
    let app = &server.app;
    let (_, sessions) = signed_in(&server, "ann", &["phone"]).await;
    let session = &sessions[0];
    let (secret, _) = enable_totp(app, session).await;
    add_passkey(app, session, "Ann's phone").await;
    let before = factors(app, session).await;
    let passkey = json!({ "passkeyId": before["passkeys"][0]["passkeyId"] });
    let changes = [
        ("AuthService/DeletePasskey", passkey),
        ("AuthService/DeleteTotp", json!({})),
        ("AuthService/CreateRecoveryCodes", json!({})),
        ("AuthService/StartTotpSetup", json!({})),
    ];
    stale(&server).await;
    for (method, body) in &changes {
        let refused = call(app, method, token(session), body.clone()).await;
        assert_eq!(refused, step_up_required(), "{method}");
    }
    assert_eq!(factors(app, session).await, before, "nothing changed");

    let challenged = attempt(app, "ann", "pw", phone()).await.unwrap();
    let code = json!({ "totpCode": totp::code(&secret, now_step() + 1) });
    let (_, opened) = answer(app, &challenged, code).await;
    let fresh = &opened["session"];
    for (method, body) in changes {
        let (status, done) = call(app, method, token(fresh), body).await;
        assert_eq!(status, StatusCode::OK, "a sign-in is a proof: {method} {done}");
    }
    assert_eq!(
        call(app, "AuthService/CreateRecoveryCodes", token(session), json!({})).await,
        step_up_required(),
        "the proof is the session's that made it"
    );
}

/// Starts a step-up of `session`, with a KE1 of `password` when there is one; the start, and with a password the KE3
/// that answers it, or 64 zeros when the password is wrong.
async fn start_step_up(app: &axum::Router, session: &Value, password: Option<&str>) -> (Value, Vec<u8>) {
    let login = password.map(|password| ClientLogin::<Suite>::start(&mut OsRng, password.as_bytes()).unwrap());
    let ke1 = login.as_ref().map(|login| STANDARD.encode(login.message.serialize()));
    let body = json!({ "ke1": ke1.unwrap_or_default() });
    let (status, started) = call(app, "AuthService/StartStepUp", token(session), body).await;
    assert_eq!(status, StatusCode::OK, "{started}");
    let Some((login, password)) = login.zip(password) else {
        return (started, vec![]);
    };
    let ke2 = STANDARD.decode(started["ke2"].as_str().unwrap()).unwrap();
    let ke2 = CredentialResponse::deserialize(&ke2).unwrap();
    let parameters = ClientLoginFinishParameters::new(Some(CONTEXT), Identifiers::default(), None);
    let ke3 = login.state.finish(&mut OsRng, password.as_bytes(), ke2, parameters);
    let ke3 = ke3.map_or_else(|_| vec![0; 64], |finish| finish.message.serialize().to_vec());
    (started, ke3)
}

/// Finishes the step-up `started` with `answer`.
async fn finish_step_up(
    app: &axum::Router,
    session: &Value,
    started: &Value,
    mut answer: Value,
) -> (StatusCode, Value) {
    answer["stepUpId"] = started["stepUpId"].clone();
    call(app, "AuthService/FinishStepUp", token(session), answer).await
}

/// Whether `session` may change its second factors now: it is told that it has no passkey "x".
async fn proved(app: &axum::Router, session: &Value) -> bool {
    let body = json!({ "passkeyId": "x" });
    let (_, answer) = call(app, "AuthService/DeletePasskey", token(session), body).await;
    answer["reason"] == "passkey.not_found"
}

#[tokio::test]
async fn a_session_proves_its_person_again_with_a_code_or_its_password() {
    let server = server().await;
    let app = &server.app;
    let (_, sessions) = signed_in(&server, "ann", &["phone", "laptop"]).await;
    let [phone, laptop] = &sessions[..] else { unreachable!() };
    let (secret, codes) = enable_totp(app, phone).await;
    stale(&server).await;

    let (started, _) = start_step_up(app, phone, None).await;
    let named = json!(["SECOND_FACTOR_TOTP", "SECOND_FACTOR_RECOVERY_CODE"]);
    assert_eq!((&started["factors"], started.get("ke2")), (&named, None));
    let wrong = json!({ "totpCode": wrong_code(&secret, now_step()) });
    assert_eq!(finish_step_up(app, phone, &started, wrong).await, failed());
    let right = json!({ "totpCode": totp::code(&secret, now_step() + 1) });
    let again = finish_step_up(app, phone, &started, right.clone()).await;
    assert_eq!(again, failed(), "a step-up takes one answer");
    assert!(!proved(app, phone).await);
    let (started, _) = start_step_up(app, phone, None).await;
    let by_another = finish_step_up(app, laptop, &started, right.clone()).await;
    assert_eq!(by_another, failed(), "a step-up proves the session that started it");
    let (started, _) = start_step_up(app, phone, None).await;
    assert_eq!(
        finish_step_up(app, phone, &started, right).await,
        (StatusCode::OK, json!({}))
    );
    assert!(proved(app, phone).await);
    assert!(!proved(app, laptop).await, "only the session that stepped up");

    let (started, ke3) = start_step_up(app, laptop, Some("pw")).await;
    let params = STANDARD.decode(started["ksfParams"].as_str().unwrap()).unwrap();
    assert!(crate::auth::ksf_params_valid(&params));
    let password = json!({ "ke3": STANDARD.encode(ke3) });
    assert_eq!(finish_step_up(app, laptop, &started, password).await.0, StatusCode::OK);
    assert!(proved(app, laptop).await);

    stale(&server).await;
    let (started, ke3) = start_step_up(app, laptop, Some("wrong")).await;
    let guess = json!({ "ke3": STANDARD.encode(ke3) });
    assert_eq!(finish_step_up(app, laptop, &started, guess).await, failed());
    let (started, _) = start_step_up(app, laptop, None).await;
    let no_password = json!({ "ke3": STANDARD.encode([0; 64]) });
    assert_eq!(
        finish_step_up(app, laptop, &started, no_password).await,
        failed(),
        "a KE3 needs a KE1"
    );
    let (started, _) = start_step_up(app, laptop, None).await;
    let recovery = json!({ "recoveryCode": codes[0] });
    assert_eq!(
        finish_step_up(app, laptop, &started, recovery.clone()).await.0,
        StatusCode::OK
    );
    assert_eq!(factors(app, laptop).await["recoveryCodesLeft"], 9, "and uses it up");
    let (started, _) = start_step_up(app, phone, None).await;
    assert_eq!(finish_step_up(app, phone, &started, recovery).await, failed());
    assert_eq!(audited(&server, "session.step_up").await, 3);
    let anonymous = call(app, "AuthService/StartStepUp", None, json!({})).await;
    assert_eq!(
        anonymous,
        denied(StatusCode::UNAUTHORIZED, "unauthenticated", "session.required")
    );
}

#[tokio::test]
async fn a_step_up_takes_a_passkey_only_if_it_verifies_its_user_and_counts_towards_the_lockout() {
    let server = server().await;
    let app = &server.app;
    let (ann, sessions) = signed_in(&server, "ann", &["phone"]).await;
    let session = &sessions[0];
    let mut passkey = add_passkey(app, session, "Ann's phone").await;
    stale(&server).await;
    let (started, _) = start_step_up(app, session, None).await;
    let named = json!(["SECOND_FACTOR_PASSKEY", "SECOND_FACTOR_RECOVERY_CODE"]);
    assert_eq!(started["factors"], named);
    let asked = options(&started, "passkeyOptionsJson");
    let allowed = json!([{ "type": "public-key", "id": b64(&passkey.id) }]);
    assert_eq!(
        (&asked["allowCredentials"], &asked["userVerification"]),
        (&allowed, &json!("required"))
    );
    passkey.flags = UP;
    let present = json!({ "passkeyCredentialJson": passkey.get(&challenge(&asked), ann.as_bytes()) });
    assert_eq!(finish_step_up(app, session, &started, present).await, failed());
    passkey.flags = UP | UV;
    let (started, _) = start_step_up(app, session, None).await;
    let asked = options(&started, "passkeyOptionsJson");
    let verified = json!({ "passkeyCredentialJson": passkey.get(&challenge(&asked), ann.as_bytes()) });
    assert_eq!(finish_step_up(app, session, &started, verified).await.0, StatusCode::OK);
    assert!(proved(app, session).await);

    // A right answer clears the handle's count; each start counts again, as a sign-in does.
    for _ in 0..5 {
        start_step_up(app, session, None).await;
    }
    let throttled = json!({
        "code": "resource_exhausted", "reason": "login.throttled", "retry_after_seconds": "30"
    });
    let body = json!({});
    let (status, refused) = call(app, "AuthService/StartStepUp", token(session), body).await;
    assert_eq!((status, refused), (StatusCode::TOO_MANY_REQUESTS, throttled.clone()));
    assert_eq!(attempt(app, "ann", "pw", phone()).await, Err(throttled));
}

#[tokio::test]
async fn a_totp_setup_started_without_a_proof_replaces_no_secret_enabled_meanwhile() {
    let server = server().await;
    let app = &server.app;
    let (_, sessions) = signed_in(&server, "ann", &["phone", "laptop"]).await;
    stale(&server).await;
    let (status, started) = call(app, "AuthService/StartTotpSetup", token(&sessions[0]), json!({})).await;
    assert_eq!(status, StatusCode::OK, "a first secret needs no proof: {started}");
    let (laptops, _) = enable_totp(app, &sessions[1]).await;
    let secret = unbase32(started["secret"].as_str().unwrap());
    let body = json!({ "setupId": started["setupId"], "code": totp::code(&secret, now_step()) });
    let finished = call(app, "AuthService/FinishTotpSetup", token(&sessions[0]), body).await;
    assert_eq!(finished, step_up_required());
    let challenged = attempt(app, "ann", "pw", phone()).await.unwrap();
    let code = json!({ "totpCode": totp::code(&laptops, now_step() + 1) });
    assert_eq!(
        answer(app, &challenged, code).await.0,
        StatusCode::OK,
        "the laptop's secret stays"
    );
}

#[tokio::test]
async fn adding_a_passkey_or_a_password_with_a_session_needs_a_proof_within_five_minutes() {
    let server = server().await;
    let app = &server.app;
    let (_, sessions) = signed_in(&server, "ann", &["phone"]).await;
    let session = &sessions[0];
    stale(&server).await;
    for method in ["StartPasskeySetup", "StartPasswordSetup", "FinishPasswordSetup"] {
        let refused = call(app, &format!("AuthService/{method}"), token(session), json!({})).await;
        assert_eq!(refused, step_up_required(), "{method}");
    }
    let (started, ke3) = start_step_up(app, session, Some("pw")).await;
    let password = json!({ "ke3": STANDARD.encode(ke3) });
    assert_eq!(finish_step_up(app, session, &started, password).await.0, StatusCode::OK);
    add_passkey(app, session, "Ann's phone").await;
    assert_eq!(
        set_password(app, "new", "", token(session)).await,
        (StatusCode::OK, json!({}))
    );
}

/// A session of `user` that proved nothing, as an OIDC sign-in opens.
async fn unproved(server: &Server, user: Uuid) -> Value {
    let token = crate::auth::new_token();
    sqlx::query(
        "WITH device AS (
            INSERT INTO devices (id, user_id, name, platform) VALUES (gen_random_uuid(), $1::uuid, 'laptop', 'linux')
            RETURNING id
        )
        INSERT INTO sessions (id, device_id, token_hash, expires_at)
        SELECT gen_random_uuid(), id, $2, now() + interval '1 hour' FROM device",
    )
    .bind(user.to_string())
    .bind(crate::auth::token_hash(&token))
    .execute(&server.pool)
    .await
    .unwrap();
    json!({ "token": token })
}

#[tokio::test]
async fn an_account_with_nothing_to_prove_with_adds_its_first_passkey_or_password_without_a_step_up() {
    let server = server().await;
    let app = &server.app;
    let (olga, _) = server.person("olga").await;
    let session = &unproved(&server, olga).await;
    let mut passkey = add_passkey(app, session, "Olga's laptop").await;
    let refused = set_password(app, "pw", "", token(session)).await;
    assert_eq!(refused, step_up_required(), "a passkey is something to prove with");
    let (started, _) = start_step_up(app, session, None).await;
    let asked = options(&started, "passkeyOptionsJson");
    let verified = json!({ "passkeyCredentialJson": passkey.get(&challenge(&asked), olga.as_bytes()) });
    assert_eq!(finish_step_up(app, session, &started, verified).await.0, StatusCode::OK);
    assert_eq!(set_password(app, "pw", "", token(session)).await.0, StatusCode::OK);

    let (pia, _) = server.person("pia").await;
    let session = &unproved(&server, pia).await;
    assert_eq!(set_password(app, "pw", "", token(session)).await.0, StatusCode::OK);
    let refused = call(app, "AuthService/StartPasskeySetup", token(session), json!({})).await;
    assert_eq!(refused, step_up_required(), "a password is something to prove with");
}

#[tokio::test]
async fn an_administrator_resets_the_second_factors_of_an_account_that_lost_them() {
    let server = server().await;
    let app = &server.app;
    let admin = server.admin().await;
    let (ann, sessions) = signed_in(&server, "ann", &["phone"]).await;
    enable_totp(app, &sessions[0]).await;
    add_passkey(app, &sessions[0], "Ann's phone").await;
    let challenged = attempt(app, "ann", "pw", phone()).await.unwrap();
    assert!(challenged["secondFactor"].is_object());
    let reset = |user: &str| {
        let body = json!({ "userId": user });
        call(app, "UserService/ResetSecondFactors", token(&admin), body)
    };
    assert_eq!(reset(&ann.to_string()).await, (StatusCode::OK, json!({})));
    let signed = attempt(app, "ann", "pw", phone()).await.unwrap();
    assert!(signed["session"].is_object(), "the password alone signs in: {signed}");
    assert_eq!(factors(app, &sessions[0]).await, json!({}));
    let not_found = denied(StatusCode::NOT_FOUND, "not_found", "user.not_found");
    assert_eq!(reset(&Uuid::now_v7().to_string()).await, not_found);
    assert_eq!(reset("x").await, not_found);
    assert_eq!(audited(&server, "second_factors.reset").await, 1);
}
