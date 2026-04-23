<script setup lang="ts">
import { ref } from "vue";
import { useRouter } from "vue-router";
import type { ListItem } from "../../types";
import { NEWS_LIST } from "./new";
import { useScrollRestoration } from "@/utils/useScrollRestoration";

// 定义组件名称，用于keep-alive
defineOptions({
  name: 'Home'
});

const router = useRouter();

// 保存滚动位置
const mainContentRef = ref<HTMLElement | null>(null);
useScrollRestoration({ selector: '.el-main' });

// 文章列表数据
// 加入月份维度，数据结构按月份分组
const listItemsByMonth = ref<Record<string, ListItem[]>>(NEWS_LIST);

const activeNames = ref<string[]>(['2026-04','2026-03','2025-12','2025-11', '2025-10', '2025-08', '2025-06', '2025-04', '2024-12', '2024-09']);

// 切换到详情页
function goToDetail(item: ListItem) {
  router.push({
    name: 'Detail',
    params: { id: item.id.toString() },
    query: { 
      title: item.title,
      description: item.description,
      url: item.url || '',
      publishTime: item.publishTime || ''
    }
  });
}


</script>

<template>
  <el-container class="home-page">
    <el-header class="home-header">
      <div class="page-title">行业动态</div>
    </el-header>
    
    <el-main class="main-content" ref="mainContentRef">
      <div class="list-container">
        <div v-for="month in Object.keys(listItemsByMonth)" :key="month">
          <el-collapse  v-model="activeNames">
            <el-collapse-item :title="month" :name="month">
              <div class="list">
                <div 
                  v-for="item in listItemsByMonth[month]" 
                  :key="item.id"
                  class="list-item"
                  @click="goToDetail(item)"
                >
                  <div class="item-title">{{ item.publishTime }} - {{ item.title }}</div>
                  <div class="item-description">{{ item.description }}</div>
                </div>
              </div>
            </el-collapse-item>
          </el-collapse>
        </div>
      </div>
    </el-main>
  </el-container>
</template>

<style scoped>
.home-page {
  height: 100%;
  min-height: 0;
  display: flex;
  flex-direction: column;
  overflow: hidden;
  background: var(--app-page-bg);
}

.home-header {
  display: flex;
  flex-direction: row;
  justify-content: space-between;
  align-items: center;
  flex-shrink: 0;
  padding: 20px 20px 0 20px;
  z-index: 10;
  background: var(--app-header-bg);
  border-bottom: 1px solid var(--app-border-color);
}

.main-content {
  flex: 1;
  min-height: 0;
  padding: 1rem;
  overflow-y: auto;
  background: var(--app-page-bg);
  -webkit-overflow-scrolling: touch;
}

/* 自定义滚动条样式 */
.main-content::-webkit-scrollbar {
  width: 8px;
}

.main-content::-webkit-scrollbar-track {
  background: var(--app-page-bg);
  border-radius: 4px;
}

.main-content::-webkit-scrollbar-thumb {
  background: var(--app-border-color);
  border-radius: 4px;
}

.main-content::-webkit-scrollbar-thumb:hover {
  background: var(--app-nav-inactive-color);
}

.list-container {
  background: var(--app-card-bg);
  border-radius: 12px;
  padding: 1.5rem;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.06);
  color: var(--app-text-color);
}

.list {
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
}

.list-item {
  padding: 1rem;
  background-color: var(--app-page-bg);
  border-radius: 8px;
  border: 1px solid var(--app-border-color);
  cursor: pointer;
  transition: all 0.2s ease;
}

.list-item:hover {
  background-color: var(--app-card-bg);
  transform: translateY(-1px);
  box-shadow: 0 2px 4px rgba(0, 0, 0, 0.08);
}

.item-title {
  font-weight: 600;
  color: var(--app-title-color);
  margin-bottom: 0.25rem;
}

.item-description {
  color: var(--app-text-color);
  font-size: 0.9rem;
}

/* Element Plus 折叠面板主题适配 */
:deep(.el-collapse) {
  border-top: 1px solid var(--app-border-color);
  border-bottom: 1px solid var(--app-border-color);
  background: transparent;
}

:deep(.el-collapse-item__header) {
  background: var(--app-card-bg);
  color: var(--app-title-color);
  border-bottom: 1px solid var(--app-border-color);
  font-weight: 600;
}

:deep(.el-collapse-item__wrap) {
  background: var(--app-card-bg);
  border-bottom: 1px solid var(--app-border-color);
}

:deep(.el-collapse-item__content) {
  background: var(--app-card-bg);
  color: var(--app-text-color);
  padding-bottom: 12px;
}

/* 移动端适配 */
@media (max-width: 600px) {
  .home-header {
    padding: 12px 16px 0 16px;
  }

  .page-title {
    font-size: 16px;
  }

  .main-content {
    padding: 0.75rem;
  }

  .list-container {
    padding: 1rem;
  }

  .list-item {
    padding: 0.75rem;
  }
}
</style>
