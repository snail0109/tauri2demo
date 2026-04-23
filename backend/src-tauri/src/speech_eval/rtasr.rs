use base64::Engine;
use base64::engine::general_purpose::STANDARD as BASE64;
use futures_util::{SinkExt, StreamExt};
use std::sync::{Arc, Mutex};
use tauri::Emitter;
use tokio_tungstenite::connect_async;
use tokio_tungstenite::tungstenite::Message;

use super::auth::build_rtasr_url;
use super::types::XfConfig;

/// 每次发送的 PCM 字节数（40ms @ 16kHz 16bit mono = 1280 bytes）
const CHUNK_BYTES: usize = 1280;

/// 从 RTASR 响应的 data 字段中提取识别文本
fn extract_text_from_data(data: &str) -> Option<String> {
    // data 是 base64 编码的 JSON
    let decoded = BASE64.decode(data).ok()?;
    let json: serde_json::Value = serde_json::from_slice(&decoded).ok()?;

    // 遍历 cn.st.rt[].ws[].cw[].w 拼接文本
    let cn = json.get("cn")?;
    let st = cn.get("st")?;
    let rt_arr = st.get("rt")?.as_array()?;

    let mut text = String::new();
    for rt_item in rt_arr {
        if let Some(ws_arr) = rt_item.get("ws").and_then(|v| v.as_array()) {
            for ws_item in ws_arr {
                if let Some(cw_arr) = ws_item.get("cw").and_then(|v| v.as_array()) {
                    for cw_item in cw_arr {
                        if let Some(w) = cw_item.get("w").and_then(|v| v.as_str()) {
                            text.push_str(w);
                        }
                    }
                }
            }
        }
    }

    if text.is_empty() {
        None
    } else {
        Some(text)
    }
}

