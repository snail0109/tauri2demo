fn main() {
    let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
    if target_os == "android" {
        println!("cargo:rustc-link-lib=c++_shared");
    }

    // 编译时嵌入讯飞凭证：优先读系统环境变量，回退读 src-tauri/.env 文件
    let env_path = std::path::PathBuf::from(&std::env::var("CARGO_MANIFEST_DIR").unwrap()).join(".env");
    if env_path.exists() {
        for line in std::fs::read_to_string(&env_path).unwrap().lines() {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            if let Some((key, val)) = line.split_once('=') {
                let key = key.trim();
                let val = val.trim();
                // 系统环境变量优先；若未设置则用 .env 中的值嵌入到编译产物
                if std::env::var(key).is_err() {
                    println!("cargo:rustc-env={}={}", key, val);
                }
            }
        }
    }

    tauri_build::build()
}
