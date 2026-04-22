<template>
  <div class="input-area" :class="{ 'recording-bg': recordingState === 'recording', 'cancel-bg': recordingState === 'cancel' }">
    <template v-if="mode === 'text'">
      <div class="input-wrapper">
        <textarea ref="textareaRef" v-model="inputText" class="chat-input" :placeholder="placeholder" rows="1" @input="autoResize" @keydown="handleKeydown"></textarea>
        <button v-if="inputText.trim()" class="input-action-btn send-btn" @click="sendText" title="发送">
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <line x1="22" y1="2" x2="11" y2="13"/><polygon points="22 2 15 22 11 13 2 9 22 2"/>
          </svg>
        </button>
        <button v-else class="input-action-btn voice-toggle-btn" @click="mode = 'voice'" title="语音输入">
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/><line x1="12" y1="19" x2="12" y2="23"/><line x1="8" y1="23" x2="16" y2="23"/>
          </svg>
        </button>
      </div>
    </template>
    <template v-else>
      <VoiceButton @switch-to-text="mode = 'text'" @start-recording="$emit('start-recording')" @send-recording="$emit('send-recording')" @cancel-recording="$emit('cancel-recording')" @recording-state-change="(s) => recordingState = s" />
    </template>
  </div>
</template>

<script setup lang="ts">
import { ref, nextTick } from 'vue';
import VoiceButton from './VoiceButton.vue';

const emit = defineEmits<{
  'send-text': [text: string];
  'start-recording': [];
  'send-recording': [];
  'cancel-recording': [];
}>();

const placeholder = '发消息';

const mode = ref<'text' | 'voice'>('text');
const inputText = ref('');
const textareaRef = ref<HTMLTextAreaElement | null>(null);
const recordingState = ref<'idle' | 'recording' | 'cancel'>('idle');

function autoResize() {
  const el = textareaRef.value; if (!el) return;
  el.style.height = 'auto';
  el.style.height = Math.min(el.scrollHeight, 70) + 'px';
}
function handleKeydown(e: KeyboardEvent) { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); sendText(); } }
function sendText() {
  const text = inputText.value.trim(); if (!text) return;
  emit('send-text', text);
  inputText.value = '';
  nextTick(() => { if (textareaRef.value) textareaRef.value.style.height = 'auto'; });
}

defineExpose({ mode, switchToVoice: () => { mode.value = 'voice'; }, switchToText: () => { mode.value = 'text'; } });
</script>

<style scoped>
.input-area {
  padding: 8px 16px 12px;
  background: #fff;
  border-top: 1px solid #ebeef5;
  flex-shrink: 0;
  transition: background 0.35s ease;
}

.input-area.recording-bg {
  background: radial-gradient(ellipse at 50% 120%, #2B9EFF 0%, #90CEFF 35%, #d4eeff 65%, #ffffff 100%);
}

.input-area.cancel-bg {
  background: radial-gradient(ellipse at 50% 120%, #FF8080 0%, #FFB0B0 35%, #FFE0E0 65%, #ffffff 100%);
}
.input-wrapper { display: flex; align-items: flex-end; background: #f5f5f5; border-radius: 24px; padding: 4px 4px 4px 16px; border: 1px solid #dcdfe6; }
.chat-input { flex: 1; border: none; outline: none; background: transparent; font-size: 15px; line-height: 20px; resize: none; padding: 8px 0; max-height: 70px; font-family: inherit; color: #1a1a1a; }
.chat-input::placeholder { color: #999; }
.input-action-btn { display: flex; align-items: center; justify-content: center; width: 36px; height: 36px; border: none; border-radius: 50%; cursor: pointer; flex-shrink: 0; transition: background 0.2s; }
.send-btn { background: #2B5CE6; color: #fff; }
.send-btn:active { background: #1e47c7; }
.voice-toggle-btn { background: transparent; color: #666; }
.voice-toggle-btn:active { background: #e8e8e8; }
</style>
