<!-- 字典页 -->
<template>
  <el-container class="dictionary-container" @click="handleContainerClick">
    <!-- 头部区域 -->
    <el-header class="dictionary-header">
      <div class="page-title">翻译助手</div>
      <div class="header-controls">
        <ModelSelector 
          v-model="selectedModel"
          @model-change="handleModelChange"
          class="model-selector-header"
        />
        <el-icon @click="goToSettings"><Setting /></el-icon>
      </div>
    </el-header>
    
    <!-- 输入区域（固定） -->
    <div class="input-section">
      <el-input
        :rows="4"
        type="textarea"
        v-model="userInput"
        placeholder="请输入内容"
        resize="none"
      />
      <div class="button-container">
        <el-button @click="aiChat(RequestType.CN_TO_ES)" :disabled="isLoading">中文翻译</el-button>
        <el-button @click="aiChat(RequestType.ES_TO_CN)" :disabled="isLoading">西语翻译</el-button>
        <el-button @click="goToScan" :disabled="isLoading">图片识别</el-button>
        <!-- <el-button @click="aiChat(RequestType.CHAT)" :disabled="isLoading">AI对话</el-button> -->
        <el-button @click="clearInput" :disabled="isLoading">清空</el-button>
        <el-button v-if="isLoading" @click="abortRequest" type="danger">终止</el-button>
      </div>
    </div>
    
    <!-- 结果区域（可滚动） -->
    <div class="result-section">
      <!-- 加载状态（仅在没有流式内容时显示） -->
      <div v-if="isLoading && !streamingText" class="loading-state">
        <div class="loading-spinner"></div>
        正在会话中...
      </div>
      
      <!-- 使用Markdown渲译结果 -->
      <div
        v-if="markdownResult || (isLoading && streamingText)"
        :class="['markdown-result', { 'disable-context-menu': isMobile, 'disable-selection': isLoading }]"
      >
        <div v-html="markdownResult"></div>
      </div>
    </div>
    
    <!-- 文本选择弹窗 -->
    <TextSelectionPopup
      :visible="textSelection.isVisible.value"
      :selected-text="textSelection.selectedText.value"
      :selection-rect="textSelection.selectionRect.value"
      @close="textSelection.hidePopup"
      @translate="handlePopupTranslate"
    />
  </el-container>
</template>

<script setup lang="ts">
import { ref, computed, nextTick } from "vue";
import { ElInput, ElMessage, ElButton } from "element-plus";
import { Setting } from "@element-plus/icons-vue";
import MarkdownIt from "markdown-it";
import { callOpenAI, callOpenAIStream } from "@/services/translate";
import { RequestType } from "@/services/aiClientManager";
import { handleError, generateErrorMarkdown } from "@/utils/errorHandler";
import { useRouter } from "vue-router";
import { useSettingsStore } from "@/stores/settings";
import { useShikiHighlighter } from './hooks/useShikiHighlighter';
import { useTextSelection } from './hooks/useTextSelection';
import TextSelectionPopup from './components/TextSelectionPopup.vue';
import ModelSelector from './components/ModelSelector.vue';
import { isMobile } from '@/utils/os';
import { findWordInPrompt } from "@/utils/handle_word";
import { aiClientManager } from '@/services/aiClientManager';

// 定义组件名称，用于keep-alive
defineOptions({
  name: 'Dictionary'
});

const router = useRouter();
const settingsStore = useSettingsStore();
const userInput = ref('abajo');
const markdownResult = ref("");
const isLoading = ref(false);
const streamingText = ref(""); // 存储流式输出的原始文本
const useStreaming = ref(true); // 默认使用流式输出
const currentAbortController = ref<AbortController | null>(null); // 当前请求的终止控制器
const selectedModel = ref(""); // 当前选择的模型（用于 ModelSelector 的 v-model）

// 使用文本选择功能
const textSelection = useTextSelection({
  containerSelector: '.markdown-result',
  minTextLength: 1,
  maxTextLength: 100,
  autoHideDelay: 5000,
  shouldShow: () => !isLoading.value // 翻译过程中禁用划词功能
});

