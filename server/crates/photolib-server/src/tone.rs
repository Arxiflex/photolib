//! HDR to SDR (photolib-design docs/08 §5.6, ADR-0390): what a video's colour signalling says of its HDR, and the
//! filters that turn its pictures into SDR BT.709 for posters, sprites, R1 and the rungs encoded from the original.

use photolib_media::Failure;
use serde::{Deserialize, Serialize};

/// How a video's light is coded.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Transfer {
    /// SMPTE ST 2084, as HDR10, HDR10+ and Dolby Vision 8.1 carry it.
    Pq,
    /// ARIB STD-B67, as HLG and Dolby Vision 8.4 carry it.
    Hlg,
    /// Dolby Vision profile 5: IPT-PQ-c2, which no filter here undoes without the stream's RPU.
    Dv5,
}

/// The HDR of a video as its streams signal it, with the colour fields its files may leave out.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Tone {
    /// How its light is coded.
    pub transfer: Transfer,
    /// ffprobe's name of its primaries, empty when the file does not say.
    pub primaries: String,
    /// Its matrix coefficients, as ffprobe names them.
    pub matrix: String,
    /// Its range (`tv` or `pc`).
    pub range: String,
}

/// Which converter the settings ask for (`tone_mapping`).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ToneMapping {
    /// libplacebo where a Vulkan device works inside the media sandbox, else zimg.
    #[default]
    Auto,
    /// Always zimg, on the CPU.
    Zimg,
    /// Always libplacebo; a render fails where it cannot run.
    Placebo,
}

/// What does the HDR to SDR conversion.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Mapper {
    /// libplacebo's BT.2390 on a Vulkan device.
    Placebo,
    /// zimg's linear light and Mobius's curve on the CPU.
    Zimg,
}

/// zimg to linear light with 203 nits as 1.0 (HDR reference white, BT.2408), into BT.709's primaries, then Mobius's
/// curve, which a sweep against libplacebo's BT.2390 on the reference clips put at a mean ΔE of 2.6 to 3.3.
const ZIMG: &str = "zscale=t=linear:npl=203,format=gbrpf32le,zscale=p=bt709,tonemap=tonemap=mobius:param=0.3:desat=0,\
                    zscale=t=bt709:m=bt709:r=tv:d=error_diffusion";

/// libplacebo's BT.2390 into BT.709 as 8-bit RGB: its 4:2:0 output is not read back right on every Vulkan device.
const PLACEBO: &str = "hwupload,libplacebo=tonemapping=bt.2390:colorspace=bt709:color_primaries=bt709:color_trc=bt709:\
                       range=pc:format=rgba,hwdownload,format=rgba,scale=out_color_matrix=bt709:out_range=tv";

impl Tone {
    /// The filters from the decoded HDR picture to SDR BT.709 limited range, in a pixel format the caller sets.
    /// What the file leaves unsaid is taken as what HDR files carry: BT.2020 primaries and matrix, limited range.
    pub fn filter(&self, mapper: Mapper) -> Result<String, Failure> {
        if self.transfer == Transfer::Dv5 {
            return Err(Failure::Unsupported(
                "Dolby Vision profile 5 needs its RPU to be tone-mapped, which no filter here applies".into(),
            ));
        }
        let unknown = |value: &str| ["", "unknown", "unspecified", "reserved"].contains(&value);
        // The transfer is always said: Dolby Vision's files may carry it only in their record.
        let transfer = match self.transfer {
            Transfer::Hlg => "color_trc=arib-std-b67",
            _ => "color_trc=smpte2084",
        };
        let missing: Vec<String> = [
            (true, transfer),
            (unknown(&self.primaries), "color_primaries=bt2020"),
            (unknown(&self.matrix), "colorspace=bt2020nc"),
            (unknown(&self.range), "color_range=tv"),
        ]
        .into_iter()
        .filter(|(missing, _)| *missing)
        .map(|(_, setting)| setting.to_owned())
        .collect();
        let convert = match mapper {
            Mapper::Placebo => PLACEBO,
            Mapper::Zimg => ZIMG,
        };
        Ok(format!("setparams={},{convert}", missing.join(":")))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tone(transfer: Transfer, primaries: &str, matrix: &str, range: &str) -> Tone {
        Tone {
            transfer,
            primaries: primaries.into(),
            matrix: matrix.into(),
            range: range.into(),
        }
    }

    #[test]
    fn dolby_vision_profile_5_is_refused_rather_than_shown_green_and_purple() {
        let p5 = tone(Transfer::Dv5, "bt2020", "bt2020nc", "tv");
        for mapper in [Mapper::Zimg, Mapper::Placebo] {
            assert!(matches!(p5.filter(mapper), Err(Failure::Unsupported(why)) if why.contains("profile 5")));
        }
    }

    #[test]
    fn each_mapper_ends_in_limited_range_bt709() {
        let hlg = tone(Transfer::Hlg, "bt2020", "bt2020nc", "tv");
        let zimg = hlg.filter(Mapper::Zimg).unwrap();
        assert!(zimg.contains("tonemap=tonemap=mobius") && zimg.ends_with("m=bt709:r=tv:d=error_diffusion"));
        let placebo = hlg.filter(Mapper::Placebo).unwrap();
        assert!(
            placebo.contains(",hwupload,libplacebo=tonemapping=bt.2390"),
            "{placebo}"
        );
        assert!(placebo.ends_with("out_color_matrix=bt709:out_range=tv"), "{placebo}");
    }

    #[test]
    fn a_file_that_leaves_its_colours_unsaid_is_taken_as_bt2020_limited_range() {
        let said = tone(Transfer::Pq, "bt2020", "bt2020nc", "tv")
            .filter(Mapper::Zimg)
            .unwrap();
        assert!(said.starts_with("setparams=color_trc=smpte2084,"), "{said}");
        for blank in ["", "unknown", "unspecified", "reserved"] {
            let filter = tone(Transfer::Pq, blank, blank, blank).filter(Mapper::Zimg).unwrap();
            assert!(
                filter.starts_with(
                    "setparams=color_trc=smpte2084:color_primaries=bt2020:colorspace=bt2020nc:color_range=tv,"
                ),
                "{blank}: {filter}"
            );
        }
        let only_matrix = tone(Transfer::Hlg, "bt2020", "unknown", "pc")
            .filter(Mapper::Zimg)
            .unwrap();
        assert!(
            only_matrix.starts_with("setparams=color_trc=arib-std-b67:colorspace=bt2020nc,"),
            "{only_matrix}"
        );
    }
}
