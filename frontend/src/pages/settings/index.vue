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
type Section = null | 'speech-eval' | 'rtasr' | 'model-services' | 'chat'
const currentSection = ref<Section>(null)

const sectionTitle: Record<Exclude<Section, null>, string> = {
  'speech-eval': '语音评测配置',
  'rtasr': '实时语音转写',
  'model-services': '模型服务',
  'chat': '场景对话',
}

const openaiFormRef = ref<InstanceType<typeof ElForm>>();
const doubaoFormRef = ref<InstanceType<typeof ElForm>>();
const deepseekFormRef = ref<InstanceType<typeof ElForm>>();
const customFormRef = ref<InstanceType<typeof ElForm>>();

const providerFormRules = ref<FormRules>({
  "options.baseURL": [{ required: true, message: "请输入 API Base URL" }],
  "options.apiKey": [{ required: true, message: "请输入 API Key" }],
  defaultModel: [{ required: true, message: "请选择模型" }],
});

const customProviderFormRules = ref<FormRules>({
  name: [{ required: true, message: "请输入提供商名称" }],
  "options.baseURL": [{ required: true, message: "请输入 API Base URL" }],
  "options.apiKey": [{ required: true, message: "请输入 API Key" }],
  defaultModel: [{ required: true, message: "请选择模型" }],
});

const settingsStore = useSettingsStore();
const settings = computed(() => settingsStore.settingsState);

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
        xfSpeechEval: settings.value.xfSpeechEval,
        rtasrMode: settings.value.rtasrMode,
        rtasrApiKey: settings.value.rtasrApiKey,
      });
    } catch (error) {
      console.error("自动保存失败:", error);
    }
  }, 500);
};

