// The passkey relay (ADR-0088): runs a WebAuthn ceremony on photolibd's origin, which passkeys are bound to, for an app
// that cannot run it there itself, and hands the credential to the app. The fragment names the ceremony (`op`: create
// or get), its `options` in WebAuthn's JSON, the app's `return` address (photolib: or a loopback http: URL) and the
// button's `label` in the app's language; the app gets `credential` (WebAuthn's JSON) or `error` (a DOMException name).
'use strict';

const fragment = new URLSearchParams(location.hash.slice(1));
const op = fragment.get('op');
const bytes = (text) => Uint8Array.from(atob(text.replace(/-/g, '+').replace(/_/g, '/')), (c) => c.charCodeAt(0));
const text = (buffer) =>
  btoa(String.fromCharCode(...new Uint8Array(buffer))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const ids = (list) => (list ?? []).map((credential) => ({ ...credential, id: bytes(credential.id) }));

// Only the app may receive the credential: its own scheme, or a port on this machine's loopback (RFC 8252 §7).
function returnAddress(address) {
  try {
    const url = new URL(address);
    const loopback = url.protocol === 'http:' && ['127.0.0.1', '[::1]'].includes(url.hostname);
    return url.protocol === 'photolib:' || loopback ? url : null;
  } catch {
    return null;
  }
}

function publicKey(options) {
  const key = { ...options, challenge: bytes(options.challenge) };
  if (op === 'create') {
    key.user = { ...options.user, id: bytes(options.user.id) };
    key.excludeCredentials = ids(options.excludeCredentials);
  } else {
    key.allowCredentials = ids(options.allowCredentials);
  }
  return key;
}

function json(credential) {
  const answer = credential.response;
  const response = { clientDataJSON: text(answer.clientDataJSON) };
  if (op === 'create') {
    response.attestationObject = text(answer.attestationObject);
    response.transports = answer.getTransports?.() ?? [];
  } else {
    response.authenticatorData = text(answer.authenticatorData);
    response.signature = text(answer.signature);
    if (answer.userHandle) response.userHandle = text(answer.userHandle);
  }
  return {
    id: credential.id,
    rawId: text(credential.rawId),
    type: credential.type,
    response,
    authenticatorAttachment: credential.authenticatorAttachment,
    clientExtensionResults: credential.getClientExtensionResults(),
  };
}

const back = returnAddress(fragment.get('return'));
const button = document.getElementById('go');
if (back && ['create', 'get'].includes(op) && fragment.has('options')) {
  button.textContent = fragment.get('label') || '🔑';
  button.hidden = false;
  button.addEventListener('click', async () => {
    button.disabled = true;
    try {
      const credential = await navigator.credentials[op]({ publicKey: publicKey(JSON.parse(fragment.get('options'))) });
      back.searchParams.set('credential', JSON.stringify(json(credential)));
    } catch (error) {
      back.searchParams.set('error', error.name);
    }
    location.replace(back.href);
  });
}