const settings = computed(() => settingsStore.settingsState);


// 高亮任务管理
const highlightTasks = new Map();
const { codeToHtml } = useShikiHighlighter();

const mdi = new MarkdownIt({
  html: true,
  linkify: true,
  breaks: true,
  typographer: true,
  highlight: (code, language) => {
    const id = `shiki-${Date.now()}-${Math.random()}`;
    highlightTasks.set(id, codeToHtml(code, language));
    return `<div data-shiki-id="${id}"></div>`;
  },
});

// 处理异步高亮结果
const processHighlightedContent = async (html: string) => {
  let processedHtml = html;

  // 查找所有需要替换的占位符
  const placeholders = Array.from(html.matchAll(/<div data-shiki-id="([^"]+)"><\/div>/g));

  // 等待所有高亮任务完成并替换
  for (const [fullMatch, id] of placeholders) {
    if (highlightTasks.has(id)) {
      try {
        const highlightedCode = await highlightTasks.get(id);
        processedHtml = processedHtml.replace(fullMatch, highlightedCode);
        highlightTasks.delete(id); // 清理已完成的任务
      } catch (error) {
        console.error('代码高亮失败:', error);
        processedHtml = processedHtml.replace(fullMatch, `<code>代码高亮失败</code>`);
      }
    }
  }

  return processedHtml;
};


// 跳转至设置页面
const goToSettings = () => {
  router.push({ path: "/settings" });
};
// 跳转至图片识别界面
const goToScan = () => {
  router.push({ path: "/scan" });
};


// 处理模型切换
const handleModelChange = (modelInfo: { providerId: string; modelId: string; providerConfig: any }) => {
  try {
    // 验证提供商是否可用
    if (!aiClientManager.isProviderAvailable(modelInfo.providerId)) {
      throw new Error(`提供商 ${modelInfo.providerId} 不可用或未启用`);
    }
    
    // 更新当前选中的模型信息，格式: "providerId/modelId"
    const modelInfoString = `${modelInfo.providerId}/${modelInfo.modelId}`;
    settingsStore.settingsState.defaultModelInfo = modelInfoString;
    settingsStore.saveCurrentModelInfo(modelInfoString);
    
    console.log(`已选择模型: ${modelInfo.modelId} (${modelInfo.providerId})`);
  } catch (error) {
    console.error('模型选择失败:', error);
    ElMessage.error('模型选择失败，请检查配置');
  }
};

// 处理容器点击事件
const handleContainerClick = (event: MouseEvent) => {
  textSelection.hidePopup();
};

// 清空内容
const clearInput = () => {
  userInput.value = "abajo";
  markdownResult.value = "";
  streamingText.value = "";
};

// 终止当前请求
const abortRequest = () => {
  if (currentAbortController.value) {
    currentAbortController.value.abort();
    currentAbortController.value = null;
    isLoading.value = false;
  }
};

// 处理弹窗翻译
const handlePopupTranslate = async (text: string) => {
  if (!text.trim()) return;
  
  // 获取当前实际选中的文本，而不是弹窗传递的文本
  const selection = window.getSelection();
  const actualSelectedText = selection?.toString().trim();
  
  // 优先使用实际选中的文本，如果没有则使用传递的文本
  const textToTranslate = actualSelectedText || text;
  
  // 将选中的文本放入输入框
  userInput.value = textToTranslate;
  
  // 先隐藏弹窗
  textSelection.hidePopup();
  
  // 延迟清除选择，确保翻译完成后再清除
  const clearSelectionLater = () => {
    setTimeout(() => {
      const currentSelection = window.getSelection();
      if (currentSelection) {
        currentSelection.removeAllRanges();
      }
    }, 1000); // 延长到1秒后清除
  };
  
  // 等待DOM更新后开始翻译
  await nextTick();
  
  // 自动开始翻译（默认西语翻译）
  try {
    await aiChat(RequestType.ES_TO_CN);
  } finally {
    // 翻译完成后清除选择
    clearSelectionLater();
  }
};


