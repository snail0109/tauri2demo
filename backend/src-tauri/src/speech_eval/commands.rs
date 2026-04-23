use base64::Engine;
use base64::engine::general_purpose::STANDARD as BASE64;
use std::path::Path;
use tauri::{Manager, State};

use super::audio::{self, RecordingState};
use super::asr;
use super::client;
use super::rtasr;
use super::tts;
use super::types::{AsrResult, EvalResult, RealtimeAsrResult, XfConfig};

#[tauri::command]
pub async fn tts_synthesize(
    text: String,
    speed: i32,
    vcn: String,
    app_id: String,
    api_key: String,
    api_secret: String,
) -> Result<String, String> {
    let config = XfConfig { app_id, api_key, api_secret };
    println!("[tts] synthesize request, text={} chars, speed={}, vcn={}", text.len(), speed, vcn);
    let mp3_data = tts::xf_tts_synthesize(&config, &text, speed, &vcn).await?;
    let b64 = BASE64.encode(&mp3_data);
    println!("[tts] returning {} bytes as base64", mp3_data.len());
    Ok(b64)
}

/// 尝试解析文件路径：先按原路径查找，若为相对路径则逐级向上查找
fn resolve_file_path(file_path: &str) -> Result<std::path::PathBuf, String> {
    let path = Path::new(file_path);
    if path.exists() {
        return Ok(path.to_path_buf());
    }

    if path.is_relative() {
        if let Ok(mut dir) = std::env::current_dir() {
            for _ in 0..5 {
                if !dir.pop() {
                    break;
                }
                let candidate = dir.join(file_path);
                if candidate.exists() {
                    return Ok(candidate);
                }
            }
        }
    }

    Err(format!(
        "file not found: '{}' (cwd: {:?})",
        file_path,
        std::env::current_dir().ok()
    ))
}

#[tauri::command]
pub async fn evaluate_mp3_file(
    lang: String,
    category: String,
    ref_text: String,
    file_path: String,
    app_id: String,
    api_key: String,
    api_secret: String,
) -> Result<EvalResult, String> {
    // 1. 解析并读取 MP3 文件
    let resolved = resolve_file_path(&file_path)?;
    println!("[speech-eval] reading MP3 file: {}", resolved.display());
    let mp3_data = std::fs::read(&resolved)
        .map_err(|e| format!("failed to read MP3 file '{}': {}", resolved.display(), e))?;
    println!("[speech-eval] MP3 file loaded, {} bytes", mp3_data.len());

    // 2. 构建讯飞配置
    let config = XfConfig { app_id, api_key, api_secret };
    println!("[speech-eval] config loaded, app_id={}", config.app_id);

    // 3. 发送到讯飞 API 评测
    println!("[speech-eval] starting evaluation, lang={}, category={}", lang, category);
    let result = client::evaluate(&config, &lang, &category, &ref_text, &mp3_data).await?;
    println!("[speech-eval] evaluation complete, overall={}", result.overall);

    Ok(result)
}

#[tauri::command]
pub async fn start_recording(
    state: State<'_, RecordingState>,
    app_handle: tauri::AppHandle,
    app_id: String,
    api_key: String,
    api_secret: String,
    lang: String,
) -> Result<(), String> {
    // If XFyun credentials are provided, start real-time ASR alongside recording
    if !app_id.is_empty() && !api_key.is_empty() && !api_secret.is_empty() {
        let config = XfConfig {
            app_id: app_id.clone(),
            api_key: api_key.clone(),
            api_secret: api_secret.clone(),
        };
        let result_store = state.rtasr_result.clone();
        let handle_store = state.rtasr_handle.clone();
        let tx_store = state.rtasr_tx.clone();

        // Create channel: PCM data from cpal callback → WebSocket sender
        let (tx, rx) = tokio::sync::mpsc::channel::<Vec<i16>>(32);
        *tx_store.lock().unwrap() = Some(tx);

        // Spawn the RTASR WebSocket task
        let lang_owned = lang.clone();
        let handle = tokio::spawn(async move {
            match rtasr::start_realtime_asr(app_handle, &config, &lang_owned, rx, result_store).await {
                Ok(()) => println!("[rtasr] task completed successfully"),
                Err(e) => eprintln!("[rtasr] task failed: {}", e),
            }
        });
        *handle_store.lock().unwrap() = Some(handle);

        println!("[rtasr] real-time ASR started, lang={}", lang);
    }

    audio::start_recording(&state)
}

#[tauri::command]
pub async fn cancel_recording(state: State<'_, RecordingState>) -> Result<(), String> {
    audio::cancel_recording(&state)
}

