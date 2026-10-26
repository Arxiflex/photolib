//! Rules for migration files that PostgreSQL cannot enforce; `cargo test` applies them to every shipped migration.

use std::collections::BTreeSet;

use crate::migrate::Migration;

const SETTINGS: &[&str] = &[
    "ALTER DATABASE",
    "ALTER ROLE",
    "ALTER USER",
    "ALTER SYSTEM",
    "CREATE ROLE",
    "CREATE USER",
    "CREATE DATABASE",
    "DROP ROLE",
    "DROP USER",
    "DROP DATABASE",
    "RESET",
];
const TRANSACTION: &[&str] = &[
    "BEGIN",
    "START TRANSACTION",
    "COMMIT",
    "ROLLBACK",
    "END",
    "ABORT",
    "SAVEPOINT",
];

/// Problems in `m`; `data` holds the ids of the registered data migrations.
pub fn lint(m: &Migration, data: &[&str]) -> Vec<String> {
    let mut problems = Vec::new();
    let mut created = BTreeSet::new();
    for statement in statements(&m.sql) {
        let starts = |prefix: &str| statement == prefix || statement.starts_with(&format!("{prefix} "));
        let words: Vec<&str> = statement.split(' ').collect();
        if SETTINGS.iter().any(|prefix| starts(prefix))
            || (starts("SET") && !starts("SET LOCAL") && !starts("SET CONSTRAINTS"))
        {
            problems.push(format!(
                "`{}` changes database-, role- or session-level settings, which migrations may not do; use SET LOCAL \
                 for this transaction",
                words[..2.min(words.len())].join(" ")
            ));
        } else if TRANSACTION.iter().any(|prefix| starts(prefix)) {
            problems.push(format!(
                "`{}` controls the transaction, but every migration of an upgrade runs in one transaction",
                words[0]
            ));
        } else if words.contains(&"CONCURRENTLY") {
            problems.push(
                "CONCURRENTLY cannot run in the upgrade transaction; build indexes on existing tables in a \
                 post-migration job"
                    .into(),
            );
        }
        // The table named at `words[at]` (after IF NOT EXISTS, IF EXISTS or ONLY) and the index of the next word.
        let table = |at: usize| -> Option<(String, usize)> {
            let at = at
                + words
                    .get(at..)?
                    .iter()
                    .take_while(|w| ["IF", "NOT", "EXISTS", "ONLY"].contains(w))
                    .count();
            let name = words.get(at)?.split('(').next()?;
            Some((name.strip_prefix("PUBLIC.").unwrap_or(name).to_string(), at + 1))
        };
        let needs_prescan = if starts("CREATE TABLE") {
            created.extend(table(2).map(|(name, _)| name));
            None
        } else if starts("ALTER TABLE") {
            table(2).filter(|(_, next)| {
                actions(&words[(*next).min(words.len())..].join(" "))
                    .iter()
                    .any(|a| constrains(a))
            })
        } else if starts("CREATE UNIQUE INDEX") {
            words.iter().position(|word| *word == "ON").and_then(|on| table(on + 1))
        } else {
            None
        };
        if let Some((name, _)) = needs_prescan.filter(|(name, _)| !created.contains(name) && m.prescan().is_none()) {
            problems.push(format!(
                "adds a UNIQUE, foreign-key or NOT NULL constraint to the existing table {name}; first move the rows \
                 that violate it to quarantine with a data migration, and name it in `-- photolib:prescan <id>`"
            ));
        }
    }
    if let Some(id) = m.prescan().filter(|id| !data.contains(id)) {
        problems.push(format!("the pre-scan {id} is not a registered data migration"));
    }
    problems.into_iter().map(|problem| format!("{m}: {problem}")).collect()
}

/// The comma-separated actions of an ALTER TABLE statement, from the words after the table name.
fn actions(statement: &str) -> Vec<String> {
    let (mut actions, mut current, mut depth) = (Vec::new(), String::new(), 0);
    for c in statement.chars() {
        match c {
            '(' => depth += 1,
            ')' => depth -= 1,
            ',' if depth == 0 => {
                actions.push(std::mem::take(&mut current).trim().to_string());
                continue;
            }
            _ => {}
        }
        current.push(c);
    }
    actions.push(current.trim().to_string());
    if let Some(first) = actions.first_mut() {
        let at = ["ADD ", "ALTER ", "DROP ", "RENAME ", "SET ", "VALIDATE "]
            .iter()
            .filter_map(|verb| first.find(verb))
            .min();
        *first = first[at.unwrap_or(0)..].to_string();
    }
    actions
}

/// Whether an ALTER TABLE action adds a constraint that existing rows may violate. A new column cannot: it is NULL
/// or its default everywhere.
fn constrains(action: &str) -> bool {
    let words: Vec<&str> = action.split(' ').collect();
    let adds_column = words[0] == "ADD"
        && !["CONSTRAINT", "UNIQUE", "PRIMARY", "FOREIGN", "CHECK", "EXCLUDE"]
            .contains(&words.get(1).copied().unwrap_or(""));
    match words[0] {
        "ADD" if !adds_column => ["UNIQUE", "PRIMARY KEY", "FOREIGN KEY", "REFERENCES", "NOT NULL"]
            .iter()
            .any(|keyword| action.contains(keyword)),
        "ALTER" => action.contains("SET NOT NULL"),
        _ => false,
    }
}

