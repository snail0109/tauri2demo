use serde::{Deserialize, Serialize};

// === 讯飞 API 请求结构 ===

#[derive(Serialize)]
pub struct XfRequest {
    pub header: XfRequestHeader,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub parameter: Option<XfParameter>,
    pub payload: XfPayload,
}

#[derive(Serialize)]
pub struct XfRequestHeader {
    pub app_id: String,
    pub status: i32,
}

#[derive(Serialize)]
pub struct XfParameter {
    pub st: XfStParam,
}

#[derive(Serialize)]
pub struct XfStParam {
    pub lang: String,
    pub core: String,
    #[serde(rename = "refText")]
    pub ref_text: String,
    pub result: XfResultFormat,
}

#[derive(Serialize)]
pub struct XfResultFormat {
    pub encoding: String,
    pub compress: String,
    pub format: String,
}

#[derive(Serialize)]
pub struct XfPayload {
    pub data: XfAudioData,
}

#[derive(Serialize)]
pub struct XfAudioData {
    pub encoding: String,
    pub sample_rate: i32,
    pub channels: i32,
    pub bit_depth: i32,
    pub status: i32,
    pub seq: i32,
    pub audio: String,
    pub frame_size: i32,
}

// === 讯飞 API 响应结构 ===

#[derive(Deserialize, Debug)]
pub struct XfResponse {
    pub header: XfResponseHeader,
    pub payload: Option<XfResponsePayload>,
}

#[allow(dead_code)]
#[derive(Deserialize, Debug)]
pub struct XfResponseHeader {
    pub code: i32,
    pub message: String,
    pub sid: Option<String>,
    pub status: Option<i32>,
}

#[derive(Deserialize, Debug)]
pub struct XfResponsePayload {
    pub result: Option<XfResponseResult>,
}

#[allow(dead_code)]
#[derive(Deserialize, Debug)]
pub struct XfResponseResult {
    pub text: String,
    pub seq: Option<i32>,
    pub status: Option<i32>,
}

// === 解码后的评测结果（从 base64 text 解码） ===

#[allow(dead_code)]
#[derive(Deserialize, Debug)]
pub struct XfEvalRaw {
    pub eof: Option<i32>,
    #[serde(rename = "refText")]
    pub ref_text: Option<String>,
    pub result: Option<serde_json::Value>,
}

// === 返回给前端的结构化结果 ===

#[derive(Serialize, Clone, Debug)]
pub struct EvalResult {
    pub overall: f64,
    pub pronunciation: f64,
    pub fluency: f64,
    pub integrity: f64,
    pub words: Vec<WordScore>,
}

#[derive(Serialize, Clone, Debug)]
pub struct WordScore {
    pub word: String,
    pub overall: f64,
    pub pronunciation: f64,
    pub read_type: i32,
}

// === 讯飞 API 配置（从环境变量注入） ===

pub struct XfConfig {
    pub app_id: String,
    pub api_key: String,
    pub api_secret: String,
}

impl XfConfig {
    /// 加载讯飞凭证：运行时环境变量优先，回退到编译时嵌入值（env! 宏）
    pub fn from_env() -> Result<Self, String> {
        let app_id = std::env::var("XF_APP_ID")
            .ok()
            .filter(|v| !v.is_empty())
            .unwrap_or_else(|| env!("XF_APP_ID").to_string());
        let api_key = std::env::var("XF_API_KEY")
            .ok()
            .filter(|v| !v.is_empty())
            .unwrap_or_else(|| env!("XF_API_KEY").to_string());
        let api_secret = std::env::var("XF_API_SECRET")
            .ok()
            .filter(|v| !v.is_empty())
            .unwrap_or_else(|| env!("XF_API_SECRET").to_string());
        Ok(Self { app_id, api_key, api_secret })
    }
}

/// 讯飞 RTASR（实时语音转写）配置 -- 只需要 appId + apiKey
pub struct XfRtasrConfig {
    pub app_id: String,
    pub api_key: String,
}

impl XfRtasrConfig {
    /// 加载 RTASR 凭证：运行时环境变量优先，回退到编译时嵌入值
    pub fn from_env() -> Result<Self, String> {
        let app_id = std::env::var("XF_RTASR_APP_ID")
            .ok()
            .filter(|v| !v.is_empty())
            .unwrap_or_else(|| env!("XF_RTASR_APP_ID").to_string());
        let api_key = std::env::var("XF_RTASR_API_KEY")
            .ok()
            .filter(|v| !v.is_empty())
            .unwrap_or_else(|| env!("XF_RTASR_API_KEY").to_string());
        Ok(Self { app_id, api_key })
    }
}

// === 实时语音转写（ASR）请求/响应结构 ===

#[derive(Serialize)]
pub struct AsrRequest {
    pub header: AsrRequestHeader,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub parameter: Option<AsrParameter>,
    pub payload: AsrPayload,
}

#[derive(Serialize)]
pub struct AsrRequestHeader {
    pub app_id: String,
    pub status: i32,
}

#[derive(Serialize)]
pub struct AsrParameter {
    pub nls: AsrNlsParam,
}

#[derive(Serialize)]
pub struct AsrNlsParam {
    #[serde(rename = "eng")]
    pub eng: String,
    #[serde(rename = "aue", skip_serializing_if = "Option::is_none")]
    pub aue: Option<String>,
    #[serde(rename = "ent", skip_serializing_if = "Option::is_none")]
    pub ent: Option<String>,
}

#[derive(Serialize)]
pub struct AsrPayload {
    pub data: AsrAudioData,
}

#[derive(Serialize)]
pub struct AsrAudioData {
    pub encoding: String,
    pub sample_rate: i32,
    pub channels: i32,
    pub bit_depth: i32,
    pub status: i32,
    pub seq: i32,
    pub audio: String,
    pub frame_size: i32,
}

#[allow(dead_code)]
#[derive(Deserialize, Debug)]
pub struct AsrResponse {
    pub header: AsrResponseHeader,
    pub payload: Option<AsrResponsePayload>,
}

#[allow(dead_code)]
#[derive(Deserialize, Debug)]
pub struct AsrResponseHeader {
    pub code: i32,
    pub message: String,
    pub sid: Option<String>,
    pub status: Option<i32>,
}

#[allow(dead_code)]
#[derive(Deserialize, Debug)]
pub struct AsrResponsePayload {
    pub result: Option<AsrResponseResult>,
}

#[allow(dead_code)]
#[derive(Deserialize, Debug)]
pub struct AsrResponseResult {
    pub bg: Option<String>,
    pub ed: Option<String>,
    pub ls: Option<bool>,
    pub pg: Option<String>,
    pub rg: Option<Vec<i32>>,
    pub sn: Option<String>,
    pub wa: Option<serde_json::Value>,
}

/// ASR 识别结果
#[derive(Serialize, Clone, Debug)]
pub struct AsrResult {
    pub text: String,
}

/// 实时 ASR 识别结果
#[derive(Serialize, Clone, Debug)]
pub struct RealtimeAsrResult {
    pub text: String,
    pub audio_path: Option<String>,
}

/// 根据语言选择 WebSocket 端点
pub fn get_ws_endpoint(lang: &str) -> (&'static str, &'static str) {
    match lang {
        "cn" | "en" => (
            "cn-east-1.ws-api.xf-yun.com",
            "/v1/private/s8e098720",
        ),
        _ => (
            "cn-east-1.ws-api.xf-yun.com",
            "/v1/private/sffc17cdb",
        ),
    }
}
