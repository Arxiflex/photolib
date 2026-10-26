//! The search query language (design doc 09 §4.2): words, quoted phrases and key:value operators side by side mean
//! AND; `-` or `NOT` negates, `OR` alternates and parentheses group. Parsing never fails: what is not an operator is
//! text, and unbalanced parentheses or dangling operators are dropped.

use crate::proto::kernel::v1::{ParseQueryResponse, QueryNode, QueryNodeList, QueryTerm, query_node::Node};
use std::iter::Peekable;
use std::vec::IntoIter;

const KEYS: [&str; 35] = [
    "added", "after", "album", "before", "camera", "date", "device", "duration", "ext", "f", "file", "focal", "has",
    "is", "iso", "label", "lens", "library", "month", "mp", "near", "only", "path", "person", "pet", "place", "rating",
    "similar", "size", "sort", "tag", "text", "type", "with", "year",
];
/// Parentheses and negations nest at most this deep, so that the tree stays within every decoder's recursion limit.
const MAX_DEPTH: usize = 8;

enum Token {
    Open,
    Close,
    Or,
    Not,
    Term(QueryTerm),
}

type Tokens = Peekable<IntoIter<Token>>;

pub fn parse(query: &str) -> ParseQueryResponse {
    let mut tokens = tokenize(query).into_iter().peekable();
    let mut nodes = Vec::new();
    while tokens.peek().is_some() {
        nodes.extend(any(&mut tokens, 0));
        tokens.next_if(|t| matches!(t, Token::Close));
    }
    ParseQueryResponse {
        root: group(nodes, Node::All),
    }
}

fn any(tokens: &mut Tokens, depth: usize) -> Option<QueryNode> {
    let mut nodes = Vec::new();
    loop {
        nodes.extend(all(tokens, depth));
        if tokens.next_if(|t| matches!(t, Token::Or)).is_none() {
            return group(nodes, Node::Any);
        }
    }
}

fn all(tokens: &mut Tokens, depth: usize) -> Option<QueryNode> {
    let mut nodes = Vec::new();
    while let Some(token) = tokens.next_if(|t| !matches!(t, Token::Or | Token::Close)) {
        nodes.extend(unary(token, tokens, depth));
    }
    group(nodes, Node::All)
}

fn unary(token: Token, tokens: &mut Tokens, depth: usize) -> Option<QueryNode> {
    match token {
        Token::Term(term) => Some(QueryNode {
            node: Some(Node::Term(term)),
        }),
        // Too deep: drop the operator, so its operand joins the enclosing group.
        Token::Open | Token::Not if depth == MAX_DEPTH => None,
        Token::Open => {
            let inner = any(tokens, depth + 1);
            tokens.next_if(|t| matches!(t, Token::Close));
            inner
        }
        Token::Not => {
            let operand = tokens.next_if(|t| !matches!(t, Token::Or | Token::Close))?;
            let operand = unary(operand, tokens, depth + 1)?;
            Some(QueryNode {
                node: Some(Node::Negated(Box::new(operand))),
            })
        }
        Token::Or | Token::Close => None,
    }
}

fn group(mut nodes: Vec<QueryNode>, kind: fn(QueryNodeList) -> Node) -> Option<QueryNode> {
    match nodes.len() {
        0 | 1 => nodes.pop(),
        _ => Some(QueryNode {
            node: Some(kind(QueryNodeList { nodes })),
        }),
    }
}

fn tokenize(mut rest: &str) -> Vec<Token> {
    let mut tokens = Vec::new();
    loop {
        rest = rest.trim_start();
        let Some(first) = rest.chars().next() else {
            return tokens;
        };
        let after = &rest[first.len_utf8()..];
        let (token, tail) = match first {
            '(' => (Token::Open, after),
            ')' => (Token::Close, after),
            '"' => quoted("", after),
            '-' if after.starts_with(|c: char| !c.is_whitespace() && c != ')') => (Token::Not, after),
            _ => word(rest),
        };
        tokens.push(token);
        rest = tail;
    }
}

fn word(text: &str) -> (Token, &str) {
    let end = text
        .find(|c: char| c.is_whitespace() || "()\"".contains(c))
        .unwrap_or(text.len());
    let (word, rest) = text.split_at(end);
    match word {
        "OR" => return (Token::Or, rest),
        "NOT" => return (Token::Not, rest),
        _ => {}
    }
    if let Some((key, value)) = word.split_once(':') {
        let key = key.to_ascii_lowercase();
        if KEYS.contains(&key.as_str()) {
            if !value.is_empty() {
                return (Token::Term(term(&key, value, false)), rest);
            }
            if let Some(phrase) = rest.strip_prefix('"') {
                return quoted(&key, phrase);
            }
        }
    }
    (Token::Term(term("", word, false)), rest)
}

