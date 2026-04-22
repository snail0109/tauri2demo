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
    // 使用新的provider配置结构
    providers: createProviderConfig(),
    isDark: false,
    defaultModelInfo: '', // 格式: "providerId/modelId"
    xfSpeechEval: {
      appId: '',
      apiKey: '',
      apiSecret: '',
    },
    rtasrMode: 'llm' as 'llm' | 'standard', // 实时语音转写模式：大模型版 / 标准版
    rtasrApiKey: '', // 标准版实时语音转写独立 APIKey（大模型版共用语音评测的 apiKey）
    chatInputLanguage: 'es',
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
      if (settings.rtasrMode !== undefined) {
        settingsState.rtasrMode = settings.rtasrMode;
      }
      if (settings.rtasrApiKey !== undefined) {
        settingsState.rtasrApiKey = settings.rtasrApiKey;
      }
      if (settings.chatInputLanguage !== undefined) {
        settingsState.chatInputLanguage = settings.chatInputLanguage;
      }
    }

  };

  const saveSettings = async (data) => {
    // 保存新的多提供商配置
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
    if (data.rtasrMode !== undefined) {
      settingsState.rtasrMode = data.rtasrMode;
    }
    if (data.rtasrApiKey !== undefined) {
      settingsState.rtasrApiKey = data.rtasrApiKey;
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