/// The statements of `sql`, upper-cased, without comments or the contents of strings and dollar-quoted bodies,
/// with single spaces.
fn statements(sql: &str) -> Vec<String> {
    let mut statements = vec![String::new()];
    let mut rest = sql;
    while let Some(c) = rest.chars().next() {
        let current = statements.last_mut().expect("never empty");
        if rest.starts_with("--") {
            rest = rest.find('\n').map_or("", |at| &rest[at..]);
        } else if rest.starts_with("/*") {
            rest = rest.find("*/").map_or("", |at| &rest[at + 2..]);
        } else if c == '\'' {
            current.push_str("''");
            rest = rest[1..].find('\'').map_or("", |at| &rest[at + 2..]);
        } else if c == '"' {
            let end = rest[1..].find('"').map_or(rest.len(), |at| at + 1);
            current.push_str(&rest[1..end].to_uppercase());
            rest = rest.get(end + 1..).unwrap_or("");
        } else if let Some(tag) = dollar_tag(rest) {
            current.push_str("$$");
            rest = rest[tag.len()..].find(tag).map_or("", |at| &rest[2 * tag.len() + at..]);
        } else {
            if c == ';' {
                statements.push(String::new());
            } else {
                current.extend(c.to_uppercase());
            }
            rest = &rest[c.len_utf8()..];
        }
    }
    statements
        .iter()
        .map(|statement| statement.split_whitespace().collect::<Vec<_>>().join(" "))
        .filter(|statement| !statement.is_empty())
        .collect()
}

/// `$tag$` at the start of `text`.
fn dollar_tag(text: &str) -> Option<&str> {
    let end = text.strip_prefix('$')?.find('$')? + 2;
    text[1..end - 1]
        .chars()
        .all(|c| c.is_alphanumeric() || c == '_')
        .then(|| &text[..end])
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{data, migrate::embedded};

    fn problems(sql: &str) -> Vec<String> {
        lint(&Migration::new("0002_change.sql", sql).unwrap(), &["known"])
    }

    #[test]
    fn settings_and_transaction_control_are_rejected() {
        for (sql, words) in [
            ("ALTER DATABASE photolib SET work_mem = '8MB';", "settings"),
            ("alter role photolib set search_path = x;", "settings"),
            ("ALTER USER photolib WITH PASSWORD 'x';", "settings"),
            ("ALTER SYSTEM SET work_mem = '8MB';", "settings"),
            ("CREATE ROLE reader;", "settings"),
            ("SET work_mem = '8MB';", "settings"),
            ("RESET ALL;", "settings"),
            ("BEGIN;", "transaction"),
            ("CREATE TABLE t (x int);\nCOMMIT;", "transaction"),
            ("CREATE INDEX CONCURRENTLY t_x ON t (x);", "CONCURRENTLY"),
        ] {
            let found = problems(sql);
            assert!(
                found.len() == 1 && found[0].starts_with("0002_change: ") && found[0].contains(words),
                "{sql}: {found:?}"
            );
        }
        for sql in [
            "SET LOCAL lock_timeout = '5s';",
            "-- ALTER ROLE in a comment; BEGIN;\nCREATE TABLE t (note text DEFAULT 'SET x; COMMIT;');",
            "CREATE FUNCTION f() RETURNS int LANGUAGE sql AS $body$ SELECT 1; $body$;",
            "/* SET work_mem = 1; */ CREATE TABLE t (x int);",
        ] {
            assert_eq!(problems(sql), Vec::<String>::new(), "{sql}");
        }
    }

    #[test]
    fn a_new_constraint_on_an_existing_table_needs_a_quarantining_prescan() {
        for sql in [
            "ALTER TABLE people ALTER COLUMN email SET NOT NULL;",
            "ALTER TABLE people ADD CONSTRAINT people_email_key UNIQUE (email);",
            "ALTER TABLE ONLY public.people ADD FOREIGN KEY (album_id) REFERENCES albums (id);",
            "ALTER TABLE \"people\" ADD COLUMN nickname text, ADD PRIMARY KEY (id);",
            "CREATE UNIQUE INDEX IF NOT EXISTS people_email ON people (email);",
        ] {
            let found = problems(sql);
            assert!(
                found.len() == 1 && found[0].contains("PEOPLE") && found[0].contains("photolib:prescan"),
                "{sql}: {found:?}"
            );
            assert_eq!(
                problems(&format!("-- photolib:prescan known\n{sql}")),
                Vec::<String>::new(),
                "{sql}"
            );
            let unknown = problems(&format!("-- photolib:prescan unknown\n{sql}"));
            assert!(
                unknown.len() == 1 && unknown[0].contains("not a registered data migration"),
                "{unknown:?}"
            );
        }
        for sql in [
            "CREATE TABLE people (id int, email text);\nALTER TABLE people ADD CONSTRAINT u UNIQUE (email, id);",
            "CREATE TABLE IF NOT EXISTS people(id int);\nCREATE UNIQUE INDEX people_id ON people (id);",
            "ALTER TABLE people ADD COLUMN album_id uuid REFERENCES albums (id);",
            "ALTER TABLE people ADD nickname text NOT NULL DEFAULT '';",
            "ALTER TABLE people ADD CONSTRAINT adult CHECK (age >= 18);",
        ] {
            assert_eq!(problems(sql), Vec::<String>::new(), "{sql}");
        }
    }

    #[test]
    fn the_shipped_migrations_pass_the_lint() {
        let registered: Vec<String> = data::registry().iter().map(|d| d.id().to_string()).collect();
        let registered: Vec<&str> = registered.iter().map(String::as_str).collect();
        for m in embedded() {
            assert_eq!(lint(&m, &registered), Vec::<String>::new());
        }
    }
}
