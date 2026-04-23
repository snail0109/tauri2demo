<template>
  <div :class="['message-item', message.role === 'user' ? 'message-user' : 'message-assistant']">
    <div :class="['message-bubble', message.role === 'user' ? 'bubble-user' : 'bubble-assistant']" @click="handleBubbleClick">
      <span v-if="message.isVoice" class="voice-icon">
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/>
          <path d="M19 10v2a7 7 0 0 1-14 0v-2"/>
        </svg>
      </span>
      <span class="message-text">{{ message.content }}</span>
    </div>
    <button v-if="message.role === 'assistant'" :class="['tts-btn', { 'tts-playing': isPlaying }]" @click="$emit('play-tts', message)" :title="isPlaying ? '停止朗读' : '朗读'">
      <svg v-if="!isPlaying" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
        <polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"/>
        <path d="M19.07 4.93a10 10 0 0 1 0 14.14"/>
        <path d="M15.54 8.46a5 5 0 0 1 0 7.07"/>
      </svg>
      <svg v-else width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
        <polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"/>
        <rect x="17" y="9" width="4" height="6"/>
      </svg>
    </button>
  </div>
</template>

<script setup lang="ts">
import type { Message } from '@/stores/chat';

const props = defineProps<{ message: Message; isPlaying: boolean }>();

const emit = defineEmits<{
  'play-tts': [message: Message];
  'play-voice': [message: Message];
}>();

function handleBubbleClick() {
  // Click on voice user message to play the original audio
  if (props.message.role === 'user' && props.message.isVoice && props.message.audioPath) {
    emit('play-voice', props.message);
  }
}
</script>

<style scoped>
.message-item {
  display: flex;
  align-items: flex-end;
  gap: 4px;
  margin-bottom: 12px;
}

.message-user {
  justify-content: flex-end;
}

.message-assistant {
  justify-content: flex-start;
}

.message-bubble {
  max-width: 75%;
  padding: 10px 14px;
  font-size: 15px;
  line-height: 1.5;
  word-break: break-word;
}

.bubble-user {
  background: var(--app-primary-color);
  color: #fff;
  border-radius: 12px 12px 4px 12px;
}

.bubble-user:has(.voice-icon) {
  cursor: pointer;
}

.bubble-assistant {
  background: var(--app-card-bg);
  color: var(--app-text-color);
  border-radius: 12px 12px 12px 4px;
  box-shadow: 0 1px 4px rgba(0, 0, 0, 0.06);
  border: 1px solid var(--app-border-color);
}

.voice-icon {
  display: inline-flex;
  align-items: center;
  margin-right: 4px;
  opacity: 0.7;
}

.tts-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 28px;
  height: 28px;
  border: none;
  background: none;
  cursor: pointer;
  color: var(--app-text-color);
  opacity: 0.7;
  border-radius: 50%;
  flex-shrink: 0;
  transition: color 0.2s, background 0.2s, opacity 0.2s;
}

.tts-btn:active {
  color: var(--app-primary-color);
  background: rgba(0, 0, 0, 0.04);
}

.tts-playing {
  color: var(--app-primary-color);
  opacity: 1;
  animation: pulse 1s ease-in-out infinite;
}

@keyframes pulse {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.5; }
}

.message-text {
  white-space: pre-wrap;
}
</style>
