//! What a folder scan skips (photolib-design docs/07 §4): the defaults shared with the apps, then the
//! `.photolibignore` of each directory from the root down, in gitignore syntax (testdata/photolibignore.json). Paths
//! are `/`-separated under the root, compared in any case unless the volume tells case apart. A port of the app's
//! `ignore.dart`, which `photolib upload` and the server's external libraries run.

use std::sync::Arc;

use regex_lite::{Regex, escape};

/// The rules every scan starts with, one per word.
const DEFAULTS: &str =
    r"@eaDir \#recycle .thumbnails .trashed-* .Trash-* $RECYCLE.BIN .dtrash Thumbs.db .DS_Store .AppleDouble";

/// Ignore rules, the last that matches a path deciding.
#[derive(Clone)]
pub struct Rules {
    rules: Vec<Arc<Rule>>,
    case_sensitive: bool,
}

struct Rule {
    base: String,
    glob: Regex,
    negate: bool,
    dir_only: bool,
}

impl Rules {
    /// The defaults, on a volume that tells names apart by case or not.
    pub fn defaults(case_sensitive: bool) -> Self {
        let none = Self {
            rules: Vec::new(),
            case_sensitive,
        };
        none.add("", &DEFAULTS.replace(' ', "\n"))
    }

    /// `text` as these rules compare it: in any case, each character as Dart's case-insensitive `RegExp` sees it
    /// (ECMAScript's Canonicalize), so the apps, `photolib` and the server skip the same names.
    fn fold(&self, text: &str) -> String {
        let canonical = |c: char| {
            let mut upper = c.to_uppercase();
            match (upper.next(), upper.next()) {
                (Some(u), None) if c.is_ascii() || !u.is_ascii() => u,
                _ => c,
            }
        };
        if self.case_sensitive {
            text.into()
        } else {
            text.chars().map(canonical).collect()
        }
    }

    /// These rules followed by `text`, the `.photolibignore` of the directory `base`.
    #[must_use]
    pub fn add(&self, base: &str, text: &str) -> Self {
        let (mut rules, base, text) = (self.rules.clone(), self.fold(base), self.fold(text));
        for line in text.split('\n').filter(|line| !line.starts_with('#')) {
            // Trailing spaces go unless escaped.
            let kept = line.trim_end_matches([' ', '\r']);
            let line = if kept.ends_with('\\') {
                line.get(..=kept.len()).unwrap_or(kept)
            } else {
                kept
            };
            // A line that is no valid pattern, such as `[/]`, matches nothing.
            if let Some(rule) = rule(&base, line).filter(|_| !line.is_empty()) {
                rules.push(Arc::new(rule));
            }
        }
        Self {
            rules,
            case_sensitive: self.case_sensitive,
        }
    }

    /// Whether the last rule that matches `path`, a directory if `dir`, ignores it.
    pub fn ignores(&self, path: &str, dir: bool) -> bool {
        let path = self.fold(path);
        let below = |base: &str| match base {
            "" => Some(path.as_str()),
            base => path.strip_prefix(base)?.strip_prefix('/'),
        };
        let mut matching = self.rules.iter().rev().filter(|r| dir || !r.dir_only);
        matching
            .find(|r| below(&r.base).is_some_and(|rest| r.glob.is_match(rest)))
            .is_some_and(|r| !r.negate)
    }
}

/// The rules in force in the folder `dir`: `root`'s, then the `.photolibignore` of each folder from the root down, as
/// `read` gives it (empty without one); `None` when `dir` or a folder above it is ignored.
pub fn rules_at(root: &Rules, dir: &str, mut read: impl FnMut(&str) -> String) -> Option<Rules> {
    let mut rules = root.add("", &read(""));
    let ends = dir.match_indices('/').map(|(at, _)| at);
    for end in ends.chain((!dir.is_empty()).then_some(dir.len())) {
        let path = dir.get(..end)?;
        if rules.ignores(path, true) {
            return None;
        }
        rules = rules.add(path, &read(path));
    }
    Some(rules)
}

