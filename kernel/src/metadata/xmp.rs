//! XMP: an RDF/XML packet parsed into XMP's data model of texts, arrays and structures, and the properties a photo
//! library reads from it.

use super::{claim, degrees, location};
use crate::proto::kernel::v1::{ContainerItem, GeoPoint, ImageRegion, MotionPhotoMarkers, Panorama, StereoMode};
use crate::proto::model::v1::CaptureTime;
use std::borrow::Cow;
use std::collections::BTreeSet;

const RDF: &str = "http://www.w3.org/1999/02/22-rdf-syntax-ns#";
const XML: &str = "http://www.w3.org/XML/1998/namespace";
const DC: &str = "http://purl.org/dc/elements/1.1/";
const XMP: &str = "http://ns.adobe.com/xap/1.0/";
const PHOTOSHOP: &str = "http://ns.adobe.com/photoshop/1.0/";
const EXIF: &str = "http://ns.adobe.com/exif/1.0/";
const TIFF: &str = "http://ns.adobe.com/tiff/1.0/";
const LIGHTROOM: &str = "http://ns.adobe.com/lightroom/1.0/";
const DIGIKAM: &str = "http://www.digikam.org/ns/1.0/";
const REGIONS: &str = "http://www.metadataworkinggroup.com/schemas/regions/";
const AREA: &str = "http://ns.adobe.com/xmp/sType/Area#";
const GPANO: &str = "http://ns.google.com/photos/1.0/panorama/";
const CAMERA: &str = "http://ns.google.com/photos/1.0/camera/";
const CONTAINER: &str = "http://ns.google.com/photos/1.0/container/";
const ITEM: &str = "http://ns.google.com/photos/1.0/container/item/";
const SPHERICAL: &str = "http://ns.google.com/videos/1.0/spherical/";
const GDEPTH: &str = "http://ns.google.com/photos/1.0/depthmap/";
const HDRGM: &str = "http://ns.adobe.com/hdr-gain-map/1.0/";
/// Deeper elements are skipped: XMP nests a handful of levels, and recursion must stay bounded.
const MAX_DEPTH: usize = 32;
/// Namespaces in scope at once; a packet declares a few dozen, and each name is looked up among them.
const MAX_NAMESPACES: usize = 256;

#[derive(Default)]
pub struct Xmp {
    pub make: Option<String>,
    pub model: Option<String>,
    pub orientation: Option<u32>,
    pub location: Option<GeoPoint>,
    pub times: Vec<CaptureTime>,
    pub title: Option<String>,
    pub description: Option<String>,
    pub keywords: Vec<String>,
    pub paths: Vec<Vec<String>>,
    pub rating: Option<i32>,
    pub label: Option<String>,
    pub creators: Vec<String>,
    pub copyright: Option<String>,
    pub city: Option<String>,
    pub state: Option<String>,
    pub country: Option<String>,
    /// In the stored frame: orientation is not applied yet.
    pub regions: Vec<ImageRegion>,
    pub panorama: Option<Panorama>,
    pub motion: Option<MotionPhotoMarkers>,
    pub burst_id: Option<String>,
    /// GDepth's depth map, or a Dynamic Depth item.
    pub depth: bool,
    /// Ultra HDR's hdrgm:Version, which its primary image's XMP holds.
    pub gain_map: bool,
}

