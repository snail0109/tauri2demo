<template>
  <div class="chat-header">
    <button class="header-btn" @click="$emit('toggle-history')" title="历史会话">
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
        <circle cx="12" cy="12" r="10"/>
        <polyline points="12 6 12 12 16 14"/>
      </svg>
    </button>
    <span class="header-title">{{ title }}</span>
    <div class="header-right">
      <button class="header-btn" @click="$emit('open-scenarios')" title="情景对话">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
          <circle cx="12" cy="12" r="10"/>
          <path d="M8 14s1.5 2 4 2 4-2 4-2"/>
          <line x1="9" y1="9" x2="9.01" y2="9"/>
          <line x1="15" y1="9" x2="15.01" y2="9"/>
        </svg>
      </button>
      <button v-if="isScenario" class="header-btn" @click="$emit('open-reference')" title="参考对话">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
          <path d="M2 3h6a4 4 0 0 1 4 4v14a3 3 0 0 0-3-3H2z"/>
          <path d="M22 3h-6a4 4 0 0 0-4 4v14a3 3 0 0 1 3-3h7z"/>
        </svg>
      </button>
      <button v-else class="header-btn" @click="$emit('new-session')" title="新建对话">
        <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
          <line x1="12" y1="5" x2="12" y2="19"/>
          <line x1="5" y1="12" x2="19" y2="12"/>
        </svg>
      </button>
      <button class="header-btn" @click="$emit('open-summary')" title="总结评测">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
          <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/>
          <polyline points="14 2 14 8 20 8"/>
          <line x1="16" y1="13" x2="8" y2="13"/>
          <line x1="16" y1="17" x2="8" y2="17"/>
          <polyline points="10 9 9 9 8 9"/>
        </svg>
      </button>
    </div>
  </div>
</template>

<script setup lang="ts">
defineProps<{
  title: string;
  isScenario: boolean;
}>();

defineEmits<{
  'toggle-history': [];
  'new-session': [];
  'open-summary': [];
  'open-scenarios': [];
  'open-reference': [];
}>();
</script>

<style scoped>
.chat-header { display: flex; align-items: center; justify-content: space-between; padding: 14px 16px; background: #fff; border-bottom: 1px solid #ebeef5; flex-shrink: 0; }
.header-title { font-size: 17px; font-weight: 600; color: #1a1a1a; flex: 1; text-align: center; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.header-right { display: flex; align-items: center; gap: 4px; }
.header-btn { display: flex; align-items: center; justify-content: center; width: 36px; height: 36px; border: none; background: none; cursor: pointer; color: #555; border-radius: 8px; transition: background 0.12s; }
.header-btn:active { background: #f5f5f5; }
</style>
