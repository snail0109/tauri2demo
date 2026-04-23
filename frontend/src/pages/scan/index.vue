<template>
  <el-container class="scan-page">
    <el-header class="scan-header">
      <div class="header-left">
        <el-button text @click="goBack">返回</el-button>
        <div class="page-title">图片识别</div>
      </div>
    </el-header>

    <div class="scan-content">
      <div class="scan-card">
        <h3>AR实景扫一扫</h3>
        <p>
          上传图片后，系统将自动识别其中的西语文字，并返回对应的中文翻译、术语解释和学习示例。
        </p>

        <div class="upload-actions">
          <input
            ref="fileInputRef"
            type="file"
            accept="image/*"
            class="hidden-input"
            @change="handleFileChange"
          />
          <el-button type="primary" @click="triggerSelectImage">
            选择图片
          </el-button>
          <el-button
            type="success"
            :disabled="!selectedImageUrl"
            @click="runRecognition"
          >
            开始识别
          </el-button>
          <el-button :disabled="!selectedImageUrl" @click="resetAll">
            清空
          </el-button>
        </div>

        <div class="preview-section" v-if="selectedImageUrl">
          <h4>图片预览</h4>
          <img :src="selectedImageUrl" alt="预览图片" class="preview-image" />
          <div class="file-name" v-if="selectedFileName">
            文件名：{{ selectedFileName }}
          </div>
        </div>

        <div class="ocr-text-section" v-if="ocrText">
          <h4>识别到的文字</h4>
          <div class="ocr-text-box">{{ ocrText }}</div>
        </div>

        <div class="error-tip" v-if="errorMessage">
          {{ errorMessage }}
        </div>

        <div class="result-section" v-if="result">
          <h4>识别结果</h4>

          <div class="result-item">
            <div class="result-label">识别出的西语</div>
            <div class="result-value">{{ result.spanish }}</div>
          </div>

          <div class="result-item">
            <div class="result-label">中文翻译</div>
            <div class="result-value">{{ result.chinese }}</div>
          </div>

          <div class="result-item">
            <div class="result-label">标识类别</div>
            <div class="result-value">{{ result.category }}</div>
          </div>

          <div class="result-item">
            <div class="result-label">适用场景</div>
            <div class="result-value">{{ result.scene }}</div>
          </div>

          <div class="result-item">
            <div class="result-label">注意事项</div>
            <div class="result-value">{{ result.notice }}</div>
          </div>

          <div class="result-item">
            <div class="result-label">结果来源</div>
            <div class="result-value">
              {{ result.source === 'knowledge_base' ? '知识库匹配' : 'AI结果' }}
            </div>
          </div>

          <div class="result-item">
            <div class="result-label">术语解释</div>
            <div class="result-value">{{ result.explanation }}</div>
          </div>

          <div class="result-item">
            <div class="result-label">相关学习句（西语）</div>
            <div class="result-value">{{ result.sentenceSpanish }}</div>
          </div>

          <div class="result-item">
            <div class="result-label">对应中文</div>
            <div class="result-value">{{ result.sentenceChinese }}</div>
          </div>
        </div>

        <div class="empty-tip" v-else>
          请选择一张图片，然后点击“开始识别”。
        </div>
      </div>
    </div>
  </el-container>
</template>

<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { fileToBase64WithoutPrefix, recognizeImageByBaiduOcr } from '@/services/ocr/baidu'
import { callOpenAI } from '@/services/translate'
import { RequestType } from '@/services/aiClientManager'
import { getSettings } from '@/utils/localStorage'

defineOptions({
  name: 'Scan'
})

type DemoResult = {
  spanish: string
  chinese: string
  category: string
  explanation: string
  scene: string
  notice: string
  sentenceSpanish: string
  sentenceChinese: string
  source: 'knowledge_base' | 'ai'
}

type SignItem = {
  spanish: string
  aliases?: string[]
  chinese: string
  category: string
  explanation: string
  scene: string
  notice: string
  sentenceSpanish: string
  sentenceChinese: string
}

const router = useRouter()

const fileInputRef = ref<HTMLInputElement | null>(null)
const selectedFile = ref<File | null>(null)
const selectedImageUrl = ref('')
const selectedFileName = ref('')
const ocrText = ref('')
const errorMessage = ref('')
const result = ref<DemoResult | null>(null)