pub fn read(packet: &[u8]) -> Xmp {
    let text = String::from_utf8_lossy(packet);
    let properties: Vec<_> = parse(&text).map_or(vec![], |root| descriptions(&root));
    let get = |ns: &str, name: &str| field(&properties, ns, name);
    let text = |ns, name| get(ns, name).and_then(Value::text).map(String::from);
    let number = |ns, name| {
        text(ns, name)
            .and_then(|t| t.parse::<f64>().ok())
            .filter(|n| n.is_finite())
    };
    let mut xmp = Xmp {
        make: text(TIFF, "Make"),
        model: text(TIFF, "Model"),
        orientation: number(TIFF, "Orientation").map(|n| n as u32),
        title: text(DC, "title"),
        description: text(DC, "description"),
        keywords: get(DC, "subject").map(Value::texts).unwrap_or_default(),
        rating: number(XMP, "Rating")
            .map(f64::round)
            .filter(|r| (-1.0..=5.0).contains(r))
            .map(|r| r as i32),
        label: text(XMP, "Label"),
        creators: get(DC, "creator").map(Value::texts).unwrap_or_default(),
        copyright: text(DC, "rights"),
        city: text(PHOTOSHOP, "City"),
        state: text(PHOTOSHOP, "State"),
        country: text(PHOTOSHOP, "Country"),
        burst_id: text(CAMERA, "BurstID"),
        gain_map: text(HDRGM, "Version").is_some(),
        ..Xmp::default()
    };
    for (source, ns, name) in [
        ("xmp-exif:DateTimeOriginal", EXIF, "DateTimeOriginal"),
        ("xmp-photoshop:DateCreated", PHOTOSHOP, "DateCreated"),
        ("xmp-xmp:CreateDate", XMP, "CreateDate"),
        ("xmp-xmp:ModifyDate", XMP, "ModifyDate"),
        ("xmp-xmp:MetadataDate", XMP, "MetadataDate"),
    ] {
        if let Some(date) = text(ns, name) {
            xmp.times.push(claim(source, &date, None, None));
        }
    }
    let coordinate = |name| text(EXIF, name).as_deref().and_then(coordinate);
    if let (Some(latitude), Some(longitude)) = (coordinate("GPSLatitude"), coordinate("GPSLongitude")) {
        let sign = if text(EXIF, "GPSAltitudeRef").as_deref() == Some("1") {
            -1.0
        } else {
            1.0
        };
        let altitude = text(EXIF, "GPSAltitude")
            .as_deref()
            .and_then(rational)
            .map(|a| sign * a);
        xmp.location = location(latitude, longitude, altitude);
    }
    let mut seen = BTreeSet::new();
    for (ns, name, separator) in [(LIGHTROOM, "hierarchicalSubject", '|'), (DIGIKAM, "TagsList", '/')] {
        for keyword in get(ns, name).map(Value::texts).unwrap_or_default() {
            let path: Vec<String> = keyword.split(separator).map(|n| n.trim().to_string()).collect();
            if !path.iter().any(String::is_empty) && seen.insert(path.clone()) {
                xmp.paths.push(path);
            }
        }
    }
    let regions = get(REGIONS, "Regions").and_then(|r| r.field(REGIONS, "RegionList"));
    xmp.regions = regions.map_or(vec![], |list| list.items().iter().filter_map(region).collect());
    if let Some(projection) = text(GPANO, "ProjectionType") {
        let pixels = |name| number(GPANO, name).map_or(0, |n| n as u32);
        xmp.panorama = Some(Panorama {
            projection,
            use_panorama_viewer: text(GPANO, "UsePanoramaViewer").map(|t| t.eq_ignore_ascii_case("true")),
            full_width: pixels("FullPanoWidthPixels"),
            full_height: pixels("FullPanoHeightPixels"),
            cropped_left: pixels("CroppedAreaLeftPixels"),
            cropped_top: pixels("CroppedAreaTopPixels"),
            cropped_width: pixels("CroppedAreaImageWidthPixels"),
            cropped_height: pixels("CroppedAreaImageHeightPixels"),
            // In [0, 360): rem_euclid rounds a tiny negative heading to 360 itself.
            pose_heading_degrees: number(GPANO, "PoseHeadingDegrees").map(|h| h.rem_euclid(360.0) % 360.0),
        });
    }
    let flag = |name| number(CAMERA, name) == Some(1.0);
    let directory = get(CONTAINER, "Directory").map_or(vec![], |d| d.items().iter().map(item).collect());
    let motion = MotionPhotoMarkers {
        motion_photo: flag("MotionPhoto"),
        version: number(CAMERA, "MotionPhotoVersion").map_or(0, |n| n as u32),
        presentation_timestamp_us: number(CAMERA, "MotionPhotoPresentationTimestampUs")
            .or_else(|| number(CAMERA, "MicroVideoPresentationTimestampUs"))
            .map(|n| n as i64),
        micro_video: flag("MicroVideo"),
        micro_video_offset_bytes: number(CAMERA, "MicroVideoOffset").map_or(0, |n| n as u64),
        items: directory,
    };
    xmp.depth = get(GDEPTH, "Mime").is_some() || motion.items.iter().any(|item| item.semantic == "Depth");
    xmp.motion = (motion.motion_photo || motion.micro_video || !motion.items.is_empty()).then_some(motion);
    xmp
}

