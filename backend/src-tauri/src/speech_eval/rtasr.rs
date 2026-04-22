use futures_util::{SinkExt, StreamExt};
use std::sync::{Arc, Mutex};
use tauri::Emitter;
use tokio_tungstenite::connect_async;
use tokio_tungstenite::tungstenite::Message;

use super::auth::{build_rtasr_url, build_rtasr_llm_url};
use super::types::XfConfig;

/// 每次发送的 PCM 字节数（40ms @ 16kHz 16bit mono = 1280 bytes）
const CHUNK_BYTES: usize = 1280;

/// RTASR 版本类型
#[derive(Clone)]
enum RtasrVersion {
    /// 标准版：wss://rtasr.xfyun.cn/v1/ws，响应格式 action/data（base64 编码）
    Standard,
    /// 大模型版：wss://office-api-ast-dx.iflyaisol.com/ast/communicate/v1，响应格式 msg_type/data（纯 JSON）
    Llm,
}

/// 从标准版 RTASR 响应的 data 字段中提取识别文本
/// data 是 JSON 字符串，结构为 cn.st.rt[].ws[].cw[].w
fn extract_text_from_std_data(data: &str) -> Option<(String, bool)> {
    let json: serde_json::Value = serde_json::from_str(data).ok()?;

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
        return None;
    }

    // type="0" 为最终结果，type="1" 为中间结果；ls=true 也表示最后一帧
    let st_type = st.get("type").and_then(|v| v.as_str()).unwrap_or("1");
    let ls = json.get("ls").and_then(|v| v.as_bool()).unwrap_or(false);
    let is_final = st_type == "0" || ls;

    Some((text, is_final))
}

/// 从大模型版 RTASR 响应中提取识别文本
/// 大模型版响应 data 为纯 JSON，结构为 data.cn.st.rt[].ws[].cw[].w
fn extract_text_from_llm_data(data: &serde_json::Value) -> Option<String> {
    let cn = data.get("cn")?;
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

    if text.is_empty() { None } else { Some(text) }
}

