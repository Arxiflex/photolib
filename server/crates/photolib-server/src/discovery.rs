//! LAN discovery (OPS-29): photolibd answers multicast DNS questions for `_photolib._tcp.local` (DNS-SD, RFC 6763)
//! with its port, its instance, its base path and `public_url`, so that an app on the same network lists it and
//! nobody types an address. It only answers: no announcement on a timer. A question from a port other than 5353, as
//! the apps ask, gets its answer by unicast (RFC 6762 §6.7).

use std::net::{Ipv4Addr, SocketAddr, SocketAddrV4};

use socket2::{Domain, Protocol, Socket, Type};
use tokio::net::UdpSocket;
use tokio_util::sync::CancellationToken;

const SERVICE: &str = "_photolib._tcp.local";
const GROUP: Ipv4Addr = Ipv4Addr::new(224, 0, 0, 251);
const PORT: u16 = 5353;
const PTR: u16 = 12;
const TXT: u16 = 16;
const SRV: u16 = 33;
const ANY: u16 = 255;
const IN: u16 = 1;

/// What photolibd says of itself on the network.
#[derive(Debug, Clone)]
pub struct Service {
    /// Its instance name's first label, such as `photolib-018f9d2e`.
    pub label: String,
    /// The host name its SRV record points to, without `.local`.
    pub host: String,
    /// The port it listens on.
    pub port: u16,
    /// TXT entries: `instance`, `path` and, when set, `url`.
    pub txt: Vec<(&'static str, String)>,
}

/// The multicast DNS socket, shared with any other responder of the host (Avahi, Bonjour).
pub fn socket() -> std::io::Result<UdpSocket> {
    let socket = Socket::new(Domain::IPV4, Type::DGRAM, Some(Protocol::UDP))?;
    socket.set_reuse_address(true)?;
    socket.bind(&SocketAddr::from(SocketAddrV4::new(Ipv4Addr::UNSPECIFIED, PORT)).into())?;
    socket.join_multicast_v4(&GROUP, &Ipv4Addr::UNSPECIFIED)?;
    socket.set_nonblocking(true)?;
    UdpSocket::from_std(socket.into())
}

/// Answers the questions that reach `socket` until `shutdown`.
pub async fn respond(socket: UdpSocket, service: Service, shutdown: CancellationToken) {
    let mut packet = [0u8; 1500];
    loop {
        let received = tokio::select! {
            received = socket.recv_from(&mut packet) => received,
            () = shutdown.cancelled() => return,
        };
        let Ok((length, from)) = received else { continue };
        let unicast = from.port() != PORT;
        let Some(reply) = packet.get(..length).and_then(|query| answer(query, &service, unicast)) else {
            continue;
        };
        let to = if unicast { from } else { SocketAddr::from((GROUP, PORT)) };
        if let Err(error) = socket.send_to(&reply, to).await {
            tracing::debug!(%error, "a discovery answer was not sent");
        }
    }
}

/// The answer to `query` when it asks for Photolib servers: PTR, SRV and TXT records; for a `unicast` (legacy) query
/// with its id and question.
pub fn answer(query: &[u8], service: &Service, unicast: bool) -> Option<Vec<u8>> {
    let &[id0, id1, flags, _, count0, count1, ..] = query.get(..12)? else {
        return None;
    };
    if flags & 0x80 != 0 {
        return None;
    }
    let (mut at, mut asked) = (12, false);
    for _ in 0..u16::from_be_bytes([count0, count1]) {
        let (name, end) = name(query, at)?;
        at = end.checked_add(4)?;
        let &[kind0, kind1, _, _] = query.get(end..at)? else {
            return None;
        };
        let kind = u16::from_be_bytes([kind0, kind1]);
        asked |= name.eq_ignore_ascii_case(SERVICE) && (kind == PTR || kind == ANY);
    }
    if !asked {
        return None;
    }
    let mut out = Vec::with_capacity(256);
    out.extend_from_slice(&if unicast { [id0, id1] } else { [0, 0] });
    out.extend_from_slice(&[0x84, 0, 0, u8::from(unicast), 0, 1, 0, 0, 0, 2]);
    if unicast {
        encode(&mut out, SERVICE);
        out.extend_from_slice(&PTR.to_be_bytes());
        out.extend_from_slice(&IN.to_be_bytes());
    }
    let instance = format!("{}.{SERVICE}", service.label);
    let mut ptr = Vec::new();
    encode(&mut ptr, &instance);
    record(&mut out, SERVICE, PTR, &ptr);
    let mut srv = vec![0, 0, 0, 0];
    srv.extend_from_slice(&service.port.to_be_bytes());
    encode(&mut srv, &format!("{}.local", service.host));
    record(&mut out, &instance, SRV, &srv);
    let mut txt = Vec::new();
    for (key, value) in &service.txt {
        let entry = format!("{key}={value}");
        let entry = entry.as_bytes().get(..255).unwrap_or(entry.as_bytes());
        txt.push(u8::try_from(entry.len()).unwrap_or(u8::MAX));
        txt.extend_from_slice(entry);
    }
    record(&mut out, &instance, TXT, &txt);
    Some(out)
}

fn record(out: &mut Vec<u8>, name: &str, kind: u16, data: &[u8]) {
    encode(out, name);
    out.extend_from_slice(&kind.to_be_bytes());
    out.extend_from_slice(&IN.to_be_bytes());
    out.extend_from_slice(&120u32.to_be_bytes());
    out.extend_from_slice(&u16::try_from(data.len()).unwrap_or(u16::MAX).to_be_bytes());
    out.extend_from_slice(data);
}

fn encode(out: &mut Vec<u8>, name: &str) {
    for label in name.split('.') {
        let label = label.as_bytes().get(..63).unwrap_or(label.as_bytes());
        out.push(u8::try_from(label.len()).unwrap_or(63));
        out.extend_from_slice(label);
    }
    out.push(0);
}

/// The name at `at` and where its encoding ends; None past 128 labels and compression pointers, as a loop.
fn name(packet: &[u8], mut at: usize) -> Option<(String, usize)> {
    let (mut labels, mut end) = (Vec::new(), None);
    for _ in 0..128 {
        let length = *packet.get(at)?;
        let next = at.checked_add(1)?;
        if length == 0 {
            return Some((labels.join("."), end.unwrap_or(next)));
        }
        if length & 0xC0 == 0xC0 {
            end.get_or_insert(next.checked_add(1)?);
            at = usize::from(u16::from_be_bytes([length & 0x3F, *packet.get(next)?]));
        } else {
            at = next.checked_add(usize::from(length))?;
            labels.push(String::from_utf8_lossy(packet.get(next..at)?).into_owned());
        }
    }
    None
}

/// This machine's host name, which its own responder (Avahi, Bonjour) may resolve as `<name>.local`.
pub fn host_name() -> String {
    std::fs::read_to_string("/proc/sys/kernel/hostname")
        .ok()
        .map(|name| name.trim().to_string())
        .filter(|name| !name.is_empty())
        .unwrap_or_else(|| "photolibd".into())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn service() -> Service {
        Service {
            label: "photolib-018f9d2e".into(),
            host: "nas".into(),
            port: 8080,
            txt: vec![
                ("instance", "018f9d2e-7c1b-7d6e-9a3f-2b4c5d6e7f80".into()),
                ("path", "/photos/".into()),
                ("url", "https://photos.example.org/photos/".into()),
            ],
        }
    }

    /// A query with id 0x1234 for `name` and `kind`.
    fn query(name: &str, kind: u16) -> Vec<u8> {
        let mut query = vec![0x12, 0x34, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0];
        encode(&mut query, name);
        query.extend_from_slice(&kind.to_be_bytes());
        query.extend_from_slice(&[0x80, 1]);
        query
    }

    /// The records of an answer: name, type and data, the names in the data decoded.
    fn records(answer: &[u8]) -> Vec<(String, u16, Vec<u8>)> {
        let mut at = 12;
        for _ in 0..u16::from_be_bytes([answer[4], answer[5]]) {
            at = name(answer, at).unwrap().1 + 4;
        }
        let count = u16::from_be_bytes([answer[6], answer[7]]) + u16::from_be_bytes([answer[10], answer[11]]);
        (0..count)
            .map(|_| {
                let (owner, end) = name(answer, at).unwrap();
                let kind = u16::from_be_bytes([answer[end], answer[end + 1]]);
                let length = u16::from_be_bytes([answer[end + 8], answer[end + 9]]) as usize;
                at = end + 10 + length;
                (owner, kind, answer[end + 10..at].to_vec())
            })
            .collect()
    }

    #[test]
    fn a_question_for_photolib_servers_gets_the_instance_its_port_path_and_public_url() {
        let reply = answer(&query("_Photolib._tcp.local", PTR), &service(), true).unwrap();
        assert_eq!(&reply[..4], &[0x12, 0x34, 0x84, 0], "the id, an authoritative answer");
        let records = records(&reply);
        let instance = "photolib-018f9d2e._photolib._tcp.local";
        let kinds: Vec<_> = records.iter().map(|(owner, kind, _)| (owner.as_str(), *kind)).collect();
        assert_eq!(kinds, [(SERVICE, PTR), (instance, SRV), (instance, TXT)]);
        assert_eq!(name(&records[0].2, 0).unwrap().0, instance);
        let srv = &records[1].2;
        assert_eq!(
            (u16::from_be_bytes([srv[4], srv[5]]), name(srv, 6).unwrap().0.as_str()),
            (8080, "nas.local")
        );
        let txt = &records[2].2;
        let mut entries = Vec::new();
        let mut at = 0;
        while at < txt.len() {
            entries.push(String::from_utf8(txt[at + 1..at + 1 + txt[at] as usize].to_vec()).unwrap());
            at += 1 + txt[at] as usize;
        }
        assert_eq!(
            entries,
            [
                "instance=018f9d2e-7c1b-7d6e-9a3f-2b4c5d6e7f80",
                "path=/photos/",
                "url=https://photos.example.org/photos/"
            ]
        );
    }

    #[test]
    fn a_multicast_answer_has_no_id_and_no_question() {
        let reply = answer(&query(SERVICE, ANY), &service(), false).unwrap();
        assert_eq!(&reply[..6], &[0, 0, 0x84, 0, 0, 0]);
        assert_eq!(records(&reply).len(), 3);
    }

    #[test]
    fn other_questions_answers_and_garbage_get_nothing() {
        assert!(answer(&query("_http._tcp.local", PTR), &service(), true).is_none());
        assert!(answer(&query(SERVICE, SRV), &service(), true).is_none());
        let mut response = query(SERVICE, PTR);
        response[2] = 0x84;
        assert!(answer(&response, &service(), true).is_none());
        // A pointer to itself, a name past the end, and every prefix of a real question.
        let mut looped = vec![0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0xC0, 12, 0, 12, 0, 1];
        assert!(answer(&looped, &service(), true).is_none());
        looped[13] = 200;
        assert!(answer(&looped, &service(), true).is_none());
        let real = query(SERVICE, PTR);
        for end in 0..real.len() {
            assert!(answer(&real[..end], &service(), true).is_none(), "{end} bytes");
        }
    }

    /// The apps' question and the answer to it that their tests read (testdata/discovery).
    #[test]
    fn the_apps_question_gets_the_answer_they_read() {
        let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../testdata/discovery");
        let hex = |file: &str| {
            let text = std::fs::read_to_string(dir.join(file)).unwrap();
            let text = text.trim();
            (0..text.len())
                .step_by(2)
                .map(|at| u8::from_str_radix(&text[at..at + 2], 16).unwrap())
                .collect::<Vec<_>>()
        };
        let reply = answer(&hex("query.hex"), &service(), true).unwrap();
        let expected = std::fs::read_to_string(dir.join("answer.hex")).unwrap_or_default();
        let actual = reply
            .iter()
            .fold(String::new(), |hex, byte| hex + &format!("{byte:02x}"));
        assert_eq!(actual, expected.trim(), "testdata/discovery/answer.hex");
    }

    #[tokio::test]
    async fn a_question_from_another_port_is_answered_by_unicast() {
        let responder = UdpSocket::bind("127.0.0.1:0").await.unwrap();
        let at = responder.local_addr().unwrap();
        let shutdown = CancellationToken::new();
        let task = tokio::spawn(respond(responder, service(), shutdown.clone()));
        let app = UdpSocket::bind("127.0.0.1:0").await.unwrap();
        app.send_to(&query(SERVICE, PTR), at).await.unwrap();
        let mut reply = [0u8; 1500];
        let (length, from) = tokio::time::timeout(std::time::Duration::from_secs(5), app.recv_from(&mut reply))
            .await
            .unwrap()
            .unwrap();
        assert_eq!(from, at);
        assert_eq!(records(&reply[..length]).len(), 3);
        shutdown.cancel();
        task.await.unwrap();
    }
}