fn rule(base: &str, line: &str) -> Option<Rule> {
    let negate = line.starts_with('!');
    let line = line.strip_prefix('!').unwrap_or(line);
    let dir_only = line.ends_with('/');
    let line = line.strip_suffix('/').unwrap_or(line);
    // A slash before the end anchors the pattern to `base`; without one it matches a name at any depth.
    let mut out = String::from(if line.contains('/') { "^" } else { "^(?:.*/)?" });
    let chars: Vec<char> = line.strip_prefix('/').unwrap_or(line).chars().collect();
    let (mut rest, mut last) = (chars.as_slice(), '/');
    while let Some((&c, tail)) = rest.split_first() {
        // `**` is a whole segment, or two asterisks.
        let (piece, tail, consumed) = match (c, tail) {
            ('*', ['*']) if last == '/' => (".*".into(), &[][..], '*'),
            ('*', ['*', '/', tail @ ..]) if last == '/' => ("(?:.*/)?".into(), tail, '/'),
            ('*', _) => ("[^/]*".into(), stars(tail), '*'),
            ('?', _) => ("[^/]".into(), tail, c),
            ('\\', [next, tail @ ..]) => (escape(&next.to_string()), tail, *next),
            ('[', _) => match class(tail) {
                Some((class, tail)) => (class, tail, ']'),
                None => (escape("["), tail, c),
            },
            (c, _) => (escape(&c.to_string()), tail, c),
        };
        out.push_str(&piece);
        (rest, last) = (tail, consumed);
    }
    out.push('$');
    Some(Rule {
        base: base.into(),
        glob: Regex::new(&out).ok()?,
        negate,
        dir_only,
    })
}

/// `pattern` past its leading asterisks.
fn stars(mut pattern: &[char]) -> &[char] {
    while let ['*', tail @ ..] = pattern {
        pattern = tail;
    }
    pattern
}