const signKnowledgeBase: SignItem[] = [
  {
    spanish: 'SOLO RESIDUOS DE METAL-LATAS',
    aliases: ['SOLO RESIDUOS DE METAL LATAS'],
    chinese: '仅限金属/罐类废弃物',
    category: '废弃物分类标识',
    explanation: '该标识表示此容器仅用于收集金属制品、铁罐、铝罐等金属或罐类废弃物。',
    scene: '适用于施工现场、生活区、办公区或仓储区域的分类回收点。',
    notice: '不要混投玻璃、纸张、有机垃圾或危险废弃物。',
    sentenceSpanish: 'Los residuos de metal y latas deben colocarse en este contenedor.',
    sentenceChinese: '金属和罐类废弃物应投放到这个容器中。'
  },
  {
    spanish: 'SOLO RESIDUOS DE PAPEL-MADERA',
    aliases: ['SOLO RESIDUOS DE PAPEL MADERA'],
    chinese: '仅限纸张/木材废弃物',
    category: '废弃物分类标识',
    explanation: '该标识表示此容器用于收集纸张、纸板、木质边角料等纸类和木材类废弃物。',
    scene: '适用于施工现场材料区、包装拆解区或临时办公区。',
    notice: '不要混入玻璃、金属、有机垃圾或危险废弃物。',
    sentenceSpanish: 'El papel y la madera deben depositarse por separado en este contenedor.',
    sentenceChinese: '纸张和木材废弃物应单独投放到这个容器中。'
  },
  {
    spanish: 'SOLO RESIDUOS ORGANICOS',
    chinese: '仅限有机废弃物',
    category: '废弃物分类标识',
    explanation: '该标识表示此容器仅用于投放有机垃圾，例如食物残渣、果皮、植物残体等。',
    scene: '常见于食堂、生活营地或人员休息区。',
    notice: '不要混入玻璃、金属、塑料或危险废弃物。',
    sentenceSpanish: 'Los residuos orgánicos deben depositarse aquí.',
    sentenceChinese: '有机废弃物应投放到这里。'
  },
  {
    spanish: 'SOLO RESIDUOS DE VIDRIO',
    chinese: '仅限玻璃废弃物',
    category: '废弃物分类标识',
    explanation: '该标识表示此容器仅用于回收玻璃类废弃物。',
    scene: '适用于生活区、仓储区或分类回收点。',
    notice: '投放玻璃碎片时应注意防割伤。',
    sentenceSpanish: 'Los residuos de vidrio deben colocarse en este contenedor.',
    sentenceChinese: '玻璃类废弃物应投放到这个容器中。'
  },
  {
    spanish: 'SOLO RESIDUOS PATOLOGICOS',
    chinese: '仅限病理性废弃物',
    category: '特殊/危险废弃物标识',
    explanation: '该标识表示此容器用于收集病理性或具有感染风险的特殊废弃物。',
    scene: '多见于医疗、实验或特殊卫生处理场景。',
    notice: '不得与普通生活垃圾或可回收物混投。',
    sentenceSpanish: 'Los residuos patológicos deben tratarse por separado.',
    sentenceChinese: '病理性废弃物必须单独处理。'
  },
  {
    spanish: 'SOLO RESIDUOS DE HIDROCARBUROS',
    chinese: '仅限含烃类废弃物',
    category: '危险/污染废弃物标识',
    explanation: '该标识表示此容器用于收集与油类、燃油、润滑油等烃类物质有关的污染废弃物。',
    scene: '适用于机械设备区、燃油区、维修区等工程现场。',
    notice: '不得与普通垃圾混放，应按污染废弃物要求分类处理。',
    sentenceSpanish: 'Los residuos con hidrocarburos deben depositarse en un recipiente especial.',
    sentenceChinese: '含烃污染废弃物应投放到专用容器中。'
  },
  {
    spanish: 'SALIDA DE EMERGENCIA',
    chinese: '紧急出口',
    category: '疏散/逃生标识',
    explanation: '用于标识紧急情况下的疏散出口位置。',
    scene: '适用于施工现场通道、楼梯口、厂房及公共区域。',
    notice: '应保持通道畅通，不得堆放杂物。',
    sentenceSpanish: 'En caso de emergencia, salga por esta salida.',
    sentenceChinese: '发生紧急情况时，请从这个出口撤离。'
  },
  {
    spanish: 'PUERTA DE ESCAPE',
    chinese: '逃生门',
    category: '疏散/逃生标识',
    explanation: '用于标识紧急情况下可用于逃生的门或出口。',
    scene: '适用于厂房、施工现场临建、办公区域等。',
    notice: '逃生门不得上锁或被遮挡。',
    sentenceSpanish: 'Utilice esta puerta para evacuar en caso de peligro.',
    sentenceChinese: '发生危险时，请使用这扇门撤离。'
  },
  {
    spanish: 'ENTRADA',
    chinese: '入口',
    category: '导向标识',
    explanation: '用于标识进入某区域或通道的入口位置。',
    scene: '适用于工地大门、办公区、通道入口等。',
    notice: '请按规定方向进入。',
    sentenceSpanish: 'Por favor, entre por esta entrada.',
    sentenceChinese: '请从这个入口进入。'
  },
  {
    spanish: 'SALIDA',
    chinese: '出口',
    category: '导向标识',
    explanation: '用于标识离开某区域的出口位置。',
    scene: '适用于建筑物、施工现场、通道出口等。',
    notice: '请按出口方向有序离开。',
    sentenceSpanish: 'La salida está en esta dirección.',
    sentenceChinese: '出口在这个方向。'
  },
  {
    spanish: 'ESCALERA',
    chinese: '楼梯',
    category: '导向标识',
    explanation: '用于标识楼梯位置或前往楼梯的方向。',
    scene: '适用于楼道、疏散通道、现场建筑内部。',
    notice: '紧急情况下优先走楼梯，不使用电梯。',
    sentenceSpanish: 'Use la escalera en caso de evacuación.',
    sentenceChinese: '疏散时请使用楼梯。'
  },
  {
    spanish: 'HOMBRES TRABAJANDO',
    chinese: '前方施工 / 有工人作业',
    category: '警告标识',
    explanation: '用于提示前方或该区域存在施工或作业活动，应提高警惕。',
    scene: '适用于施工道路、工地区域、维修作业区。',
    notice: '请减速慢行，注意避让施工人员。',
    sentenceSpanish: 'Hay trabajadores en esta zona, avance con precaución.',
    sentenceChinese: '该区域有工人作业，请小心通行。'
  },
  {
    spanish: 'SUPERFICIE RESBALADIZA',
    chinese: '地面湿滑',
    category: '警告标识',
    explanation: '用于提示地面湿滑，人员行走时存在滑倒风险。',
    scene: '适用于清洁区域、潮湿地面、设备清洗区。',
    notice: '请减速慢行，防止滑倒。',
    sentenceSpanish: 'La superficie está resbaladiza, camine con cuidado.',
    sentenceChinese: '地面湿滑，请小心行走。'
  },
  {
    spanish: 'RIESGO CHOQUE ELECTRICO',
    aliases: ['RIESGO ELECTRICO'],
    chinese: '有触电风险',
    category: '警告标识',
    explanation: '用于提示该区域或设备存在电击、触电危险。',
    scene: '适用于配电箱、电力设备区、施工电源附近。',
    notice: '非专业人员禁止接触带电设备。',
    sentenceSpanish: 'Existe riesgo de choque eléctrico en esta zona.',
    sentenceChinese: '该区域存在触电风险。'
  },
  {
    spanish: 'PELIGRO DE INCENDIO',
    chinese: '火灾危险',
    category: '警告标识',
    explanation: '用于提示该区域存在火灾风险或易燃因素。',
    scene: '适用于油料区、仓储区、易燃品附近。',
    notice: '严禁烟火，并做好防火措施。',
    sentenceSpanish: 'Hay peligro de incendio en esta área.',
    sentenceChinese: '该区域存在火灾危险。'
  },
  {
    spanish: 'ATENCION RIESGO DE EXPLOSION',
    chinese: '注意爆炸风险',
    category: '警告标识',
    explanation: '用于提示该区域可能存在爆炸危险。',
    scene: '适用于易燃易爆物料区、气体设备区。',
    notice: '严禁明火，并按规范操作设备。',
    sentenceSpanish: 'Atención, existe riesgo de explosión.',
    sentenceChinese: '注意，该区域存在爆炸风险。'
  },
  {
    spanish: 'ATENCION RIESGO CAUSTICO',
    chinese: '注意腐蚀性风险',
    category: '警告标识',
    explanation: '用于提示该区域可能存在腐蚀性化学品或腐蚀性伤害风险。',
    scene: '适用于化学品存放区、清洗剂使用区。',
    notice: '接触前应佩戴合适的防护装备。',
    sentenceSpanish: 'Atención, esta zona presenta riesgo cáustico.',
    sentenceChinese: '注意，该区域存在腐蚀性风险。'
  },
  {
    spanish: 'ATENCION ZONA DE CARGAS',
    chinese: '注意装卸/吊装区域',
    category: '警告标识',
    explanation: '用于提示该区域为货物装卸、起吊或载荷活动区域。',
    scene: '适用于仓储区、吊装区、货运区。',
    notice: '请勿在吊装或装卸作业范围内停留。',
    sentenceSpanish: 'Esta es una zona de cargas, manténgase alejado.',
    sentenceChinese: '这是装卸区域，请勿靠近停留。'
  },
  {
    spanish: 'ATENCION VEHICULOS INDUSTRIALES',
    chinese: '注意工业车辆',
    category: '警告标识',
    explanation: '用于提示该区域有叉车、工业运输车等车辆通行。',
    scene: '适用于仓储区、厂房通道、物流区域。',
    notice: '注意观察来车，按规定路线行走。',
    sentenceSpanish: 'Tenga cuidado con los vehículos industriales en circulación.',
    sentenceChinese: '请注意正在通行的工业车辆。'
  },
  {
    spanish: 'MATAFUEGOS',
    chinese: '灭火器',
    category: '消防标识',
    explanation: '用于标识灭火器所在位置，便于紧急情况下快速取用。',
    scene: '适用于厂房、办公区、施工现场和公共区域。',
    notice: '应保持灭火器前无遮挡，便于随时取用。',
    sentenceSpanish: 'En caso de emergencia, use el matafuegos más cercano.',
    sentenceChinese: '发生紧急情况时，请使用最近的灭火器。'
  },
  {
    spanish: 'NICHOS HIDRANTES',
    chinese: '消防栓箱 / 消火栓位置',
    category: '消防标识',
    explanation: '用于标识消防栓或消防水带设施所在位置。',
    scene: '适用于厂房、建筑物公共区域和消防设施点位。',
    notice: '消防设施前不得堆放杂物。',
    sentenceSpanish: 'Mantenga libre el acceso a los hidrantes.',
    sentenceChinese: '请保持消防栓通道畅通。'
  },
  {
    spanish: 'ABIERTO',
    chinese: '开启 / 营业中',
    category: '信息标识',
    explanation: '用于表示当前门店、窗口或区域处于开启状态。',
    scene: '适用于服务窗口、门店、办公区域入口。',
    notice: '结合现场状态理解其具体含义。',
    sentenceSpanish: 'El acceso está abierto en este momento.',
    sentenceChinese: '该区域当前处于开启状态。'
  },
  {
    spanish: 'CERRADO',
    chinese: '关闭 / 停止开放',
    category: '信息标识',
    explanation: '用于表示当前门店、窗口或区域处于关闭状态。',
    scene: '适用于服务窗口、门店、办公区域入口。',
    notice: '结合现场时间和管理规定理解其具体含义。',
    sentenceSpanish: 'El acceso está cerrado por ahora.',
    sentenceChinese: '该区域当前暂不开放。'
  },
  {
    spanish: 'OBLIGACION DE USAR GUANTES DE SEGURIDAD',
    aliases: ['OBLIGACION DE USAR GUANTES'],
    chinese: '必须佩戴安全手套',
    category: '强制防护标识',
    explanation: '表示进入该区域或进行该作业时必须佩戴安全手套。',
    scene: '适用于机械作业区、搬运区、化学品接触区。',
    notice: '作业前应检查手套是否完好。',
    sentenceSpanish: 'Antes de trabajar aquí, póngase guantes de seguridad.',
    sentenceChinese: '在这里作业前，请佩戴安全手套。'
  },
  {
    spanish: 'OBLIGACION DE USAR CASCO DE SEGURIDAD',
    aliases: ['USAR CASCO DE SEGURIDAD'],
    chinese: '必须佩戴安全帽',
    category: '强制防护标识',
    explanation: '表示进入该区域前必须佩戴安全帽。',
    scene: '适用于施工现场、高空作业区、吊装区域。',
    notice: '安全帽应正确佩戴并扣紧帽带。',
    sentenceSpanish: 'Es obligatorio usar casco de seguridad en esta zona.',
    sentenceChinese: '该区域必须佩戴安全帽。'
  },
  {
    spanish: 'OBLIGACION DE USAR PROTECCION RESPIRATORIA',
    aliases: ['USAR PROTECCION RESPIRATORIA'],
    chinese: '必须佩戴呼吸防护装备',
    category: '强制防护标识',
    explanation: '表示进入该区域或进行该作业时必须佩戴呼吸防护装备。',
    scene: '适用于粉尘区、喷涂区、化学品作业区。',
    notice: '应根据风险类型选择合适的呼吸防护设备。',
    sentenceSpanish: 'Debe usar protección respiratoria antes de entrar.',
    sentenceChinese: '进入前必须佩戴呼吸防护装备。'
  },
  {
    spanish: 'OBLIGACION DE USAR BARBIJO',
    chinese: '必须佩戴口罩',
    category: '强制防护标识',
    explanation: '表示该区域要求佩戴口罩或面部防护用品。',
    scene: '适用于粉尘区、卫生要求较高区域或特殊作业场景。',
    notice: '请按规范佩戴并确保遮住口鼻。',
    sentenceSpanish: 'Use barbijo correctamente en esta área.',
    sentenceChinese: '在该区域请规范佩戴口罩。'
  },
  {
    spanish: 'OBLIGACION DE USAR PROTECTORES AUDITIVOS',
    aliases: ['USAR PROTECTORES AUDITIVOS'],
    chinese: '必须佩戴听力防护器',
    category: '强制防护标识',
    explanation: '表示该区域噪声较大，必须佩戴耳塞或耳罩等听力防护用品。',
    scene: '适用于高噪声车间、设备运行区、施工机械附近。',
    notice: '进入前请确认防护器具佩戴到位。',
    sentenceSpanish: 'Es obligatorio usar protectores auditivos en esta zona.',
    sentenceChinese: '该区域必须佩戴听力防护器。'
  },
  {
    spanish: 'PELIGRO EXPLOSIVO',
    aliases: ['PELIGRO EXPLOSIVOS'],
    chinese: '爆炸危险',
    category: '危险标识',
    explanation: '用于提示该区域或物质存在爆炸危险。',
    scene: '适用于易燃易爆品存放区、压力容器区域等。',
    notice: '严禁明火，避免碰撞和违规操作。',
    sentenceSpanish: 'Existe peligro explosivo en esta área.',
    sentenceChinese: '该区域存在爆炸危险。'
  },
  {
    spanish: 'PELIGRO ALTA TENSION',
    aliases: ['ALTA TENSION', 'ALTO VOLTAJE'],
    chinese: '高压危险',
    category: '危险标识',
    explanation: '用于提示设备或区域存在高压电危险。',
    scene: '适用于变电设备、电力控制区、高压柜附近。',
    notice: '未经授权禁止靠近或操作。',
    sentenceSpanish: 'Hay peligro de alta tensión, no se acerque.',
    sentenceChinese: '此处有高压危险，请勿靠近。'
  },
  {
    spanish: 'PELIGRO PRODUCTOS TOXICOS',
    chinese: '有毒物品危险',
    category: '危险标识',
    explanation: '用于提示该区域存在有毒化学品或有毒物质。',
    scene: '适用于化学品仓库、实验区、危化品处理区。',
    notice: '应避免直接接触，并按要求做好防护。',
    sentenceSpanish: 'Tenga cuidado con los productos tóxicos en esta zona.',
    sentenceChinese: '请注意该区域的有毒物品。'
  },
  {
    spanish: 'PELIGRO RIESGO CAUSTICO',
    chinese: '腐蚀危险',
    category: '危险标识',
    explanation: '用于提示该区域存在腐蚀性物质或腐蚀伤害风险。',
    scene: '适用于酸碱作业区、清洗区、化学品区域。',
    notice: '作业时应佩戴防护手套、护目镜等防护用品。',
    sentenceSpanish: 'Existe riesgo cáustico, use el equipo de protección adecuado.',
    sentenceChinese: '存在腐蚀风险，请佩戴合适的防护装备。'
  },
{
  spanish: 'TESORERIA',
  chinese: '出纳处 / 财务处',
  category: '导向标识',
  explanation: '用于标识出纳、收费或财务办理区域。',
  scene: '适用于办公楼、服务大厅、行政区域。',
  notice: '请按现场流程办理业务。',
  sentenceSpanish: 'La tesorería está en esta dirección.',
  sentenceChinese: '出纳处在这个方向。'
},
{
  spanish: 'CONTADURIA',
  chinese: '会计部',
  category: '导向标识',
  explanation: '用于标识会计、账务或财务管理部门位置。',
  scene: '适用于办公区、行政楼、服务窗口。',
  notice: '请按功能分区前往对应办公室。',
  sentenceSpanish: 'La contaduría se encuentra en esta área.',
  sentenceChinese: '会计部位于这个区域。'
},
{
  spanish: 'CUENTAS CORRIENTES',
  chinese: '往来账户 / 活期账户业务',
  category: '导向标识',
  explanation: '用于标识账户、往来业务或相关办理窗口。',
  scene: '适用于银行、服务大厅、财务办理区域。',
  notice: '请根据窗口指引排队办理。',
  sentenceSpanish: 'Las cuentas corrientes se atienden aquí.',
  sentenceChinese: '往来账户业务在这里办理。'
},
{
  spanish: 'PAGO A PROVEEDORES',
  chinese: '供应商付款处',
  category: '导向标识',
  explanation: '用于标识供应商付款或结算办理区域。',
  scene: '适用于企业办公区、财务服务窗口。',
  notice: '请按规定时间和流程办理付款业务。',
  sentenceSpanish: 'El pago a proveedores se realiza en esta oficina.',
  sentenceChinese: '供应商付款业务在这个办公室办理。'
},
{
  spanish: 'ESPACIO CONFINADO',
  aliases: ['ESPACIOS CONFINADOS'],
  chinese: '受限空间',
  category: '危险标识',
  explanation: '用于提示该区域属于受限空间，进入前必须确认内部环境和安全条件。',
  scene: '适用于罐体、井下、密闭设备间、地下管廊等区域。',
  notice: '进入前必须检测气体、确认通风，并按规定办理作业许可。',
  sentenceSpanish: 'No entre al espacio confinado sin verificar la atmósfera interna.',
  sentenceChinese: '未经内部环境确认，不得进入受限空间。'
},
{
  spanish: 'NO INGRESAR SIN HABER VERIFICADO ATMOSFERA INTERNA',
  chinese: '未经确认内部空气环境，不得进入',
  category: '危险标识',
  explanation: '用于提醒进入前必须先检测内部空气或气体环境是否安全。',
  scene: '适用于受限空间、储罐、井道、密闭区域等。',
  notice: '必须按规范检测氧气、有毒气体和可燃气体。',
  sentenceSpanish: 'Antes de entrar, verifique la atmósfera interna del lugar.',
  sentenceChinese: '进入前必须先确认内部空气环境是否安全。'
},
{
  spanish: 'RESIDUOS PELIGROSOS',
  chinese: '危险废弃物',
  category: '废弃物分类标识',
  explanation: '表示该容器或区域用于收集危险废弃物。',
  scene: '适用于化学品区、维修区、污染物暂存点。',
  notice: '不得与普通垃圾混投，应按危险废弃物规范处理。',
  sentenceSpanish: 'Los residuos peligrosos deben colocarse en este contenedor.',
  sentenceChinese: '危险废弃物应投放到这个容器中。'
},
{
  spanish: 'RESIDUOS PLASTICOS',
  chinese: '塑料废弃物',
  category: '废弃物分类标识',
  explanation: '表示该容器专门用于收集塑料类废弃物。',
  scene: '适用于生活区、材料回收点、办公区。',
  notice: '请勿混入有机垃圾、玻璃或危险废弃物。',
  sentenceSpanish: 'Los residuos plásticos deben depositarse aquí.',
  sentenceChinese: '塑料废弃物应投放到这里。'
},
{
  spanish: 'RESIDUOS COMUNES',
  chinese: '普通废弃物',
  category: '废弃物分类标识',
  explanation: '表示该容器用于收集一般生活垃圾或普通废弃物。',
  scene: '适用于生活区、办公区、公共区域。',
  notice: '请不要混入危险废弃物和可单独回收物。',
  sentenceSpanish: 'Los residuos comunes deben depositarse en este contenedor.',
  sentenceChinese: '普通废弃物应投放到这个容器中。'
},
{
  spanish: 'OBLIGACION DE USAR CALZADO DE SEGURIDAD',
  aliases: ['USAR CALZADO DE SEGURIDAD'],
  chinese: '必须穿安全鞋',
  category: '强制防护标识',
  explanation: '表示进入该区域或进行该作业时必须穿戴安全鞋。',
  scene: '适用于施工现场、仓储区、机械作业区。',
  notice: '安全鞋应符合防砸、防滑等要求。',
  sentenceSpanish: 'Es obligatorio usar calzado de seguridad en esta zona.',
  sentenceChinese: '该区域必须穿安全鞋。'
},
{
  spanish: 'NO CONECTAR ELECTRICISTA TRABAJANDO',
  aliases: ['NO CONECTAR'],
  chinese: '禁止送电，电工正在作业',
  category: '锁定挂牌标识',
  explanation: '用于提示设备当前处于检修或带电作业状态，禁止接通电源。',
  scene: '适用于电气检修、设备维护、断电作业场景。',
  notice: '未得到许可不得擅自送电或操作开关。',
  sentenceSpanish: 'No conecte la energía, hay un electricista trabajando.',
  sentenceChinese: '禁止送电，电工正在作业。'
},
{
  spanish: 'NO TOCAR',
  chinese: '禁止触碰',
  category: '警告标识',
  explanation: '用于提示设备、部件或区域禁止触碰，以防造成危险或设备损坏。',
  scene: '适用于运行设备、高温表面、危险部件附近。',
  notice: '请勿擅自触碰设备或装置。',
  sentenceSpanish: 'No toque este equipo.',
  sentenceChinese: '请不要触碰这个设备。'
},
{
  spanish: 'EQUIPO DEFECTUOSO',
  chinese: '设备故障',
  category: '设备状态标识',
  explanation: '用于标识设备当前存在故障，不可正常使用。',
  scene: '适用于机械设备、电气设备、工具设备。',
  notice: '故障设备应停止使用并及时报修。',
  sentenceSpanish: 'Este equipo está defectuoso y no debe utilizarse.',
  sentenceChinese: '该设备已故障，不得继续使用。'
},
{
  spanish: 'EN REPARACION',
  chinese: '维修中',
  category: '设备状态标识',
  explanation: '用于标识设备当前正在维修或保养中。',
  scene: '适用于机械设备、电气设备、维护区域。',
  notice: '维修期间禁止擅自启动或操作设备。',
  sentenceSpanish: 'El equipo está en reparación.',
  sentenceChinese: '设备正在维修中。'
},
{
  spanish: 'NO PONER EN MARCHA',
  chinese: '禁止启动',
  category: '锁定挂牌标识',
  explanation: '用于提示设备当前不得启动，通常用于维修或检修状态。',
  scene: '适用于机械检修、电气维护、停机保养场景。',
  notice: '启动前必须确认维修工作已经结束。',
  sentenceSpanish: 'No ponga en marcha este equipo.',
  sentenceChinese: '请勿启动该设备。'
},
{
  spanish: 'FUERA DE SERVICIO',
  chinese: '停止使用 / 已停用',
  category: '设备状态标识',
  explanation: '用于表示设备、设施或装置当前不在服务状态，不能使用。',
  scene: '适用于电梯、设备、公共设施或维修装置。',
  notice: '请勿继续使用已停用设备。',
  sentenceSpanish: 'Este equipo está fuera de servicio.',
  sentenceChinese: '该设备当前已停用。'
},
{
  spanish: 'NO TOCAR ESTA VALVULA',
  chinese: '禁止触碰此阀门',
  category: '警告标识',
  explanation: '用于提示现场人员不得操作或触碰该阀门。',
  scene: '适用于管道系统、气体设备、化学品装置。',
  notice: '未经授权不得擅自开启、关闭或调整阀门。',
  sentenceSpanish: 'No toque esta válvula.',
  sentenceChinese: '请不要触碰这个阀门。'
},
{
  spanish: 'NO OBSTRUIR ELEMENTOS CONTRA INCENDIOS',
  aliases: ['NO OBSTRUIR ELEMENTOS DE INCENDIO'],
  chinese: '禁止遮挡消防设施',
  category: '消防标识',
  explanation: '用于提示灭火器、消防栓、消防箱等设施前方不得堆放物品。',
  scene: '适用于消防设施周边、仓储区、公共区域。',
  notice: '应始终保持消防设施取用通道畅通。',
  sentenceSpanish: 'No obstruya los elementos contra incendios.',
  sentenceChinese: '请勿遮挡消防设施。'
},
{
  spanish: 'RIESGO ELECTRICO',
  chinese: '触电风险 / 电气危险',
  category: '警告标识',
  explanation: '用于提示该区域存在电气危险或触电风险。',
  scene: '适用于配电箱、电气设备、施工电源附近。',
  notice: '非专业人员禁止靠近或操作。',
  sentenceSpanish: 'Existe riesgo eléctrico en esta zona.',
  sentenceChinese: '该区域存在电气危险。'
},
{
  spanish: 'TELEFONOS LINEA DE EMERGENCIA',
  aliases: ['TELEFONOS DE EMERGENCIA'],
  chinese: '紧急联系电话',
  category: '信息标识',
  explanation: '用于提供事故、火警、安保或医疗等紧急联系方式。',
  scene: '适用于施工现场、办公区、公共场所。',
  notice: '发生紧急情况时应按流程及时联系相关部门。',
  sentenceSpanish: 'En caso de emergencia, consulte estos teléfonos.',
  sentenceChinese: '发生紧急情况时，请查看这些联系电话。'
},
{
  spanish: 'NO INTRODUCIR LA MANO CON EL EQUIPO EN FUNCIONAMIENTO',
  aliases: [
    'PELIGRO NO INTRODUCIR LA MANO CON EL EQUIPO EN FUNCIONAMIENTO',
    'NO INTRODUCIR LA MANO',
    'EQUIPO EN FUNCIONAMIENTO'
  ],
  chinese: '设备运行时禁止将手伸入',
  category: '危险/禁止操作标识',
  explanation: '用于警示设备运行过程中，禁止将手伸入设备工作区域，以防发生夹伤、卷入或切伤事故。',
  scene: '适用于传送装置、旋转部件、机械加工设备、切割设备等运行区域。',
  notice: '设备运行时不得将手伸入内部；检修前应先停机、断电并确认设备已停止。',
  sentenceSpanish: 'No introduzca la mano mientras el equipo esté en funcionamiento.',
  sentenceChinese: '设备运行时请勿将手伸入。'
}
]

