<template>
  <div class="chat-page">
    <ChatHeader
      :title="activeSession?.title || '对话'"
      :is-scenario="isScenario"
      @toggle-history="showHistory = true"
      @new-session="handleNewSession"
      @open-summary="handleOpenSummary"
      @open-scenarios="showScenarioBrowser = true"
      @open-reference="showReferenceDialogue = true"
    />
    <MessageList
      ref="messageListRef"
      :messages="activeSession?.messages || []"
      :playing-message-id="playingMessageId"
      :show-scenario-entry="true"
      :scenario="currentScenario"
      @play-tts="handlePlayTts"
      @play-voice="handlePlayVoice"
      @open-scenarios="showScenarioBrowser = true"
    />
    <InputArea
      ref="inputAreaRef"
      :input-language="inputLanguage"
      @send-text="handleSendText"
      @start-recording="handleStartRecording"
      @send-recording="handleSendRecording"
      @cancel-recording="handleCancelRecording"
      @change-language="handleChangeLanguage"
    />
    <HistorySidebar
      :visible="showHistory"
      :sessions="sortedSessions"
      :active-session-id="activeSessionId"
      @close="showHistory = false"
      @select-session="handleSelectSession"
      @delete-session="handleDeleteSession"
    />
    <ScenarioBrowser
      :visible="showScenarioBrowser"
      @close="showScenarioBrowser = false"
      @select-scenario="handleSelectScenario"
    />
    <ReferenceDialogue
      :visible="showReferenceDialogue"
      :scenario-id="activeSession?.scenarioId"
      @close="showReferenceDialogue = false"
    />
    <SummaryDialog
      :visible="showSummary"
      :session="activeSession"
      @close="showSummary = false"
    />
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted, onActivated } from 'vue';
import { storeToRefs } from 'pinia';
import { invoke } from '@tauri-apps/api/core';
import { ElMessage } from 'element-plus';
import { useChatStore } from '@/stores/chat';
import { useSettingsStore } from '@/stores/settings';
import { aiClientManager } from '@/services/aiClientManager';
import ChatHeader from './ChatHeader.vue';
import MessageList from './MessageList.vue';
import InputArea from './InputArea.vue';
import HistorySidebar from './HistorySidebar.vue';
import ScenarioBrowser from './ScenarioBrowser.vue';
import ReferenceDialogue from './ReferenceDialogue.vue';
import SummaryDialog from './SummaryDialog.vue';
import { scenarios } from './data/scenarios';
import type { Message } from '@/stores/chat';
import type { Scenario } from './data/scenarios';

defineOptions({ name: 'Chat' });

const chatStore = useChatStore();
const settingsStore = useSettingsStore();

const { activeSession, sortedSessions, activeSessionId } = storeToRefs(chatStore);

const messageListRef = ref<InstanceType<typeof MessageList> | null>(null);
const inputAreaRef = ref<InstanceType<typeof InputArea> | null>(null);
const showHistory = ref(false);
const showScenarioBrowser = ref(false);
const showReferenceDialogue = ref(false);
const showSummary = ref(false);
const isLoading = ref(false);
const currentAbortController = ref<AbortController | null>(null);
const playingMessageId = ref<string | null>(null);
const currentAudio = ref<HTMLAudioElement | null>(null);

const isScenario = computed(() => !!activeSession.value?.scenarioId);

const currentScenario = computed<Scenario | undefined>(() => {
  if (!activeSession.value?.scenarioId) return undefined;
  return scenarios.find(s => s.id === activeSession.value!.scenarioId);
});

// Input language for voice recognition
const inputLanguage = computed(() => {
  return activeSession.value?.inputLanguage || 'es';
});

onMounted(() => {
  chatStore.ensureActiveSession(settingsStore.settingsState.chatDefaultPrompt || '');
});

onActivated(() => {
  chatStore.ensureActiveSession(settingsStore.settingsState.chatDefaultPrompt || '');
});

// === Send text message ===
async function handleSendText(text: string) {
  if (isLoading.value) return;
  chatStore.addMessage('user', text);
  await requestAIReply();
}

// === Voice recording ===
async function handleStartRecording() {
  try {
    const { appId, apiKey, apiSecret } = settingsStore.settingsState.xfSpeechEval;
    const lang = inputLanguage.value;
    await invoke('start_recording', { appId, apiKey, apiSecret, lang });
  } catch (e) {
    ElMessage.error('录音启动失败');
    console.error(e);
  }
}

async function handleSendRecording() {
  if (isLoading.value) return;
  try {
    const result = await invoke<{ text: string; audio_path?: string }>('stop_realtime_asr');
    if (result.text) {
      chatStore.addMessage('user', result.text, true, result.audio_path);
      await requestAIReply();
    } else {
      ElMessage.warning('未识别到语音内容');
    }
  } catch (e) {
    ElMessage.error('语音识别失败');
    console.error(e);
  }
}