/// 启动实时 ASR WebSocket 客户端
///
/// 从 pcm_rx 接收 i16 PCM 数据，实时发送到讯飞 RTASR WebSocket，
/// 中间结果通过 Tauri 事件推送，最终结果存入 result_store。
///
/// use_llm=true 使用大模型版，use_llm=false 使用标准版。
/// 如果连接失败，自动降级到另一版本。
pub async fn start_realtime_asr(
    app_handle: tauri::AppHandle,
    config: &XfConfig,
    lang: &str,
    mut pcm_rx: tokio::sync::mpsc::Receiver<Vec<i16>>,
    result_store: Arc<Mutex<Option<String>>>,
    use_llm: bool,
) -> Result<(), String> {
    // 大模型版只支持 autodialect（中英+方言）和 autominor（37语种）
    // 标准版有自己的语言代码
    let rtasr_lang_llm = "autominor"; // 支持西班牙语等37语种
    let rtasr_lang_std = match lang {
        "es" => "es",
        "zh" => "cn",
        "en" => "en",
        _ => lang,
    };

    // 标准版使用独立的 apiKey（rtasrApiKey），大模型版使用语音评测的 apiKey + apiSecret
    // 注意：标准版鉴权的 apiKey 与语音评测不同，由前端传入正确的 apiKey

    // Connect to the selected version only — no fallback
    let (url, version) = if use_llm {
        (
            build_rtasr_llm_url(&config.app_id, &config.api_key, &config.api_secret, rtasr_lang_llm),
            RtasrVersion::Llm,
        )
    } else {
        (
            build_rtasr_url(&config.app_id, &config.api_key, rtasr_lang_std),
            RtasrVersion::Standard,
        )
    };

    let version_name = match version {
        RtasrVersion::Llm => "LLM",
        RtasrVersion::Standard => "standard",
    };
    let url_preview = if url.len() > 100 {
        format!("{}...{}", &url[..60], &url[url.len() - 20..])
    } else {
        url.clone()
    };
    println!("[rtasr] connecting ({}): {}", version_name, url_preview);

    let ws_stream = connect_async(url.as_str()).await
        .map_err(|e| format!("RTASR {} connect failed: {}", version_name, e))?
        .0;
    let connected_version = version;
    println!("[rtasr] connected using {} version", version_name);
    let (mut write, mut read) = ws_stream.split();

    // Wait for session start before sending audio
    let mut session_started = false;
    let mut session_id = None; // 大模型版需要 sessionId

    while let Some(msg) = read.next().await {
        let msg = msg.map_err(|e| format!("RTASR receive error: {}", e))?;
        match msg {
            Message::Text(text) => {
                if let Ok(resp) = serde_json::from_str::<serde_json::Value>(&text) {
                    match connected_version {
                        RtasrVersion::Standard => {
                            // 标准版：action = "started" 表示握手成功
                            let action = resp.get("action").and_then(|a| a.as_str()).unwrap_or("");
                            match action {
                                "started" => {
                                    println!("[rtasr] standard session started");
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
                        RtasrVersion::Llm => {
                            // 大模型版：msg_type = "action", data.sessionId 表示握手成功
                            let msg_type = resp.get("msg_type").and_then(|m| m.as_str()).unwrap_or("");
                            if msg_type == "action" {
                                if let Some(data) = resp.get("data") {
                                    if let Some(sid) = data.get("sessionId").and_then(|s| s.as_str()) {
                                        println!("[rtasr] LLM session started, sessionId={}", sid);
                                        session_id = Some(sid.to_string());
                                        session_started = true;
                                        break;
                                    }
                                }
                            }
                            // Check for error
                            if resp.get("code").is_some() || resp.get("msg_type").and_then(|m| m.as_str()) == Some("error") {
                                let code = resp.get("code").and_then(|c| c.as_str()).unwrap_or("unknown");
                                let desc = resp.get("desc").and_then(|d| d.as_str()).unwrap_or("unknown");
                                return Err(format!("RTASR LLM error: code={}, desc={}", code, desc));
                            }
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
    let session_id_clone = session_id.clone();
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
        let end_msg = if let Some(sid) = session_id_clone {
            serde_json::json!({"end": true, "sessionId": sid}).to_string()
        } else {
            r#"{"end": true}"#.to_string()
        };
        if write.send(Message::Text(end_msg.into())).await.is_err() {
            println!("[rtasr] failed to send end signal");
        }
        println!("[rtasr] audio sending complete, end signal sent");
    });

    // Read responses and emit partial results
    let mut final_text = String::new();
    let mut last_partial = String::new();

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
                println!("[rtasr] server msg: {}", &text[..text.len().min(400)]);
                if let Ok(resp) = serde_json::from_str::<serde_json::Value>(&text) {
                    match connected_version {
                        RtasrVersion::Standard => {
                            // 标准版：action = "result"，data 为 JSON 字符串
                            let action = resp.get("action").and_then(|a| a.as_str()).unwrap_or("");
                            match action {
                                "result" => {
                                    if let Some(data) = resp.get("data").and_then(|d| d.as_str()) {
                                        if let Some((recognized_text, is_final)) = extract_text_from_std_data(data) {
                                            if is_final {
                                                if !final_text.is_empty() { final_text.push(' '); }
                                                final_text.push_str(&recognized_text);
                                                last_partial.clear();
                                            } else {
                                                last_partial = recognized_text.clone();
                                            }

                                            let _ = app_handle.emit(
                                                "asr-partial",
                                                serde_json::json!({ "text": recognized_text, "is_final": is_final }),
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
                        RtasrVersion::Llm => {
                            // 大模型版：msg_type = "result"，data 为纯 JSON
                            let msg_type = resp.get("msg_type").and_then(|m| m.as_str()).unwrap_or("");
                            match msg_type {
                                "result" => {
                                    if let Some(data) = resp.get("data") {
                                        if let Some(recognized_text) = extract_text_from_llm_data(data) {
                                            // type=0 为 final，type=1 为 partial
                                            let st = data.get("cn").and_then(|cn| cn.get("st"));
                                            let is_final = st
                                                .and_then(|s| s.get("type"))
                                                .and_then(|t| t.as_i64())
                                                .unwrap_or(1) == 0;

                                            if is_final {
                                                if !final_text.is_empty() { final_text.push(' '); }
                                                final_text.push_str(&recognized_text);
                                                last_partial.clear();
                                            } else {
                                                last_partial = recognized_text.clone();
                                            }

                                            let _ = app_handle.emit(
                                                "asr-partial",
                                                serde_json::json!({ "text": recognized_text, "is_final": is_final }),
                                            );
                                        }
                                    }
                                }
                                "error" => {
                                    let code = resp.get("code").and_then(|c| c.as_str()).unwrap_or("unknown");
                                    let desc = resp.get("desc").and_then(|d| d.as_str()).unwrap_or("unknown");
                                    println!("[rtasr] LLM error: code={}, desc={}", code, desc);
                                    break;
                                }
                                _ => {}
                            }
                        }
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

    // If no final frame arrived, fall back to last partial result
    if final_text.is_empty() && !last_partial.is_empty() {
        println!("[rtasr] no final frame received, using last partial: {}", last_partial);
        final_text = last_partial;
    }

    // Store final result
    *result_store.lock().unwrap() = Some(final_text.clone());
    println!("[rtasr] recognition complete, final text: {}", final_text);

    Ok(())
}