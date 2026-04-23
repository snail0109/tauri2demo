<script setup lang="ts">
import { ref, computed } from 'vue'
import { invoke } from '@tauri-apps/api/core'
import { ElMessage } from 'element-plus'
import EvalResult from './components/EvalResult.vue'
import { useDailySentence } from './composables/useDailySentence'
import { useSettingsStore } from '@/stores/settings'

defineOptions({
  name: 'SpeechEval',
})

interface EvalResultData {
  overall: number
  pronunciation: number
  fluency: number
  integrity: number
  words: { word: string; overall: number; pronunciation: number; read_type: number }[]
}

const { sentence, shownCount, total, canPrev, canNext, prev, next } = useDailySentence()
const settingsStore = useSettingsStore()
const xfConfig = computed(() => settingsStore.settingsState.xfSpeechEval)
const recording = ref(false)
const loading = ref(false)
const evalResult = ref<EvalResultData | null>(null)
const errorMsg = ref('')

// TTS
type PlayMode = 'normal' | 'slow'
const playingMode = ref<PlayMode | null>(null)
let currentAudio: HTMLAudioElement | null = null

function stopPlayback() {
  if (currentAudio) {
    currentAudio.pause()
    currentAudio.src = ''
    currentAudio = null
  }
  // Also stop native TTS if active
  const nativeTTS = (window as any).NativeTTS
  if (nativeTTS?.stop) nativeTTS.stop()
  if ('speechSynthesis' in window) speechSynthesis.cancel()
  playingMode.value = null
}

async function play(mode: PlayMode) {
  // Toggle off if same mode
  if (playingMode.value === mode) {
    stopPlayback()
    return
  }

  const { appId, apiKey, apiSecret } = xfConfig.value
  console.log('[tts] play called, mode=', mode, 'appId=', appId, 'text=', sentence.value.sentence_original)
  if (!appId || !apiKey || !apiSecret) {
    ElMessage.warning('请先在设置页面填写讯飞语音评测的 App ID、API Key 和 API Secret')
    return
  }

  stopPlayback()
  playingMode.value = mode

  try {
    const speed = mode === 'slow' ? 30 : 50
    const vcn = 'x2_spes_aurora'
    console.log('[tts] invoking tts_synthesize...')
    const b64 = await invoke<string>('tts_synthesize', {
      text: sentence.value.sentence_original,
      speed,
      vcn,
      appId,
      apiKey,
      apiSecret,
    })
    console.log('[tts] got base64 response, length=', b64.length)
    const binary = atob(b64)
    const bytes = new Uint8Array(binary.length)
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i)
    console.log('[tts] decoded audio bytes=', bytes.length)
    const blob = new Blob([bytes], { type: 'audio/mp3' })
    const url = URL.createObjectURL(blob)
    const audio = new Audio(url)
    currentAudio = audio
    audio.onended = () => {
      playingMode.value = null
      URL.revokeObjectURL(url)
      currentAudio = null
    }
    audio.onerror = () => {
      playingMode.value = null
      // ElMessage.warning('音频播放失败')
      URL.revokeObjectURL(url)
      currentAudio = null
    }
    console.log('[tts] calling audio.play()...')
    await audio.play()
    console.log('[tts] audio.play() succeeded')
  } catch (e: any) {
    playingMode.value = null
    console.error('[tts] error:', e)
    ElMessage.warning('讯飞 TTS 失败: ' + e)
  }
}

async function handleStart() {
  const { appId, apiKey, apiSecret } = xfConfig.value
  if (!appId || !apiKey || !apiSecret) {
    ElMessage.warning('请先在设置页面填写讯飞语音评测的 App ID、API Key 和 API Secret')
    return
  }
  stopPlayback()
  errorMsg.value = ''
  evalResult.value = null
  try {
    await invoke('start_recording')
    recording.value = true
  } catch (e: any) {
    errorMsg.value = e.toString()
    ElMessage.error('启动录音失败: ' + e)
  }
}

