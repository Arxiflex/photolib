//! Storage templates (photolib-design docs/07 §2–3, ADR-0089): where an original goes in its managed library, worked
//! out once at ingest and again only by the re-layout job.

use std::str::FromStr;

pub const DEFAULT: &str = "{{year}}/{{year}}-{{month}}/{{filename}}";

/// What a template reads: the capture time as `YYYY MM DD HH MI SS`, the camera and the file's name.
pub struct Fields<'a> {
    pub time: &'a str,
    pub make: Option<&'a str>,
    pub model: Option<&'a str>,
    pub filename: &'a str,
}

/// A parsed template: text and `{{token}}` or `{{token|default:"text"}}` values.
pub struct Template(Vec<Part>);

enum Part {
    Text(String),
    Value(Token, String),
}

#[derive(Clone, Copy, PartialEq)]
enum Token {
    /// The n-th field of the time: year, month, day, hour, minute, second.
    Time(usize),
    Filename,
    Make,
    Model,
}

const TOKENS: [(&str, Token); 9] = [
    ("year", Token::Time(0)),
    ("month", Token::Time(1)),
    ("day", Token::Time(2)),
    ("hour", Token::Time(3)),
    ("minute", Token::Time(4)),
    ("second", Token::Time(5)),
    ("filename", Token::Filename),
    ("make", Token::Make),
    ("model", Token::Model),
];

impl FromStr for Template {
    type Err = String;

    /// Refuses unknown tokens and templates whose last folder lacks `{{filename}}`, where names collide and lose
    /// their extensions.
    fn from_str(text: &str) -> Result<Template, String> {
        let (mut parts, mut rest, mut named) = (vec![], text, false);
        while !rest.is_empty() {
            let Some(inner) = rest.strip_prefix("{{") else {
                let (literal, next) = rest.split_at(rest.find("{{").unwrap_or(rest.len()));
                named &= !literal.contains('/');
                parts.push(Part::Text(literal.into()));
                rest = next;
                continue;
            };
            let (inner, next) = inner
                .split_once("}}")
                .ok_or_else(|| format!("an unclosed {{{{ in the template {text:?}"))?;
            let (name, default) = match inner.split_once('|') {
                None => (inner, ""),
                Some((name, filter)) => (
                    name,
                    (filter.strip_prefix("default:\"").and_then(|d| d.strip_suffix('"')))
                        .ok_or_else(|| format!("{{{{{inner}}}}}: the only filter is default:\"text\""))?,
                ),
            };
            let token = (TOKENS.iter().find(|(known, _)| *known == name))
                .ok_or_else(|| format!("{{{{{name}}}}} is not one of {:?}", TOKENS.map(|t| t.0)))?
                .1;
            named |= token == Token::Filename;
            parts.push(Part::Value(token, default.into()));
            rest = next;
        }
        match named {
            true => Ok(Template(parts)),
            false => Err(format!("the last folder of {text:?} must hold {{{{filename}}}}")),
        }
    }
}

impl Template {
    /// The file's path below the library's originals: values cannot add folders, and every name is one a store
    /// accepts; folders left empty are dropped.
    pub fn render(&self, fields: &Fields) -> String {
        let time: Vec<&str> = fields.time.split(' ').collect();
        let mut path = String::new();
        for part in &self.0 {
            let value = match part {
                Part::Text(text) => {
                    path += text;
                    continue;
                }
                Part::Value(Token::Time(n), _) => time.get(*n).copied().unwrap_or_default(),
                Part::Value(Token::Filename, _) => fields.filename,
                Part::Value(Token::Make, _) => fields.make.unwrap_or_default(),
                Part::Value(Token::Model, _) => fields.model.unwrap_or_default(),
            };
            let value = match (value.trim(), part) {
                ("", Part::Value(_, default)) => default.as_str(),
                _ => value,
            };
            path.extend(value.chars().map(|c| if c == '/' { '_' } else { c }));
        }
        let mut names: Vec<String> = path.split('/').map(name).collect();
        let last = (names.pop().filter(|last| !last.is_empty())).unwrap_or_else(|| UNNAMED.into());
        names.retain(|name| !name.is_empty());
        names.push(last);
        names.join("/")
    }
}

/// A name without control characters or bidirectional overrides (which make a name read as another), without
/// surrounding white space (which S3 keys cannot have), never `.` or `..`, and at most 200 bytes with its extension
/// kept, which leaves room for a number.
fn name(raw: &str) -> String {
    let hidden = |c: char| c.is_control() || matches!(c, '\u{202a}'..='\u{202e}' | '\u{2066}'..='\u{2069}');
    let clean: String = raw.chars().map(|c| if hidden(c) { '_' } else { c }).collect();
    let clean = clean.trim();
    if clean == "." || clean == ".." {
        return UNNAMED.into();
    }
    if clean.len() <= 200 {
        return clean.into();
    }
    let ext = clean.rfind('.').map_or("", |i| &clean[i..]);
    let ext = if ext.len() <= 16 { ext } else { "" };
    let mut end = 200 - ext.len();
    while !clean.is_char_boundary(end) {
        end -= 1;
    }
    format!("{}{ext}", clean[..end].trim_end())
}

/// What stands for a name that is empty, `.` or `..`.
const UNNAMED: &str = "_";