const normalizeText = (text: string) => {
  return text
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[-_/]/g, ' ')
    .replace(/[^\w\s]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
}

const getCurrentModelInfoForAI = (): string => {
  const settings = getSettings()

  if (!settings) {
    throw new Error('未找到 AI 设置信息，请先在设置页配置模型')
  }

  const settingsData = JSON.parse(settings)
  const providers = settingsData.providers || {}

  for (const providerId of Object.keys(providers)) {
    const provider = providers[providerId]
    if (provider?.enabled && provider?.defaultModel) {
      return `${providerId}/${provider.defaultModel}`
    }
  }

  throw new Error('未找到可用的 AI 提供商或默认模型')
}

const extractJsonFromAIResponse = (rawText: string) => {
  const cleaned = rawText
    .replace(/```json/gi, '')
    .replace(/```/g, '')
    .trim()

  const firstBrace = cleaned.indexOf('{')
  const lastBrace = cleaned.lastIndexOf('}')

  if (firstBrace === -1 || lastBrace === -1 || lastBrace <= firstBrace) {
    throw new Error('AI 返回内容不是有效 JSON')
  }

  return cleaned.slice(firstBrace, lastBrace + 1)
}

const findKnowledgeMatch = (ocrRawText: string): DemoResult | null => {
  const normalizedOcr = normalizeText(ocrRawText)

  for (const item of signKnowledgeBase) {
    const candidates = [item.spanish, ...(item.aliases || [])]

    for (const candidate of candidates) {
      const normalizedCandidate = normalizeText(candidate)

      if (
        normalizedOcr.includes(normalizedCandidate) ||
        normalizedCandidate.includes(normalizedOcr)
      ) {
        return {
          spanish: item.spanish,
          chinese: item.chinese,
          category: item.category,
          explanation: item.explanation,
          scene: item.scene,
          notice: item.notice,
          sentenceSpanish: item.sentenceSpanish,
          sentenceChinese: item.sentenceChinese,
          source: 'knowledge_base'
        }
      }
    }
  }

  return null
}