// 翻译函数（支持流式和普通输出）
const aiChat = async (prompt: RequestType) => {
  if (!userInput.value.trim()) {
    markdownResult.value = "";
    streamingText.value = "";
    return;
  }

  // 西语翻译预处理，先匹配本地单词表，如果找到匹配的内容，直接显示，不调用 API
  if (prompt === RequestType.ES_TO_CN) {
    // 先在本地单词库中查找匹配的内容
    const localMatch = findWordInPrompt(userInput.value);
    if (localMatch) {
      // 如果找到匹配的内容，直接显示，不调用 API
      isLoading.value = true;
      streamingText.value = "";
      markdownResult.value = "";
      
      try {
        // 模拟一个短暂的加载过程，提供更好的用户体验
        await new Promise(resolve => setTimeout(resolve, 300));
        
        const rawHtml = mdi.render(localMatch);
        markdownResult.value = await processHighlightedContent(rawHtml);
        console.log("找到本地匹配结果");
        
        ElMessage.success("会话完成");
        return; // 直接返回，不继续执行 API 调用
      } catch (error) {
        console.error('处理本地匹配结果时出错:', error);
        // 如果处理本地结果出错，继续执行 API 调用
      } finally {
        isLoading.value = false;
      }
    }
  }


  // 创建新的AbortController
  currentAbortController.value = new AbortController();
  isLoading.value = true;
  streamingText.value = ""; // 清空之前的流式文本
  markdownResult.value = ""; // 清空之前的结果

  try {
    if (useStreaming.value) {
      // 使用流式输出
      await callOpenAIStream({
        text: userInput.value,
        currentModelInfo: settingsStore.settingsState.defaultModelInfo,
        onData: async (chunk: string) => {
        // 每收到一个数据块就更新显示
        streamingText.value += chunk;
        const rawHtml = mdi.render(streamingText.value);
        markdownResult.value = await processHighlightedContent(rawHtml);
      },
        requestType: prompt,
        abortController: currentAbortController.value
      });
    } else {
      // 使用普通输出
      const result = await callOpenAI({
        text: userInput.value,
        currentModelInfo: settingsStore.settingsState.defaultModelInfo,
        requestType: prompt,
        abortController: currentAbortController.value
      });
      const rawHtml = mdi.render(result);
      markdownResult.value = await processHighlightedContent(rawHtml);
    }
    ElMessage.success("会话完成");
  } catch (error) {
    // 使用统一的错误处理
    const errorInfo = handleError(error);
    const rawHtml = mdi.render(generateErrorMarkdown(errorInfo));
    markdownResult.value = await processHighlightedContent(rawHtml);
  } finally {
    isLoading.value = false;
    currentAbortController.value = null; // 清理AbortController
    
    // 翻译完成后重置文本选择状态，确保功能正常
    setTimeout(() => {
      textSelection.resetAfterTranslation();
      // 移动端额外检查是否有文本选择
      textSelection.checkMobileSelection();
    }, 300); // 增加延迟，确保DOM完全更新
  }
};

</script>

<style scoped>
.dictionary-container {
  height: 100%;
  min-height: 0;
  display: flex;
  flex-direction: column;
  overflow: hidden;
  background: var(--app-page-bg);
}

.dictionary-header {
  display: flex;
  flex-direction: row;
  justify-content: space-between;
  align-items: center;
  flex-shrink: 0;
  padding: 20px 20px 0 20px;
  z-index: 10;
  background: var(--app-header-bg);
  color: var(--app-title-color);
  border-bottom: 1px solid var(--app-border-color);
}

.header-controls {
  display: flex;
  align-items: center;
  gap: 16px;
}

.header-controls :deep(.el-icon) {
  color: var(--app-primary-color);
  cursor: pointer;
}

.model-selector-header {
  margin-right: 8px;
}

/* 输入区域（固定不滚动） */
.input-section {
  flex-shrink: 0;
  padding: 20px;
  z-index: 9;
  background: var(--app-page-bg);
}

.button-container {
  margin-top: 10px;
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}

