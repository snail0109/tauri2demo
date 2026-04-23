<!-- 系统设置页面 - 两级导航结构 -->
<script setup lang="ts">
import { computed, ref, watch, onMounted } from "vue";
import {
  ElInput,
  ElForm,
  ElFormItem,
  ElButton,
  ElMessage,
  ElSelect,
  ElOption,
  ElSwitch,
  ElColorPicker,
  FormRules,
} from "element-plus";
import { useSettingsStore } from "@/stores/settings";
import {
  VOLCENGINE_BASE_URL,
  OPENAI_BASE_URL,
  DEEPSEEK_BASE_URL,
} from "@/utils/constant";
import { isMobile } from "@/utils/os";
import { providers } from "@/utils/constant/providers";
import {
  setCachedModels,
  setCachedTestResult,
  getCachedModels,
  isCacheExpired,
  clearProviderCache,
} from "@/utils/localStorage";

defineOptions({ name: 'Settings' });

// 一级导航状态：null = 列表首页
type Section = null | 'model-services' | 'theme'
const currentSection = ref<Section>(null)

const sectionTitle: Record<Exclude<Section, null>, string> = {
  'model-services': '模型服务',
  'theme': '界面配色',
}


const settingsStore = useSettingsStore();
const settings = computed(() => settingsStore.settingsState);


const defaultTheme = {
  pageBg: '#f5f5f5',
  headerBg: '#ffffff',
  cardBg: '#ffffff',
  titleColor: '#1a1a1a',
  textColor: '#303133',
  primaryColor: '#2B5CE6',
  borderColor: '#ebeef5',
  navBg: '#ffffff',
  navActiveColor: '#2B5CE6',
  navInactiveColor: '#909399',
};

const applyThemeToDocument = (theme: typeof defaultTheme) => {
  document.documentElement.style.setProperty('--app-page-bg', theme.pageBg);
  document.documentElement.style.setProperty('--app-header-bg', theme.headerBg);
  document.documentElement.style.setProperty('--app-card-bg', theme.cardBg);
  document.documentElement.style.setProperty('--app-title-color', theme.titleColor);
  document.documentElement.style.setProperty('--app-text-color', theme.textColor);
  document.documentElement.style.setProperty('--app-primary-color', theme.primaryColor);
  document.documentElement.style.setProperty('--app-border-color', theme.borderColor);
  document.documentElement.style.setProperty('--app-nav-bg', theme.navBg);
  document.documentElement.style.setProperty('--app-nav-active-color', theme.navActiveColor);
  document.documentElement.style.setProperty('--app-nav-inactive-color', theme.navInactiveColor);
};

const themeFields = [
  { key: 'pageBg', label: '页面背景' },
  { key: 'headerBg', label: '顶部背景' },
  { key: 'cardBg', label: '卡片背景' },
  { key: 'titleColor', label: '标题颜色' },
  { key: 'textColor', label: '正文颜色' },
  { key: 'primaryColor', label: '主色' },
  { key: 'borderColor', label: '边框颜色' },
  { key: 'navBg', label: '导航背景' },
  { key: 'navActiveColor', label: '导航激活色' },
  { key: 'navInactiveColor', label: '导航未激活色' },
] as const;

const themePresets = [
  {
    name: '默认蓝',
    values: {
      ...defaultTheme,
    },
  },
  {
    name: '薄荷绿',
    values: {
      pageBg: '#f3fbf8',
      headerBg: '#e8f8f1',
      cardBg: '#eefbf5',
      titleColor: '#1f3b2f',
      textColor: '#355848',
      primaryColor: '#10b981',
      borderColor: '#cdeee0',
      navBg: '#eefbf5',
      navActiveColor: '#10b981',
      navInactiveColor: '#7a8a83',
    },
  },
  {
    name: '樱花粉',
    values: {
      pageBg: '#fff6fa',
      headerBg: '#ffeef5',
      cardBg: '#fff3f8',
      titleColor: '#3f2d38',
      textColor: '#5f4b57',
      primaryColor: '#ec4899',
      borderColor: '#f7cddd',
      navBg: '#fff3f8',
      navActiveColor: '#ec4899',
      navInactiveColor: '#9b8a93',
    },
  },
  {
    name: '深色灰',
    values: {
      pageBg: '#18181b',
      headerBg: '#27272a',
      cardBg: '#27272a',
      titleColor: '#fafafa',
      textColor: '#e4e4e7',
      primaryColor: '#60a5fa',
      borderColor: '#3f3f46',
      navBg: '#18181b',
      navActiveColor: '#60a5fa',
      navInactiveColor: '#a1a1aa',
    },
  },
]

