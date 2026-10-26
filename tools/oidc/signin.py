"""Signs in at a real OpenID Connect provider as a person in a browser would, for photolibd's interoperability checks.

  signin.py URL                       sign in at an authorization URL; print where the provider redirects
  signin.py --record ISSUER CLIENT    sign in as photolibd's client would and print the provider's keys, ID token and
                                      userinfo as a fixture for testdata/oidc/ (no secret, no access token)

OIDC_KIND (keycloak or authelia) says how the provider's login page works; OIDC_USER and OIDC_PASSWORD are the
person; OIDC_SECRET is the client's secret, if any; OIDC_SCOPES what to ask for (openid profile email); OIDC_CA a CA
file the provider's certificate chains to.
"""
import base64, hashlib, html, json, os, re, secrets, ssl, sys, urllib.error, urllib.parse, urllib.request

REDIRECT = "app.photolib:/oidc"


class Stay(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args):
        return None


opener = urllib.request.build_opener(
    urllib.request.HTTPSHandler(context=ssl.create_default_context(cafile=os.environ.get("OIDC_CA"))), Stay)
cookies = {}


def go(url, data=None, headers={}):
    """One request with every cookie set so far: a provider may mark them Secure on http://localhost."""
    headers = {**headers, "Cookie": "; ".join(f"{name}={value}" for name, value in cookies.items())}
    try:
        response = opener.open(urllib.request.Request(url, data=data, headers=headers))
    except urllib.error.HTTPError as error:
        response = error
    for cookie in response.headers.get_all("Set-Cookie") or []:
        name, _, value = cookie.split(";")[0].partition("=")
        cookies[name.strip()] = value
    return response.status, response.headers, response.read().decode()


def sign_in(url):
    """The URL the provider redirects to once the person signed in at the authorization URL `url`."""
    user, password = os.environ["OIDC_USER"], os.environ["OIDC_PASSWORD"]
    status, headers, body = go(url)
    if os.environ["OIDC_KIND"] == "keycloak":
        action = html.unescape(re.search(r'action="([^"]+)"', body).group(1))
        status, headers, body = go(action, urllib.parse.urlencode({"username": user, "password": password}).encode())
    else:
        portal = urllib.parse.urlparse(headers["Location"])
        flow = dict(urllib.parse.parse_qsl(portal.query))
        login = {"username": user, "password": password, "keepMeLoggedIn": False,
                 "flowID": flow.get("flow_id"), "flow": flow.get("flow"), "subflow": flow.get("subflow")}
        status, headers, body = go(f"{portal.scheme}://{portal.netloc}/api/firstfactor", json.dumps(login).encode(),
                                   {"Content-Type": "application/json"})
        status, headers, body = go(json.loads(body)["data"]["redirect"])
    return headers.get("Location") or sys.exit(f"no redirect: {status} {body[:2000]}")


def record(issuer, client):
    discovery = json.loads(go(issuer.rstrip("/") + "/.well-known/openid-configuration")[2])
    verifier, nonce = secrets.token_urlsafe(48), secrets.token_urlsafe(24)
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
    query = {"response_type": "code", "client_id": client, "redirect_uri": REDIRECT, "nonce": nonce,
             "scope": os.environ.get("OIDC_SCOPES", "openid profile email"), "state": secrets.token_urlsafe(24),
             "code_challenge": challenge, "code_challenge_method": "S256"}
    redirect = sign_in(discovery["authorization_endpoint"] + "?" + urllib.parse.urlencode(query))
    code = dict(urllib.parse.parse_qsl(urllib.parse.urlparse(redirect).query))["code"]
    form = {"grant_type": "authorization_code", "code": code, "redirect_uri": REDIRECT, "code_verifier": verifier}
    headers = {"Content-Type": "application/x-www-form-urlencoded"}
    if os.environ.get("OIDC_SECRET"):
        basic = f"{client}:{os.environ['OIDC_SECRET']}".encode()
        headers["Authorization"] = "Basic " + base64.b64encode(basic).decode()
    else:
        form["client_id"] = client
    tokens = json.loads(go(discovery["token_endpoint"], urllib.parse.urlencode(form).encode(), headers)[2])
    userinfo = go(discovery["userinfo_endpoint"], headers={"Authorization": "Bearer " + tokens["access_token"]})[2]
    print(json.dumps({
        "issuer": issuer, "client_id": client, "nonce": nonce,
        "jwks": json.loads(go(discovery["jwks_uri"])[2]),
        # The ID token's parts apart, so that no secret scanner takes a test token for a credential.
        "id_token_parts": tokens["id_token"].split("."),
        "userinfo": json.loads(userinfo),
    }, indent=2))


if __name__ == "__main__":
    record(*sys.argv[2:4]) if sys.argv[1] == "--record" else print(sign_in(sys.argv[1]))