#[tauri::command]
pub async fn stop_recording_and_evaluate(
    state: State<'_, RecordingState>,
    lang: String,
    category: String,
    ref_text: String,
    app_id: String,
    api_key: String,
    api_secret: String,
) -> Result<EvalResult, String> {
    // 1. 停止录音，获取 PCM 数据
    println!("[speech-eval] stopping recording...");
    let pcm_data = audio::stop_recording(&state)?;
    println!("[speech-eval] recorded {} PCM samples", pcm_data.len());

    // 2. 构建讯飞配置
    let config = XfConfig { app_id, api_key, api_secret };
    println!("[speech-eval] config loaded, app_id={}", config.app_id);

    // 3. PCM → MP3 编码
    println!("[speech-eval] encoding {} PCM samples to MP3...", pcm_data.len());
    let mp3_data = audio::encode_pcm_to_mp3(&pcm_data)?;
    println!("[speech-eval] MP3 encoded, {} bytes", mp3_data.len());

    // 4. 发送到讯飞 API 评测
    println!("[speech-eval] starting evaluation, lang={}, category={}", lang, category);
    let result = client::evaluate(&config, &lang, &category, &ref_text, &mp3_data).await?;
    println!("[speech-eval] evaluation complete, overall={}", result.overall);

    Ok(result)
}

#[tauri::command]
pub async fn stop_recording_and_recognize(
    state: State<'_, RecordingState>,
    app_id: String,
    api_key: String,
    api_secret: String,
) -> Result<AsrResult, String> {
    println!("[asr] stopping recording...");
    let pcm_data = audio::stop_recording(&state)?;
    println!("[asr] recorded {} PCM samples", pcm_data.len());
    let config = XfConfig { app_id, api_key, api_secret };
    println!("[asr] encoding {} PCM samples to MP3...", pcm_data.len());
    let mp3_data = audio::encode_pcm_to_mp3(&pcm_data)?;
    println!("[asr] MP3 encoded, {} bytes", mp3_data.len());
    println!("[asr] starting recognition...");
    let result = asr::recognize(&config, &mp3_data).await?;
    println!("[asr] recognition complete, text={}", result.text);
    Ok(result)
}

/// 停止实时语音转写：停止录音，等待 ASR 结果，保存音频文件
#[tauri::command]
pub async fn stop_realtime_asr(
    state: State<'_, RecordingState>,
    app_handle: tauri::AppHandle,
) -> Result<RealtimeAsrResult, String> {
    // 1. 停止录音
    println!("[rtasr] stopping recording...");
    let pcm_data = audio::stop_recording(&state)?;

    // 2. Drop the sender to signal the RTASR task to send end frame
    *state.rtasr_tx.lock().unwrap() = None;

    // 3. Wait for the RTASR task to complete
    // Extract handle before awaiting to avoid holding MutexGuard across await
    let rtasr_handle = state.rtasr_handle.lock().unwrap().take();
    if let Some(handle) = rtasr_handle {
        match handle.await {
            Ok(()) => println!("[rtasr] task completed"),
            Err(e) => println!("[rtasr] task join error: {}", e),
        }
    }

    // 4. Get the final result from the RTASR task
    let text = state
        .rtasr_result
        .lock()
        .unwrap()
        .take()
        .unwrap_or_default();

    // 5. Save PCM as MP3 for later playback/evaluation
    let audio_path = if !pcm_data.is_empty() {
        match save_recording_to_file(&pcm_data, &app_handle) {
            Ok(path) => {
                println!("[rtasr] audio saved to: {}", path);
                Some(path)
            }
            Err(e) => {
                eprintln!("[rtasr] failed to save audio: {}", e);
                None
            }
        }
    } else {
        None
    };

    println!("[rtasr] recognition complete, text={}, audio_path={:?}", text, audio_path);

    // Clear RTASR state
    *state.rtasr_result.lock().unwrap() = None;

    Ok(RealtimeAsrResult { text, audio_path })
}

/// Save recorded PCM data to a temporary MP3 file
fn save_recording_to_file(
    pcm_data: &[i16],
    app_handle: &tauri::AppHandle,
) -> Result<String, String> {
    // Encode PCM to MP3
    let mp3_data = audio::encode_pcm_to_mp3(pcm_data)?;

    // Use app data directory for persistent storage
    let app_data_dir = app_handle
        .path()
        .app_data_dir()
        .map_err(|e| format!("failed to get app data dir: {}", e))?;

    // Create recordings subdirectory if needed
    let recordings_dir = app_data_dir.join("recordings");
    std::fs::create_dir_all(&recordings_dir)
        .map_err(|e| format!("failed to create recordings dir: {}", e))?;

    // Generate unique filename
    let filename = format!("{}.mp3", chrono::Utc::now().format("%Y%m%d_%H%M%S_%f"));
    let file_path = recordings_dir.join(&filename);

    std::fs::write(&file_path, &mp3_data)
        .map_err(|e| format!("failed to write audio file: {}", e))?;

    Ok(file_path.to_string_lossy().to_string())
}