function handleCancelRecording() {
  try {
    invoke('cancel_recording').catch(() => {});
  } catch (_e) {
    // Ignore cancel errors
  }
}

// === Language change ===
function handleChangeLanguage(lang: string) {
  if (activeSession.value) {
    chatStore.updateInputLanguage(lang);
  }
}

// === AI reply ===
async function requestAIReply() {
  const session = chatStore.activeSession;
  if (!session) return;

  const modelInfo = settingsStore.settingsState.defaultModelInfo;
  if (!modelInfo) {
    ElMessage.warning('请先在设置中配置 AI 模型');
    return;
  }

  isLoading.value = true;
  currentAbortController.value = new AbortController();
  chatStore.addMessage('assistant', '');

  try {
    const historyMessages = session.messages
      .filter((_, idx) => idx < session.messages.length - 1)
      .map(m => ({ role: m.role as 'user' | 'assistant', content: m.content }));

    let fullText = '';

    await aiClientManager.chatStream({
      messages: historyMessages,
      currentModelInfo: modelInfo,
      systemPrompt: session.systemPrompt || undefined,
      onData: (chunk: string) => {
        fullText += chunk;
        chatStore.updateLastAssistantMessage(fullText);
      },
      abortController: currentAbortController.value,
    });
  } catch (e) {
    console.error('AI request failed:', e);
  } finally {
    isLoading.value = false;
    currentAbortController.value = null;
    chatStore.saveSessions();
  }
}

// === TTS playback ===
async function handlePlayTts(msg: Message) {
  if (playingMessageId.value === msg.id) { stopTts(); return; }
  stopTts();

  try {
    playingMessageId.value = msg.id;
    const { appId, apiKey, apiSecret } = settingsStore.settingsState.xfSpeechEval;
    const b64 = await invoke<string>('tts_synthesize', {
      text: msg.content, speed: 50, vcn: 'x4_yezi', appId, apiKey, apiSecret,
    });

    const binaryStr = atob(b64);
    const bytes = new Uint8Array(binaryStr.length);
    for (let i = 0; i < binaryStr.length; i++) bytes[i] = binaryStr.charCodeAt(i);
    const blob = new Blob([bytes], { type: 'audio/mp3' });
    const url = URL.createObjectURL(blob);
    const audio = new Audio(url);
    currentAudio.value = audio;

    audio.onended = () => { playingMessageId.value = null; currentAudio.value = null; URL.revokeObjectURL(url); };
    audio.onerror = () => { playingMessageId.value = null; currentAudio.value = null; URL.revokeObjectURL(url); ElMessage.error('播放失败'); };
    audio.play();
  } catch (e) {
    playingMessageId.value = null;
    ElMessage.error('语音合成失败');
    console.error(e);
  }
}

function stopTts() {
  if (currentAudio.value) { currentAudio.value.pause(); currentAudio.value = null; }
  playingMessageId.value = null;
}

// === Voice message playback ===
async function handlePlayVoice(msg: Message) {
  if (!msg.audioPath) {
    ElMessage.info('该语音消息无录音记录');
    return;
  }
  stopTts();
  try {
    playingMessageId.value = msg.id;
    const audio = new Audio(msg.audioPath);
    currentAudio.value = audio;
    audio.onended = () => { playingMessageId.value = null; currentAudio.value = null; };
    audio.onerror = () => { playingMessageId.value = null; currentAudio.value = null; ElMessage.error('播放录音失败'); };
    audio.play();
  } catch (e) {
    playingMessageId.value = null;
    ElMessage.error('播放录音失败');
    console.error(e);
  }
}

// === Session management ===
function handleNewSession() {
  chatStore.createSession(settingsStore.settingsState.chatDefaultPrompt || '');
  showHistory.value = false;
}
function handleSelectSession(id: string) { chatStore.switchSession(id); showHistory.value = false; }
function handleDeleteSession(id: string) { chatStore.deleteSession(id); chatStore.ensureActiveSession(settingsStore.settingsState.chatDefaultPrompt || ''); }

// === Scenario management ===
function handleSelectScenario(scenario: Scenario) {
  chatStore.createScenarioSession(scenario);
  showScenarioBrowser.value = false;
}

// === Summary ===
function handleOpenSummary() {
  showSummary.value = true;
}
</script>

<style scoped>
.chat-page {
  height: 100%;
  min-height: 0;
  display: flex;
  flex-direction: column;
  background: var(--app-page-bg);
  color: var(--app-text-color);
  overflow: hidden;
}
</style>
