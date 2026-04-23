import { defineStore } from "pinia";
import { reactive } from "vue";
import { 
  getCurrentModelInfo, 
  getSettings, 
  setCurrentModelInfo, 
  setSettings,
  getCachedModels,
  getCachedTestResult,
  isCacheExpired
} from "@/utils/localStorage";
import { 
  createProviderConfig, 
} from "@/utils/constant/providers";

export const useSettingsStore = defineStore("settings", () => {
const settingsState = reactive({
  providers: createProviderConfig(),
  isDark: false,
  defaultModelInfo: '',
  xfSpeechEval: {
    appId: '',
    apiKey: '',
    apiSecret: '',
  },
  baiduOcr: {
    apiKey: '',
    secretKey: '',
  },
  chatDefaultPrompt: '',
  theme: {
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
  }
});


  const loadSettings = async () => {
    // 先从本地缓存读取
    const currentModelInfo = getCurrentModelInfo();
    if (currentModelInfo) {
      // 现在存储的是简化格式 "providerId/modelId"，直接使用
      settingsState.defaultModelInfo = currentModelInfo;
    }
    let settings = getSettings();
    if (settings) {
      settings = JSON.parse(settings);
      
      // 加载新的多提供商配置
      if (settings.providers) {
        Object.keys(settings.providers).forEach(providerId => {
          if (settingsState.providers[providerId]) {
            // 合并保存的配置到默认配置
            const savedConfig = settings.providers[providerId];
            const currentProvider = settingsState.providers[providerId];
            
            // 更新provider配置，保持默认结构
            currentProvider.enabled = savedConfig.enabled ?? currentProvider.enabled;
            if (savedConfig.options) {
              currentProvider.options = {
                ...currentProvider.options,
                ...savedConfig.options
              };
            }
            // 兼容旧的配置格式
            if (savedConfig.apiBaseUrl) {
              currentProvider.options = currentProvider.options || {};
              currentProvider.options.baseURL = savedConfig.apiBaseUrl;
            }
            if (savedConfig.apiKey) {
              currentProvider.options = currentProvider.options || {};
              currentProvider.options.apiKey = savedConfig.apiKey;
            }
            if (savedConfig.selectedModel) {
              currentProvider.defaultModel = savedConfig.selectedModel;
            }
            if (savedConfig.name && providerId === "openai-compatible") {
              currentProvider.name = savedConfig.name;
              currentProvider.options = currentProvider.options || {};
            }
            
            // 加载缓存的模型列表
            const cachedModels = getCachedModels(providerId);
            if (cachedModels) {
              try {
                const modelCache = JSON.parse(cachedModels);
                if (modelCache && !isCacheExpired(modelCache.timestamp)) {
                  currentProvider.models = modelCache.models;
                }
              } catch (error) {
                console.warn(`加载 ${providerId} 模型缓存失败:`, error);
              }
            }
            
            // 加载缓存的测试结果
            const cachedTestResult = getCachedTestResult(providerId);
            if (cachedTestResult) {
              try {
                const testCache = JSON.parse(cachedTestResult);
                if (testCache && !isCacheExpired(testCache.timestamp)) {
                  currentProvider.available = testCache.available;
                }
              } catch (error) {
                console.warn(`加载 ${providerId} 测试结果缓存失败:`, error);
              }
            }
          }
        });
      }
      if (settings.xfSpeechEval) {
        Object.assign(settingsState.xfSpeechEval, settings.xfSpeechEval);
      }
      if (settings.baiduOcr) {
        Object.assign(settingsState.baiduOcr, settings.baiduOcr);
      }
      if (settings.chatDefaultPrompt !== undefined) {
        settingsState.chatDefaultPrompt = settings.chatDefaultPrompt;
      }
      if (settings.theme) {
        Object.assign(settingsState.theme, settings.theme);
      }
    }

  };

  const saveSettings = async (data) => {
    if (data.providers) {
      Object.keys(data.providers).forEach(provider => {
        if (settingsState.providers[provider]) {
          Object.assign(settingsState.providers[provider], data.providers[provider]);
        }
      });
    }

    if (data.xfSpeechEval) {
      Object.assign(settingsState.xfSpeechEval, data.xfSpeechEval);
    }

    if (data.baiduOcr) {
      Object.assign(settingsState.baiduOcr, data.baiduOcr);
    }

    if (data.chatDefaultPrompt !== undefined) {
      settingsState.chatDefaultPrompt = data.chatDefaultPrompt;
    }

    if (data.theme) {
      Object.assign(settingsState.theme, data.theme);
    }

    setSettings(settingsState);
  };

  const saveCurrentModelInfo = (modelInfo: any) => {
    setCurrentModelInfo(modelInfo);
  };

  return {
    settingsState,
    loadSettings,
    saveSettings,
    saveCurrentModelInfo
  };
});
