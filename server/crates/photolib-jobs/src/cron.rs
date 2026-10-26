//! Five-field cron expressions (minute, hour, day of month, month, day of week) in UTC: numbers, `*`, ranges,
//! lists and steps. As in cron, a day matches either restricted day field when both are restricted.

use std::str::FromStr;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Cron {
    fields: [u64; 5],
    any_day: (bool, bool),
}

/// The values each field allows; 7 is a second Sunday in the day of week.
const RANGES: [(u32, u32); 5] = [(0, 59), (0, 23), (1, 31), (1, 12), (0, 7)];
/// The longest gap between two occurrences: February 29 skips 2100.
const HORIZON_DAYS: i64 = 9 * 366;

impl FromStr for Cron {
    type Err = String;

    fn from_str(text: &str) -> Result<Self, String> {
        let words: Vec<&str> = text.split_whitespace().collect();
        let [_, _, day, _, weekday] = words[..] else {
            return Err(format!(
                "'{text}' is not five fields: minute hour day-of-month month day-of-week"
            ));
        };
        let mut fields = [0; 5];
        for (bits, (word, (low, high))) in fields.iter_mut().zip(words.iter().zip(RANGES)) {
            *bits = field(word, low, high)?;
        }
        fields[4] |= fields[4] >> 7 & 1;
        Ok(Cron {
            fields,
            any_day: (day == "*", weekday == "*"),
        })
    }
}

/// The values of one field as bits: a comma-separated list of `*`, `n` or `n-m`, each with an optional `/step`.
fn field(word: &str, low: u32, high: u32) -> Result<u64, String> {
    let invalid = || format!("'{word}' is not a cron field of values {low}-{high}");
    let number = |text: &str| text.parse::<u32>().map_err(|_| invalid());
    let mut bits = 0;
    for part in word.split(',') {
        let (range, step) = match part.split_once('/') {
            Some((range, step)) => (range, Some(number(step)?).filter(|step| *step > 0).ok_or_else(invalid)?),
            None => (part, 1),
        };
        let (from, to) = match range.split_once('-') {
            _ if range == "*" => (low, high),
            Some((from, to)) => (number(from)?, number(to)?),
            None if step > 1 => (number(range)?, high),
            None => (number(range)?, number(range)?),
        };
        if from < low || to > high || from > to {
            return Err(invalid());
        }
        bits |= (from..=to)
            .step_by(step as usize)
            .fold(0, |bits, value| bits | 1 << value);
    }
    Ok(bits)
}

impl Cron {
    /// The first time it matches after `after`, both in seconds since the Unix epoch; `None` if it never matches.
    pub fn next_after(&self, after: i64) -> Option<i64> {
        let [minute, hour, day, month, weekday] = self.fields;
        let has = |bits: u64, value: i64| bits >> value & 1 == 1;
        let mut t = after.div_euclid(60) * 60 + 60;
        let end = t + HORIZON_DAYS * 86_400;
        while t < end {
            let days = t.div_euclid(86_400);
            let (m, d) = month_and_day(days);
            let w = (days + 4).rem_euclid(7);
            let day_matches = match self.any_day {
                (false, false) => has(day, d) || has(weekday, w),
                _ => has(day, d) && has(weekday, w),
            };
            if !has(month, m) || !day_matches {
                t = (days + 1) * 86_400;
            } else if !has(hour, t.rem_euclid(86_400) / 3600) {
                t = (t.div_euclid(3600) + 1) * 3600;
            } else if !has(minute, t.rem_euclid(3600) / 60) {
                t += 60;
            } else {
                return Some(t);
            }
        }
        None
    }
}

/// The month and day of a day counted from 1970-01-01 (Howard Hinnant's `civil_from_days`).
fn month_and_day(days: i64) -> (i64, i64) {
    let day_of_era = (days + 719_468).rem_euclid(146_097);
    let year_of_era = (day_of_era - day_of_era / 1460 + day_of_era / 36_524 - day_of_era / 146_096) / 365;
    let day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
    let shifted_month = (5 * day_of_year + 2) / 153;
    let month = if shifted_month < 10 {
        shifted_month + 3
    } else {
        shifted_month - 9
    };
    (month, day_of_year - (153 * shifted_month + 2) / 5 + 1)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 2026-10-16T01:07:30Z, a Friday.
    const NOW: i64 = 1_792_112_850;

    fn next(cron: &str, after: i64) -> i64 {
        cron.parse::<Cron>().unwrap().next_after(after).unwrap()
    }

    #[test]
    fn the_next_occurrence_is_the_first_matching_minute_after_the_given_time() {
        for (cron, expected) in [
            ("* * * * *", 1_792_112_880),
            ("*/15 * * * *", 1_792_113_300),
            ("5-10/5 * * * *", 1_792_113_000),
            ("5/20 * * * *", 1_792_113_900),
            ("0 3 * * *", 1_792_119_600),
            ("30 2 1 1 *", 1_798_770_600),
            ("0 0 29 2 *", 1_835_395_200),
            ("0 12 * * 1-5", 1_792_152_000),
            ("0 12 * * 0,6", 1_792_238_400),
            ("0 12 * * 7", 1_792_324_800),
            // The 13th or a Friday: the next Friday comes first.
            ("0 0 13 * 5", 1_792_713_600),
        ] {
            assert_eq!(next(cron, NOW), expected, "{cron}");
        }
        assert_eq!(next("0 3 * * *", 1_792_119_600), 1_792_206_000, "strictly after");
    }

    #[test]
    fn invalid_expressions_name_the_problem() {
        for (cron, problem) in [
            ("* * * *", "five fields"),
            ("60 * * * *", "60"),
            ("* 24 * * *", "24"),
            ("* * 0 * *", "0"),
            ("* * * 13 *", "13"),
            ("* * * * 8", "8"),
            ("5-1 * * * *", "5-1"),
            ("*/0 * * * *", "*/0"),
            ("a * * * *", "a"),
            ("1,,2 * * * *", "1,,2"),
        ] {
            let error = cron.parse::<Cron>().unwrap_err();
            assert!(error.contains(problem), "{cron}: {error}");
        }
    }

    #[test]
    fn schedules_keep_their_dates_past_2100() {
        for (cron, after, expected) in [
            // From 2100-02-28T12:00Z, a Sunday: 2100 has no February 29.
            ("0 3 * * *", 4_107_499_200, 4_107_553_200),
            ("0 12 * * 1", 4_107_499_200, 4_107_585_600),
            // From 2096-03-01: the next February 29 is in 2104.
            ("0 0 29 2 *", 3_981_398_400, 4_233_686_400),
        ] {
            assert_eq!(next(cron, after), expected, "{cron}");
        }
    }

    #[test]
    fn a_date_that_never_comes_has_no_next_occurrence() {
        assert_eq!("0 0 30 2 *".parse::<Cron>().unwrap().next_after(NOW), None);
    }

    #[test]
    fn days_map_to_the_gregorian_calendar_for_two_centuries() {
        let (mut year, mut month, mut day) = (1970, 1, 1);
        for days in 0..73_000 {
            assert_eq!(month_and_day(days), (month, day), "day {days} of {year}");
            let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
            let length = [31, 28 + leap as i64, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
            day += 1;
            if day > length[month as usize - 1] {
                (month, day) = (month % 12 + 1, 1);
                year += (month == 1) as i64;
            }
        }
    }
}
