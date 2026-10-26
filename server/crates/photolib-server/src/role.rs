use std::{fmt, str::FromStr};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum WorkerClass {
    Cpu,
    Io,
    Gpu,
    Transcode,
    Import,
    Export,
}

const CLASSES: [(WorkerClass, &str); 6] = [
    (WorkerClass::Cpu, "cpu"),
    (WorkerClass::Io, "io"),
    (WorkerClass::Gpu, "gpu"),
    (WorkerClass::Transcode, "transcode"),
    (WorkerClass::Import, "import"),
    (WorkerClass::Export, "export"),
];

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Role {
    Api,
    Scheduler,
    Worker(WorkerClass),
    Ml,
}

fn class_names() -> String {
    CLASSES.map(|(_, name)| name).join(", ")
}

impl FromStr for Role {
    type Err = String;

    fn from_str(name: &str) -> Result<Self, String> {
        match name {
            "api" => Ok(Role::Api),
            "scheduler" => Ok(Role::Scheduler),
            "ml" => Ok(Role::Ml),
            "worker" => Err(format!(
                "a worker needs a class, as worker:<class> (classes: {})",
                class_names()
            )),
            _ => match name.strip_prefix("worker:") {
                Some(class) => CLASSES
                    .iter()
                    .find(|(_, known)| *known == class)
                    .map(|(class, _)| Role::Worker(*class))
                    .ok_or_else(|| format!("unknown worker class '{class}' (classes: {})", class_names())),
                None => Err(format!(
                    "unknown role '{name}' (roles: api, scheduler, worker:<class>, ml, all)"
                )),
            },
        }
    }
}

impl serde::Serialize for Role {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.collect_str(self)
    }
}

impl fmt::Display for Role {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Role::Api => f.write_str("api"),
            Role::Scheduler => f.write_str("scheduler"),
            Role::Ml => f.write_str("ml"),
            Role::Worker(class) => {
                let name = CLASSES
                    .iter()
                    .find(|(known, _)| known == class)
                    .map_or("", |(_, name)| name);
                write!(f, "worker:{name}")
            }
        }
    }
}

impl Role {
    /// Every role but `ml` works on the database and the data directory; `ml` may run on a remote node without them.
    pub fn needs_instance(self) -> bool {
        self != Role::Ml
    }
}

/// Turns the configured role names into roles, expanding `all` and rejecting contradictions.
pub fn resolve(names: &[String]) -> Result<Vec<Role>, String> {
    if names.is_empty() {
        return Err("list at least one role".into());
    }
    if names.iter().any(|name| name == "all") {
        return match names.len() {
            1 => Ok([Role::Api, Role::Scheduler]
                .into_iter()
                .chain(CLASSES.map(|(class, _)| Role::Worker(class)))
                .chain([Role::Ml])
                .collect()),
            _ => Err("'all' already includes every role; use it alone".into()),
        };
    }
    let mut roles = Vec::new();
    for name in names {
        let role = name.parse::<Role>()?;
        if roles.contains(&role) {
            return Err(format!("role '{role}' is listed twice"));
        }
        roles.push(role);
    }
    Ok(roles)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testing::assert_contains;

    fn names(list: &[&str]) -> Vec<String> {
        list.iter().map(|name| name.to_string()).collect()
    }

    #[test]
    fn every_role_round_trips_through_its_name() {
        for name in [
            "api",
            "scheduler",
            "ml",
            "worker:cpu",
            "worker:io",
            "worker:gpu",
            "worker:transcode",
            "worker:import",
            "worker:export",
        ] {
            let role: Role = name.parse().unwrap();
            assert_eq!(role.to_string(), name);
        }
    }

    #[test]
    fn invalid_roles_name_the_problem_and_valid_choices() {
        for (name, expected) in [
            ("worker", vec!["worker:<class>", "cpu"]),
            ("worker:fast", vec!["fast", "transcode"]),
            ("database", vec!["database", "scheduler", "all"]),
        ] {
            assert_contains(&name.parse::<Role>().unwrap_err(), &expected);
        }
    }

    #[test]
    fn all_expands_to_every_role_once() {
        let roles = resolve(&names(&["all"])).unwrap();
        assert_eq!(roles.len(), 9);
        assert_eq!(roles[0], Role::Api);
        assert!(roles.contains(&Role::Worker(WorkerClass::Gpu)) && roles.contains(&Role::Ml));
    }

    #[test]
    fn roles_keep_the_order_they_were_given() {
        let roles = resolve(&names(&["worker:io", "api"])).unwrap();
        assert_eq!(roles, [Role::Worker(WorkerClass::Io), Role::Api]);
    }

    #[test]
    fn contradictory_or_empty_role_lists_are_refused() {
        for (input, expected) in [
            (vec!["all", "api"], vec!["all", "alone"]),
            (vec!["api", "ml", "api"], vec!["api", "twice"]),
            (vec![], vec!["at least one"]),
        ] {
            assert_contains(&resolve(&names(&input)).unwrap_err(), &expected);
        }
    }

    #[test]
    fn only_ml_runs_without_the_database_and_the_data_directory() {
        assert!(Role::Api.needs_instance() && Role::Worker(WorkerClass::Cpu).needs_instance());
        assert!(!Role::Ml.needs_instance());
    }
}
