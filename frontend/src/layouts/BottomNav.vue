<template>
  <nav class="bottom-nav" v-if="$route.name !== 'Detail'">
    <router-link
      to="/"
      class="nav-item"
      :class="{ active: $route.name === 'Home' }"
    >
      <svg class="nav-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
        <path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>
        <polyline points="9 22 9 12 15 12 15 22"/>
      </svg>
      <span class="nav-text">首页</span>
    </router-link>

    <router-link
      to="/dictionary"
      class="nav-item"
      :class="{ active: $route.name === 'Dictionary' }"
    >
      <svg class="nav-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
        <path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/>
        <path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/>
      </svg>
      <span class="nav-text">翻译</span>
    </router-link>

    <router-link
      to="/speech-eval"
      class="nav-item"
      :class="{ active: $route.name === 'SpeechEval' }"
    >
      <svg class="nav-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
        <path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/>
        <path d="M19 10v2a7 7 0 0 1-14 0v-2"/>
        <line x1="12" y1="19" x2="12" y2="23"/>
        <line x1="8" y1="23" x2="16" y2="23"/>
      </svg>
      <span class="nav-text">词典</span>
    </router-link>

    <router-link
      to="/chat"
      class="nav-item"
      :class="{ active: $route.name === 'Chat' }"
    >
      <svg class="nav-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
        <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>
      </svg>
      <span class="nav-text">对话</span>
    </router-link>

    <router-link
      to="/settings"
      class="nav-item"
      :class="{ active: $route.name === 'Settings' }"
    >
      <svg class="nav-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
        <circle cx="12" cy="12" r="3"/>
        <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1 0 2.83 2 2 0 0 1-2.83 0l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-2 2 2 2 0 0 1-2-2v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83 0 2 2 0 0 1 0-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1-2-2 2 2 0 0 1 2-2h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 0-2.83 2 2 0 0 1 2.83 0l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 2-2 2 2 0 0 1 2 2v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 0 2 2 0 0 1 0 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 2 2 2 2 0 0 1-2 2h-.09a1.65 1.65 0 0 0-1.51 1z"/>
      </svg>
      <span class="nav-text">设置</span>
    </router-link>
  </nav>
</template>
<script setup lang="ts">
// 使用路由导航，不再需要props和emit
</script>


<style scoped>
.bottom-nav {
  position: fixed;
  bottom: 0;
  left: 0;
  right: 0;
  background: var(--app-nav-bg);
  border-top: 0.5px solid var(--app-border-color);
  display: flex;
  padding: 8px 0;
  padding-bottom: calc(8px + var(--safe-area-inset-bottom));
}

.nav-item {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 0.5rem;
  cursor: pointer;
  transition: all 0.2s ease;
  border-radius: 8px;
  margin: 0 0.25rem;
  text-decoration: none;
}

.nav-item:hover {
  background-color: var(--app-page-bg);
}

.nav-icon {
  width: 24px;
  height: 24px;
  margin-bottom: 4px;
  color: var(--app-nav-inactive-color);
  transition: color 0.2s ease;
}

.nav-item.active .nav-icon {
  color: var(--app-nav-active-color);
}

.nav-text {
  font-size: 0.8rem;
  color: var(--app-nav-inactive-color);
  transition: color 0.2s ease;
}

.nav-item.active .nav-text {
  color: var(--app-nav-active-color);
}

@media (max-width: 768px) {
  .bottom-nav {
    padding-top: 0.25rem;
  }

  .nav-item {
    padding-top: 0.25rem;
  }

  .nav-icon {
    width: 22px;
    height: 22px;
  }

  .nav-text {
    font-size: 0.7rem;
  }
}
</style>