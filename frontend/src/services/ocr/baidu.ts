import { invoke } from '@tauri-apps/api/core'

export async function recognizeImageByBaiduOcr(
  imageBase64: string,
  apiKey: string,
  secretKey: string
) {
  const text = await invoke<string>('baidu_ocr', {
    imageBase64,
    apiKey,
    secretKey
  })

  return { text }
}

export async function fileToBase64WithoutPrefix(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader()

    reader.onload = () => {
      const result = reader.result
      if (typeof result !== 'string') {
        reject(new Error('读取图片失败'))
        return
      }

      const base64 = result.split(',')[1]
      if (!base64) {
        reject(new Error('Base64转换失败'))
        return
      }

      resolve(base64)
    }

    reader.onerror = () => reject(new Error('读取文件出错'))
    reader.readAsDataURL(file)
  })
}