const translateByAI = async (text: string): Promise<DemoResult> => {
  const currentModelInfo = getCurrentModelInfoForAI()

  const prompt = `
你是一个工程现场西语标识解析助手。

请把下面这段西班牙语标识文本整理为一个 JSON 对象。
不要输出 markdown，不要输出解释性文字，不要加代码块，只返回 JSON。

JSON 字段必须严格为：
{
  "spanish": "标准化后的西语标识文本",
  "chinese": "中文翻译",
  "category": "标识类别",
  "explanation": "术语解释",
  "scene": "适用场景",
  "notice": "注意事项",
  "sentenceSpanish": "相关学习句（西语）",
  "sentenceChinese": "对应中文"
}

要求：
1. 内容要贴合工程现场、安全标识、设备提示语场景
2. 如果文本本身是警示句，就按警示标识理解
3. 输出必须是合法 JSON
4. 不要包含多余字段

待处理文本：
${text}
  `.trim()

  try {
    const responseText = await callOpenAI({
      text: prompt,
      currentModelInfo,
      requestType: RequestType.CHAT
    })

    const jsonText = extractJsonFromAIResponse(responseText)
    const data = JSON.parse(jsonText)

    return {
      spanish: data.spanish || text,
      chinese: data.chinese || '暂无翻译',
      category: data.category || 'AI临时结果',
      explanation: data.explanation || '暂无解释',
      scene: data.scene || '待AI补充',
      notice: data.notice || '请结合现场规范进行判断。',
      sentenceSpanish: data.sentenceSpanish || 'Esta señal requiere interpretación adicional.',
      sentenceChinese: data.sentenceChinese || '该标识需要进一步解释。',
      source: 'ai'
    }
  } catch (error) {
    console.error('AI兜底解析失败：', error)

    return {
      spanish: text,
      chinese: 'AI 返回格式异常，暂未成功解析',
      category: 'AI临时结果',
      explanation: '当前文本未命中知识库，且 AI 返回内容无法解析为结构化 JSON。',
      scene: '待AI补充',
      notice: '建议检查模型配置、提示词或返回格式。',
      sentenceSpanish: 'Esta señal aún requiere revisión manual.',
      sentenceChinese: '该标识目前仍需要人工确认。',
      source: 'ai'
    }
  }
}

