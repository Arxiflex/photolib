//! PP-OCR's recogniser output as text (design 09 §6). OCR text is read from pictures anyone can make, so it is untrusted
//! input everywhere it goes (threat model T33): [`clean`] runs before it is stored.

mod read;
pub use read::{DETECTOR, Infer, Line, Rgb, Script, read, read_lines};

/// Greedy CTC decoding of a recogniser's output, `probabilities` being steps of `charset.len() + 1` scores: class 0 is
/// the blank, class `n` the `n`-th entry of `charset`. A repeat with no blank between is one character.
pub fn decode(probabilities: &[f32], charset: &[impl AsRef<str>]) -> String {
    decode_scored(probabilities, charset).0
}

/// The text of [`decode`], and the mean of the scores of the characters chosen: how sure the recogniser was, 0 for none.
#[allow(clippy::cast_precision_loss, reason = "a count of characters")]
pub fn decode_scored(probabilities: &[f32], charset: &[impl AsRef<str>]) -> (String, f32) {
    let (mut text, mut sum, mut count) = (String::new(), 0.0, 0_u32);
    let mut last = 0;
    for step in probabilities.chunks_exact(charset.len().saturating_add(1)) {
        let (best, score) = step
            .iter()
            .enumerate()
            .fold((0, f32::MIN), |b, (i, v)| if *v > b.1 { (i, *v) } else { b });
        if best != last
            && let Some(c) = best.checked_sub(1).and_then(|i| charset.get(i))
        {
            text.push_str(c.as_ref());
            sum += score;
            count = count.saturating_add(1);
        }
        last = best;
    }
    (text, if count == 0 { 0.0 } else { sum / count as f32 })
}

/// Text as stored and shown: no NUL or control characters but line breaks and tabs, no bidirectional overrides, spaces
/// trimmed, at most [`MAX_CHARS`] characters. Markup stays as it was read, inert text: every shown place escapes it.
pub fn clean(text: &str) -> String {
    text.chars()
        .filter(|c| matches!(c, '\n' | '\t') || !(c.is_control() || is_bidi(*c)))
        .take(MAX_CHARS)
        .collect::<String>()
        .trim()
        .to_owned()
}

/// Embeddings, overrides, isolates and marks that reorder the text around them.
fn is_bidi(c: char) -> bool {
    matches!(c, '\u{61c}' | '\u{200e}' | '\u{200f}' | '\u{202a}'..='\u{202e}' | '\u{2066}'..='\u{2069}')
}

/// The longest text kept for a picture.
pub const MAX_CHARS: usize = 20_000;

#[cfg(test)]
mod tests {
    use super::*;

    /// Logits with one hot class per step.
    fn steps(classes: usize, hot: &[usize]) -> Vec<f32> {
        hot.iter()
            .flat_map(|h| (0..classes).map(move |c| if c == *h { 5.0 } else { 0.0 }))
            .collect()
    }

    #[test]
    fn ctc_decoding_reads_latin_cyrillic_and_cjk_charsets() {
        for (charset, text) in [
            (vec!["a", "b", "c"], "abc"),
            (vec!["п", "р", "и", "в", "е", "т"], "привет"),
            (vec!["東", "京", "駅"], "東京駅"),
        ] {
            // Class 0 is the blank, class n the charset's n-th character.
            let hot: Vec<usize> = text
                .chars()
                .flat_map(|c| [charset.iter().position(|s| s.starts_with(c)).unwrap() + 1, 0])
                .collect();
            assert_eq!(decode(&steps(charset.len() + 1, &hot), &charset), text);
        }
    }

    #[test]
    fn ctc_collapses_repeats_but_not_across_a_blank() {
        let charset = ["a", "b"];
        assert_eq!(decode(&steps(3, &[1, 1, 0, 1, 2, 2]), &charset), "aab");
        assert_eq!(decode(&[], &charset), "");
        assert_eq!(decode(&steps(3, &[0, 0]), &charset), "");
    }

    #[test]
    fn untrusted_text_is_cleaned_but_markup_is_kept_as_text() {
        let xss = "<img src=x onerror=alert(1)>\"'<script>alert(1)</script>";
        assert_eq!(clean(xss), xss);
        assert_eq!(clean("  a\0b\u{7}c\u{202e}d\u{2066}e\n f\tg \r\n"), "abcde\n f\tg");
        assert_eq!(clean("東京 привет"), "東京 привет");
        assert_eq!(clean(&"é".repeat(MAX_CHARS + 5)).chars().count(), MAX_CHARS);
    }
}