/// Spherical Video V1's XML: the projection when it says the video is spherical, and the stereo mode.
pub fn spherical(xml: &[u8]) -> (Option<String>, StereoMode) {
    let root = parse(&String::from_utf8_lossy(xml));
    let children = root.iter().flat_map(|root| &root.children);
    let value = |name| {
        let mut values = children.clone().filter(|e| e.is(SPHERICAL, name));
        values.next().map(|e| e.text.trim().to_ascii_lowercase())
    };
    let projection = (value("Spherical").as_deref() == Some("true"))
        .then(|| value("ProjectionType").unwrap_or_else(|| "equirectangular".into()));
    let stereo = match value("StereoMode").as_deref() {
        Some("top-bottom") => StereoMode::TopBottom,
        Some("left-right") => StereoMode::LeftRight,
        _ => StereoMode::Unspecified,
    };
    (projection, stereo)
}

/// An mwg-rs region: its area's centre and size, normalised, to the top-left corner and size.
fn region(value: &Value) -> Option<ImageRegion> {
    let area = value.field(REGIONS, "Area")?;
    let text = |v: &Value, ns, name| v.field(ns, name).and_then(Value::text).unwrap_or_default().to_string();
    if !matches!(text(area, AREA, "unit").as_str(), "" | "normalized") {
        return None;
    }
    let number = |name| text(area, AREA, name).parse::<f64>().ok().filter(|n| n.is_finite());
    let (width, height) = (number("w")?, number("h")?);
    Some(ImageRegion {
        name: text(value, REGIONS, "Name"),
        r#type: text(value, REGIONS, "Type"),
        x: number("x")? - width / 2.0,
        y: number("y")? - height / 2.0,
        width,
        height,
    })
}

/// A Container:Directory entry: a Container:Item structure, or its fields straight in the list item.
fn item(value: &Value) -> ContainerItem {
    let item = value.field(CONTAINER, "Item").unwrap_or(value);
    let text = |name| item.field(ITEM, name).and_then(Value::text).unwrap_or_default();
    ContainerItem {
        mime: text("Mime").into(),
        semantic: text("Semantic").into(),
        length_bytes: text("Length").parse().unwrap_or(0),
        padding_bytes: text("Padding").parse().unwrap_or(0),
    }
}

/// "48,51.504N" or "48,51,30.24N" in degrees.
fn coordinate(text: &str) -> Option<f64> {
    let hemisphere = text.chars().last()?;
    let sign = match hemisphere {
        'N' | 'E' => 1.0,
        'S' | 'W' => -1.0,
        _ => return None,
    };
    let body = &text[..text.len() - hemisphere.len_utf8()];
    let parts: Vec<f64> = body.split(',').map(|p| p.trim().parse().ok()).collect::<Option<_>>()?;
    degrees(&parts).map(|d| sign * d)
}

/// "3500/100" or "35".
fn rational(text: &str) -> Option<f64> {
    let value = match text.split_once('/') {
        Some((n, d)) => n.trim().parse::<f64>().ok()? / d.trim().parse::<f64>().ok()?,
        None => text.trim().parse().ok()?,
    };
    value.is_finite().then_some(value)
}

/// A namespace URI and a local name.
type Name = (String, String);

/// An XMP value: a simple text, an array (bag, sequence or language alternatives, the default language first) or a
/// structure.
enum Value {
    Text(String),
    Array(Vec<Value>),
    Struct(Vec<(Name, Value)>),
}

impl Value {
    /// A simple value: the text, an array's first item, or a structure's rdf:value.
    fn text(&self) -> Option<&str> {
        match self {
            Value::Text(text) => Some(text.as_str()).filter(|t| !t.is_empty()),
            Value::Array(items) => items.first()?.text(),
            Value::Struct(fields) => field(fields, RDF, "value")?.text(),
        }
    }

    fn texts(&self) -> Vec<String> {
        match self {
            Value::Array(items) => items.iter().filter_map(Value::text).map(String::from).collect(),
            other => other.text().map(String::from).into_iter().collect(),
        }
    }

    fn items(&self) -> &[Value] {
        match self {
            Value::Array(items) => items,
            _ => &[],
        }
    }

    fn field(&self, ns: &str, name: &str) -> Option<&Value> {
        match self {
            Value::Struct(fields) => field(fields, ns, name),
            _ => None,
        }
    }
}