const extractSpanishText = async () => {
  if (!selectedFile.value) return ''

  const settings = getSettings()
  if (!settings) {
    throw new Error('未找到设置，请先在设置页配置百度 OCR')
  }

  const settingsData = JSON.parse(settings)
  const apiKey = settingsData.baiduOcr?.apiKey || ''
  const secretKey = settingsData.baiduOcr?.secretKey || ''

  if (!apiKey || !secretKey) {
    throw new Error('请先在设置页填写百度 OCR 的 API Key 和 Secret Key')
  }

  const imageBase64 = await fileToBase64WithoutPrefix(selectedFile.value)
  const ocrResult = await recognizeImageByBaiduOcr(imageBase64, apiKey, secretKey)
  return ocrResult?.text ?? ''
}

const goBack = () => {
  router.back()
}

const triggerSelectImage = () => {
  fileInputRef.value?.click()
}

const handleFileChange = (event: Event) => {
  const target = event.target as HTMLInputElement
  const file = target.files?.[0]

  if (!file) return

  selectedFile.value = file
  selectedFileName.value = file.name
  selectedImageUrl.value = URL.createObjectURL(file)
  ocrText.value = ''
  errorMessage.value = ''
  result.value = null
}

const runRecognition = async () => {
  if (!selectedImageUrl.value) return

  errorMessage.value = ''
  ocrText.value = ''
  result.value = null

  try {
    const extractedText = await extractSpanishText()
    ocrText.value = extractedText

    if (!extractedText.trim()) {
      result.value = {
        spanish: 'texto no identificado',
        chinese: '未识别到有效西语文本',
        category: '未匹配',
        explanation: '当前图片中未提取到足够清晰的西语文字。',
        scene: '请尝试上传更清晰、文字更完整的图片。',
        notice: '建议确保图片清晰、无遮挡、无明显倾斜。',
        sentenceSpanish: 'Por favor, vuelva a tomar una foto más clara.',
        sentenceChinese: '请重新拍摄或选择更清晰的图片。',
        source: 'knowledge_base'
      }
      return
    }

    const matched = findKnowledgeMatch(extractedText)
    if (matched) {
      result.value = matched
      return
    }

    // 当前先用函数，后面再接真 AI
    const aiResult = await translateByAI(extractedText)
    result.value = aiResult
  } catch (error) {
    console.error('OCR识别失败原始错误：', error)
    errorMessage.value = `识别失败：${String(error)}`
  }
}

