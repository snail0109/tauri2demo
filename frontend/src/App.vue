<script setup lang="ts">
import { onMounted, watch } from 'vue'
import { useSettingsStore } from '@/stores/settings'

const settingsStore = useSettingsStore()

const applyTheme = () => {
  const theme = settingsStore.settingsState.theme
  const root = document.documentElement

  root.style.setProperty('--app-page-bg', theme.pageBg)
  root.style.setProperty('--app-header-bg', theme.headerBg)
  root.style.setProperty('--app-card-bg', theme.cardBg)
  root.style.setProperty('--app-title-color', theme.titleColor)
  root.style.setProperty('--app-text-color', theme.textColor)
  root.style.setProperty('--app-primary-color', theme.primaryColor)
  root.style.setProperty('--app-border-color', theme.borderColor)
  root.style.setProperty('--app-nav-bg', theme.navBg)
  root.style.setProperty('--app-nav-active-color', theme.navActiveColor)
  root.style.setProperty('--app-nav-inactive-color', theme.navInactiveColor)
}

onMounted(async () => {
  await settingsStore.loadSettings()
  applyTheme()
})

watch(
  () => settingsStore.settingsState.theme,
  () => {
    applyTheme()
  },
  { deep: true }
)
</script>

<template>
  <div class="app">
    <router-view />
  </div>
</template>

<style>
#app {
  touch-action: pan-y;
  overflow-x: hidden;
  width: 100%;
  background: var(--app-page-bg);
  color: var(--app-text-color);
}
</style>

<style scoped>
.app {
  height: 100vh;
  display: flex;
  flex-direction: column;
  background-color: var(--app-page-bg);
  overflow-x: hidden;
  width: 100%;
}
</style>

<style>

#app {
  /* 防止应用容器被拖拽 */
  touch-action: pan-y;
  overflow-x: hidden;
  width: 100%;
}
</style>

<style scoped>
.app {
  height: 100vh;
  display: flex;
  flex-direction: column;
  background-color: #f5f5f5;

  /* 防止内容溢出导致横向滚动 */
  overflow-x: hidden;
  width: 100%;
}

</style>