async function handleStop() {
  recording.value = false
  loading.value = true
  errorMsg.value = ''
  try {
    const result = await invoke<EvalResultData>('stop_recording_and_evaluate', {
      lang: 'sp',
      category: 'sent',
      refText: sentence.value.sentence_original,
      appId: xfConfig.value.appId,
      apiKey: xfConfig.value.apiKey,
      apiSecret: xfConfig.value.apiSecret,
    })
    evalResult.value = result
  } catch (e: any) {
    errorMsg.value = e.toString()
    ElMessage.error('评测失败: ' + e)
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div class="daily-sentence-page">
    <!-- Header -->
    <div class="page-header">
      <div class="page-title">每日一句</div>
      <div class="page-nav">
        <button class="nav-btn" :disabled="!canPrev" @click="prev">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
            <polyline points="15 18 9 12 15 6" />
          </svg>
        </button>
        <span class="page-progress">{{ shownCount }}/{{ total }}</span>
        <button class="nav-btn" :disabled="!canNext" @click="next">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
            <polyline points="9 6 15 12 9 18" />
          </svg>
        </button>
      </div>
    </div>

    <div class="page-body">
      <!-- Sentence card -->
      <div class="sentence-card">
        <div class="sentence-date">{{ sentence.date.replace('.', ' ') }}</div>
        <div class="sentence-original">{{ sentence.sentence_original }}</div>
        <div class="sentence-translation">{{ sentence.sentence_translation }}</div>

        <!-- Action bar -->
        <div class="action-bar">
          <button class="action-item" :class="{ active: playingMode === 'normal' }" @click="play('normal')">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
              <polygon points="11,5 6,9 2,9 2,15 6,15 11,19 11,5" />
              <path d="M15.54 8.46a5 5 0 0 1 0 7.07" />
              <path d="M19.07 4.93a10 10 0 0 1 0 14.14" />
            </svg>
            <span>常速</span>
          </button>

          <div class="action-divider" />

          <button class="action-item" :class="{ active: playingMode === 'slow' }" @click="play('slow')">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
              <polygon points="11,5 6,9 2,9 2,15 6,15 11,19 11,5" />
              <path d="M15.54 8.46a5 5 0 0 1 0 7.07" />
            </svg>
            <span>慢速</span>
          </button>

          <div class="action-divider" />

          <button class="action-item follow" :class="{ recording }" @click="recording ? handleStop() : handleStart()" :disabled="loading">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
              <path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z" />
              <path d="M19 10v2a7 7 0 0 1-14 0v-2" />
              <line x1="12" y1="19" x2="12" y2="23" />
              <line x1="8" y1="23" x2="16" y2="23" />
            </svg>
            <span>{{ loading ? '评测中' : recording ? '停止' : '跟读' }}</span>
          </button>
        </div>
      </div>

      <!-- Error message -->
      <div v-if="errorMsg" class="error-msg">{{ errorMsg }}</div>

      <!-- Word analysis -->
      <div v-if="sentence.analysis && sentence.analysis.length" class="analysis-card">
        <div class="analysis-title">解析：</div>
        <div v-for="item in sentence.analysis" :key="item.word" class="analysis-item">
          <div class="analysis-word-line">
            <span class="analysis-word">{{ item.word }}</span>
            <span class="analysis-pos">{{ item.pos }}</span>
            <span class="analysis-def">{{ item.definition }}</span>
          </div>
          <div class="analysis-example">{{ item.example }}</div>
          <div class="analysis-example-trans">{{ item.example_translation }}</div>
        </div>
      </div>

      <!-- Eval result -->
      <EvalResult :result="evalResult" />
    </div>
  </div>
</template>

<style scoped>
.daily-sentence-page {
  height: 100%;
  display: flex;
  flex-direction: column;
  background: #fafafa;
}

.page-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 14px 16px;
  background: white;
  border-bottom: 1px solid #ebeef5;
}

.page-title {
  font-size: 22px;
  font-weight: 700;
  color: #333;
}

.page-nav {
  display: flex;
  align-items: center;
  gap: 8px;
}

.nav-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 28px;
  height: 28px;
  border: 1px solid #e0e0e0;
  border-radius: 6px;
  background: #fff;
  color: #666;
  cursor: pointer;
  padding: 0;
  transition: background 0.15s, color 0.15s;
}

.nav-btn:hover:not(:disabled) {
  background: #f5f5f5;
  color: #333;
}

.nav-btn:disabled {
  opacity: 0.35;
  cursor: not-allowed;
}

.page-progress {
  font-size: 12px;
  color: #999;
  min-width: 36px;
  text-align: center;
}

.page-body {
  flex: 1;
  overflow-y: auto;
  padding: 16px;
}

.sentence-card {
  background: white;
  border-radius: 12px;
  padding: 20px;
  box-shadow: 0 2px 12px rgba(0, 0, 0, 0.06);
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.sentence-date {
  font-size: 13px;
  font-weight: 600;
  color: #e05a4b;
}

.sentence-original {
  font-size: 18px;
  font-weight: 400;
  color: #1a1a1a;
  line-height: 1.6;
}

.sentence-translation {
  font-size: 14px;
  color: #999;
  line-height: 1.6;
}

/* Action bar */
.action-bar {
  display: flex;
  align-items: center;
  border-top: 1px solid #f0f0f0;
  padding-top: 14px;
  margin-top: 2px;
}

.action-item {
  flex: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 5px;
  background: none;
  border: none;
  cursor: pointer;
  color: #999;
  font-size: 14px;
  padding: 4px 0;
  transition: color 0.15s;
}

.action-item:disabled {
  cursor: not-allowed;
  opacity: 0.5;
}

.action-item.active {
  color: #e05a4b;
}

.action-item.follow.recording {
  color: #e05a4b;
}

.action-divider {
  width: 1px;
  height: 18px;
  background: #ebebeb;
}

.error-msg {
  color: #f56c6c;
  font-size: 13px;
  text-align: center;
  padding: 8px;
  background: #fef0f0;
  border-radius: 4px;
  margin-top: 12px;
}

/* Analysis card */
.analysis-card {
  background: white;
  border-radius: 12px;
  padding: 16px 20px;
  box-shadow: 0 2px 12px rgba(0, 0, 0, 0.06);
  display: flex;
  flex-direction: column;
  gap: 14px;
  margin-top: 12px;
}

.analysis-title {
  font-size: 14px;
  font-weight: 600;
  color: #333;
}

.analysis-item {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.analysis-word-line {
  display: flex;
  align-items: baseline;
  gap: 6px;
  flex-wrap: wrap;
}

.analysis-word {
  font-size: 15px;
  font-weight: 600;
  color: #1a1a1a;
}

.analysis-pos {
  font-size: 12px;
  color: #999;
}

.analysis-def {
  font-size: 14px;
  color: #555;
}

.analysis-example {
  font-size: 14px;
  color: #e05a4b;
  font-style: italic;
  line-height: 1.5;
}

.analysis-example-trans {
  font-size: 13px;
  color: #999;
  line-height: 1.5;
}
</style>