const applyThemePreset = (values: typeof defaultTheme) => {
  Object.assign(settings.value.theme, values);
  applyThemeToDocument(settings.value.theme);
  document.documentElement.style.setProperty('--el-color-primary', values.primaryColor)
};

const resetTheme = () => {
  Object.assign(settings.value.theme, defaultTheme);
  applyThemeToDocument(settings.value.theme);
  document.documentElement.style.setProperty('--el-color-primary', defaultTheme.primaryColor)
};

const getAvailableModels = (providerId: string) => {
  const providerModels = providers[providerId].models;
  return Object.keys(providerModels).map((key) => ({ id: key, name: key }));
};

const customAvailableModels = ref([]);
const loadingModels = ref(false);

let saveTimeout: ReturnType<typeof setTimeout> | null = null;
const autoSave = () => {
  if (saveTimeout) clearTimeout(saveTimeout);
  saveTimeout = setTimeout(async () => {
    try {
      await settingsStore.saveSettings({
        providers: settings.value.providers,
        chatDefaultPrompt: settings.value.chatDefaultPrompt,
        theme: settings.value.theme,
      });
    } catch (error) {
      console.error("自动保存失败:", error);
    }
  }, 500);
};

watch(
  () => [
    settings.value.providers,
    settings.value.chatDefaultPrompt,
    settings.value.theme,
  ],
  () => { autoSave(); },
  { deep: true }
);

watch(
  () => settings.value.theme,
  (theme) => {
    applyThemeToDocument(theme as typeof defaultTheme);
  },
  { deep: true, immediate: true }
);

const queryModels = async (providerId: string, forceRefresh = false) => {
  const providerConfig = settings.value.providers[providerId];
  const baseURL = providerConfig.options.baseURL;
  const apiKey = providerConfig.options.apiKey;

  if (!baseURL || !apiKey) {
    ElMessage.warning("请先配置 API Base URL 和 API Key");
    return;
  }

  if (forceRefresh) {
    clearProviderCache(providerId);
  } else {
    const cachedModels = getCachedModels(providerId);
    if (cachedModels) {
      try {
        const modelCache = JSON.parse(cachedModels);
        if (modelCache && !isCacheExpired(modelCache.timestamp)) {
          const models = modelCache.models;
          customAvailableModels.value = models.sort((a: any, b: any) => a.id.localeCompare(b.id));
          settings.value.providers[providerId].models = models.reduce((acc: any, model: any) => {
            acc[model.id] = model;
            return acc;
          }, {});
          settings.value.providers[providerId].available = true;
          ElMessage.success(`从缓存加载了 ${models.length} 个可用模型`);
          return;
        }
      } catch (error) {
        console.warn(`加载 ${providerId} 模型缓存失败:`, error);
      }
    }
  }

  loadingModels.value = true;
  try {
    const response = await fetch(baseURL + `/models`, {
      method: "GET",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
      },
    });
    if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);

    const data = await response.json();
    if (data.data && Array.isArray(data.data)) {
      const models = data.data.sort((a: any, b: any) => a.id.localeCompare(b.id));
      customAvailableModels.value = models;
      settings.value.providers[providerId].models = models.reduce((acc: any, model: any) => {
        acc[model.id] = model;
        return acc;
      }, {});
      settings.value.providers[providerId].available = true;
      settingsStore.saveSettings({ providers: settings.value.providers });
      setCachedModels(providerId, models);
      setCachedTestResult(providerId, true);
      ElMessage.success(`成功获取 ${models.length} 个可用模型`);
    } else {
      throw new Error("Invalid response format");
    }
  } catch (error) {
    console.error("查询模型列表失败:", error);
    ElMessage.error("查询模型列表失败，请检查配置是否正确");
    customAvailableModels.value = [];
  } finally {
    loadingModels.value = false;
  }
};