.button-container :deep(.el-button) {
  background: var(--app-card-bg);
  color: var(--app-text-color);
  border-color: var(--app-border-color);
}

.button-container :deep(.el-button:hover) {
  color: var(--app-primary-color);
  border-color: var(--app-primary-color);
}

.button-container :deep(.el-button--primary) {
  background: var(--app-primary-color);
  border-color: var(--app-primary-color);
  color: #fff;
}

/* 结果区域（可滚动） */
.result-section {
  flex: 1;
  min-height: 0;
  overflow-y: auto;
  overflow-x: hidden;
  padding: 0 20px 20px 20px;
  background-color: var(--app-page-bg);
  -webkit-overflow-scrolling: touch;
}

/* 自定义滚动条样式 */
.result-section::-webkit-scrollbar {
  width: 8px;
}

.result-section::-webkit-scrollbar-track {
  background: #f1f1f1;
  border-radius: 4px;
}

.result-section::-webkit-scrollbar-thumb {
  background: #c1c1c1;
  border-radius: 4px;
}

.result-section::-webkit-scrollbar-thumb:hover {
  background: #a8a8a8;
}

.markdown-result {
  padding: 20px;
  background-color: var(--app-card-bg);
  color: var(--app-text-color);
  border: 1px solid var(--app-border-color);
  border-radius: 8px;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.08);
  max-width: 100%;
  overflow-wrap: break-word;
  word-wrap: break-word;
  word-break: break-word;
  box-sizing: border-box;
}

/* 确保markdown内容中的元素不超出容器 */
.markdown-result * {
  max-width: 100%;
  box-sizing: border-box;
}

/* 加载状态样式 */
.loading-state {
  padding: 20px;
  text-align: center;
  color: var(--app-primary-color);
  font-size: 14px;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
}

/* 加载动画 */
.loading-spinner {
  width: 16px;
  height: 16px;
  border: 2px solid #f3f3f3;
  border-top: 2px solid var(--app-primary-color);
  border-radius: 50%;
  animation: spin 1s linear infinite;
}

@keyframes spin {
  0% {
    transform: rotate(0deg);
  }
  100% {
    transform: rotate(360deg);
  }
}

/* 文本选择增强样式 */
.markdown-result {
  user-select: text;
  -webkit-user-select: text;
  -moz-user-select: text;
  -ms-user-select: text;
}

.markdown-result::selection {
  background-color: var(--app-primary-color);
  color: white;
}

.markdown-result::-moz-selection {
  background-color: var(--app-primary-color);
  color: white;
}

/* 移动端优化文本选择的样式类 */
.disable-context-menu {
  -webkit-touch-callout: none;
  -webkit-user-select: text;
  -moz-user-select: text;
  -ms-user-select: text;
  user-select: text;
  touch-action: manipulation;
  -webkit-tap-highlight-color: transparent;
}

/* 翻译过程中禁用文本选择 */
.disable-selection {
  user-select: none !important;
  -webkit-user-select: none !important;
  -moz-user-select: none !important;
  -ms-user-select: none !important;
  pointer-events: auto;
  cursor: default;
}

.disable-selection * {
  user-select: none !important;
  -webkit-user-select: none !important;
  -moz-user-select: none !important;
  -ms-user-select: none !important;
}

.input-section :deep(.el-textarea__inner) {
  background: var(--app-card-bg);
  color: var(--app-text-color);
  border-color: var(--app-border-color);
}

.input-section :deep(.el-textarea__inner::placeholder) {
  color: var(--app-nav-inactive-color);
}

/* 移动端适配 */
@media (max-width: 600px) {
  .dictionary-header {
    padding: 12px 16px 0px 16px;
    flex-direction: row;
    gap: 8px;
  }

  .page-title {
    font-size: 16px;
  }

  .input-section {
    padding: 12px 16px;
  }

  .result-section {
    padding: 12px 16px;
  }

  .markdown-result {
    padding: 12px;
  }

  .button-container {
    gap: 6px;
  }

  .button-container .el-button {
    font-size: 13px;
    padding: 8px 12px;
  }
}
</style>