const resetAll = () => {
  selectedFile.value = null
  selectedImageUrl.value = ''
  selectedFileName.value = ''
  ocrText.value = ''
  errorMessage.value = ''
  result.value = null

  if (fileInputRef.value) {
    fileInputRef.value.value = ''
  }
}
</script>

<style scoped>
.scan-page {
  height: 100%;
  min-height: 0;
  display: flex;
  flex-direction: column;
  background: var(--app-page-bg);
}

.scan-header {
  display: flex;
  align-items: center;
  padding: 20px;
  background: var(--app-header-bg);
  border-bottom: 1px solid var(--app-border-color);
}

.header-left {
  display: flex;
  align-items: center;
  gap: 12px;
}

.page-title {
  font-size: 20px;
  font-weight: 700;
  color: var(--app-title-color);
}

.scan-content {
  flex: 1;
  min-height: 0;
  overflow-y: auto;
  padding: 20px 20px 110px;
  box-sizing: border-box;
  -webkit-overflow-scrolling: touch;
}

.scan-card {
  background: var(--app-card-bg);
  border: 1px solid var(--app-border-color);
  border-radius: 12px;
  padding: 20px;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.06);
}

.scan-card h3 {
  margin: 0 0 12px 0;
  font-size: 18px;
  color: var(--app-title-color);
}

