<template>
  <div class="voice-area">
    <div class="voice-container">
      <!-- Hint text shown during recording -->
      <transition name="hint-fade">
        <div v-if="isPressed" class="recording-hint" :class="{ 'hint-cancel': isInCancelZone }">
          <div class="hint-icon-wrap">
            <svg v-if="!isInCancelZone" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
              <line x1="12" y1="19" x2="12" y2="5"/><polyline points="5 12 12 5 19 12"/>
            </svg>
            <svg v-else width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
              <circle cx="12" cy="12" r="10"/><line x1="15" y1="9" x2="9" y2="15"/><line x1="9" y1="9" x2="15" y2="15"/>
            </svg>
          </div>
          <span class="hint-text">{{ isInCancelZone ? '松手取消' : '上移取消' }}</span>
        </div>
      </transition>

      <div class="voice-btn-wrapper" ref="btnRef">
        <button
          class="voice-btn"
          :class="{ 'voice-active': isPressed && !isInCancelZone, 'voice-cancel': isInCancelZone }"
          @touchstart.prevent="onTouchStart"
          @touchmove.prevent="onTouchMove"
          @touchend.prevent="onTouchEnd"
          @mousedown.prevent="onMouseDown"
          @mouseup.prevent="onMouseUp"
          @mouseleave.prevent="onMouseLeave"
        >
          <div v-if="isPressed && !isInCancelZone && !partialText" class="sound-wave">
            <span v-for="i in 5" :key="i" class="wave-bar" :style="{ animationDelay: `${i * 0.1}s` }"></span>
          </div>
          <span v-else-if="isInCancelZone" class="cancel-text">松开取消</span>
          <span v-else-if="isPressed && partialText" class="partial-text">{{ partialText }}</span>
          <span v-else>按住说话</span>
        </button>
      </div>
    </div>
    <button class="mode-toggle" @click="$emit('switch-to-text')" title="切换到文本输入">
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
        <rect x="2" y="4" width="20" height="16" rx="2"/>
        <line x1="6" y1="10" x2="18" y2="10"/>
        <line x1="6" y1="14" x2="14" y2="14"/>
      </svg>
    </button>
  </div>
</template>

<script setup lang="ts">
import { ref, watch, onUnmounted } from 'vue';
import { listen, type UnlistenFn } from '@tauri-apps/api/event';

const emit = defineEmits<{
  'switch-to-text': [];
  'start-recording': [];
  'send-recording': [];
  'cancel-recording': [];
  'recording-state-change': [state: 'idle' | 'recording' | 'cancel'];
}>();

const isPressed = ref(false);
const isInCancelZone = ref(false);
const btnRef = ref<HTMLElement | null>(null);
const partialText = ref('');
let unlisten: UnlistenFn | null = null;

// Emit state changes when cancel zone changes
watch(isInCancelZone, (val) => {
  if (isPressed.value) {
    emit('recording-state-change', val ? 'cancel' : 'recording');
  }
});

// Cancel zone: finger moved > 80px above the button's top edge
function isInCancelArea(touchY: number): boolean {
  const btn = btnRef.value?.querySelector('.voice-btn');
  if (!btn) return false;
  const rect = btn.getBoundingClientRect();
  return rect.top - touchY > 80;
}

async function startListening() {
  partialText.value = '';
  try {
    unlisten = await listen<{ text: string; is_final: boolean }>('asr-partial', (event) => {
      if (event.payload.text) {
        partialText.value = event.payload.text;
      }
    });
  } catch (e) {
    console.warn('Failed to listen for asr-partial events:', e);
  }
}

function stopListening() {
  if (unlisten) {
    unlisten();
    unlisten = null;
  }
  partialText.value = '';
}

function onTouchStart(_e: TouchEvent) {
  isPressed.value = true;
  isInCancelZone.value = false;
  emit('start-recording');
  emit('recording-state-change', 'recording');
  startListening();
}

function onTouchMove(e: TouchEvent) {
  if (!isPressed.value) return;
  const touch = e.touches[0];
  isInCancelZone.value = isInCancelArea(touch.clientY);
}

function onTouchEnd(_e: TouchEvent) {
  if (!isPressed.value) return;
  const wasCancelling = isInCancelZone.value;
  isPressed.value = false;
  isInCancelZone.value = false;
  stopListening();
  emit('recording-state-change', 'idle');
  if (wasCancelling) {
    emit('cancel-recording');
  } else {
    emit('send-recording');
  }
}

function onMouseDown() {
  isPressed.value = true;
  isInCancelZone.value = false;
  emit('start-recording');
  emit('recording-state-change', 'recording');
  startListening();
}

function onMouseUp() {
  if (!isPressed.value) return;
  isPressed.value = false;
  stopListening();
  isInCancelZone.value = false;
  emit('recording-state-change', 'idle');
  emit('send-recording');
}

function onMouseLeave() {
  if (!isPressed.value) return;
  isPressed.value = false;
  stopListening();
  isInCancelZone.value = false;
  emit('recording-state-change', 'idle');
  emit('cancel-recording');
}

onUnmounted(() => {
  stopListening();
});
</script>

<style scoped>
.voice-area {
  display: flex;
  align-items: center;
  gap: 12px;
  width: 100%;
}

.voice-container {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 6px;
}

/* Recording hint above button */
.recording-hint {
  display: flex;
  align-items: center;
  gap: 6px;
  color: #4A9EFF;
  font-size: 13px;
  font-weight: 500;
  transition: color 0.2s;
  height: 24px;
}

.recording-hint.hint-cancel {
  color: #f56c6c;
}

.hint-icon-wrap {
  display: flex;
  align-items: center;
  justify-content: center;
}

.hint-text {
  letter-spacing: 0.5px;
}

.hint-fade-enter-active, .hint-fade-leave-active {
  transition: opacity 0.2s, transform 0.2s;
}

.hint-fade-enter-from, .hint-fade-leave-to {
  opacity: 0;
  transform: translateY(4px);
}

.voice-btn-wrapper {
  position: relative;
  width: 100%;
}

.voice-btn {
  width: 100%;
  height: 44px;
  border: none;
  background: #f5f5f5;
  border-radius: 22px;
  font-size: 15px;
  color: #333;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: all 0.2s;
  user-select: none;
  -webkit-user-select: none;
}

.voice-active {
  background: rgba(255, 255, 255, 0.6);
  transform: scale(1.02);
  box-shadow: 0 2px 12px rgba(74, 158, 255, 0.2);
}

.voice-cancel {
  background: rgba(255, 255, 255, 0.6);
  color: #f56c6c;
  transform: scale(0.98);
  box-shadow: 0 2px 12px rgba(245, 108, 108, 0.2);
}

.cancel-text {
  font-size: 14px;
  color: #f56c6c;
}

.partial-text {
  font-size: 13px;
  color: #333;
  max-width: 100%;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  padding: 0 12px;
}

.sound-wave {
  display: flex;
  align-items: center;
  gap: 3px;
  height: 24px;
}

.wave-bar {
  width: 3px;
  height: 8px;
  background: #2B5CE6;
  border-radius: 2px;
  animation: wave 0.6s ease-in-out infinite;
}

@keyframes wave {
  0%, 100% { height: 8px; }
  50% { height: 20px; }
}

.mode-toggle {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 36px;
  height: 36px;
  border: none;
  background: none;
  cursor: pointer;
  color: #666;
  border-radius: 8px;
  flex-shrink: 0;
}

.mode-toggle:active {
  background: #f5f5f5;
}
</style>
