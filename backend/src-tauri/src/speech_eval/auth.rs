use base64::Engine;
use base64::engine::general_purpose::STANDARD as BASE64;
use chrono::Utc;
use hmac::{Hmac, Mac};
use sha1::Sha1;
use sha2::Sha256;
use url::form_urlencoded;

type HmacSha256 = Hmac<Sha256>;
type HmacSha1 = Hmac<Sha1>;

/// 生成讯飞 WebSocket 鉴权 URL
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

/// 生成讯飞 RTASR (实时语音转写标准版) 鉴权 URL
/// 鉴权方式：appid + ts → MD5(appid+ts) → HMAC-SHA1(apiKey, md5_result) → Base64 → signa
pub fn build_rtasr_url(app_id: &str, api_key: &str, lang: &str) -> String {
    let ts = chrono::Utc::now().timestamp().to_string();
    let base_string = format!("{}{}", app_id, ts);

    // Step 2: MD5 hash of base_string (lowercase hex)
    let md5_result = format!("{:x}", md5::compute(base_string.as_bytes()));

    // Step 3: HMAC-SHA1 with apiKey, then Base64 encode
    let mut mac = HmacSha1::new_from_slice(api_key.as_bytes())
        .expect("HMAC key length is always valid");
    mac.update(md5_result.as_bytes());
    let signa = BASE64.encode(mac.finalize().into_bytes());

    let signa_encoded: String = form_urlencoded::Serializer::new(String::new())
        .append_pair("signa", &signa)
        .finish();
    let signa_encoded = &signa_encoded["signa=".len()..];

    format!(
        "wss://rtasr.xfyun.cn/v1/ws?appid={}&ts={}&signa={}&lang={}&vad_eos=2000",
        app_id, ts, signa_encoded, lang
    )
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
    fn test_build_rtasr_url_contains_required_params() {
        let url = build_rtasr_url("test_appid", "test_apikey", "cn");
        assert!(url.starts_with("wss://rtasr.xfyun.cn/v1/ws?"));
        assert!(url.contains("appid=test_appid"));
        assert!(url.contains("lang=cn"));
        assert!(url.contains("ts="));
        assert!(url.contains("signa="));
        assert!(url.contains("vad_eos=2000"));
    }

    #[test]
    fn test_build_rtasr_url_signa_is_hmac_sha1_base64() {
        let url = build_rtasr_url("test_appid", "test_apikey", "cn");
        let signa_part = url.split("signa=").nth(1).unwrap();
        // signa is the first query param after signa=, so split on '&' to isolate it
        let signa_value = signa_part.split('&').next().unwrap();
        let signa_decoded = urlencoding::decode(signa_value).unwrap();
        let decoded = BASE64.decode(signa_decoded.as_ref());
        assert!(decoded.is_ok(), "signa should be valid base64");
        // HMAC-SHA1 produces 20 bytes
        assert_eq!(decoded.unwrap().len(), 20);
    }
}