/// The `n`-th key for `key` when the first ones are taken: `key` itself first, then `a/IMG (2).HEIC`.
pub fn numbered(key: &str, n: u32) -> String {
    let (stem, ext) = extension(key);
    match n {
        1 => key.to_owned(),
        n => format!("{stem} ({n}){ext}"),
    }
}

/// Whether `key` is `base` or one of its numbered keys.
pub fn is_numbered(key: &str, base: &str) -> bool {
    let (stem, ext) = extension(base);
    let n = (key.strip_prefix(stem).and_then(|n| n.strip_prefix(" (")))
        .and_then(|n| n.strip_suffix(ext)?.strip_suffix(')')?.parse::<u32>().ok());
    key == base || n.is_some_and(|n| n >= 2 && numbered(base, n) == key)
}

/// A key split before the extension of its last name.
fn extension(key: &str) -> (&str, &str) {
    let name = key.rfind('/').map_or(0, |i| i + 1);
    match key[name..].rfind('.') {
        Some(dot) if dot > 0 => key.split_at(name + dot),
        _ => (key, ""),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fields<'a>(filename: &'a str, make: Option<&'a str>, model: Option<&'a str>) -> Fields<'a> {
        Fields {
            time: "2020 02 29 18 03 11",
            make,
            model,
            filename,
        }
    }

    fn render(template: &str, fields: &Fields) -> String {
        template.parse::<Template>().unwrap().render(fields)
    }

    #[test]
    fn templates_render_the_capture_time_the_camera_and_the_name() {
        let photo = fields("IMG_1.jpg", None, Some("EOS / 5D"));
        assert_eq!(render(DEFAULT, &photo), "2020/2020-02/IMG_1.jpg");
        assert_eq!(
            render(
                "{{make|default:\"No camera\"}}/{{model}}/{{year}}{{month}}{{day}}_{{hour}}{{minute}}{{second}} {{filename}}",
                &photo
            ),
            "No camera/EOS _ 5D/20200229_180311 IMG_1.jpg"
        );
        // A value that is empty without a default leaves no empty folder.
        assert_eq!(render("{{make}}/{{day}}/{{filename}}", &photo), "29/IMG_1.jpg");
    }

    #[test]
    fn hostile_names_and_values_always_render_a_key_below_the_library() {
        let long = format!("{}.jpeg", "é".repeat(200));
        for name in [
            "../../etc/passwd",
            "..",
            ".",
            "",
            "a\nb\u{202e}gpj.exe",
            "\u{1b}[31m red .jpg ",
            "日本語 写真.HEIC",
            "back\\slash.jpg",
            &long,
        ] {
            let photo = fields(name, Some(".."), Some(" /\0 "));
            let path = render("{{make}}/{{model}}/{{filename}}", &photo);
            let key = format!("libraries/l/originals/{path}");
            assert!(photolib_storage::check_key(&key).is_ok(), "{name:?}: {key:?}");
            for segment in path.split('/') {
                assert!(
                    !segment
                        .chars()
                        .any(|c| c.is_control() || ('\u{202a}'..='\u{202e}').contains(&c))
                        && segment.trim() == segment
                        && segment.len() <= 200
                        && segment != "..",
                    "{name:?}: {path:?}"
                );
            }
        }
        assert!(render("{{filename}}", &fields(&long, None, None)).ends_with("éé.jpeg"));
        assert_eq!(render("{{filename}}", &fields("../x.jpg", None, None)), ".._x.jpg");
        assert_eq!(render("{{filename}}", &fields("", None, None)), "_");
    }

    #[test]
    fn templates_without_the_name_in_their_last_folder_or_with_unknown_tokens_are_refused() {
        for bad in [
            "",
            "{{year}}/x",
            "{{filename}}/{{year}}",
            "{{year}",
            "{{year}}/{{filename}",
            "{{nope}}/{{filename}}",
            "{{make|upper}}/{{filename}}",
            "{{make|default:\"x}}/{{filename}}",
        ] {
            assert!(bad.parse::<Template>().is_err(), "{bad:?}");
        }
        for good in [DEFAULT, "{{filename}}", "a/{{year}} {{filename}}.bak"] {
            assert!(good.parse::<Template>().is_ok(), "{good:?}");
        }
    }

    #[test]
    fn a_taken_key_is_numbered_before_its_extension() {
        assert_eq!(numbered("a/IMG.HEIC", 1), "a/IMG.HEIC");
        assert_eq!(numbered("a/IMG.HEIC", 2), "a/IMG (2).HEIC");
        assert_eq!(numbered("a.b/c", 3), "a.b/c (3)");
        assert_eq!(numbered("a/.hidden", 2), "a/.hidden (2)");
        assert_eq!(numbered("a/x.tar.gz", 12), "a/x.tar (12).gz");
        for (key, yes) in [
            ("a/IMG.HEIC", true),
            ("a/IMG (2).HEIC", true),
            ("a/IMG (17).HEIC", true),
            ("a/IMG (1).HEIC", false),
            ("a/IMG (x).HEIC", false),
            ("a/IMG (2).heic", false),
            ("b/IMG (2).HEIC", false),
        ] {
            assert_eq!(is_numbered(key, "a/IMG.HEIC"), yes, "{key}");
        }
    }
}