.scan-card p {
  margin: 0 0 20px 0;
  color: var(--app-text-color);
  line-height: 1.6;
}

.upload-actions {
  display: flex;
  flex-wrap: wrap;
  gap: 12px;
  margin-bottom: 20px;
}

.hidden-input {
  display: none;
}

.preview-section,
.result-section {
  margin-top: 20px;
}

.preview-section h4,
.result-section h4 {
  margin-bottom: 12px;
  font-size: 16px;
  color: var(--app-title-color);
}

.preview-image {
  width: 100%;
  max-width: 360px;
  border-radius: 12px;
  border: 1px solid var(--app-border-color);
  display: block;
  margin-bottom: 10px;
}

.file-name {
  color: var(--app-text-color);
  font-size: 14px;
}

.result-item {
  padding: 14px 16px;
  border-radius: 10px;
  background: var(--app-page-bg);
  margin-bottom: 12px;
  border: 1px solid var(--app-border-color);
}

.result-label {
  font-size: 13px;
  color: var(--app-text-color);
  margin-bottom: 6px;
}

.result-value {
  font-size: 16px;
  color: var(--app-text-color);
  line-height: 1.6;
}

.empty-tip {
  margin-top: 24px;
  color: var(--app-text-color);
  font-size: 14px;
}

.ocr-text-section {
  margin-top: 20px;
}

.ocr-text-section h4 {
  margin-bottom: 12px;
  font-size: 16px;
  color: var(--app-title-color);
}

.ocr-text-box {
  padding: 14px 16px;
  border-radius: 10px;
  background: var(--app-page-bg);
  border: 1px solid var(--app-border-color);
  color: var(--app-text-color);
  line-height: 1.8;
  white-space: pre-wrap;
}

.error-tip {
  margin-top: 16px;
  padding: 12px 14px;
  border-radius: 10px;
  background: #fff1f2;
  border: 1px solid #fecdd3;
  color: #be123c;
  line-height: 1.6;
}

@media (max-width: 600px) {
  .scan-header {
    padding: 12px 16px;
  }

  .scan-content {
    padding: 12px 16px;
  }

  .page-title {
    font-size: 16px;
  }

  .upload-actions {
    flex-direction: column;
  }

  .preview-image {
    max-width: 100%;
  }
}
</style>