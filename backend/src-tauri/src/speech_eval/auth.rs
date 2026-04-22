use base64::Engine;
use base64::engine::general_purpose::STANDARD as BASE64;
use chrono::Utc;
use hmac::{Hmac, Mac};
use sha2::Sha256;
use sha1::Sha1;
use md5::Digest;
use url::form_urlencoded;

type HmacSha256 = Hmac<Sha256>;
type HmacSha1 = Hmac<Sha1>;

/// 生成讯飞 WebSocket 鉴权 URL（语音评测、TTS、ASR 等使用）
/// 鉴权方式：HMAC-SHA256(apiSecret, host+date+request-line)
pub fn build_auth_url(host: &str, path: &str, api_key: &str, api_secret: &str) -> String {
    // Step 1: 生成 RFC1123 格式的 UTC 时间
    let date = Utc::now().format("%a, %d %b %Y %H:%M:%S GMT").to_string();

    // Step 2: 构建签名原文
    let signature_origin = format!(
        "host: {}\ndate: {}\nGET {} HTTP/1.1",
        host, date, path
    );

    // Step 3: HMAC-SHA256 签名
    let mut mac = HmacSha256::new_from_slice(api_secret.as_bytes())
        .expect("HMAC key length is always valid");
    mac.update(signature_origin.as_bytes());
    let signature = BASE64.encode(mac.finalize().into_bytes());

    // Step 4: 构建 authorization_origin
    let authorization_origin = format!(
        r#"api_key="{}", algorithm="hmac-sha256", headers="host date request-line", signature="{}""#,
        api_key, signature
    );

    // Step 5: base64 编码得到最终 authorization
    let authorization = BASE64.encode(authorization_origin.as_bytes());

    // Step 6: 拼接完整 URL
    let encoded_date: String = form_urlencoded::Serializer::new(String::new())
        .append_pair("date", &date)
        .finish();
    let encoded_date = &encoded_date["date=".len()..];

    format!(
        "wss://{}{}?host={}&date={}&authorization={}",
        host, path, host, encoded_date, authorization
    )
}

/// 生成讯飞 RTASR 标准版鉴权 URL
/// 鉴权方式：signa = Base64(HmacSHA1(MD5(appid + ts), apiKey))
/// URL: wss://rtasr.xfyun.cn/v1/ws?appid={}&ts={}&signa={}&lang={}&vad_eos=2000
pub fn build_rtasr_url(app_id: &str, api_key: &str, lang: &str) -> String {
    let ts = Utc::now().timestamp().to_string();

    // Step 1: baseString = appid + ts
    let base_string = format!("{}{}", app_id, ts);

    // Step 2: MD5(baseString)
    let md5_result = format!("{:x}", md5::Md5::digest(base_string.as_bytes()));

    // Step 3: signa = Base64(HmacSHA1(MD5_result, apiKey))
    let mut mac = HmacSha1::new_from_slice(api_key.as_bytes())
        .expect("HMAC key length is always valid");
    mac.update(md5_result.as_bytes());
    let signa = BASE64.encode(mac.finalize().into_bytes());

    // Step 4: URL encode signa
    let signa_encoded: String = form_urlencoded::Serializer::new(String::new())
        .append_pair("signa", &signa)
        .finish();
    let signa_encoded = &signa_encoded["signa=".len()..];

    format!(
        "wss://rtasr.xfyun.cn/v1/ws?appid={}&ts={}&signa={}&lang={}&vad_eos=2000",
        app_id, ts, signa_encoded, lang
    )
}

/// percent-encode 一个字符串（RFC 3986），保留字母、数字和 -_.~ 不编码
fn percent_encode(s: &str) -> String {
    let mut out = String::with_capacity(s.len() * 3);
    for b in s.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(b as char);
            }
            _ => {
                out.push('%');
                out.push_str(&format!("{:02X}", b));
            }
        }
    }
    out
}

