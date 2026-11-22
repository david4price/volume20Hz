use std::{env, path::PathBuf, process::Command};

fn main() {
    let out = PathBuf::from(env::var_os("OUT_DIR").expect("Cargo output directory"));
    let arch = match env::var("CARGO_CFG_TARGET_ARCH").unwrap().as_str() {
        "aarch64" => "arm64",
        "x86_64" => "x86_64",
        arch => panic!("Unsupported macOS architecture: {arch}"),
    };
    println!("cargo:rerun-if-changed=src/audio.h");
    let mut archive = Command::new("ar");
    archive.arg("crs").arg(out.join("libvolume_macos.a"));
    for name in ["macos", "audio"] {
        let source = format!("src/{name}.m");
        let object = out.join(format!("{name}.o"));
        println!("cargo:rerun-if-changed={source}");
        let success = Command::new("clang")
            .args(["-arch", arch, "-fobjc-arc", "-fblocks", "-c", &source, "-o"])
            .arg(&object)
            .status()
            .expect("Install Xcode Command Line Tools");
        assert!(success.success(), "Could not compile {source}");
        archive.arg(object);
    }
    let success = archive.status().expect("Xcode archive tool");
    assert!(success.success(), "Could not archive macOS bindings");
    println!("cargo:rustc-link-search=native={}", out.display());
    println!("cargo:rustc-link-lib=static=volume_macos");
    for framework in ["AppKit", "AudioToolbox", "CoreAudio", "QuartzCore"] {
        println!("cargo:rustc-link-lib=framework={framework}");
    }
}
