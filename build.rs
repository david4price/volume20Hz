use std::{env, path::PathBuf, process::Command};

fn main() {
    let out = PathBuf::from(env::var_os("OUT_DIR").expect("Cargo output directory"));
    let arch = match env::var("CARGO_CFG_TARGET_ARCH").unwrap().as_str() {
        "aarch64" => "arm64",
        "x86_64" => "x86_64",
        arch => panic!("Unsupported macOS architecture: {arch}"),
    };
    let object = out.join("macos.o");
    let success = Command::new("clang")
        .args([
            "-arch",
            arch,
            "-fobjc-arc",
            "-fblocks",
            "-c",
            "src/macos.m",
            "-o",
        ])
        .arg(&object)
        .status()
        .expect("Install Xcode Command Line Tools");
    assert!(success.success(), "Could not compile macOS bindings");
    println!("cargo:rerun-if-changed=src/macos.m");
    let success = Command::new("ar")
        .arg("crs")
        .arg(out.join("libvolume_macos.a"))
        .arg(object)
        .status()
        .expect("Xcode archive tool");
    assert!(success.success(), "Could not archive macOS bindings");
    println!("cargo:rustc-link-search=native={}", out.display());
    println!("cargo:rustc-link-lib=static=volume_macos");
    for framework in [
        "AppKit",
        "AVFoundation",
        "AVFAudio",
        "CoreAudio",
        "QuartzCore",
    ] {
        println!("cargo:rustc-link-lib=framework={framework}");
    }
}