watch(
  () => [settings.value.providers, settings.value.xfSpeechEval, settings.value.rtasrMode, settings.value.rtasrApiKey, settings.value.chatInputLanguage],
  () => { autoSave(); },
  { deep: true }
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
        <button class="menu-item" @click="currentSection = 'speech-eval'">
          <span class="menu-icon speech-icon">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
              <path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/>
              <path d="M19 10v2a7 7 0 0 1-14 0v-2"/>
              <line x1="12" y1="19" x2="12" y2="23"/>
              <line x1="8" y1="23" x2="16" y2="23"/>
            </svg>
          </span>
          <span class="menu-label">语音评测配置</span>
          <svg class="menu-chevron" width="7" height="12" viewBox="0 0 7 12" fill="none">
            <path d="M1 1L6 6L1 11" stroke="#C0C4CC" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
          </svg>
        </button>
        <button class="menu-item" @click="currentSection = 'rtasr'">
          <span class="menu-icon rtasr-icon">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
              <path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/>
              <path d="M19 10v2a7 7 0 0 1-14 0v-2"/>
              <line x1="12" y1="19" x2="12" y2="23"/>
              <line x1="8" y1="23" x2="16" y2="23"/>
            </svg>
          </span>
          <span class="menu-label">实时语音转写</span>
          <svg class="menu-chevron" width="7" height="12" viewBox="0 0 7 12" fill="none">
            <path d="M1 1L6 6L1 11" stroke="#C0C4CC" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
          </svg>
        </button>
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
        <button class="menu-item" @click="currentSection = 'chat'">
          <span class="menu-icon chat-icon">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
              <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>
            </svg>
          </span>
          <span class="menu-label">场景对话</span>
          <svg class="menu-chevron" width="7" height="12" viewBox="0 0 7 12" fill="none">
            <path d="M1 1L6 6L1 11" stroke="#C0C4CC" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
          </svg>
        </button>
      </div>

    </div>

    <!-- 二级页面：语音评测配置 -->
    <div v-else-if="currentSection === 'speech-eval'" class="settings-body">
      <div class="form-group">
        <div class="form-group-header">
          <span class="form-group-title">讯飞开放平台</span>
        </div>
        <div class="form-row">
          <label class="form-label">App ID</label>
          <el-input
            v-model="settings.xfSpeechEval.appId"
            placeholder="请输入 App ID"
            class="form-input"
          />
        </div>
        <div class="form-row">
          <label class="form-label">API Key</label>
          <el-input
            v-model="settings.xfSpeechEval.apiKey"
            placeholder="请输入 API Key"
            show-password
            class="form-input"
          />
        </div>
        <div class="form-row">
          <label class="form-label">API Secret</label>
          <el-input
            v-model="settings.xfSpeechEval.apiSecret"
            placeholder="请输入 API Secret"
            show-password
            class="form-input"
          />
        </div>
      </div>
    </div>

    <!-- 二级页面：实时语音转写 -->
    <div v-else-if="currentSection === 'rtasr'" class="settings-body">
      <div class="form-group">
        <div class="form-group-header">
          <span class="form-group-title">转写版本</span>
        </div>
        <div class="form-row">
          <label class="form-label">版本选择</label>
          <el-select v-model="settings.rtasrMode" style="width:100%">
            <el-option value="llm" label="大模型版" />
            <el-option value="standard" label="标准版" />
          </el-select>
        </div>
        <div v-if="settings.rtasrMode === 'llm'" class="form-hint">
          大模型版使用语音评测配置中的 App ID 和 API Key，无需额外配置
        </div>
      </div>
      <div v-if="settings.rtasrMode === 'standard'" class="form-group">
        <div class="form-group-header">
          <span class="form-group-title">标准版配置</span>
        </div>
        <div class="form-row">
          <label class="form-label">API Key</label>
          <el-input
            v-model="settings.rtasrApiKey"
            placeholder="请输入标准版 API Key"
            show-password
            class="form-input"
          />
        </div>
        <div class="form-hint">
          标准版使用独立的 API Key，与语音评测的 API Key 不同
        </div>
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

    <!-- 二级页面：场景对话 -->
    <div v-else-if="currentSection === 'chat'" class="settings-body">
      <div class="form-group">
        <div class="form-group-header">
          <span class="form-group-title">语音识别语言</span>
        </div>
        <div class="form-row">
          <label class="form-label">输入语言</label>
          <el-select v-model="settings.chatInputLanguage" style="width:100%">
            <el-option value="es" label="西语（Español）" />
            <el-option value="zh" label="中文" />
            <el-option value="en" label="英文（English）" />
          </el-select>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.settings-page {
  height: 100%;
  display: flex;
  flex-direction: column;
  background: #f5f5f5;
}

/* 标题栏 */
.settings-header {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 14px 16px;
  background: #fff;
  border-bottom: 1px solid #ebeef5;
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
  color: #e05a4b;
  padding: 0;
  margin-left: -6px;
}

.header-title {
  font-size: 17px;
  font-weight: 600;
  color: #1a1a1a;
}

/* 滚动内容区 */
.settings-body {
  flex: 1;
  overflow-y: auto;
  padding: 16px 16px 32px;
  display: flex;
  flex-direction: column;
  gap: 12px;
}

/* 一级菜单组 */
.menu-group {
  background: #fff;
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
  background: #fff;
  cursor: pointer;
  text-align: left;
  border-bottom: 1px solid #f5f5f5;
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
.rtasr-icon  { background: #f0f9ff; color: #3b82f6; }
.model-icon  { background: #f0f4ff; color: #5b7cee; }
.chat-icon   { background: #e8f4fd; color: #2B5CE6; }

.menu-label {
  flex: 1;
  font-size: 15px;
  color: #303133;
}

.menu-chevron {
  flex-shrink: 0;
}

/* 二级表单 */
.form-group {
  background: #fff;
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
  border-bottom: 1px solid #f5f5f5;
}

.form-group-title {
  font-size: 14px;
  font-weight: 600;
  color: #606266;
}

.form-row {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 10px 0;
  border-bottom: 1px solid #f5f5f5;
}

.form-row:last-child {
  border-bottom: none;
}

.form-label {
  font-size: 14px;
  color: #606266;
  white-space: nowrap;
  min-width: 72px;
  flex-shrink: 0;
}

.form-input {
  flex: 1;
}

.form-hint {
  font-size: 12px;
  color: #909399;
  padding: 8px 0 4px;
  line-height: 1.5;
}

</style>