const testProvider = async (providerId: string) => {
  const providerConfig = settings.value.providers[providerId];
  const baseURL = providerConfig.options.baseURL;
  const apiKey = providerConfig.options.apiKey;

  if (!baseURL || !apiKey) {
    ElMessage.warning("请先配置 API Base URL 和 API Key");
    return;
  }

  try {
    const response = await fetch(baseURL + `/chat/completions`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${apiKey}` },
      body: JSON.stringify({
        model: providerConfig.defaultModel,
        messages: [{ role: "user", content: "Hello, how are you?" }],
      }),
    });
    if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
    settings.value.providers[providerId].available = true;
    settingsStore.saveSettings({ providers: settings.value.providers });
    setCachedTestResult(providerId, true);
    ElMessage.success("测试成功");
  } catch (error) {
    settings.value.providers[providerId].available = false;
    setCachedTestResult(providerId, false);
    console.error(`${providerId} 测试失败:`, error);
    ElMessage.error("测试失败，请检查配置是否正确");
    throw error;
  }
};

onMounted(() => {
  const cachedModels = getCachedModels("openai-compatible");
  if (cachedModels) {
    const modelCache = JSON.parse(cachedModels);
    if (modelCache && !isCacheExpired(modelCache.timestamp)) {
      customAvailableModels.value = modelCache.models;
    }
  }
});
</script>

<template>
  <div class="settings-page">
    <!-- 顶部标题栏 -->
    <div class="settings-header">
      <button v-if="currentSection" class="back-btn" @click="currentSection = null">
        <svg width="10" height="16" viewBox="0 0 10 16" fill="none">
          <path d="M8 2L2 8L8 14" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
        </svg>
      </button>
      <span class="header-title">
        {{ currentSection ? sectionTitle[currentSection] : '设置' }}
      </span>
    </div>

    <!-- 一级菜单列表 -->
    <div v-if="!currentSection" class="settings-body">
      <div class="menu-group">
        <button class="menu-item" @click="currentSection = 'model-services'">
          <span class="menu-icon model-icon">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
              <circle cx="12" cy="12" r="3"/>
              <path d="M12 1v4M12 19v4M4.22 4.22l2.83 2.83M16.95 16.95l2.83 2.83M1 12h4M19 12h4M4.22 19.78l2.83-2.83M16.95 7.05l2.83-2.83"/>
            </svg>
          </span>
          <span class="menu-label">模型服务</span>
          <svg class="menu-chevron" width="7" height="12" viewBox="0 0 7 12" fill="none">
            <path d="M1 1L6 6L1 11" stroke="#C0C4CC" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
          </svg>
        </button>
        <button class="menu-item" @click="currentSection = 'theme'">
          <span class="menu-icon model-icon">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <circle cx="12" cy="12" r="3"/>
              <path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M4.93 19.07l1.41-1.41M17.66 6.34l1.41-1.41"/>
            </svg>
          </span>
          <span class="menu-label">界面配色</span>
          <svg class="menu-chevron" width="7" height="12" viewBox="0 0 7 12" fill="none">
            <path d="M1 1L6 6L1 11" stroke="#C0C4CC" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
          </svg>
        </button>
      </div>

    </div>

    <!-- 二级页面：模型服务 -->
    <div v-else-if="currentSection === 'model-services'" class="settings-body">
      <!-- 火山引擎 -->
      <div class="form-group">
        <div class="form-group-header">
          <span class="form-group-title">火山引擎（豆包）</span>
          <el-switch
            :style="{ '--el-switch-on-color': settings.providers.doubao.available ? '#13ce66' : '#ff4949' }"
            v-model="settings.providers.doubao.enabled"
          />
        </div>
        <template v-if="settings.providers.doubao.enabled">
          <div class="form-row">
            <label class="form-label">Base URL</label>
            <el-input v-model="settings.providers.doubao.options.baseURL" :placeholder="VOLCENGINE_BASE_URL" class="form-input" />
          </div>
          <div class="form-row">
            <label class="form-label">API Key</label>
            <el-input v-model="settings.providers.doubao.options.apiKey" placeholder="请输入 API Key" show-password class="form-input">
              <template #append><el-button @click="testProvider('doubao')">测试</el-button></template>
            </el-input>
          </div>
          <div class="form-row">
            <label class="form-label">模型</label>
            <el-select v-model="settings.providers.doubao.defaultModel" placeholder="请选择模型" style="width:100%">
              <el-option v-for="model in getAvailableModels('doubao')" :key="model.id" :label="model.name" :value="model.id" />
            </el-select>
          </div>
        </template>
      </div>

      <!-- DeepSeek -->
      <div class="form-group">
        <div class="form-group-header">
          <span class="form-group-title">DeepSeek</span>
          <el-switch
            :style="{ '--el-switch-on-color': settings.providers.deepseek.available ? '#13ce66' : '#ff4949' }"
            v-model="settings.providers.deepseek.enabled"
          />
        </div>
        <template v-if="settings.providers.deepseek.enabled">
          <div class="form-row">
            <label class="form-label">Base URL</label>
            <el-input v-model="settings.providers.deepseek.options.baseURL" :placeholder="DEEPSEEK_BASE_URL" class="form-input" />
          </div>
          <div class="form-row">
            <label class="form-label">API Key</label>
            <el-input v-model="settings.providers.deepseek.options.apiKey" placeholder="请输入 API Key" show-password class="form-input">
              <template #append><el-button @click="testProvider('deepseek')">测试</el-button></template>
            </el-input>
          </div>
          <div class="form-row">
            <label class="form-label">模型</label>
            <el-select v-model="settings.providers.deepseek.defaultModel" placeholder="请选择模型" style="width:100%">
              <el-option v-for="model in getAvailableModels('deepseek')" :key="model.id" :label="model.name" :value="model.id" />
            </el-select>
          </div>
        </template>
      </div>

      <!-- OpenAI 官方 -->
      <div class="form-group">
        <div class="form-group-header">
          <span class="form-group-title">OpenAI 官方</span>
          <el-switch
            :style="{ '--el-switch-on-color': settings.providers.openai.available ? '#13ce66' : '#ff4949' }"
            v-model="settings.providers.openai.enabled"
          />
        </div>
        <template v-if="settings.providers.openai.enabled">
          <div class="form-row">
            <label class="form-label">Base URL</label>
            <el-input v-model="settings.providers.openai.options.baseURL" :placeholder="OPENAI_BASE_URL" class="form-input" />
          </div>
          <div class="form-row">
            <label class="form-label">API Key</label>
            <el-input v-model="settings.providers.openai.options.apiKey" placeholder="请输入 API Key" show-password class="form-input">
              <template #append><el-button @click="testProvider('openai')">测试</el-button></template>
            </el-input>
          </div>
          <div class="form-row">
            <label class="form-label">模型</label>
            <el-select v-model="settings.providers.openai.defaultModel" placeholder="请选择模型" style="width:100%">
              <el-option v-for="model in getAvailableModels('openai')" :key="model.id" :label="model.name" :value="model.id" />
            </el-select>
          </div>
        </template>
      </div>

      <!-- 自定义 OpenAI 兼容 -->
      <div class="form-group">
        <div class="form-group-header">
          <span class="form-group-title">自定义 OpenAI 兼容</span>
          <el-switch
            :style="{ '--el-switch-on-color': settings.providers['openai-compatible'].available ? '#13ce66' : '#ff4949' }"
            v-model="settings.providers['openai-compatible'].enabled"
          />
        </div>
        <template v-if="settings.providers['openai-compatible'].enabled">
          <div class="form-row">
            <label class="form-label">名称</label>
            <el-input v-model="settings.providers['openai-compatible'].name" placeholder="自定义提供商名称" class="form-input" />
          </div>
          <div class="form-row">
            <label class="form-label">Base URL</label>
            <el-input v-model="settings.providers['openai-compatible'].options.baseURL" placeholder="API Base URL" class="form-input" />
          </div>
          <div class="form-row">
            <label class="form-label">API Key</label>
            <el-input v-model="settings.providers['openai-compatible'].options.apiKey" placeholder="请输入 API Key" show-password class="form-input">
              <template #append><el-button @click="queryModels('openai-compatible')">获取模型</el-button></template>
            </el-input>
          </div>
          <div class="form-row">
            <label class="form-label">模型</label>
            <el-select v-model="settings.providers['openai-compatible'].defaultModel" placeholder="请选择模型" style="width:100%">
              <el-option v-for="model in customAvailableModels" :key="model.id" :label="model.id" :value="model.id">
                <span>{{ model.id }}</span>
                <span v-if="model.owned_by" style="float:right;color:#8492a6;font-size:13px">{{ model.owned_by }}</span>
              </el-option>
            </el-select>
          </div>
        </template>
      </div>
    </div>

    <div v-else-if="currentSection === 'theme'" class="settings-body">
      <div class="form-group">
        <div class="form-group-header">
          <span class="form-group-title">全局主题颜色</span>
          <el-button link type="primary" @click="resetTheme">恢复默认</el-button>
        </div>

        <div class="theme-preset-list">
          <button
            v-for="preset in themePresets"
            :key="preset.name"
            class="theme-preset-btn"
            @click="applyThemePreset(preset.values)"
          >
            {{ preset.name }}
          </button>
        </div>

        <div
          v-for="item in themeFields"
          :key="item.key"
          class="form-row theme-row"
        >
          <label class="form-label">{{ item.label }}</label>

          <div class="theme-control">
            <div
              class="theme-color-preview"
              :style="{ background: settings.theme[item.key] }"
            ></div>

            <el-color-picker
              v-model="settings.theme[item.key]"
              class="theme-picker"
            />

            <el-input
              v-model="settings.theme[item.key]"
              class="theme-hex-input"
              placeholder="#ffffff"
            />
          </div>
        </div>
      </div>

      <div class="form-group">
        <div class="form-group-header">
          <span class="form-group-title">实时预览</span>
        </div>

        <div class="theme-demo" :style="{ background: settings.theme.pageBg }">
          <div
            class="theme-demo-header"
            :style="{
              background: settings.theme.headerBg,
              color: settings.theme.titleColor,
              borderColor: settings.theme.borderColor
            }"
          >
            界面预览
          </div>

          <div
            class="theme-demo-card"
            :style="{
              background: settings.theme.cardBg,
              color: settings.theme.textColor,
              borderColor: settings.theme.borderColor
            }"
          >
            <div
              class="theme-demo-dot"
              :style="{ background: settings.theme.primaryColor }"
            ></div>
            当前主色效果预览
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.settings-page {
  height: 100%;
  min-height: 0;
  display: flex;
  flex-direction: column;
  background: var(--app-page-bg);
  overflow: hidden;
}

/* 标题栏 */
.settings-header {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 14px 16px;
  background: var(--app-header-bg);
  border-bottom: 1px solid var(--app-border-color);
  flex-shrink: 0;
}

.back-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 32px;
  height: 32px;
  border: none;
  background: none;
  cursor: pointer;
  color: var(--app-primary-color);
  padding: 0;
  margin-left: -6px;
}

.header-title {
  font-size: 17px;
  font-weight: 600;
  color: var(--app-title-color);
}

/* 滚动内容区 */
.settings-body {
  flex: 1 1 auto;
  height: 0;
  min-height: 0;
  overflow-y: auto;
  overflow-x: hidden;
  display: flex;
  flex-direction: column;
  gap: 12px;
  padding: 16px 16px calc(120px + var(--safe-area-inset-bottom));
  box-sizing: border-box;
  -webkit-overflow-scrolling: touch;
  touch-action: pan-y;
}
.settings-body > * {
  flex-shrink: 0;
}
/* 一级菜单组 */
.menu-group {
  background: var(--app-card-bg);
  border-radius: 12px;
  overflow: hidden;
  box-shadow: 0 1px 4px rgba(0,0,0,0.06);
}

.menu-item {
  display: flex;
  align-items: center;
  gap: 12px;
  width: 100%;
  padding: 14px 16px;
  border: none;
  background: var(--app-card-bg);
  cursor: pointer;
  text-align: left;
  border-bottom: 1px solid var(--app-border-color);
  transition: background 0.12s;
}

.menu-item:last-child {
  border-bottom: none;
}

.menu-item:active {
  background: #f9f9f9;
}

.menu-icon {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 34px;
  height: 34px;
  border-radius: 8px;
  flex-shrink: 0;
}

.speech-icon { background: #fff1f0; color: #e05a4b; }
.model-icon  { background: #f0f4ff; color: #5b7cee; }
.chat-icon   { background: #e8f4fd; color: #2B5CE6; }

.menu-label {
  flex: 1;
  font-size: 15px;
  color: var(--app-text-color);
}

.menu-chevron {
  flex-shrink: 0;
}

/* 二级表单 */
.form-group {
  background: var(--app-card-bg);
  border-radius: 12px;
  overflow: hidden;
  box-shadow: 0 1px 4px rgba(0,0,0,0.06);
  padding: 0 16px;
}

.form-group-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 14px 0;
  border-bottom: 1px solid var(--app-border-color);
}

.form-group-title {
  font-size: 14px;
  font-weight: 600;
  color: var(--app-text-color);
}

.form-row {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 10px 0;
  border-bottom: 1px solid var(--app-border-color);
}

.form-row:last-child {
  border-bottom: none;
}

.form-label {
  font-size: 14px;
  color: var(--app-text-color);
  white-space: nowrap;
  min-width: 72px;
  flex-shrink: 0;
}

.form-input {
  flex: 1;
}

.theme-row {
  align-items: center;
}

.theme-control {
  flex: 1;
  display: flex;
  align-items: center;
  gap: 10px;
}

.theme-color-preview {
  width: 28px;
  height: 28px;
  border-radius: 8px;
  border: 1px solid var(--app-border-color);
  flex-shrink: 0;
}

.theme-picker {
  flex-shrink: 0;
}

.theme-hex-input {
  flex: 1;
}

.theme-preset-list {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  padding: 12px 0 4px 0;
}

.theme-preset-btn {
  border: 1px solid var(--app-border-color);
  background: var(--app-card-bg);
  color: var(--app-text-color);
  border-radius: 999px;
  padding: 6px 14px;
  cursor: pointer;
  font-size: 13px;
}

.theme-preset-btn:hover {
  border-color: var(--app-primary-color);
  color: var(--app-primary-color);
}

.theme-demo {
  padding: 16px;
  border-radius: 12px;
  transition: all 0.2s ease;
}

.theme-demo-header {
  padding: 12px 14px;
  border: 1px solid;
  border-radius: 10px;
  font-weight: 600;
  margin-bottom: 12px;
}

.theme-demo-card {
  padding: 14px;
  border: 1px solid;
  border-radius: 12px;
  display: flex;
  align-items: center;
  gap: 10px;
}

.theme-demo-dot {
  width: 14px;
  height: 14px;
  border-radius: 50%;
  flex-shrink: 0;
}

</style>
