//! XMP packets and JPEGs that carry one, for the tests of sidecars and keywords.

/// An XMP packet of `fields`, the attributes and elements of its description.
pub(crate) fn xmp(fields: &str) -> String {
    format!(
        r#"<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
<rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmlns:dc="http://purl.org/dc/elements/1.1/"
 xmlns:lr="http://ns.adobe.com/lightroom/1.0/" xmlns:digiKam="http://www.digikam.org/ns/1.0/"
 xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/" xmlns:exif="http://ns.adobe.com/exif/1.0/"
 {fields}</rdf:Description></rdf:RDF></x:xmpmeta>"#
    )
}

/// The RDF bag `name` of `items`.
pub(crate) fn bag(name: &str, items: &[&str]) -> String {
    let items: String = items.iter().map(|i| ["<rdf:li>", i, "</rdf:li>"].concat()).collect();
    format!("<{name}><rdf:Bag>{items}</rdf:Bag></{name}>")
}

/// `jpeg` with the XMP `packet` in an APP1 segment after its start of image.
pub(crate) fn with_xmp(jpeg: &[u8], packet: &str) -> Vec<u8> {
    let app1 = [&b"http://ns.adobe.com/xap/1.0/\0"[..], packet.as_bytes()].concat();
    let length = u16::try_from(app1.len() + 2).unwrap().to_be_bytes();
    [&jpeg[..2], &[0xff, 0xe1], &length, &app1, &jpeg[2..]].concat()
}