/// A phrase up to the closing quote, or to the end when there is none.
fn quoted<'a>(key: &str, text: &'a str) -> (Token, &'a str) {
    let (phrase, rest) = text.split_once('"').unwrap_or((text, ""));
    (Token::Term(term(key, phrase, true)), rest)
}

fn term(key: &str, value: &str, phrase: bool) -> QueryTerm {
    QueryTerm {
        key: key.into(),
        value: value.into(),
        phrase,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::proto::kernel::v1::{QueryNodeList, QueryTerm, query_node::Node};
    use prost::Message;

    fn node(node: Node) -> QueryNode {
        QueryNode { node: Some(node) }
    }
    fn term(key: &str, value: &str, phrase: bool) -> QueryNode {
        node(Node::Term(QueryTerm {
            key: key.into(),
            value: value.into(),
            phrase,
        }))
    }
    fn word(value: &str) -> QueryNode {
        term("", value, false)
    }
    fn not(operand: QueryNode) -> QueryNode {
        node(Node::Negated(Box::new(operand)))
    }
    fn all(nodes: Vec<QueryNode>) -> QueryNode {
        node(Node::All(QueryNodeList { nodes }))
    }
    fn any(nodes: Vec<QueryNode>) -> QueryNode {
        node(Node::Any(QueryNodeList { nodes }))
    }
    fn root(query: &str) -> Option<QueryNode> {
        parse(query).root
    }

    #[test]
    fn queries_preserve_terms_precedence_and_error_recovery() {
        for (query, expected) in [
            ("", None),
            (" \t\n", None),
            ("()", None),
            ("beach", Some(word("beach"))),
            ("  sunset   über ", Some(all(vec![word("sunset"), word("über")]))),
            (
                r#""happy birthday" cake"#,
                Some(all(vec![term("", "happy birthday", true), word("cake")])),
            ),
            (
                r#"cake "happy birth"#,
                Some(all(vec![word("cake"), term("", "happy birth", true)])),
            ),
            ("tag:beach", Some(term("tag", "beach", false))),
            ("Type:video", Some(term("type", "video", false))),
            (r#"album:"summer 2019""#, Some(term("album", "summer 2019", true))),
            ("with:anna,ben", Some(term("with", "anna,ben", false))),
            ("colour:red", Some(word("colour:red"))),
            ("tag:", Some(word("tag:"))),
            ("-has:gps", Some(not(term("has", "gps", false)))),
            ("cat NOT dog", Some(all(vec![word("cat"), not(word("dog"))]))),
            (r#"-"red car""#, Some(not(term("", "red car", true)))),
            ("a - b", Some(all(vec![word("a"), word("-"), word("b")]))),
            ("not or", Some(all(vec![word("not"), word("or")]))),
            ("a b OR c", Some(any(vec![all(vec![word("a"), word("b")]), word("c")]))),
            ("a OR b OR c", Some(any(vec![word("a"), word("b"), word("c")]))),
            (
                "(a OR b) c",
                Some(all(vec![any(vec![word("a"), word("b")]), word("c")])),
            ),
            ("-(a b)", Some(not(all(vec![word("a"), word("b")])))),
            ("(a b", Some(all(vec![word("a"), word("b")]))),
            ("a ) b", Some(all(vec![word("a"), word("b")]))),
            ("OR a OR OR b OR", Some(any(vec![word("a"), word("b")]))),
            ("a NOT", Some(word("a"))),
            ("NOT ) a", Some(word("a"))),
        ] {
            assert_eq!(root(query), expected, "{query:?}");
        }
    }

    #[test]
    fn nesting_is_bounded_so_any_decoder_reads_the_tree() {
        for query in [
            "(".repeat(100_000),
            "-".repeat(100_000) + "a",
            "NOT ".repeat(50_000) + "a",
        ] {
            let bytes = parse(&query).encode_to_vec();
            ParseQueryResponse::decode(bytes.as_slice()).expect("decodes within prost's recursion limit");
        }
        let deep = "(".repeat(20) + "a b" + &")".repeat(20);
        assert_eq!(root(&deep), Some(all(vec![word("a"), word("b")])));
    }

    #[test]
    fn any_text_parses() {
        const ALPHABET: [&str; 14] = [
            "a", "b", " ", "(", ")", "\"", "-", ":", "OR", "NOT", "tag", "é", "\t", "😀",
        ];
        let mut seed = 0x9e37_79b9_7f4a_7c15_u64;
        for _ in 0..20_000 {
            let mut query = String::new();
            for _ in 0..seed % 24 {
                seed ^= seed << 13;
                seed ^= seed >> 7;
                seed ^= seed << 17;
                query += ALPHABET[(seed % ALPHABET.len() as u64) as usize];
            }
            let bytes = parse(&query).encode_to_vec();
            ParseQueryResponse::decode(bytes.as_slice()).expect(&query);
        }
    }
}
