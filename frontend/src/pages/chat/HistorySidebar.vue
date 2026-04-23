<template>
  <div class="sidebar-overlay" v-if="visible" @click.self="$emit('close')">
    <transition name="slide">
      <div v-if="visible" class="sidebar-panel">
        <div class="sidebar-header">
          <span class="sidebar-title">历史会话</span>
          <button class="close-btn" @click="$emit('close')">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
              <line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
            </svg>
          </button>
        </div>
        <div class="session-list">
          <div v-for="session in sessions" :key="session.id" :class="['session-item', { active: session.id === currentActiveId }]" @click="$emit('select-session', session.id)">
            <div class="session-info">
              <div class="session-title">
                <span v-if="session.scenarioId" class="scenario-badge" title="情景对话">
                  <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                    <circle cx="12" cy="12" r="10"/><path d="M8 14s1.5 2 4 2 4-2 4-2"/><line x1="9" y1="9" x2="9.01" y2="9"/><line x1="15" y1="9" x2="15.01" y2="9"/>
                  </svg>
                </span>
                {{ session.title }}
              </div>
              <div class="session-date">{{ formatDate(session.updatedAt) }}</div>
            </div>
            <button class="delete-btn" @click.prevent.stop="handleDelete(session.id, $event)" title="删除" type="button">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
                <polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/>
              </svg>
            </button>
          </div>
          <div v-if="sessions.length === 0" class="empty-list">暂无历史会话</div>
        </div>
      </div>
    </transition>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue';
import { ElMessageBox } from 'element-plus';
import type { ChatSession } from '@/stores/chat';

const props = defineProps<{ visible: boolean; sessions: ChatSession[]; activeSessionId: string | null }>();
const emit = defineEmits<{ 'close': []; 'select-session': [id: string]; 'delete-session': [id: string] }>();

const currentActiveId = computed(() => props.activeSessionId || '');

function formatDate(timestamp: number): string {
  const d = new Date(timestamp);
  return `${d.getMonth() + 1}/${d.getDate()} ${d.getHours().toString().padStart(2, '0')}:${d.getMinutes().toString().padStart(2, '0')}`;
}

async function handleDelete(id: string, e: Event) {
  e.stopPropagation();
  e.preventDefault();
  try {
    await ElMessageBox.confirm('确定删除此会话？', '删除确认', {
      confirmButtonText: '删除',
      cancelButtonText: '取消',
      type: 'warning',
    });
    emit('delete-session', id);
  } catch {
    // User cancelled
  }
}
</script>

<style scoped>
.sidebar-overlay { position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0, 0, 0, 0.3); z-index: 100; }
.sidebar-panel { position: absolute; top: 0; left: 0; width: 70%; max-width: 320px; height: 100%; background: #fff; display: flex; flex-direction: column; box-shadow: 2px 0 8px rgba(0, 0, 0, 0.1); }
.slide-enter-active, .slide-leave-active { transition: transform 0.3s ease; }
.slide-enter-from, .slide-leave-to { transform: translateX(-100%); }
.sidebar-header { display: flex; align-items: center; justify-content: space-between; padding: 14px 16px; border-bottom: 1px solid #ebeef5; flex-shrink: 0; }
.sidebar-title { font-size: 17px; font-weight: 600; color: #1a1a1a; }
.close-btn { display: flex; align-items: center; justify-content: center; width: 32px; height: 32px; border: none; background: none; cursor: pointer; color: #999; border-radius: 8px; }
.close-btn:active { background: #f5f5f5; }
.session-list { flex: 1; overflow-y: auto; padding: 8px 0; }
.session-item { display: flex; align-items: center; padding: 12px 16px; cursor: pointer; transition: background 0.12s; border-bottom: 1px solid #f5f5f5; }
.session-item:active { background: #f9f9f9; }
.session-item.active { background: #f0f4ff; }
.session-info { flex: 1; min-width: 0; }
.session-title { font-size: 15px; color: #303133; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; display: flex; align-items: center; gap: 4px; }
.scenario-badge { display: inline-flex; align-items: center; color: #2B5CE6; flex-shrink: 0; }
.session-date { font-size: 12px; color: #999; margin-top: 2px; }
.delete-btn { display: flex; align-items: center; justify-content: center; width: 28px; height: 28px; border: none; background: none; cursor: pointer; color: #c0c4cc; border-radius: 4px; flex-shrink: 0; z-index: 1; }
.delete-btn:active { color: #f56c6c; background: #fef0f0; }
.empty-list { padding: 32px 16px; text-align: center; color: #999; font-size: 14px; }
</style>
