
<script setup lang="ts">
import BottomNav from './BottomNav.vue'
import { useSafeArea } from '@/utils/useSafeArea'
const { safeAreaTop, safeAreaBottom } = useSafeArea()
console.log(safeAreaTop.value, safeAreaBottom.value)

</script>

<template>
  <div class="default-layout">
    <!-- 主内容区域 -->
    <main class="main-content">
      <router-view v-slot="{ Component, route }">
        <keep-alive>
          <component :is="Component" v-if="route.meta.keepAlive" :key="route.name" />
        </keep-alive>
        <component :is="Component" v-if="!route.meta.keepAlive" :key="route.name" />
      </router-view>
    </main>
    
    <!-- 底部导航栏 -->
    <BottomNav />
  </div>
</template>

<style scoped>
.default-layout {
  height: 100%;
  min-height: 0;
  display: flex;
  flex-direction: column;
  background-color: #f5f5f5;
  /* 保留顶部安全区 */
  padding-top: var(--safe-area-inset-top);
  box-sizing: border-box; /* padding 计入高度内，不增加总高度 */
  overflow: hidden; /* 防止整个布局滚动 */
}

.main-content {
  flex: 1;
  min-height: 0;
  overflow: hidden;
  box-sizing: border-box;
  padding-bottom: calc(80px + var(--safe-area-inset-bottom)); /* 为底部导航栏+安全区留空间 */
}
</style>
