<template>
  <div class="message-list" ref="listRef">
    <div v-if="messages.length === 0" class="empty-guide">
      <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="#c0c4cc" stroke-width="1" stroke-linecap="round" stroke-linejoin="round">
        <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>
      </svg>
      <p class="guide-text">开始一段西班牙语对话吧</p>
      <button v-if="showScenarioEntry" class="scenario-entry-btn" @click="emit('open-scenarios')">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <circle cx="12" cy="12" r="10"/>
          <path d="M8 14s1.5 2 4 2 4-2 4-2"/>
          <line x1="9" y1="9" x2="9.01" y2="9"/>
          <line x1="15" y1="9" x2="15.01" y2="9"/>
        </svg>
        试试情景对话
      </button>
    </div>
    <template v-else>
      <!-- Scenario info card -->
      <div v-if="scenario" class="scenario-info-card">
        <div class="scenario-card-header">
          <span class="scenario-card-title">{{ scenario.title }}</span>
          <span :class="['scenario-difficulty', scenario.difficulty]">{{ difficultyLabels[scenario.difficulty] }}</span>
        </div>
        <div class="scenario-card-es">{{ scenario.titleEs }}</div>
        <div class="scenario-card-section">
          <div class="section-label">场景</div>
          <div class="section-text">{{ scenario.setting }}</div>
        </div>
        <div class="scenario-card-section">
          <div class="section-label">背景</div>
          <div class="section-text">{{ scenario.situation }}</div>
        </div>
        <div class="scenario-card-roles">
          <div class="role-row">
            <span class="role-label">你：</span>
            <span class="role-name">{{ scenario.userRole.name }}</span>
            <span class="role-desc">{{ scenario.userRole.title }}</span>
          </div>
          <div class="role-row">
            <span class="role-label">AI：</span>
            <span class="role-name">{{ scenario.aiRole.name }}</span>
            <span class="role-desc">{{ scenario.aiRole.title }}</span>
            <span v-if="scenario.aiRole.personality" class="role-personality">（{{ scenario.aiRole.personality }}）</span>
          </div>
        </div>
      </div>
      <MessageItem v-for="msg in messages" :key="msg.id" :message="msg" :is-playing="playingMessageId === msg.id" @play-tts="handlePlayTts" @play-voice="handlePlayVoice" />
    </template>
  </div>
</template>

<script setup lang="ts">
import { ref, watch, nextTick } from 'vue';
import MessageItem from './MessageItem.vue';
import type { Message } from '@/stores/chat';
import type { Scenario } from './data/scenarios';
import { difficultyLabels } from './data/scenarios';

const props = defineProps<{
  messages: Message[];
  playingMessageId: string | null;
  showScenarioEntry: boolean;
  scenario?: Scenario;
}>();

const emit = defineEmits<{ 'play-tts': [message: Message]; 'play-voice': [message: Message]; 'open-scenarios': [] }>();
const listRef = ref<HTMLElement | null>(null);

function scrollToBottom() {
  nextTick(() => { if (listRef.value) { listRef.value.scrollTop = listRef.value.scrollHeight; } });
}

function handlePlayTts(msg: Message) { emit('play-tts', msg); }
function handlePlayVoice(msg: Message) { emit('play-voice', msg); }

watch(() => props.messages.length, () => scrollToBottom());
watch(() => { const last = props.messages[props.messages.length - 1]; return last?.content?.length || 0; }, () => scrollToBottom());

defineExpose({ scrollToBottom });
</script>

<style scoped>
.message-list {
  flex: 1;
  min-height: 0;
  overflow-y: auto;
  overflow-x: hidden;
  padding: 16px 16px calc(8px + 72px + var(--safe-area-inset-bottom));
  background: var(--app-page-bg);
  -webkit-overflow-scrolling: touch;
  touch-action: pan-y;
}
.message-list::-webkit-scrollbar { width: 4px; }
.message-list::-webkit-scrollbar-track { background: transparent; }
.message-list::-webkit-scrollbar-thumb { background: #ddd; border-radius: 2px; }
.empty-guide {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  height: 100%;
  gap: 16px;
}

.guide-text {
  font-size: 15px;
  color: var(--app-text-color);
  opacity: 0.7;
}

.scenario-entry-btn {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 8px 20px;
  border: 1px solid var(--app-primary-color);
  border-radius: 20px;
  background: var(--app-card-bg);
  color: var(--app-primary-color);
  font-size: 14px;
  cursor: pointer;
  transition: all 0.15s;
}

.scenario-entry-btn:active {
  background: var(--app-primary-color);
  color: #fff;
}

/* Scenario info card */
.scenario-info-card {
  background: var(--app-card-bg);
  border-radius: 12px;
  padding: 14px;
  margin-bottom: 12px;
  box-shadow: 0 1px 4px rgba(0,0,0,0.06);
  border-left: 3px solid var(--app-primary-color);
}

.scenario-card-title {
  font-size: 16px;
  font-weight: 600;
  color: var(--app-title-color);
}

.scenario-card-es {
  font-size: 13px;
  color: var(--app-text-color);
  opacity: 0.7;
  font-style: italic;
  margin-bottom: 10px;
}

.section-label {
  font-size: 12px;
  color: var(--app-text-color);
  opacity: 0.7;
  margin-bottom: 2px;
  font-weight: 500;
}

.section-text {
  font-size: 13px;
  color: var(--app-text-color);
  line-height: 1.6;
}

.role-label {
  color: var(--app-text-color);
  opacity: 0.7;
  flex-shrink: 0;
}

.role-name {
  font-weight: 500;
  color: var(--app-text-color);
}

.role-desc {
  color: var(--app-text-color);
  opacity: 0.7;
  font-size: 12px;
}

.role-personality {
  color: var(--app-text-color);
  opacity: 0.55;
  font-size: 11px;
}
</style>
