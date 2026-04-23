use base64::Engine;
use base64::engine::general_purpose::STANDARD as BASE64;
use serde::Serialize;
use std::path::Path;
use tauri::{Manager, State};

use super::audio::{self, RecordingState};
use super::asr;
use super::client;
use super::rtasr;
use super::tts;
use super::types::{AsrResult, EvalResult, RealtimeAsrResult, XfConfig, XfRtasrConfig};

#[tauri::command]
pub async fn tts_synthesize(
    text: String,
    speed: i32,
    vcn: String,
) -> Result<String, String> {
    let config = XfConfig::from_env()?;
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
) -> Result<EvalResult, String> {
    // 1. 解析并读取 MP3 文件
    let resolved = resolve_file_path(&file_path)?;
    println!("[speech-eval] reading MP3 file: {}", resolved.display());
    let mp3_data = std::fs::read(&resolved)
        .map_err(|e| format!("failed to read MP3 file '{}': {}", resolved.display(), e))?;
    println!("[speech-eval] MP3 file loaded, {} bytes", mp3_data.len());

    // 2. 构建讯飞配置
    let config = XfConfig::from_env()?;
    println!("[speech-eval] config loaded, app_id={}", config.app_id);

    // 3. 发送到讯飞 API 评测
    println!("[speech-eval] starting evaluation, lang={}, category={}", lang, category);
    let result = client::evaluate(&config, &lang, &category, &ref_text, &mp3_data).await?;
    println!("[speech-eval] evaluation complete, overall={}", result.overall);

    Ok(result)
}

/// 词典/跟读专用：纯录音，不启动实时 ASR。
/// 不要在这里加任何 RTASR/WebSocket 相关逻辑，以免影响讯飞评测打分。
#[tauri::command]
pub async fn start_recording(state: State<'_, RecordingState>) -> Result<(), String> {
    // 确保不会因为之前对话流程的残留导致回调走 RTASR 分支
    *state.rtasr_tx.lock().unwrap() = None;
    audio::start_recording(&state)
}

/// 对话专用：录音 + 实时语音转写（RTASR）。
/// 与 `start_recording` 完全独立，互不影响。
#[tauri::command]
pub async fn start_realtime_asr_recording(
    state: State<'_, RecordingState>,
    app_handle: tauri::AppHandle,
    lang: String,
) -> Result<(), String> {
    let config = XfRtasrConfig::from_env()?;
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
) -> Result<EvalResult, String> {
    // 1. 停止录音，获取 PCM 数据
    println!("[speech-eval] stopping recording...");
    let pcm_data = audio::stop_recording(&state)?;
    println!("[speech-eval] recorded {} PCM samples", pcm_data.len());

    // 1.5 调试：统计 PCM 峰值与 RMS，确认麦克风是否真的收到声音
    if !pcm_data.is_empty() {
        let mut peak: i32 = 0;
        let mut sum_sq: f64 = 0.0;
        for &s in &pcm_data {
            let a = (s as i32).abs();
            if a > peak { peak = a; }
            sum_sq += (s as f64) * (s as f64);
        }
        let rms = (sum_sq / pcm_data.len() as f64).sqrt();
        println!(
            "[speech-eval][debug] PCM stats: samples={}, peak={}, rms={:.1}, peak_ratio={:.4}",
            pcm_data.len(),
            peak,
            rms,
            peak as f64 / i16::MAX as f64,
        );
    }

    // 2. 构建讯飞配置
    let config = XfConfig::from_env()?;
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
) -> Result<AsrResult, String> {
    println!("[asr] stopping recording...");
    let pcm_data = audio::stop_recording(&state)?;
    println!("[asr] recorded {} PCM samples", pcm_data.len());
    let config = XfConfig::from_env()?;
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

/// 录音文件信息
#[derive(Serialize, Clone)]
pub struct RecordingEntry {
    pub name: String,
    pub size: u64,
    pub path: String,
    pub created_at: String,
}

/// 获取录音缓存列表
#[tauri::command]
pub async fn list_recordings(app_handle: tauri::AppHandle) -> Result<Vec<RecordingEntry>, String> {
    let app_data_dir = app_handle
        .path()
        .app_data_dir()
        .map_err(|e| format!("failed to get app data dir: {}", e))?;
    let recordings_dir = app_data_dir.join("recordings");

    if !recordings_dir.exists() {
        return Ok(Vec::new());
    }

    let mut entries = Vec::new();
    let dir = std::fs::read_dir(&recordings_dir)
        .map_err(|e| format!("failed to read recordings dir: {}", e))?;

    for entry in dir {
        let entry = entry.map_err(|e| format!("failed to read dir entry: {}", e))?;
        let path = entry.path();
        if !path.is_file() || !path.extension().map(|e| e == "mp3").unwrap_or(false) {
            continue;
        }
        let metadata = entry.metadata().map_err(|e| format!("failed to read metadata: {}", e))?;
        let created = metadata.created()
            .map(|t| {
                let datetime: chrono::DateTime<chrono::Local> = t.into();
                datetime.format("%Y-%m-%d %H:%M:%S").to_string()
            })
            .unwrap_or_else(|_| "unknown".to_string());
        entries.push(RecordingEntry {
            name: path.file_name().unwrap().to_string_lossy().to_string(),
            size: metadata.len(),
            path: path.to_string_lossy().to_string(),
            created_at: created,
        });
    }

    // 按创建时间倒序排列
    entries.sort_by(|a, b| b.created_at.cmp(&a.created_at));
    Ok(entries)
}

/// 删除单个录音文件
#[tauri::command]
pub async fn delete_recording(path: String) -> Result<(), String> {
    std::fs::remove_file(&path)
        .map_err(|e| format!("failed to delete recording: {}", e))
}

/// 清理全部录音文件
#[tauri::command]
pub async fn clear_recordings(app_handle: tauri::AppHandle) -> Result<u64, String> {
    let app_data_dir = app_handle
        .path()
        .app_data_dir()
        .map_err(|e| format!("failed to get app data dir: {}", e))?;
    let recordings_dir = app_data_dir.join("recordings");

    if !recordings_dir.exists() {
        return Ok(0);
    }

    let mut count = 0u64;
    let dir = std::fs::read_dir(&recordings_dir)
        .map_err(|e| format!("failed to read recordings dir: {}", e))?;

    for entry in dir {
        let entry = entry.map_err(|e| format!("failed to read dir entry: {}", e))?;
        let path = entry.path();
        if path.is_file() && path.extension().map(|e| e == "mp3").unwrap_or(false) {
            std::fs::remove_file(&path)
                .map_err(|e| format!("failed to delete {}: {}", path.display(), e))?;
            count += 1;
        }
    }

    Ok(count)
}