fn field<'v>(fields: &'v [(Name, Value)], ns: &str, name: &str) -> Option<&'v Value> {
    fields.iter().find(|((n, l), _)| n == ns && l == name).map(|(_, v)| v)
}

struct Element {
    name: Name,
    attributes: Vec<(Name, String)>,
    children: Vec<Element>,
    text: String,
}

impl Element {
    fn is(&self, ns: &str, name: &str) -> bool {
        self.name.0 == ns && self.name.1 == name
    }

    fn attribute(&self, ns: &str, name: &str) -> Option<&str> {
        self.attributes
            .iter()
            .find(|((n, l), _)| n == ns && l == name)
            .map(|(_, v)| v.as_str())
    }
}

/// The properties of every rdf:Description of the packet's rdf:RDF.
fn descriptions(root: &Element) -> Vec<(Name, Value)> {
    let rdf = std::iter::once(root).chain(&root.children).find(|e| e.is(RDF, "RDF"));
    rdf.map_or(vec![], |rdf| rdf.children.iter().flat_map(properties).collect())
}

/// A node element's properties: its attributes other than RDF's and XML's, and its child elements.
fn properties(node: &Element) -> Vec<(Name, Value)> {
    let attributes = node.attributes.iter().filter(|((ns, _), _)| ns != RDF && ns != XML);
    let attributes = attributes.map(|(name, text)| (name.clone(), Value::Text(text.trim().to_string())));
    attributes
        .chain(node.children.iter().map(|c| (c.name.clone(), value(c))))
        .collect()
}

/// The value of a property element, in each of the forms RDF/XML allows.
fn value(element: &Element) -> Value {
    if let Some(resource) = element.attribute(RDF, "resource") {
        return Value::Text(resource.to_string());
    }
    match element.children.first() {
        Some(list) if ["Bag", "Seq", "Alt"].iter().any(|kind| list.is(RDF, kind)) => {
            let mut items: Vec<_> = list.children.iter().filter(|li| li.is(RDF, "li")).collect();
            items.sort_by_key(|li| li.attribute(XML, "lang") != Some("x-default"));
            Value::Array(items.into_iter().map(value).collect())
        }
        Some(node) if node.is(RDF, "Description") => Value::Struct(properties(node)),
        None if properties(element).is_empty() => Value::Text(element.text.trim().to_string()),
        _ => Value::Struct(properties(element)),
    }
}

/// The first element of an XML document with its descendants, namespaces resolved; tolerant of what XMP does not
/// use (DTDs, processing instructions) and of damage: unclosed elements close at the end.
fn parse(text: &str) -> Option<Element> {
    let mut stack: Vec<(Element, usize)> = Vec::new();
    let mut scopes: Vec<(String, String)> = vec![("xml".into(), XML.into())];
    let mut skipped = 0;
    let mut rest = text;
    let close = |stack: &mut Vec<(Element, usize)>, element: Element| match stack.last_mut() {
        Some((parent, _)) => {
            parent.children.push(element);
            None
        }
        None => Some(element),
    };
    while let Some(start) = rest.find('<') {
        if let (Some((top, _)), 0) = (stack.last_mut(), skipped) {
            top.text.push_str(&decode(&rest[..start]));
        }
        rest = &rest[start..];
        if let Some(after) = rest.strip_prefix("<!--") {
            let Some((_, after)) = after.split_once("-->") else {
                break;
            };
            rest = after;
        } else if let Some(after) = rest.strip_prefix("<![CDATA[") {
            let Some((data, after)) = after.split_once("]]>") else {
                break;
            };
            if let (Some((top, _)), 0) = (stack.last_mut(), skipped) {
                top.text.push_str(data);
            }
            rest = after;
        } else if rest.starts_with("<?") || rest.starts_with("<!") {
            let Some((_, after)) = rest.split_once('>') else {
                break;
            };
            rest = after;
        } else if let Some(after) = rest.strip_prefix("</") {
            let Some((_, after)) = after.split_once('>') else {
                break;
            };
            rest = after;
            if skipped > 0 {
                skipped -= 1;
                continue;
            }
            let Some((element, scope)) = stack.pop() else {
                continue;
            };
            scopes.truncate(scope);
            if let Some(root) = close(&mut stack, element) {
                return Some(root);
            }
        } else {
            let Some(end) = tag_end(&rest[1..]).map(|end| end + 1) else {
                break;
            };
            let (tag, empty) = match rest[1..end].strip_suffix('/') {
                Some(tag) => (tag, true),
                None => (&rest[1..end], false),
            };
            rest = &rest[end + 1..];
            if skipped > 0 || stack.len() >= MAX_DEPTH {
                skipped += usize::from(!empty);
                continue;
            }
            let Some((name, attributes)) = parse_tag(tag) else {
                break;
            };
            let scope = scopes.len();
            for (key, value) in &attributes {
                if let Some(prefix) = key.strip_prefix("xmlns:").or((*key == "xmlns").then_some(""))
                    && scopes.len() < MAX_NAMESPACES
                {
                    scopes.push((prefix.into(), value.to_string()));
                }
            }
            let resolve = |name: &str, default: bool| {
                let (prefix, local) = name.split_once(':').unwrap_or(("", name));
                let uri = scopes
                    .iter()
                    .rev()
                    .find(|(p, _)| p == prefix)
                    .map(|(_, uri)| uri.as_str());
                let uri = if prefix.is_empty() && !default {
                    ""
                } else {
                    uri.unwrap_or_default()
                };
                (uri.to_string(), local.to_string())
            };
            let element = Element {
                name: resolve(name, true),
                attributes: attributes
                    .iter()
                    .filter(|(key, _)| *key != "xmlns" && !key.starts_with("xmlns:"))
                    .map(|(key, value)| (resolve(key, false), value.to_string()))
                    .collect(),
                children: vec![],
                text: String::new(),
            };
            if !empty {
                stack.push((element, scope));
            } else {
                scopes.truncate(scope);
                if let Some(root) = close(&mut stack, element) {
                    return Some(root);
                }
            }
        }
    }
    let mut root = None;
    while let Some((element, _)) = stack.pop() {
        root = close(&mut stack, element);
    }
    root
}