/// 启动实时 ASR WebSocket 客户端
///
/// 从 pcm_rx 接收 i16 PCM 数据，实时发送到讯飞 RTASR WebSocket，
/// 中间结果通过 Tauri 事件推送，最终结果存入 result_store。
///
/// 优先使用大模型版，如果连接/鉴权失败则降级到标准版。
pub async fn start_realtime_asr(
    app_handle: tauri::AppHandle,
    config: &XfConfig,
    lang: &str,
    mut pcm_rx: tokio::sync::mpsc::Receiver<Vec<i16>>,
    result_store: Arc<Mutex<Option<String>>>,
) -> Result<(), String> {
    // Map frontend language codes to RTASR language codes
    let rtasr_lang = match lang {
        "es" => "en", // RTASR doesn't have "es", use "en" for non-Chinese
        "zh" => "cn",
        "en" => "en",
        _ => "en",
    };

    // Try LLM version first, then fall back to standard version
    let urls = [
        build_rtasr_url(&config.app_id, &config.api_key, rtasr_lang, true),
        build_rtasr_url(&config.app_id, &config.api_key, rtasr_lang, false),
    ];

    let mut ws_stream = None;
    for (attempt, url) in urls.iter().enumerate() {
        let version = if attempt == 0 { "LLM" } else { "standard" };
        let url_preview = if url.len() > 100 {
            format!("{}...{}", &url[..60], &url[url.len() - 20..])
        } else {
            url.clone()
        };
        println!("[rtasr] attempt {} ({}): {}", attempt + 1, version, url_preview);

        match connect_async(url.as_str()).await {
            Ok((stream, _)) => {
                println!("[rtasr] connected using {} version", version);
                ws_stream = Some(stream);
                break;
            }
            Err(e) => {
                println!("[rtasr] {} version connect failed: {}", version, e);
                if attempt == urls.len() - 1 {
                    return Err(format!("RTASR WebSocket connect failed (tried both versions): {}", e));
                }
                continue;
            }
        }
    }

    let ws_stream = ws_stream.ok_or("RTASR: no WebSocket connection established")?;
    let (mut write, mut read) = ws_stream.split();

    // Wait for "started" action before sending audio
    let mut session_started = false;
    while let Some(msg) = read.next().await {
        let msg = msg.map_err(|e| format!("RTASR receive error: {}", e))?;
        match msg {
            Message::Text(text) => {
                if let Ok(resp) = serde_json::from_str::<serde_json::Value>(&text) {
                    let action = resp.get("action").and_then(|a| a.as_str()).unwrap_or("");
                    match action {
                        "started" => {
                            println!("[rtasr] session started");
                            session_started = true;
                            break;
                        }
                        "error" => {
                            let code = resp.get("code").and_then(|c| c.as_str()).unwrap_or("unknown");
                            let desc = resp.get("desc").and_then(|d| d.as_str()).unwrap_or("unknown");
                            return Err(format!("RTASR error: code={}, desc={}", code, desc));
                        }
                        _ => {
                            println!("[rtasr] unexpected action before started: {}", action);
                        }
                    }
                }
            }
            Message::Close(_) => {
                return Err("RTASR WebSocket closed before session started".to_string());
            }
            _ => {}
        }
    }

    if !session_started {
        return Err("RTASR: session never started".to_string());
    }

    // Spawn a task to send PCM data to the WebSocket
    let write_task = tokio::spawn(async move {
        // Buffer to accumulate PCM bytes until we have enough for a chunk
        let mut pcm_buffer: Vec<u8> = Vec::new();

        while let Some(pcm_i16_chunk) = pcm_rx.recv().await {
            // Convert i16 samples to bytes (little-endian)
            for &sample in &pcm_i16_chunk {
                pcm_buffer.extend_from_slice(&sample.to_le_bytes());
            }

            // Send in CHUNK_BYTES chunks
            while pcm_buffer.len() >= CHUNK_BYTES {
                let chunk: Vec<u8> = pcm_buffer.drain(..CHUNK_BYTES).collect();
                if write.send(Message::Binary(chunk.into())).await.is_err() {
                    println!("[rtasr] failed to send audio chunk, WebSocket may be closed");
                    return;
                }
            }
        }

        // Send any remaining buffered data
        if !pcm_buffer.is_empty() {
            let _ = write.send(Message::Binary(pcm_buffer.into())).await;
        }

        // Send end signal
        let end_msg = r#"{"end": true}"#;
        if write.send(Message::Text(end_msg.into())).await.is_err() {
            println!("[rtasr] failed to send end signal");
        }
        println!("[rtasr] audio sending complete, end signal sent");
    });

    // Read responses and emit partial results
    let mut final_text = String::new();
    while let Some(msg) = read.next().await {
        let msg = match msg {
            Ok(m) => m,
            Err(e) => {
                println!("[rtasr] receive error: {}", e);
                break;
            }
        };

        match msg {
            Message::Text(text) => {
                if let Ok(resp) = serde_json::from_str::<serde_json::Value>(&text) {
                    let action = resp.get("action").and_then(|a| a.as_str()).unwrap_or("");

                    match action {
                        "result" => {
                            if let Some(data) = resp.get("data").and_then(|d| d.as_str()) {
                                if let Some(recognized_text) = extract_text_from_data(data) {
                                    // Check if this is a final result (ls = true)
                                    let is_final = {
                                        if let Ok(decoded) = BASE64.decode(data) {
                                            if let Ok(json) = serde_json::from_slice::<serde_json::Value>(&decoded) {
                                                json.get("ls").and_then(|v| v.as_bool()).unwrap_or(false)
                                            } else {
                                                false
                                            }
                                        } else {
                                            false
                                        }
                                    };

                                    if is_final {
                                        final_text = recognized_text.clone();
                                    }

                                    // Emit partial result to frontend
                                    let _ = app_handle.emit(
                                        "asr-partial",
                                        serde_json::json!({
                                            "text": recognized_text,
                                            "is_final": is_final,
                                        }),
                                    );
                                }
                            }
                        }
                        "error" => {
                            let code = resp.get("code").and_then(|c| c.as_str()).unwrap_or("unknown");
                            let desc = resp.get("desc").and_then(|d| d.as_str()).unwrap_or("unknown");
                            println!("[rtasr] error: code={}, desc={}", code, desc);
                            break;
                        }
                        _ => {}
                    }
                }
            }
            Message::Close(_) => {
                println!("[rtasr] WebSocket closed by server");
                break;
            }
            _ => {}
        }
    }

    // Wait for the write task to finish
    let _ = write_task.await;

    // Store final result
    *result_store.lock().unwrap() = Some(final_text.clone());
    println!("[rtasr] recognition complete, final text: {}", final_text);

    Ok(())
}