/// 生成讯飞 RTASR 大模型版鉴权 URL
/// 鉴权方式：参数按名升序排列，原始值拼接 baseString，签名后 percent-encode 拼入 URL
/// URL: wss://office-api-ast-dx.iflyaisol.com/ast/communicate/v1?{请求参数}
/// accessKeyId = apiKey, accessKeySecret = apiSecret（与语音评测配置一致）
pub fn build_rtasr_llm_url(app_id: &str, access_key_id: &str, access_key_secret: &str, lang: &str) -> String {
    // 固定参数
    let audio_encode = "pcm_s16le";
    let samplerate = "16000";

    // utc 时间格式：yyyy-MM-dd'T'HH:mm:ss+0800
    let beijing_offset = chrono::FixedOffset::east_opt(8 * 3600).unwrap();
    let now_bj = chrono::Utc::now().with_timezone(&beijing_offset);
    let utc = now_bj.format("%Y-%m-%dT%H:%M:%S%z").to_string();

    // uuid
    let uuid_str = uuid::Uuid::new_v4().to_string().replace("-", "");

    // 所有请求参数（不包含 signature），按参数名升序排序
    let mut params: Vec<(&str, String)> = vec![
        ("accessKeyId", access_key_id.to_string()),
        ("appId", app_id.to_string()),
        ("audio_encode", audio_encode.to_string()),
        ("lang", lang.to_string()),
        ("samplerate", samplerate.to_string()),
        ("utc", utc.clone()),
        ("uuid", uuid_str.clone()),
    ];
    params.sort_by(|a, b| a.0.cmp(b.0));

    // baseString：key 和 value 都做 percent-encode（对应 Python urllib.parse.quote(x, safe='')）
    let base_string = params.iter()
        .map(|(k, v)| format!("{}={}", percent_encode(k), percent_encode(v)))
        .collect::<Vec<_>>()
        .join("&");

    // signature = Base64(HmacSHA1(baseString, accessKeySecret))
    let mut mac = HmacSha1::new_from_slice(access_key_secret.as_bytes())
        .expect("HMAC key length is always valid");
    mac.update(base_string.as_bytes());
    let signature = BASE64.encode(mac.finalize().into_bytes());

    // 拼接完整 URL：参数值做 percent-encode（RFC 3986）
    let mut all_params = params.clone();
    all_params.push(("signature", signature.clone()));

    let params_str = all_params.iter()
        .map(|(k, v)| format!("{}={}", k, percent_encode(v)))
        .collect::<Vec<_>>()
        .join("&");

    format!("wss://office-api-ast-dx.iflyaisol.com/ast/communicate/v1?{}", params_str)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_build_auth_url_format() {
        let url = build_auth_url(
            "cn-east-1.ws-api.xf-yun.com",
            "/v1/private/s8e098720",
            "test_api_key",
            "test_api_secret",
        );
        assert!(url.starts_with("wss://cn-east-1.ws-api.xf-yun.com/v1/private/s8e098720?"));
        assert!(url.contains("host=cn-east-1.ws-api.xf-yun.com"));
        assert!(url.contains("date="));
        assert!(url.contains("authorization="));
    }

    #[test]
    fn test_build_auth_url_authorization_is_valid_base64() {
        let url = build_auth_url(
            "cn-east-1.ws-api.xf-yun.com",
            "/v1/private/s8e098720",
            "test_key",
            "test_secret",
        );
        let auth_param = url.split("authorization=").nth(1).unwrap();
        let decoded = BASE64.decode(auth_param);
        assert!(decoded.is_ok(), "authorization should be valid base64");
        let decoded_str = String::from_utf8(decoded.unwrap()).unwrap();
        assert!(decoded_str.contains("api_key=\"test_key\""));
        assert!(decoded_str.contains("algorithm=\"hmac-sha256\""));
        assert!(decoded_str.contains("headers=\"host date request-line\""));
        assert!(decoded_str.contains("signature=\""));
    }

    #[test]
    fn test_build_rtasr_url_format() {
        let url = build_rtasr_url("595f23df", "d9f4aa7ea6d94faca62cd88a28fd5234", "cn");
        assert!(url.starts_with("wss://rtasr.xfyun.cn/v1/ws?"));
        assert!(url.contains("appid=595f23df"));
        assert!(url.contains("lang=cn"));
        assert!(url.contains("signa="));
    }

    #[test]
    fn test_build_rtasr_llm_url_format() {
        let url = build_rtasr_llm_url("test_appid", "test_key_id", "test_key_secret", "cn");
        assert!(url.starts_with("wss://office-api-ast-dx.iflyaisol.com/ast/communicate/v1?"));
        assert!(url.contains("appId=test_appid"));
        assert!(url.contains("accessKeyId=test_key_id"));
        assert!(url.contains("signature="));
    }
}