/// The bracket expression `pattern` starts with, past its `[`, as a class that never matches a slash, and what
/// follows it; none when it is not closed. Its first character is never the closing one.
fn class(pattern: &[char]) -> Option<(String, &[char])> {
    let (&first, others) = pattern.split_first()?;
    let (body, close) = others.split_at(others.iter().position(|&c| c == ']')?);
    let not = matches!(first, '!' | '^');
    let mut members: Vec<char> = if not { vec![] } else { vec![first] };
    members.extend_from_slice(body);
    let mut class = String::from(if not { "[^/" } else { "[" });
    let mut members = members.as_slice();
    while let Some((&low, tail)) = members.split_first() {
        let (high, tail) = match tail {
            ['-', high, tail @ ..] => (*high, tail),
            _ => (low, tail),
        };
        members = tail;
        // A slash lies between '.' and '0'.
        for (low, high) in [(low, high.min('.')), (low.max('0'), high)] {
            if low <= high {
                class.push_str(&escape(&low.to_string()));
                class.push('-');
                class.push_str(&escape(&high.to_string()));
            }
        }
    }
    class.push(']');
    Some((class, close.get(1..)?))
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use super::{Rules, rules_at};

    /// The cases the app's folder indexer runs too.
    #[test]
    fn ignore_rules_follow_the_shared_cases() {
        let cases = include_str!("../../../../testdata/photolibignore.json");
        let cases: serde_json::Value = serde_json::from_str(cases).unwrap();
        for case in cases["cases"].as_array().unwrap() {
            let read = |dir: &str| case["rules"][dir].as_str().unwrap_or_default().to_owned();
            let defaults = Rules::defaults(case["caseSensitive"].as_bool().unwrap_or(true));
            let ignored = |path: &str| {
                let (path, dir) = path.strip_suffix('/').map_or((path, false), |path| (path, true));
                let parent = path.rsplit_once('/').map_or("", |(parent, _)| parent);
                rules_at(&defaults, parent, read).is_none_or(|rules| rules.ignores(path, dir))
            };
            for (list, expected) in [("ignored", true), ("kept", false)] {
                for path in case[list].as_array().unwrap() {
                    let path = path.as_str().unwrap();
                    assert_eq!(ignored(path), expected, "{}: {path}", case["name"]);
                }
            }
        }
    }

    #[test]
    fn a_class_never_matches_a_slash_even_in_a_range() {
        let rules = Rules::defaults(true).add("", "a[+-0]b\n[/]\n");
        assert!(rules.ignores("a+b", false) && rules.ignores("a0b", false));
        assert!(!rules.ignores("a/b", false) && !rules.ignores("/", false));
    }

    /// As Dart's case-insensitive `RegExp` does, beyond ASCII.
    #[test]
    fn any_case_is_any_case_in_any_script() {
        let rules = Rules::defaults(false).add("x", "Черновики/\n");
        assert!(rules.ignores("x/y/черновики", true) && rules.ignores("x/ЧЕРНОВИКИ", true));
        assert!(!rules.ignores("черновики", true) && !rules.ignores("x/черновики", false));
    }

    /// xorshift64*, so that every run draws the same cases.
    struct Draw(u64);

    impl Draw {
        fn below(&mut self, n: usize) -> usize {
            self.0 ^= self.0 >> 12;
            self.0 ^= self.0 << 25;
            self.0 ^= self.0 >> 27;
            (self.0.wrapping_mul(0x2545_f491_4f6c_dd1d) >> 33) as usize % n
        }

        fn pick<'a, T>(&mut self, from: &'a [T]) -> &'a T {
            &from[self.below(from.len())]
        }

        fn text(&mut self, alphabet: &[char], most: usize) -> String {
            (0..self.below(most + 1)).map(|_| *self.pick(alphabet)).collect()
        }
    }

    /// Whether `glob`, a pattern without `!` or a trailing slash, matches all of `path`: a direct reading of gitignore
    /// globs, to check the regular expressions they compile to.
    fn reference(glob: &str, path: &str) -> bool {
        let anchored = glob.contains('/');
        let glob: Vec<char> = glob.strip_prefix('/').unwrap_or(glob).chars().collect();
        let path: Vec<char> = path.chars().collect();
        let starts = (0..=path.len()).filter(|&i| i == 0 || (!anchored && path[i - 1] == '/'));
        starts.into_iter().any(|i| matches(&glob, &path[i..], None))
    }

    fn matches(glob: &[char], path: &[char], last: Option<char>) -> bool {
        let Some((&c, rest)) = glob.split_first() else {
            return path.is_empty();
        };
        let segment = last.is_none_or(|last| last == '/');
        let after_slash =
            |rest: &[char]| (0..path.len()).any(|i| path[i] == '/' && matches(rest, &path[i + 1..], Some('/')));
        match (c, rest) {
            ('*', ['*']) if segment => true,
            ('*', ['*', '/', rest @ ..]) if segment => matches(rest, path, Some('/')) || after_slash(rest),
            ('*', _) => {
                let rest = &rest[rest.iter().take_while(|&&c| c == '*').count()..];
                let reach = path.iter().position(|&c| c == '/').unwrap_or(path.len());
                (0..=reach).any(|i| matches(rest, &path[i..], Some('*')))
            }
            ('?', _) => path.first().is_some_and(|&p| p != '/') && matches(rest, &path[1..], Some('?')),
            ('[', [_, more @ ..]) if more.contains(&']') => {
                let end = more.iter().position(|&c| c == ']').unwrap() + 1;
                let (set, rest) = (&rest[..end], &rest[end + 1..]);
                let not = matches!(set[0], '!' | '^');
                let items = &set[usize::from(not)..];
                let inside = |p: char| {
                    let mut i = 0;
                    while i < items.len() {
                        let (low, high, used) = match items.get(i + 1..i + 3) {
                            Some(['-', high]) => (items[i], *high, 3),
                            _ => (items[i], items[i], 1),
                        };
                        if low <= p && p <= high {
                            return true;
                        }
                        i += used;
                    }
                    false
                };
                path.first().is_some_and(|&p| p != '/' && inside(p) != not) && matches(rest, &path[1..], Some(']'))
            }
            ('\\', [escaped, rest @ ..]) => path.first() == Some(escaped) && matches(rest, &path[1..], Some(*escaped)),
            (c, _) => path.first() == Some(&c) && matches(rest, &path[1..], Some(c)),
        }
    }

    #[test]
    fn globs_match_what_gitignore_reads_them_to_match() {
        let (mut draw, mut matched) = (Draw(0x9e37_79b9_7f4a_7c15), 0);
        let glob_chars = [
            'a', 'b', 'A', '.', '*', '*', '?', '[', ']', '!', '^', '-', '/', '\\', '0',
        ];
        let name_chars = ['a', 'b', 'A', '.', '-', '!', '[', ']', '*', '\\', '0', '+'];
        let near_chars = ['a', 'b', 'A', '.', '/', '/', '0', '-'];
        for _ in 0..20_000 {
            let glob = draw.text(&glob_chars, 7);
            let glob = glob.trim_end_matches(['/', ' ']).trim_start_matches(['!', '#']);
            // Half the paths are near the glob: its wildcards filled in, slashes included, so that most nearly match.
            let path = if draw.below(2) == 0 {
                (0..=draw.below(3))
                    .map(|_| draw.text(&name_chars, 3))
                    .collect::<Vec<_>>()
                    .join("/")
            } else {
                {
                    let (mut path, mut rest) = (String::new(), glob.trim_start_matches('/'));
                    while let Some(c) = rest.chars().next() {
                        let class = rest.get(2..).and_then(|more| more.find(']')).filter(|_| c == '[');
                        let (next, skip) = match (c, class, draw.below(8)) {
                            ('*', ..) => (draw.text(&near_chars, 3), 1),
                            ('[', Some(end), _) => (draw.pick(&near_chars).to_string(), end + 3),
                            ('\\', ..) => (rest.chars().nth(1).map(String::from).unwrap_or_default(), 2),
                            ('?', ..) | (_, _, 0) => (draw.pick(&near_chars).to_string(), 1),
                            (c, ..) => (c.to_string(), 1),
                        };
                        path += &next;
                        rest = rest.get(skip.min(rest.len())..).unwrap_or_default();
                    }
                    path
                }
            };
            if glob.is_empty() || path.split('/').any(str::is_empty) {
                continue;
            }
            let ours = Rules::defaults(true).add("", glob).ignores(&path, false);
            assert_eq!(ours, reference(glob, &path), "{glob:?} on {path:?}");
            matched += usize::from(ours);
        }
        assert!(matched > 3000, "the cases match now and then: {matched}");
    }

    /// A walk that never enters an ignored folder keeps exactly the files that the rules in force in their folders
    /// keep, path by path: what a scanner holds is what a walk finds, so an exclusion applies to it without a walk.
    #[test]
    fn a_walk_keeps_what_the_rules_of_each_path_keep() {
        let mut draw = Draw(0x2545_f491_4f6c_dd1d);
        let dirs = ["a", "b", "A", "raw", "@eaDir"];
        let files = ["x.jpg", "X.JPG", "y.tmp", "z"];
        let lines = [
            "*.tmp",
            "raw/",
            "/a",
            "!x.jpg",
            "a/**",
            "**/b",
            "[ab]",
            "?",
            "x.*",
            "!raw/",
            "A/",
            "b/x.jpg",
            "!*.JPG",
            "*",
            "!a",
            "\\!z",
            "**/raw/*.jpg",
        ];
        for _ in 0..3000 {
            let mut tree = vec![];
            for _ in 0..=draw.below(12) {
                let depth = draw.below(4);
                let mut path: Vec<&str> = (0..depth).map(|_| *draw.pick(&dirs)).collect();
                path.push(draw.pick(&files));
                tree.push(path.join("/"));
            }
            let mut ignores = BTreeMap::new();
            for _ in 0..draw.below(4) {
                let dir = draw.pick(&tree).rsplit_once('/').map_or("", |(dir, _)| dir).to_owned();
                let text: Vec<&str> = (0..=draw.below(3)).map(|_| *draw.pick(&lines)).collect();
                ignores.insert(dir, text.join("\n"));
            }
            let read = |dir: &str| ignores.get(dir).cloned().unwrap_or_default();
            let defaults = Rules::defaults(draw.below(2) == 0);

            let mut walked = vec![];
            let mut pending = vec![(String::new(), defaults.clone())];
            while let Some((dir, above)) = pending.pop() {
                let rules = above.add(&dir, &read(&dir));
                let prefix = if dir.is_empty() {
                    String::new()
                } else {
                    format!("{dir}/")
                };
                let mut children: Vec<(&str, bool)> = (tree.iter())
                    .filter_map(|path| path.strip_prefix(&prefix))
                    .map(|rest| rest.split_once('/').map_or((rest, false), |(child, _)| (child, true)))
                    .collect();
                children.sort_unstable();
                children.dedup();
                for (name, dir) in children {
                    let path = format!("{prefix}{name}");
                    match (rules.ignores(&path, dir), dir) {
                        (true, _) => {}
                        (false, true) => pending.push((path, rules.clone())),
                        (false, false) => walked.push(path),
                    }
                }
            }
            walked.sort();
            let mut kept: Vec<String> = (tree.iter())
                .filter(|path| {
                    let dir = path.rsplit_once('/').map_or("", |(dir, _)| dir);
                    rules_at(&defaults, dir, read).is_some_and(|rules| !rules.ignores(path, false))
                })
                .cloned()
                .collect();
            kept.sort();
            kept.dedup();
            assert_eq!(walked, kept, "{tree:?} with {ignores:?}");
        }
    }
}
