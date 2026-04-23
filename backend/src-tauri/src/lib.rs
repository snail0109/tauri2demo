mod speech_eval;

use speech_eval::audio::RecordingState;
use speech_eval::commands;
use serde::Deserialize;
use tauri_plugin_log::{Target, TargetKind};

fn custom_log_out(
    out: tauri_plugin_log::fern::FormatCallback,
    message: &std::fmt::Arguments,
    record: &log::Record,
) {
    out.finish(format_args!(
        "{}[{}] {}",
        chrono::Local::now().format("[%Y-%m-%d %H:%M:%S%.3f]"),
        record.level(),
        message
    ))
}

const BAIDU_API_KEY: &str = "YOUR_BAIDU_API_KEY";
const BAIDU_SECRET_KEY: &str = "YOUR_BAIDU_SECRET_KEY";

// Learn more about Tauri commands at https://tauri.app/develop/calling-rust/
#[tauri::command]
fn greet(name: &str) -> String {
    format!("Hello, {}! You've been greeted from Rust!", name)
}

#[derive(Deserialize)]
struct TokenResponse {
    access_token: Option<String>,
    error: Option<String>,
    error_description: Option<String>,
}

#[derive(Deserialize)]
struct OcrWord {
    words: String,
}

#[derive(Deserialize)]
struct OcrResponse {
    words_result: Option<Vec<OcrWord>>,
    error_code: Option<i64>,
    error_msg: Option<String>,
}

// baidu OCR command
#[tauri::command]
async fn baidu_ocr(image_base64: String) -> Result<String, String> {
    println!("=== step 1: enter baidu_ocr ===");

    let client = reqwest::Client::new();

    let token_url = format!(
        "https://aip.baidubce.com/oauth/2.0/token?grant_type=client_credentials&client_id={}&client_secret={}",
        urlencoding::encode(BAIDU_API_KEY),
        urlencoding::encode(BAIDU_SECRET_KEY)
    );

    println!("=== step 2: request token ===");

    let token_resp = client
        .post(&token_url)
        .send()
        .await
        .map_err(|e| format!("获取 token 请求失败: {}", e))?;

    println!("=== step 3: token status = {} ===", token_resp.status());

    if !token_resp.status().is_success() {
        return Err(format!("获取 token 失败: HTTP {}", token_resp.status()));
    }

    let token_data: TokenResponse = token_resp
        .json()
        .await
        .map_err(|e| format!("解析 token 响应失败: {}", e))?;

    println!("=== step 4: token json parsed ===");

    let access_token = token_data.access_token.ok_or_else(|| {
        token_data
            .error_description
            .or(token_data.error)
            .unwrap_or_else(|| "未拿到 access_token".to_string())
    })?;

    println!("=== step 5: got access_token ===");

    let ocr_url = format!(
        "https://aip.baidubce.com/rest/2.0/ocr/v1/general_basic?access_token={}",
        urlencoding::encode(&access_token)
    );

    let params = [
        ("image", image_base64),
        ("language_type", "SPA".to_string()),
        ("detect_direction", "true".to_string()),
        ("paragraph", "false".to_string()),
    ];

    println!("=== step 6: request OCR ===");

    let ocr_resp = client
        .post(&ocr_url)
        .form(&params)
        .send()
        .await
        .map_err(|e| format!("OCR 请求失败: {}", e))?;

    println!("=== step 7: ocr status = {} ===", ocr_resp.status());

    if !ocr_resp.status().is_success() {
        return Err(format!("OCR 调用失败: HTTP {}", ocr_resp.status()));
    }

    let ocr_data: OcrResponse = ocr_resp
        .json()
        .await
        .map_err(|e| format!("解析 OCR 响应失败: {}", e))?;

    println!("=== step 8: ocr json parsed ===");

    if let Some(code) = ocr_data.error_code {
        return Err(format!(
            "百度 OCR 错误 {}: {}",
            code,
            ocr_data.error_msg.unwrap_or_default()
        ));
    }

    let text = ocr_data
        .words_result
        .unwrap_or_default()
        .into_iter()
        .map(|w| w.words)
        .collect::<Vec<_>>()
        .join("\n");

    println!("=== step 9: success ===");

    Ok(text)
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_http::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(
            tauri_plugin_log::Builder::new()
                .targets([
                    Target::new(TargetKind::Stdout),
                    Target::new(TargetKind::LogDir { file_name: None }),
                    Target::new(TargetKind::Webview),
                ])
                .level(if cfg!(debug_assertions) {
                    log::LevelFilter::Trace
                } else {
                    log::LevelFilter::Info
                })
                .format(move |out, message, record| {
                    custom_log_out(out, message, record);
                })
                .max_file_size(50000)
                .build(),
        )
        // ===== 他的：录音状态管理 =====
        .manage(RecordingState::new())
        .invoke_handler(tauri::generate_handler![
            greet,
            baidu_ocr,
            commands::start_recording,
            commands::start_realtime_asr_recording,
            commands::cancel_recording,
            commands::stop_recording_and_evaluate,
            commands::evaluate_mp3_file,
            commands::tts_synthesize,
            commands::stop_recording_and_recognize,
            commands::stop_realtime_asr,
            commands::list_recordings,
            commands::delete_recording,
            commands::clear_recordings
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
