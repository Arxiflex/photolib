// Generates the conformance service from the vendored protos at build time: protox compiles them without protoc and
// connectrpc-build turns the descriptors into buffa messages and a Connect service trait.
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let files = ["config", "server_compat", "service"].map(|name| format!("connectrpc/conformance/v1/{name}.proto"));
    let descriptors = protox::compile(&files, ["proto"])?;
    let path = std::path::Path::new(&std::env::var("OUT_DIR")?).join("conformance.binpb");
    std::fs::write(&path, prost::Message::encode_to_vec(&descriptors))?;
    connectrpc_build::Config::new()
        .descriptor_set(path)
        .files(&files)
        .include_file("_connectrpc.rs")
        .compile()?;
    println!("cargo::rerun-if-changed=proto");
    Ok(())
}
