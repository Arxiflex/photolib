use std::fmt;

use serde::{Deserialize, Serialize, Serializer};

/// A value that must never reach a log line, an error message or a serialised copy of the configuration.
#[derive(Clone, Deserialize, PartialEq, Eq)]
#[serde(transparent)]
pub struct Secret<T>(T);

impl<T> Secret<T> {
    pub fn new(value: T) -> Self {
        Secret(value)
    }

    pub fn expose(&self) -> &T {
        &self.0
    }
}

impl<T> fmt::Debug for Secret<T> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("[redacted]")
    }
}

impl<T> fmt::Display for Secret<T> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("[redacted]")
    }
}

impl<T> Serialize for Secret<T> {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.serialize_str("[redacted]")
    }
}

/// 256 random bits as 64 lowercase hexadecimal digits.
pub fn random_hex() -> String {
    let mut bytes = [0; 32];
    getrandom::fill(&mut bytes).expect("the operating system provides random numbers");
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_secret_prints_as_redacted_everywhere() {
        let secret = Secret::new("hunter2".to_string());
        assert_eq!(format!("{secret:?}"), "[redacted]");
        assert_eq!(format!("{secret}"), "[redacted]");
        assert_eq!(serde_json::to_string(&secret).unwrap(), "\"[redacted]\"");
    }

    #[test]
    fn a_secret_deserialises_from_the_plain_value_and_is_exposed_on_request() {
        let secret: Secret<String> = serde_json::from_str("\"hunter2\"").unwrap();
        assert_eq!(secret.expose(), "hunter2");
    }

    #[test]
    fn a_structure_holding_a_secret_never_prints_it() {
        #[derive(Debug)]
        struct Holder {
            _url: Secret<String>,
        }
        let printed = format!(
            "{:?}",
            Holder {
                _url: Secret::new("hunter2".into())
            }
        );
        assert!(!printed.contains("hunter2"), "{printed}");
    }
}