/// Where a tag's closing '>' is, outside quoted attribute values.
fn tag_end(tag: &str) -> Option<usize> {
    let mut quote = None;
    tag.char_indices().find_map(|(at, c)| {
        match (quote, c) {
            (None, '"' | '\'') => quote = Some(c),
            (Some(q), _) if q == c => quote = None,
            (None, '>') => return Some(at),
            _ => {}
        }
        None
    })
}

type Attributes<'t> = Vec<(&'t str, Cow<'t, str>)>;

/// A start tag's name and attributes, the values decoded.
fn parse_tag(tag: &str) -> Option<(&str, Attributes<'_>)> {
    let tag = tag.trim();
    let (name, mut rest) = tag.split_once(char::is_whitespace).unwrap_or((tag, ""));
    let mut attributes = vec![];
    while let Some((key, after)) = rest.split_once('=') {
        let after = after.trim_start();
        let quote = after.chars().next().filter(|c| *c == '"' || *c == '\'')?;
        let (value, after) = after[1..].split_once(quote)?;
        attributes.push((key.trim(), decode(value)));
        rest = after;
    }
    Some((name, attributes))
}

/// Text with XML's predefined and numeric character references replaced.
fn decode(text: &str) -> Cow<'_, str> {
    if !text.contains('&') {
        return Cow::Borrowed(text);
    }
    let mut out = String::with_capacity(text.len());
    let mut rest = text;
    while let Some(at) = rest.find('&') {
        out.push_str(&rest[..at]);
        rest = &rest[at..];
        let entity = rest.find(';').filter(|&end| end <= 10).map(|end| (&rest[1..end], end));
        let decoded = entity.and_then(|(name, end)| {
            let c = match name {
                "lt" => '<',
                "gt" => '>',
                "amp" => '&',
                "quot" => '"',
                "apos" => '\'',
                _ => {
                    let code = match name.strip_prefix("#x").or_else(|| name.strip_prefix("#X")) {
                        Some(hex) => u32::from_str_radix(hex, 16).ok(),
                        None => name.strip_prefix('#')?.parse().ok(),
                    };
                    char::from_u32(code?)?
                }
            };
            Some((c, end))
        });
        match decoded {
            Some((c, end)) => {
                out.push(c);
                rest = &rest[end + 1..];
            }
            None => {
                out.push('&');
                rest = &rest[1..];
            }
        }
    }
    out.push_str(rest);
    Cow::Owned(out)
}
