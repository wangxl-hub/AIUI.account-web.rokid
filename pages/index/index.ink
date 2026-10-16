<script def>
{
  "navigationBarTitleText": "小绿 · AI眼镜具象化助手"
}
</script>

<script setup>
function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }

const STORAGE_KEY = 'xiaolv_state_v1';
const DEFAULT_STATE = {
  name: '小绿',
  satiety: 80,
  mood: 80,
  energy: 80,
  intimacy: 10,
  level: 1,
  exp: 0,
  race: 0,
  lastUpdate: 0,
  born: 0,
  day: '',
  loginDone: false,
  standCount: 0,
  scheduleCount: 0,
  qaCount: 0,
  companionDone: false,
  weatherDone: false,
  streak: 0,
};

/* ===== 角色视觉系统：8x8 像素矩阵，三层明度 =====
   █ = 亮绿(#00ff88)   ░ = 中绿(#00aa55)   空格 = 灭
   形态取自设计稿 2.1 基础形态 + 2.2 表情状态库（开心/警觉/思考/困倦/打招呼/惊讶）
   多色渲染：splitRows() 将每行拆为 bright(█/▓) 和 mid(░) 两组字符串，
   模板用两个 text 叠放 position:absolute 分别着色 #00ff88 / #00aa55 */
const BASE = [
  "  ░██░  ",
  " ░████░ ",
  "░██████░",
  "██    ██",
  "███  ███",
  "░██████░",
  " ░█░░█░ ",
  "  ░  ░  "
];
const AVATAR = {
  idle:      BASE,
  happy:     ["  ░██░  ", " ░████░ ", "░██████░", "██ ██ ██", "██ ██ ██", "░██████░", " ░█░░█░ ", "  ░  ░  "],
  alert:     ["  ░██░  ", " ░████░ ", "░██████░", "█  ██  █", "███  ███", "░██████░", " ░█░░█░ ", "  ░  ░  "],
  thinking:  ["  ░██░  ", " ░████░ ", "░██████░", "█ █  █ █", "████████", "░██████░", " ░█░░█░ ", "  ░  ░  "],
  sleepy:    ["  ░░░░  ", " ░████░ ", "░██████░", "███  ███", "████████", "░██████░", "  ░  ░  ", "        "],
  wave:      ["  ░██░  ", " ░████░ ", "░██████░", " █    ██", " ██  ███", "░██████░", " ░█░░█░ ", "  ░  ░  "],
  surprised: ["  ░██░  ", " ░████░ ", "░██████░", "█      █", "██ ██ ██", "░██████░", " ░█░░█░ ", "  ░  ░  "],
};
// 设计稿 7.2：Lv10+ 解锁种族切换（小人 / 小动物 / 小机器人）
const RACES = [
  { key: 'human', label: '像素小人', rows: null },
  { key: 'beast', label: '小动物', rows: ["  ░  ░  ", " ░████░ ", "░██████░", "██ ██ ██", "░██████░", " ██  ██ ", " ░█  █░ ", " ░    ░ "] },
  { key: 'robot', label: '小机器人', rows: ["  ████  ", " █    █ ", "█ ████ █", "█ █  █ █", "█      █", "░██████░", " ░█  █░ ", " ░████░ "] },
];
// 设计稿 7.2：Lv4-6 配饰解锁（帽子 / 围巾 / 背包），每级 1 件
const ACCESSORY = {
  4: { name: '小绿帽', apply: function (m) { var r = m.slice(); r[0] = " ██████ "; return r; } },
  5: { name: '围巾',   apply: function (m) { var r = m.slice(); r[4] = "░██████░"; return r; } },
  6: { name: '背包',   apply: function (m) { var r = m.slice(); r[3] = r[3].substring(0, 6) + "██"; r[4] = r[4].substring(0, 6) + "░░"; return r; } },
};

function avatarRows(expr, level, race) {
  var r = (RACES[race] && RACES[race].rows) ? RACES[race].rows.slice() : (AVATAR[expr] || AVATAR.idle).slice();
  // Lv7-10 进化：体型变化 + 暗绿变体（用 ▓ 表达厚重实心块）
  if (level >= 7 && race === 0) {
    for (var i = 0; i < r.length; i++) r[i] = r[i].replace(/█/g, '▓');
  }
  // 配饰叠加
  for (var lv = 4; lv <= Math.min(6, level); lv++) {
    if (ACCESSORY[lv]) r = ACCESSORY[lv].apply(r);
  }
  return r;
}
function avatarStr(expr, level, race) { return avatarRows(expr, level, race).join('\n'); }

/* splitRows：将矩阵拆为 bright 和 mid 两组字符串
   bright 行中 ░/空格 替换为空格（只保留 █▓），mid 行中 █▓ 替换为空格（只保留 ░）
   模板用两个 text position:absolute 叠放，分别着色 #00ff88 / #00aa55 */
function splitRows(rows) {
  var bright = [], mid = [];
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i];
    /* WXSS 禁用 white-space：\n 与连续空格会被折叠成一行（实测 8 行塌成 4 行 / 44px）。
       对策：①每行独立元素（模板 8 个 text）②空格全部换成不换行空格 U+00A0（等宽且不被折叠）。 */
    bright.push(row.replace(/░/g, ' ').replace(/ /g, '\u00a0'));
    mid.push(row.replace(/[█▓]/g, ' ').replace(/ /g, '\u00a0'));
  }
  return { bright: bright, mid: mid };
}
function splitAvatar(expr, level, race) {
  return splitRows(avatarRows(expr, level, race));
}

function faceForExpr(expr) {
  switch (expr) {
    case 'happy': return '(^_^)';
    case 'alert': return '(o_o)';
    case 'thinking': return '(~_~)?';
    case 'sleepy': return '(-_-)z';
    case 'wave': return '(^_^)/';
    case 'surprised': return '(o_o)!';
    default: return '(._.)';
  }
}
function exprLabelOf(expr) {
  switch (expr) {
    case 'happy': return '开心';
    case 'alert': return '警觉';
    case 'thinking': return '思考';
    case 'sleepy': return '困倦';
    case 'wave': return '打招呼';
    case 'surprised': return '惊讶';
    default: return '待机';
  }
}
/* 设计稿 2.2 表情状态库 -- 每种表情绑定专属动画
   WXSS 不支持 animation/@keyframes，改用 JS setInterval 驱动 transform/opacity
   - 待机   呼吸 opacity 0.9->1.0
   - 开心   跳跃 translateY 0->-8px->0
   - 警觉   摇晃 translateX +/-3px
   - 思考   倾斜 rotate(-5deg)
   - 困倦   下沉 translateY(4px) + 呼吸
   - 惊讶   静态定格 */
function animForExpr(expr) {
  switch (expr) {
    case 'happy': return 'bounce';
    case 'wave': return 'bounce';
    case 'alert': return 'shake';
    case 'thinking': return 'think';
    case 'sleepy': return 'sleep';
    case 'surprised': return 'still';
    default: return 'breathe';
  }
}
// 设计稿 7.2 成长路线图
function rankOf(level) {
  if (level >= 10) return '自由期·种族切换';
  if (level >= 7) return '进化期·体型进化';
  if (level >= 4) return '成长期·配饰解锁';
  return '初始期·基础形态';
}
function unlockOf(level) {
  if (level >= 10) return '解锁种族切换：小人 / 小动物 / 小机器人';
  if (level >= 7) return '解锁：体型进化 + 暗绿配色变体 + 打招呼表情';
  if (level >= 4) return '解锁：' + (ACCESSORY[Math.min(6, level)] ? ACCESSORY[Math.min(6, level)].name : '配饰') + ' + 惊讶/困倦表情';
  return '成长中：再升 ' + Math.max(1, 4 - level) + ' 级解锁配饰';
}
// 表情按等级解锁（Lv1-3 三种基础表情）
function exprUnlocked(expr, level) {
  if (expr === 'happy' || expr === 'alert' || expr === 'thinking' || expr === 'idle') return true;
  if (expr === 'surprised' || expr === 'sleepy') return level >= 4;
  if (expr === 'wave') return level >= 7;
  return true;
}

function todayStr() {
  var d = new Date();
  return d.getFullYear() + '-' + (d.getMonth() + 1) + '-' + d.getDate();
}
function hourOf() { return new Date().getHours(); }

function load() {
  try {
    var wxs = (typeof wx !== 'undefined') ? wx : null;
    if (wxs && wxs.getStorageSync) {
      var s = wxs.getStorageSync(STORAGE_KEY);
      if (s && s.name) {
        var st = Object.assign({}, DEFAULT_STATE, s);
        if (st.day !== todayStr()) {
          st.day = todayStr();
          st.loginDone = false; st.standCount = 0; st.scheduleCount = 0;
          st.qaCount = 0; st.companionDone = false; st.weatherDone = false;
        }
        return st;
      }
    }
  } catch (e) {}
  var now = Date.now();
  return Object.assign({}, DEFAULT_STATE, { lastUpdate: now, born: now, day: todayStr() });
}
function save(state) {
  try {
    var wxs = (typeof wx !== 'undefined') ? wx : null;
    if (wxs && wxs.setStorageSync) wxs.setStorageSync(STORAGE_KEY, state);
  } catch (e) {}
}
function decay(state) {
  var now = Date.now(), last = state.lastUpdate || now;
  var minutes = Math.max(0, (now - last) / 60000);
  state.satiety = clamp(state.satiety - minutes * 0.6, 0, 100);
  state.energy = clamp(state.energy - minutes * 0.4, 0, 100);
  state.mood = clamp(state.mood - minutes * 0.25, 0, 100);
  state.lastUpdate = now;
  return state;
}
// 设计稿 7.1：Lv1->2 需 100 EXP，每级递增 50
function expThreshold(level) { return 100 + (level - 1) * 50; }
function addExp(state, n) {
  state.exp += n;
  var leveled = false;
  while (state.exp >= expThreshold(state.level)) {
    state.exp -= expThreshold(state.level);
    state.level += 1;
    leveled = true;
  }
  return leveled;
}
function bar(v) {
  var n = Math.round(clamp(v, 0, 100) / 10);
  return '█'.repeat(n) + '░'.repeat(10 - n);
}
function expBar(state) {
  var need = expThreshold(state.level);
  var n = Math.round(clamp(state.exp / need, 0, 1) * 10);
  return '█'.repeat(n) + '░'.repeat(10 - n);
}
function pick(arr) { return arr[Math.floor(Math.random() * arr.length)]; }

/* 演示数据源：早安/日程/久坐/天气四类场景的静态展示文案。
   TODO: 替换为设备端真实数据（天气 API / 日历事件 / IMU 静止检测），
   保留字段结构（title/main/unit/line1/line2/timeline）即可无缝接入。 */
var MOCK = {
  morning: { title: '早上好！', main: '28° 晴', unit: '今日概览', line1: '日程：3 场会议 · 下一场 10:00 周会', line2: '降雨概率 10% · 紫外线中等', timeline: '09:00[~] -> 14:00[~] -> 18:00[!]' },
  schedule: { title: '日程！', main: '10', unit: 'min 后开始', line1: '09:42 周度复盘会', line2: '3 号会议室 · 6 人', timeline: 'T-10min 跑入 -> T-1min 跳动 -> T-0 挥手告别' },
  sedentaryAlert: { title: '久坐了！', main: '52', unit: 'min 未活动', line1: '站起来活动一下吧', line2: 'IMU 检测：静止时长阈值 50 min', timeline: '' },
  sedentaryStand: { title: '站起来啦！', main: '已站立', unit: '反馈闭环：站立 >=10 秒', line1: '刚才静坐 52 min', line2: '', timeline: '' },
  weather: { title: '下雨啦！', main: '2 小时后有雨', unit: '预警类型：降雨', line1: '建议：记得带伞', line2: '降温 6° · 东南风 3 级', timeline: '13:00 [~] -> 14:00 [!] -> 16:00 [~]' },
};

/* ===== 定位意图识别 + 获取（aiui-dev skill geolocation.md / navigator.md） =====
   navigator.geolocation.getCurrentPosition(success, error?, options?)
   运行时事实库确认 Geolocation 接口存在、GEOLOCATION 权限 supported=true
   定位失败/超时/不可用时返回 null 降级，不阻塞主流程 */

// 意图识别：判断问题是否需要获取定位
function needsLocation(text) {
  return /(天气|下雨|降雨|带伞|降温|气温|温度|大风|热不热|冷不冷|穿什么|附近|周边|最近|哪里有|哪家|周围|旁边|怎么走|导航|路线|多远|在哪|地址)/.test(text);
}

// 获取定位：返回 Promise<coords|null>，8 秒超时降级
function getLocation() {
  return new Promise(function (resolve) {
    var resolved = false;
    function done(val) { if (!resolved) { resolved = true; resolve(val); } }
    try {
      if (typeof navigator === 'undefined' || !navigator.geolocation || typeof navigator.geolocation.getCurrentPosition !== 'function') {
        done(null); return;
      }
      // 超时兜底：8 秒后强制降级
      var timer = setTimeout(function () { done(null); }, 8000);
      navigator.geolocation.getCurrentPosition(
        function (position) {
          clearTimeout(timer);
          if (position && position.coords) {
            done({ latitude: position.coords.latitude, longitude: position.coords.longitude });
          } else {
            done(null);
          }
        },
        function (error) {
          clearTimeout(timer);
          console.error('[getLocation] 定位失败:', error && error.code, error && error.message);
          done(null);
        },
        { enableHighAccuracy: true, timeout: 8000, maximumAge: 60000 }
      );
    } catch (e) {
      console.error('[getLocation] 异常:', e && (e.message || String(e)));
      done(null);
    }
  });
}

/* ===== 设计稿 5.1 三种交互层级 ===== */
var L1 = 'L1 感知层';
var L2 = 'L2 通知层';
var L3 = 'L3 互动层';

// 思考超时：灵珠首条 content 超过该时长未到达则断连并提示重新提问（真机联调后可酌情放宽）
var THINK_TIMEOUT_MS = 15000;

export default {
  data: {
    // 多色像素矩阵：bright(█▓) 和 mid(░) 两组叠放
    avatarBright0: splitAvatar('idle', 1, 0).bright[0], avatarBright1: splitAvatar('idle', 1, 0).bright[1], avatarBright2: splitAvatar('idle', 1, 0).bright[2], avatarBright3: splitAvatar('idle', 1, 0).bright[3], avatarBright4: splitAvatar('idle', 1, 0).bright[4], avatarBright5: splitAvatar('idle', 1, 0).bright[5], avatarBright6: splitAvatar('idle', 1, 0).bright[6], avatarBright7: splitAvatar('idle', 1, 0).bright[7],
    avatarMid0: splitAvatar('idle', 1, 0).mid[0], avatarMid1: splitAvatar('idle', 1, 0).mid[1], avatarMid2: splitAvatar('idle', 1, 0).mid[2], avatarMid3: splitAvatar('idle', 1, 0).mid[3], avatarMid4: splitAvatar('idle', 1, 0).mid[4], avatarMid5: splitAvatar('idle', 1, 0).mid[5], avatarMid6: splitAvatar('idle', 1, 0).mid[6], avatarMid7: splitAvatar('idle', 1, 0).mid[7],
    face: '(._.)',
    animKind: 'breathe',
    avatarOpacity: 1.0,
    avatarTransform: '',
    dotsOn: 'off',
    name: '小绿',
    level: 1,
    rank: '初始期·基础形态',
    exprLabel: '待机',
    expText: '0 / 100',
    expBar: '░░░░░░░░░░',
    // 卡片区（设计稿 6.1 卡片类型）
    layerText: L1,
    cardTitle: '',
    cardMain: '小绿在呢',
    cardUnit: '',
    cardLine1: '',
    cardLine2: '',
    cardTimeline: '',
    cardTip: '',
    cardClass: 'status',
    bubble: '',
    bars: '',
    btnA: '早安', btnB: '日程', btnC: '久坐',
    btnD: '天气', btnE: '问答', btnF: '陪我',
    btnG: '确认', btnH: '换表情', btnI: '重置',
    hint: '语音：早安 / 日程 / 天气 / 陪我 / 状态',
  },
  acts: [],
  _timer: null,
  _animTimer: null,
  _animExpr: 'idle',
  _animStep: 0,
  _recognition: null,
  _asrTimeout: null,
  _interruptTimer: null,
  _listening: false,
  _agentId: '7695229372914991104',
  _agentConversationId: null,
  _api: null,
  _fallbackTimers: [],
  _thinkTimer: null,
  _thinkCounter: null,
  _thinkStarted: false,
  _thinkSeconds: 0,
  _eventSource: null,
  _llmFallbackTimer: null,
  onLoad() {
    this.acts = ['morning', 'schedule', 'sedentary', 'weather', 'qa', 'companion', 'confirm', 'cycleExpr', 'reset'];
    this.toIdle(true);
    this.startAmbient();
    this.startAnim();
    // 启用环境感知：接收语音唤醒 + 头部动作回调（events.md 文档依据）
    // enableWorldAwareness 是 Page-only，有 try/catch 兜底
    try { this.enableWorldAwareness(); } catch (e) {}
  },
  onShow() { this.refresh(); },
  onUnload() {
    this.stopAmbient();
    this.stopAnim();
    this.stopRecognition();
    this.clearAsrTimeout();
    if (this._interruptTimer) { clearTimeout(this._interruptTimer); this._interruptTimer = null; }
    if (this._fallbackTimers) { this._fallbackTimers.forEach(function (t) { clearTimeout(t); }); this._fallbackTimers = []; }
    if (this._llmFallbackTimer) { clearTimeout(this._llmFallbackTimer); this._llmFallbackTimer = null; }
    this.clearThinkTimers();
    this.closeEventSource();
  },
  // 清除思考超时和计时的辅助方法
  clearThinkTimers() {
    if (this._thinkTimer) { clearTimeout(this._thinkTimer); this._thinkTimer = null; }
    if (this._thinkCounter) { clearInterval(this._thinkCounter); this._thinkCounter = null; }
  },
  // 关闭 EventSource 并释放引用
  closeEventSource() {
    try {
      if (this._eventSource && typeof this._eventSource.close === 'function') {
        this._eventSource.close();
      }
    } catch (e) {}
    this._eventSource = null;
  },
  /* ===== ASR 语音识别通道（references/apis/ai.md: SpeechRecognition） =====
     onVoiceWakeup 是宿主唤醒信号回调，不自动建立 ASR 通道。
     需主动创建 SpeechRecognition 实例并调用 start() 建立通道。
     start() 必须在 InkView 交互状态下调用（onVoiceWakeup / bindtap 均满足）。
     onresult 接收识别结果，提取 transcript 调用 handleInput 路由。

     语音输入等待：startRecognition 后设 10 秒超时定时器，
     onresult 触发时清除超时；超时未触发则播报"没有听太清"并回 idle。
     此阶段不启动思考计时器。
     语音打断：用户说"小绿小绿"时，先 abort 当前 ASR + cancel 语音播报，
     播报"我在呢，你请说"，再重启 ASR 等待下一轮输入。 */
  clearAsrTimeout() {
    if (this._asrTimeout) {
      clearTimeout(this._asrTimeout);
      this._asrTimeout = null;
    }
  },
  // 语音播报辅助函数（aiui-dev skill ai.md: speechSynthesis.speak）
  speak(text) {
    try {
      speechSynthesis.cancel();
      var u = new SpeechSynthesisUtterance(text);
      u.volume = 1.0; // SpeechSynthesisUtterance.volume 取值 0~1，超范围会被裁剪且异常
      speechSynthesis.speak(u); // 第二参数 'enqueue' 非标准，靠 cancel() 控制队列
    } catch (e) {
      console.error('[speak] 语音播报失败:', e && (e.message || String(e)));
    }
  },
  /* ===== 接入 Rokid OpenAPI 灵珠智能体，SSE 流式获取大模型回答 =====
     skill 标准写法：await import('open') + await createOpenAPI()
     在页面方法中调用 OpenAPI（skill 推荐）
     api.agent.invokeAgentApi({ body }) 返回 EventSource，不要 await
     SSE 事件处理：error 独立路径，content 片段逐条拼接
     Currently use the concatenated message.content as the response;
     do not depend on or replace it with message.final_answer */
  async askAgent(question, s) {
    var self = this;
    var FALLBACK = '小绿暂时连不上云端大脑，换个说法或等会儿再问我~';

    /* 统一渲染灵珠回答/错误：合并原 finish/finishError，错误态表情改为 alert */
    function renderAnswer(opts) {
      if (!self || self._mode !== 'agent') return;
      self._expr = opts.expr || 'happy';
      var raw = (opts.answer || '').replace(/\s+/g, ' ').trim();
      var clean = raw || FALLBACK;
      self.setData(Object.assign(self.setAvatar(self._expr, s.level, s.race || 0), {
        cardTitle: opts.title || '',
        exprLabel: opts.exprLabel || exprLabelOf(self._expr),
        face: faceForExpr(self._expr),
        animKind: 'bounce',
        dotsOn: 'off',
        cardMain: clean.slice(0, 20),
        cardUnit: opts.unit || '小绿说',
        cardLine1: clean.slice(20, 44),
        cardLine2: (opts.line2 !== undefined ? opts.line2 : clean.slice(44, 68)),
        bubble: opts.bubble || '',
        cardTip: opts.tip || '',
        cardClass: opts.cardClass || 'text',
      }));
      self._animExpr = self._expr;
      // 语音播报：完全按照灵珠智能体返回的内容/错误信息播报
      // 空内容时等待 3 秒再用 FALLBACK 兜底，保证用户有听觉反馈
      // 开始语音播报时停止思考计时
      if (raw) {
        self.clearThinkTimers();
        self.speak(raw);
      } else {
        var fbTimer = setTimeout(function () {
          self.clearThinkTimers();
          self.speak(FALLBACK);
          // 触发后从队列移除，避免定时器泄漏
          if (self._fallbackTimers) {
            var fi = self._fallbackTimers.indexOf(fbTimer);
            if (fi >= 0) self._fallbackTimers.splice(fi, 1);
          }
        }, 3000);
        if (!self._fallbackTimers) self._fallbackTimers = [];
        self._fallbackTimers.push(fbTimer);
      }
    }
    function finish(answer) {
      answered = true;
      renderAnswer({ title: 'AI 回答', exprLabel: '开心', unit: '小绿说', bubble: '答案来啦 (^_^)', tip: '小绿已联网为你解答', expr: 'happy', answer: answer });
    }
    function finishError(errMsg) {
      answered = true;
      renderAnswer({ title: '出错了', exprLabel: '警觉', unit: '小绿说', bubble: '出了点小问题', tip: '换个说法再试试', expr: 'alert', line2: '', answer: errMsg });
    }
    // 回退通道：AIUI 端侧内置大模型（LanguageModel），无外部 key、密钥不外泄
    // 仅在灵珠 3s 无首响应、或灵珠通道整体不可用时调用
    async function callBuiltinLLM() {
      answered = true; // 标记已接管，屏蔽后续灵珠迟到事件
      try {
        if (typeof LanguageModel === 'undefined') throw new Error('LanguageModel 不可用');
        var status = await LanguageModel.availability();
        if (status !== 'available') throw new Error('LanguageModel 不可用');
        var session = await LanguageModel.create({
          initialPrompts: [{ role: 'system', content: '你是住在 Rokid 眼镜里的具象化 AI 助手「小绿」，用简洁口语化中文回答，不超过 60 字。' }]
        });
        var ans = await session.prompt(question);
        try { session.destroy(); } catch (e) {}
        if (self._mode !== 'agent') return;
        var clean = (ans || '').replace(/\s+/g, ' ').trim();
        if (!clean) throw new Error('空回答');
        renderAnswer({ title: 'AI 回答', exprLabel: '开心', unit: '小绿说', bubble: '答案来啦 (^_^)', tip: 'AIUI 内置大模型', expr: 'happy', answer: clean });
      } catch (e) {
        console.error('[askAgent] 内置大模型失败:', e && (e.message || String(e)));
        if (self._mode !== 'agent') return;
        renderAnswer({ title: '出错了', exprLabel: '警觉', unit: '小绿说', bubble: '出了点小问题', tip: '换个说法再试试', expr: 'alert', line2: '', answer: FALLBACK });
      }
    }

    // 会话 ID：同一会话复用，首次生成
    if (!self._agentConversationId) {
      self._agentConversationId = Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
    }

    var content = '';
    var answered = false; // 任一通道（灵珠/内置大模型）已给出最终答案后置 true，屏蔽迟到事件
    try {
      // skill 标准写法：await import('open') 解构 + await createOpenAPI()
      // 在页面方法中调用 OpenAPI（skill 推荐，不作为全局方法）
      var mod = await import('open');
      console.log('[askAgent] open 模块加载成功, mod keys:', Object.keys(mod || {}));
      var api = await mod.createOpenAPI();
      console.log('[askAgent] createOpenAPI 成功, api keys:', Object.keys(api || {}));
      if (api && api.agent) {
        console.log('[askAgent] api.agent keys:', Object.keys(api.agent));
      }
      if (!api || !api.agent || typeof api.agent.invokeAgentApi !== 'function') {
        console.error('[askAgent] api.agent.invokeAgentApi 不存在, api 结构:', JSON.stringify(api ? Object.keys(api) : 'null'));
        callBuiltinLLM();
        return;
      }
      // invokeAgentApi 返回 EventSource，不要 await
      var result = api.agent.invokeAgentApi({
        body: {
          conversation_id: self._agentConversationId,
          agent_id: self._agentId,
          question: question
        }
      });
      // 保存 EventSource 引用，便于超时时关闭
      self._eventSource = result;
      // 思考超时机制：THINK_TIMEOUT_MS 内未收到首条 content 则断开连接，提示用户重新提问
      // 思考计时从此处开始（invokeAgentApi 返回后），语音输入等待阶段不启动此计时
      self._thinkStarted = false;
      self._thinkSeconds = 0;
      self._thinkTimer = setTimeout(function () {
        if (self._thinkStarted) return; // 已开始思考，忽略超时
        // 断开 EventSource
        self.closeEventSource();
        // 清除思考计时器（保留 _thinkTimer 的清理给 clearThinkTimers）
        self.clearThinkTimers();
        // 语音播报超时提示
        self.speak('思考超时了，请重新提问');
        // 显示超时态，回待机
        self.setData({
          cardTitle: '思考超时',
          cardMain: '请重新提问',
          cardUnit: '',
          cardLine1: '小绿等了 15 秒还没收到回应',
          cardLine2: '',
          cardTip: '请重新说一次你的问题',
          bubble: '超时了，再说一次吧',
          cardClass: 'text',
        });
        self.toIdle();
      }, THINK_TIMEOUT_MS);
      // 3 秒无首响应（thought/content/action 均未到达）则回退 AIUI 内置大模型
      self._llmFallbackTimer = setTimeout(function () {
        if (answered) return;
        if (self._thinkStarted) return; // 灵珠已开始返回，不回退
        // 关闭灵珠流并切换内置大模型
        self.closeEventSource();
        if (self._thinkTimer) { clearTimeout(self._thinkTimer); self._thinkTimer = null; }
        self.clearThinkTimers();
        self.setData({ cardTitle: '思考中...', cardTip: '灵珠响应慢，切换本地大模型…', bubble: '让我想想…' });
        callBuiltinLLM();
      }, 3000);
      // SSE 事件处理（aiui-cloud-apis skill invoke-agent-api.md）
      // e.type: 'data'/'inProgress' = 中间流式输出, 'end'/'done' = 完成, 'error' = 可捕获错误
      result.onmessage = function (e) {
        // 已由内置大模型接管或已出答案：屏蔽灵珠迟到事件
        if (answered) return;
        // 任意灵珠事件到达即取消 3 秒回退计时
        if (self._llmFallbackTimer) { clearTimeout(self._llmFallbackTimer); self._llmFallbackTimer = null; }
        // 1. 先处理 error 事件：独立路径，不依赖 content 累积
        if (e.type === 'error') {
          var errMsg = '';
          try {
            var errPayload = JSON.parse(e.data);
            if (errPayload && errPayload.message && errPayload.message.content) {
              errMsg = errPayload.message.content;
            }
            console.error('[askAgent] SSE error 事件:', e.data, errPayload);
          } catch (err) {
            console.error('[askAgent] SSE error 事件 JSON.parse 失败:', err, 'raw:', e.data);
          }
          finishError(errMsg || FALLBACK);
          return;
        }

        // 2. 解析 payload（非 error 事件）
        var payload = null;
        try {
          payload = JSON.parse(e.data);
        } catch (err) {
          console.error('[askAgent] SSE 事件 JSON.parse 失败:', err, 'type:', e.type, 'raw:', e.data);
          return;
        }
        if (!payload) return;

        // 3. thought / action 事件：统一展示为思考态
        //    不向用户展示具体思考内容和插件调用细节
        //    只启动思考计时器，表情保持 thinking，cardTip 显示"小绿正在思考..."
        if (payload.step === 'thought' || payload.step === 'action') {
          if (!self._thinkStarted) {
            self._thinkStarted = true;
            if (self._thinkTimer) { clearTimeout(self._thinkTimer); self._thinkTimer = null; }
            self._thinkCounter = setInterval(function () {
              if (!self || self._mode !== 'agent') { self.clearThinkTimers(); return; }
              self._thinkSeconds++;
              self.setData({ cardTip: '小绿正在思考... ' + self._thinkSeconds + 's' });
            }, 1000);
          }
        }

        // 5. content 片段拼接：step==='content' 且 message.content 非空
        //    收到首条 content 时清除 10 秒思考超时并启动思考计时器
        //    content 拼接期间继续计时，直到 finish() 收到完整答案后停止
        //    skill: Currently use the concatenated message.content as the response;
        //    do not depend on or replace it with message.final_answer
        if (payload.step === 'content' && payload.message && payload.message.content) {
          // 收到首条 content：清除 10 秒思考超时，启动思考计时器
          if (!self._thinkStarted) {
            self._thinkStarted = true;
            if (self._thinkTimer) { clearTimeout(self._thinkTimer); self._thinkTimer = null; }
            self._thinkCounter = setInterval(function () {
              if (!self || self._mode !== 'agent') { self.clearThinkTimers(); return; }
              self._thinkSeconds++;
              self.setData({ cardTip: '小绿正在思考... ' + self._thinkSeconds + 's' });
            }, 1000);
          }
          content += payload.message.content;
        }

        // 6. end/done 事件：展示完整回答（只用 content 拼接结果）
        if (e.type === 'end' || e.type === 'done') {
          finish(content);
        }
      };
    } catch (err) {
      // import / createOpenAPI / invokeAgentApi 失败：回退 AIUI 内置大模型
      console.error('[askAgent] import/createOpenAPI/invokeAgentApi 失败:', err && (err.message || err.stack || JSON.stringify(err)) || String(err));
      callBuiltinLLM();
    }
  },
  // 定位增强版：先判断是否需要定位 → 获取定位 → 拼接 question → 调用 askAgent
  async askAgentWithLocation(question, s) {
    var self = this;
    if (!needsLocation(question)) {
      // 不需要定位，直接调用
      this.askAgent(question, s);
      return;
    }
    // 需要定位：显示"正在获取定位…"连接态
    if (self._mode === 'agent') {
      self.setData({
        cardTitle: '定位中…',
        cardTip: '正在获取你的位置信息',
        bubble: '定位中…',
      });
    }
    var coords = await getLocation();
    var finalQuestion = question;
    if (coords) {
      finalQuestion = '[当前位置：经度' + coords.longitude.toFixed(4) + ', 纬度' + coords.latitude.toFixed(4) + '] ' + question;
      if (self._mode === 'agent') {
        self.setData({
          cardTitle: '连接中...',
          cardTip: '已获取定位，正在发送给灵珠智能体…',
          bubble: '让我想想…',
        });
      }
    } else {
      if (self._mode === 'agent') {
        self.setData({
          cardTitle: '连接中...',
          cardTip: '定位不可用，正在发送给灵珠智能体…',
          bubble: '让我想想…',
        });
      }
    }
    self.askAgent(finalQuestion, s);
  },
  startRecognition() {
    var self = this;
    // 先清理已有实例和超时定时器
    this.stopRecognition();
    this.clearAsrTimeout();
    try {
      var recognition = new SpeechRecognition();
      recognition.lang = 'zh-CN';
      recognition.continuous = false;
      recognition.interimResults = false;
      recognition.maxAlternatives = 1;
      // 语音输入直接调用灵珠智能体进行意图识别和搜索答案
      // 不走本地预设场景匹配，由灵珠智能体统一处理意图
      recognition.onresult = function (event) {
        self.clearAsrTimeout();
        self._listening = false;
        try {
          var results = event.results;
          var idx = event.resultIndex;
          if (results && results[idx] && results[idx][0] && results[idx][0].transcript) {
            var transcript = results[idx][0].transcript.trim();
            if (transcript) self.handleVoiceInput(transcript);
          }
        } catch (e) {}
      };
      // 错误处理：清除超时，回待机态
      recognition.onerror = function (event) {
        self.clearAsrTimeout();
        self._listening = false;
        try {
          var errMsg = (event && event.message) ? event.message : ((event && event.error) ? event.error : '未知错误');
          self.setData({ bubble: '语音识别异常: ' + errMsg });
        } catch (e) {}
        self._recognition = null;
      };
      // 识别结束：清理实例引用和超时
      recognition.onend = function () {
        self.clearAsrTimeout();
        self._listening = false;
        self._recognition = null;
      };
      // 建立 ASR 通道
      recognition.start();
      this._recognition = recognition;
      this._listening = true;
      // 10 秒超时兜底：没有语音输入则播报"没有听太清"并回 idle
      // 此阶段不启动思考计时器，思考计时从 invokeAgentApi 返回后开始
      this._asrTimeout = setTimeout(function () {
        self._listening = false;
        self._asrTimeout = null;
        // 停止当前识别
        self.stopRecognition();
        // 播报"没有听太清"
        self.speak('没有听太清');
        // 回待机态
        self.toIdle();
      }, 10000);
    } catch (e) {
      // SpeechRecognition 不可用或 start() 失败（InvalidStateError 等）
      this._listening = false;
      try {
        this.setData({ bubble: '语音通道暂不可用，可用按钮交互' });
      } catch (e2) {}
    }
  },
  stopRecognition() {
    try {
      if (this._recognition) {
        this._recognition.abort();
        this._recognition = null;
      }
      this._listening = false;
    } catch (e) {}
  },
  // 语音打断：用户呼叫"小绿小绿"时，打断当前 ASR 和语音播报，回应"我在呢，你请说"，再重启 ASR
  interruptForWakeup() {
    // 1. 停止当前 ASR 识别
    this.stopRecognition();
    this.clearAsrTimeout();
    // 2. 取消正在播放的语音播报（aiui-dev skill ai.md: speechSynthesis.cancel）
    try { speechSynthesis.cancel(); } catch (e) {}
    // 3. 播报"我在呢，你请说"
    this.speak('我在呢，你请说');
    // 4. 显示打断反馈
    var s = decay(load());
    this.apply(s, {
      mode: 'companion', expr: 'wave', layer: L3,
      anim: 'bounce',
      title: '我在呢',
      main: '我在呢，你请说',
      unit: '',
      line1: '',
      line2: '',
      timeline: '', tip: '语音打断 · 重新聆听中',
      card: 'text', bubble: '我在呢，你请说~',
      ttl: 0,
      hint: '请说出你的问题',
    });
    // 5. 延迟 1.5 秒后重启 ASR 通道（等待播报结束）
    var self = this;
    if (this._interruptTimer) { clearTimeout(this._interruptTimer); }
    this._interruptTimer = setTimeout(function () {
      self._interruptTimer = null;
      self.startRecognition();
    }, 1500);
  },
  // 语音唤醒回调（events.md 文档依据）
  // onVoiceWakeup 是宿主唤醒信号，触发后：
  // - "小绿"/"小绿小绿" → 语音打断路径（无论当前状态）
  // - 其他 keyword / clickAiAssist → 直接调用灵珠智能体进行意图识别
  // - 之后建立 ASR 通道接收后续语音输入
  onVoiceWakeup(event) {
    try {
      var kw = event.keyword || '';
      // 语音打断："小绿"/"小绿小绿"/"乐奇"/"Hi Rokid" 视为唤醒呼叫
      if (kw === '小绿' || kw === '小绿小绿' || kw === '乐奇' || kw === 'Hi Rokid') {
        this.interruptForWakeup();
        return;
      }
      // 其他 keyword / clickAiAssist 直接调用灵珠智能体进行意图识别和搜索答案
      if (kw) {
        this.handleVoiceInput(kw);
      }
      // 建立 ASR 通道：onVoiceWakeup 是宿主交互信号，满足 start() 的交互状态要求
      this.startRecognition();
    } catch (e) { this.toIdle(); }
  },
  // 语音输入专用路由：直接调用灵珠智能体进行意图识别和搜索答案
  // 不走本地预设场景匹配，由灵珠智能体统一处理所有意图
  // 此阶段显示连接态（连接中...），不启动思考计时，思考计时从 invokeAgentApi 返回后开始
  handleVoiceInput(text) {
    var t = (text || '').trim();
    if (!t) { this.toIdle(); return; }
    var s = decay(load());
    // 显示连接态：语音输入已收到，正在发送给灵珠智能体
    // 此阶段不启动思考计时，思考计时从 invokeAgentApi 返回后开始
    this.apply(s, {
      mode: 'agent', expr: 'alert', layer: L3,
      anim: 'shake', dots: true,
      title: '连接中...',
      main: '',
      unit: '联网回答',
      line1: '', line2: '', timeline: '',
      tip: '正在发送给灵珠智能体…',
      card: 'text', bubble: '让我想想…', ttl: 0,
      hint: '语音输入 · 灵珠智能体意图识别',
    });
    this.askAgentWithLocation(t, s);
  },
  // 头部动作：点头=确认，摇头=忽略/关闭（events.md 文档依据）
  onHeadGesture(event) {
    try {
      if (event.gesture === 'nod') {
        if (this._mode === 'sedentary') { this.handleInput('站起来'); return; }
        this.toIdle();
      } else if (event.gesture === 'shake') {
        this.toIdle();
      }
    } catch (e) { this.toIdle(); }
  },
  // JS 驱动动画：WXSS 不支持 animation/@keyframes，用 setInterval 驱动 transform/opacity
  startAnim() {
    var self = this;
    this.stopAnim();
    this._animStep = 0;
    try {
      this._animTimer = setInterval(function () {
        self._animStep = (self._animStep + 1) % 100;
        var kind = self._animExpr || 'idle';
        var t = self._animStep;
        var transform = '', opacity = 1.0;
        if (kind === 'breathe') {
          // 待机呼吸：opacity 0.9->1.0 sin 曲线
          opacity = 0.9 + 0.1 * (0.5 + 0.5 * Math.sin(t * 2 * Math.PI / 100));
        } else if (kind === 'bounce') {
          // 跳跃：translateY 0->-8px->0
          var phase = (t % 20) / 20;
          var dy = Math.sin(phase * Math.PI) * -8;
          transform = 'translateY(' + dy.toFixed(1) + 'px)';
        } else if (kind === 'shake') {
          // 摇晃：translateX +/-3px
          var phase2 = (t % 16) / 16;
          var dx = Math.sin(phase2 * Math.PI * 2) * 3;
          transform = 'translateX(' + dx.toFixed(1) + 'px)';
        } else if (kind === 'sleep') {
          // 困倦：下沉 + 呼吸
          opacity = 0.85 + 0.15 * (0.5 + 0.5 * Math.sin(t * 2 * Math.PI / 100));
          transform = 'translateY(4px)';
        } else if (kind === 'think') {
          // 思考：倾斜 -5deg
          transform = 'rotate(-5deg)';
        }
        // still = 惊讶定格，无变化
        self.setData({ avatarOpacity: opacity, avatarTransform: transform });
      }, 50);
    } catch (e) {}
  },
  stopAnim() { try { if (this._animTimer) clearInterval(this._animTimer); this._animTimer = null; } catch (e) {} },
  startAmbient() {
    var self = this;
    this.stopAmbient();
    try {
      // 设计稿 2.1：待机缓慢呼吸；场景8：15% 概率随机小动作（眨眼/扭头/打哈欠）
      this._timer = setInterval(function () {
        var s = load();
        var mode = self._mode || 'idle';
        if (mode !== 'idle') return;
        if (Math.random() < 0.15) {
          var act = pick(['blink', 'turn', 'yawn']);
          var st0 = load();
          var back = function (delay) {
            setTimeout(function () {
              var st = load();
              self.setData(Object.assign(self.setAvatar(self._expr || 'idle', st.level, st.race || 0), {
                animKind: animForExpr(self._expr || 'idle'),
                exprLabel: exprLabelOf(self._expr || 'idle'),
              }));
              self._animExpr = self._expr || 'idle';
            }, delay);
          };
          if (act === 'blink') {
            // 眨眼：scaleY 压扁一次（用 transform 模拟）
            self._animExpr = 'blink';
            self.setData({ animKind: 'blink', exprLabel: '眨眼' });
            back(700);
          } else if (act === 'turn') {
            // 扭头：偏转 8deg 再回正
            self._animExpr = 'turn';
            self.setData({ animKind: 'turn', exprLabel: '扭头' });
            back(900);
          } else {
            // 打哈欠：切困倦形态
            if (exprUnlocked('sleepy', st0.level)) {
              self._animExpr = 'sleep';
              self.setData(Object.assign(self.setAvatar('sleepy', st0.level, st0.race || 0), { animKind: 'sleep', exprLabel: '打哈欠' }));
            } else {
              self.setData({ exprLabel: '打哈欠' });
            }
            back(1200);
          }
        }
      }, 4000);
    } catch (e) {}
  },
  stopAmbient() { try { if (this._timer) clearInterval(this._timer); } catch (e) {} },
  refresh() { var s = decay(load()); save(s); this.renderStats(s); },
  renderStats(s) {
    this.setData({
      name: s.name, level: s.level, rank: rankOf(s.level),
      expText: Math.round(s.exp) + ' / ' + expThreshold(s.level),
      expBar: expBar(s),
      bars: '心情' + bar(s.mood) + ' 精力' + bar(s.energy) + ' 亲密' + bar(s.intimacy) + ' 饱食' + bar(s.satiety),
    });
  },
  /* 渲染助手：根据表情/等级/种族生成 16 个像素矩阵字段的 patch，
     消除各场景重复的 avatarBright0..7 / avatarMid0..7 内联赋值 */
  setAvatar(expr, level, race) {
    var parts = splitAvatar(expr, level, race || 0);
    return {
      avatarBright0: parts.bright[0], avatarBright1: parts.bright[1], avatarBright2: parts.bright[2], avatarBright3: parts.bright[3], avatarBright4: parts.bright[4], avatarBright5: parts.bright[5], avatarBright6: parts.bright[6], avatarBright7: parts.bright[7],
      avatarMid0: parts.mid[0], avatarMid1: parts.mid[1], avatarMid2: parts.mid[2], avatarMid3: parts.mid[3], avatarMid4: parts.mid[4], avatarMid5: parts.mid[5], avatarMid6: parts.mid[6], avatarMid7: parts.mid[7]
    };
  },
  // 统一渲染入口：scene = 卡片内容 + 层级 + 表情 + 按钮
  apply(s, scene) {
    this._mode = scene.mode;
    this._expr = scene.expr;
    save(s);
    this.renderStats(s);
    var expr = scene.free ? (exprUnlocked(scene.expr, s.level) ? scene.expr : 'idle') : scene.expr;
    var patch = Object.assign(this.setAvatar(expr, s.level, s.race || 0), {
      face: faceForExpr(expr),
      animKind: scene.anim || animForExpr(expr),
      dotsOn: scene.dots ? 'on' : 'off',
      exprLabel: scene.exprLabel || exprLabelOf(expr),
      layerText: scene.layer,
      cardTitle: scene.title || '',
      cardMain: scene.main || '',
      cardUnit: scene.unit || '',
      cardLine1: scene.line1 || '',
      cardLine2: scene.line2 || '',
      cardTimeline: scene.timeline || '',
      cardTip: scene.tip || '',
      cardClass: scene.card || 'status',
      bubble: scene.bubble || '',
      hint: scene.hint || this.data.hint,
    });
    this.setData(patch);
    this._animExpr = scene.anim || animForExpr(expr);
    // L2 通知层：3-5 秒自动消失回待机（设计稿 5.1）
    if (scene.layer === L2) {
      var self = this;
      try {
        setTimeout(function () { if (self._mode === scene.mode) self.toIdle(); }, scene.ttl || 4000);
      } catch (e) {}
    }
  },
  // 场景8：状态栏待机态（状态卡片，仅角色 + 1 行文字，无边框）
  toIdle(force) {
    var s = decay(load());
    var night = (hourOf() >= 23 || hourOf() < 6);
    var expr = night ? 'sleepy' : 'idle';
    var tip = night ? '夜间睡眠态 z' : '持续常驻 · 缓慢呼吸';
    this.apply(s, {
      mode: 'idle', expr: expr, exprLabel: night ? '睡眠' : '待机', layer: L1,
      title: '', main: night ? '小绿睡着了 z' : '小绿在呢', unit: '', line1: '', line2: '',
      timeline: '', tip: tip, card: 'status', bubble: '', ttl: 0,
      hint: '语音：早安 / 日程 / 天气 / 陪我 / 状态',
    });
  },
  // 升级：设计稿场景7 成长奖励时刻（LEVEL UP + 新外观预览）
  levelUp(s, base) {
    var self = this;
    var upScene = {
      mode: 'levelup', expr: 'happy', exprLabel: '开心', layer: L3,
      anim: 'bounce',
      title: '* LEVEL UP *',
      main: 'Lv.' + s.level,
      unit: unlockOf(s.level),
      line1: '形态：' + rankOf(s.level),
      line2: '经验条已重置 · 新外观生效',
      timeline: '', tip: '叮！升到 Lv.' + s.level + ' 啦~', card: 'levelup', bubble: 'LEVEL UP!',
      hint: '成长奖励时刻 · 每 1-3 天一次',
    };
    this.apply(s, upScene);
    try {
      setTimeout(function () { if (base) self.apply(s, base); }, 3200);
    } catch (e) {}
  },
  handleInput(text) {
    var t = (text || '').trim();
    if (!t) { this.toIdle(); return; }
    var s = decay(load());
    var self = this;

    /* ---- 场景1 早安问候（S级）：每日首次佩戴 +5，连续登录 +3/天递增 ---- */
    if (/(早安|早上好|早呀|morning|醒来|起床|开工|戴上|佩戴|新的一天)/i.test(t)) {
      var gain = 0;
      if (!s.loginDone) { s.loginDone = true; gain += 5; }
      s.streak = (s.streak || 0) + 1;
      gain += Math.min(3, s.streak);
      var up = addExp(s, gain);
      var scene = {
        mode: 'morning', expr: 'wave', layer: L2,
        title: MOCK.morning.title,
        main: MOCK.morning.main,
        unit: MOCK.morning.unit,
        line1: MOCK.morning.line1,
        line2: MOCK.morning.line2,
        timeline: MOCK.morning.timeline,
        tip: '今日首次佩戴 +' + gain + ' EXP',
        card: 'double', bubble: '早上好呀~', ttl: 5000,
        hint: '首次佩戴触发 · 停留 5 秒后收回状态栏',
      };
      if (up) this.levelUp(s, scene); else this.apply(s, scene);
      try {
        var selfm = this;
        setTimeout(function () {
          if (selfm._mode !== 'morning') return;
          selfm._expr = 'happy';
          selfm.setData(Object.assign(selfm.setAvatar('happy', s.level, s.race || 0), { face: faceForExpr('happy'), animKind: 'bounce', exprLabel: '开心' }));
          selfm._animExpr = 'bounce';
        }, 1200);
      } catch (e) {}
      return;
    }

    /* ---- 场景5 AI 问答互动（S级）：连接灵珠智能体获取回答 ---- */
    if (/(是什么|什么是|为什么|怎么办|怎么办呢|如何做|怎样|请问一下|解释一下|是什么意思|区别是什么|哪个更好|值得买吗|推荐一下)/.test(t)) {
      var g5 = 0;
      if (s.qaCount < 10) { s.qaCount++; g5 += 1; }
      var up5 = addExp(s, g5);
      var sc5 = {
        mode: 'agent', expr: 'alert', layer: L3,
        anim: 'shake', dots: true,
        title: '连接中...',
        main: '',
        unit: '联网回答',
        line1: '',
        line2: '',
        timeline: '', tip: g5 ? '完成问答 +' + g5 + ' EXP' : '每日问答上限 10 次',
        card: 'text', bubble: '让我想想…', ttl: 0,
        hint: '正在发送给灵珠智能体…',
      };
      if (up5) this.levelUp(s, sc5); else this.apply(s, sc5);
      this.askAgentWithLocation(t, s);
      return;
    }

    /* ---- 场景3 日程预警（S级）：T-10min 跑入，查看 +2，最多 3 次/天 ---- */
    if (/(日程|会议|安排|行程|周会|复盘|几点开会)/.test(t)) {
      var g2 = 0;
      if (s.scheduleCount < 3) { s.scheduleCount++; g2 += 2; }
      var up2 = addExp(s, g2);
      var sc2 = {
        mode: 'schedule', expr: 'alert', layer: L2,
        anim: 'bounce',
        title: MOCK.schedule.title,
        main: MOCK.schedule.main,
        unit: MOCK.schedule.unit,
        line1: MOCK.schedule.line1,
        line2: MOCK.schedule.line2,
        timeline: MOCK.schedule.timeline,
        tip: g2 ? '查看日程 +' + g2 + ' EXP' : '轻触镜腿 -> 查看详情',
        card: 'single', bubble: '该开会啦！', ttl: 4500,
        hint: '日历事件前 10 分钟自动触发',
      };
      if (up2) this.levelUp(s, sc2); else this.apply(s, sc2);
      return;
    }

    /* ---- 场景2 久坐哨兵（A级）：IMU 静止 50min，站立响应 +3，最多 4 次/天 ---- */
    if (/(久坐|坐了|一直坐着|不动|活动|伸懒腰|站起来|起来走走|站立)/.test(t)) {
      if (/(站起来|站立|起来|活动|伸懒腰|走走|运动)/.test(t)) {
        var g3 = 0;
        if (s.standCount < 4) { s.standCount++; g3 += 3; }
        var up3 = addExp(s, g3);
        var sc3 = {
          mode: 'sedentary', expr: 'happy', layer: L2,
          title: MOCK.sedentaryStand.title,
          main: MOCK.sedentaryStand.main,
          unit: MOCK.sedentaryStand.unit,
          line1: MOCK.sedentaryStand.line1,
          line2: '本次 +' + g3 + ' EXP（今日 ' + s.standCount + '/4）',
          timeline: MOCK.sedentaryStand.timeline, tip: '真棒！活动一下对身体好~', card: 'single', bubble: '谢谢配合 (^_^)', ttl: 3500,
          hint: 'IMU 检测静止 50 分钟 -> 站立响应给奖励',
        };
        if (up3) this.levelUp(s, sc3); else this.apply(s, sc3);
      } else {
        this.apply(s, {
          mode: 'sedentary', expr: 'alert', layer: L2,
          title: MOCK.sedentaryAlert.title,
          main: MOCK.sedentaryAlert.main,
          unit: MOCK.sedentaryAlert.unit,
          line1: MOCK.sedentaryAlert.line1,
          line2: MOCK.sedentaryAlert.line2,
          timeline: MOCK.sedentaryAlert.timeline, tip: '站立 +3 EXP', card: 'single', bubble: '动一动嘛！', ttl: 4000,
          hint: '说站起来响应即可获得奖励',
        });
      }
      return;
    }

    /* ---- 场景4 天气突变预警（A级）：降雨/降温时间线，带伞响应 +3，1 次/天 ---- */
    if (/(天气|下雨|降雨|带伞|降温|气温|大风|温度)/.test(t)) {
      var g4 = 0;
      if (!s.weatherDone) { s.weatherDone = true; g4 += (/(带伞|记得|外套|加衣)/.test(t) ? 3 : 1); }
      var up4 = addExp(s, g4);
      var sc4 = {
        mode: 'weather', expr: 'surprised', layer: L2,
        title: MOCK.weather.title,
        main: MOCK.weather.main,
        unit: MOCK.weather.unit,
        line1: MOCK.weather.line1,
        line2: MOCK.weather.line2,
        timeline: MOCK.weather.timeline,
        tip: g4 ? '响应提醒 +' + g4 + ' EXP' : '底部建议闪烁提醒',
        card: 'timeline', bubble: '别淋湿啦！', ttl: 4500,
        hint: '天气 API 检测未来 2 小时降雨 / 降温',
      };
      if (up4) this.levelUp(s, sc4); else this.apply(s, sc4);
      return;
    }

    /* ---- 场景6 情绪陪伴模式（A级）：全屏 + 对话气泡，每日首次 +5 ---- */
    if (/(陪我|聊天|无聊|难受|难过|想你|孤单|心情不好|陪陪|说话|小绿)/.test(t)) {
      var g6 = 0;
      if (!s.companionDone) { s.companionDone = true; g6 += 5; }
      s.intimacy = clamp(s.intimacy + 8, 0, 100);
      s.mood = clamp(s.mood + 10, 0, 100);
      var up6 = addExp(s, g6);
      var sc6 = {
        mode: 'companion', expr: 'wave', layer: L3,
        anim: 'bounce',
        title: '小绿',
        main: pick(['今天听起来有点累呢，要不要跟我说说？', '我在呢，想说什么都可以~', '陪你聊天最开心啦，慢慢说。']),
        unit: '',
        line1: '我随时都在的。',
        line2: '亲密度 +8 · 心情 +10',
        timeline: '', tip: g6 ? '情绪陪伴 +' + g6 + ' EXP' : '今日陪伴奖励已领取',
        card: 'text', bubble: '我在听…', ttl: 0,
        hint: '说话 / 结束 -- 用户控制结束',
      };
      if (up6) this.levelUp(s, sc6); else this.apply(s, sc6);
      try {
        var self6 = this;
        setTimeout(function () {
          if (self6._mode !== 'companion') return;
          self6._expr = 'happy';
          self6.setData(Object.assign(self6.setAvatar('happy', s.level, s.race || 0), { face: faceForExpr('happy'), animKind: 'bounce', exprLabel: '说话' }));
          self6._animExpr = 'bounce';
        }, 1000);
      } catch (e) {}
      return;
    }

    /* ---- 场景8 状态栏待机态查询 ---- */
    if (/(状态|怎么样|还好吗|查看|数值|形态)/.test(t)) {
      this.apply(s, {
        mode: 'idle', expr: 'idle', layer: L1,
        title: '状态栏待机',
        main: '饱食 ' + Math.round(s.satiety) + ' · 心情 ' + Math.round(s.mood) + ' · 精力 ' + Math.round(s.energy),
        unit: 'Lv.' + s.level + ' · ' + rankOf(s.level),
        line1: '亲密 ' + Math.round(s.intimacy) + ' · EXP ' + Math.round(s.exp) + '/' + expThreshold(s.level),
        line2: unlockOf(s.level),
        timeline: '', tip: '角色 24px 常驻角落 · 缓慢呼吸', card: 'status', bubble: '', ttl: 0,
        hint: 'L1 感知层：零信息密度，持续存在',
      });
      return;
    }
    if (/(名字|你是谁|介绍|叫什么|你谁|你是什么)/.test(t)) {
      this.apply(s, {
        mode: 'companion', expr: 'wave', layer: L3,
        title: '自我介绍',
        main: '我叫小绿，住在你眼镜里的具象化 AI 助手',
        unit: '核心理念：角色是入口不是宠物',
        line1: '每次出现都携带一个实用信息（天气/日程/久坐/问答）',
        line2: '8 大场景 · 三层交互模型 · 养成闭环',
        timeline: '', tip: '', card: 'text', bubble: '很高兴认识你 (^_^)/', ttl: 0,
        hint: '说早安 / 日程 / 天气 / 陪我 / 状态唤起我',
      });
      return;
    }
    // 养成互动
    if (/(喂|吃|饭|食|零食|饿|点心)/.test(t)) {
      s.satiety = clamp(s.satiety + 25, 0, 100);
      var u1 = addExp(s, 5);
      var m1 = pick(['啊呜~好吃！饱饱的啦', '谢谢投喂，小绿满血复活！', '嚼嚼嚼…这味道不错嘛']);
      var sc7 = { mode: 'companion', expr: 'happy', layer: L3, title: '喂养', main: m1, unit: '饱食度 +25', line1: '', line2: '', timeline: '', tip: '+5 EXP', card: 'text', bubble: m1, ttl: 0, hint: 'L3 互动层：喂食互动' };
      if (u1) this.levelUp(s, sc7); else this.apply(s, sc7);
      return;
    }
    if (/(摸|抱|亲|疼|逗|撸|喜欢|抱抱)/.test(t)) {
      s.mood = clamp(s.mood + 20, 0, 100);
      s.intimacy = clamp(s.intimacy + 6, 0, 100);
      var u2 = addExp(s, 4);
      var m2 = pick(['被你摸摸好开心~', '最喜欢你啦！贴贴', '嘿嘿，再多陪我一会儿嘛']);
      var sc8 = { mode: 'companion', expr: 'happy', layer: L3, title: '亲密互动', main: m2, unit: '心情 +20 · 亲密 +6', line1: '', line2: '', timeline: '', tip: '+4 EXP', card: 'text', bubble: m2, ttl: 0, hint: 'L3 互动层：抚摸互动' };
      if (u2) this.levelUp(s, sc8); else this.apply(s, sc8);
      return;
    }
    if (/(睡|休息|困|觉|眯|躺|下班|再见|拜拜|摘下)/.test(t)) {
      if (/(下班|再见|拜拜|摘下)/.test(t)) {
        this.apply(s, { mode: 'idle', expr: 'wave', layer: L2, title: '下班告别', main: '今天辛苦啦，拜拜~', unit: '', line1: '摘下眼镜我就去睡啦，明天见！', line2: '', timeline: '', tip: '摘下检测 -> 挥手告别', card: 'status', bubble: '明天见 (^_^)/', ttl: 3500, hint: 'L2 通知层：摘下检测' });
        return;
      }
      s.energy = clamp(s.energy + 30, 0, 100);
      var u3 = addExp(s, 3);
      var m3 = pick(['呼…zzz 睡饱啦，精神多了', '眯一会儿，养精蓄锐~', '好梦哦，醒来继续陪你']);
      var sc9 = { mode: 'idle', expr: 'sleepy', layer: L1, title: '休息', main: m3, unit: '精力 +30', line1: '', line2: '', timeline: '', tip: '+3 EXP', card: 'status', bubble: 'z Z Z', ttl: 3000, hint: '夜间睡眠态' };
      if (u3) this.levelUp(s, sc9); else this.apply(s, sc9);
      return;
    }
    if (/(玩|游戏|耍|遛)/.test(t)) {
      s.mood = clamp(s.mood + 15, 0, 100);
      s.energy = clamp(s.energy - 10, 0, 100);
      var u4 = addExp(s, 4);
      var m4 = pick(['玩得好开心！再来一局~', '耶！和你玩最棒了', '嘻嘻，小绿赢啦']);
      var sc10 = { mode: 'companion', expr: 'happy', layer: L3, title: '玩耍', main: m4, unit: '心情 +15 · 精力 -10', line1: '', line2: '', timeline: '', tip: '+4 EXP', card: 'text', bubble: m4, ttl: 0, hint: 'L3 互动层：玩耍互动' };
      if (u4) this.levelUp(s, sc10); else this.apply(s, sc10);
      return;
    }
    if (/(洗|澡|干净|清洁|搓)/.test(t)) {
      s.mood = clamp(s.mood + 10, 0, 100);
      var u5 = addExp(s, 2);
      var m5 = pick(['洗完香喷喷的~', '干净舒服！', '泡泡浴真治愈']);
      var sc11 = { mode: 'companion', expr: 'happy', layer: L3, title: '清洁', main: m5, unit: '心情 +10', line1: '', line2: '', timeline: '', tip: '+2 EXP', card: 'text', bubble: m5, ttl: 0, hint: 'L3 互动层：清洁互动' };
      if (u5) this.levelUp(s, sc11); else this.apply(s, sc11);
      return;
    }
    // 兜底：不匹配任何预设场景 -> 连接灵珠智能体获取大模型回答
    var scAgent = {
      mode: 'agent', expr: 'alert', layer: L3,
      anim: 'shake', dots: true,
      title: '连接中...',
      main: '',
      unit: '联网回答',
      line1: '', line2: '',
      timeline: '', tip: '正在发送给灵珠智能体…',
      card: 'text', bubble: '让我想想…', ttl: 0,
      hint: '不匹配预设场景 · 连接大模型回答',
    };
    this.apply(s, scAgent);
    this.askAgentWithLocation(t, s);
  },

  /* ===== 设计稿 5.2 输入方式：语音（主要）/ 触控镜腿（辅助）/ 头部动作 ===== */
  onInput(e) { this.setData({ inputText: e.detail.value }); },
  onConfirm(e) { var t = (e.detail.value || '').trim(); this.setData({ inputText: '' }); this.handleInput(t); },
  onTapA() { this.handleInput('早安'); },
  onTapB() { this.handleInput('日程'); },
  onTapC() { this.handleInput('久坐'); },
  onTapD() { this.handleInput('天气'); },
  onTapE() { this.handleInput('什么是人工智能'); },
  onTapF() { this.handleInput('陪我'); },
  onTapG() {
    var s = decay(load());
    if (this._mode === 'sedentary') { this.handleInput('站起来'); return; }
    this.toIdle();
  },
  onTapH() {
    var s = decay(load());
    var order = ['idle', 'happy', 'alert', 'thinking', 'sleepy', 'wave', 'surprised'];
    var cur = this._expr || 'idle';
    var i = order.indexOf(cur);
    var next = order[(i + 1) % order.length];
    if (!exprUnlocked(next, s.level)) next = 'idle';
    this._expr = next;
    this.setData(Object.assign(this.setAvatar(next, s.level, s.race || 0), { face: faceForExpr(next), animKind: animForExpr(next), exprLabel: exprLabelOf(next) }));
    this._animExpr = animForExpr(next);
  },
  onTapI() {
    try {
      var wxs = (typeof wx !== 'undefined') ? wx : null;
      if (wxs && wxs.removeStorageSync) wxs.removeStorageSync(STORAGE_KEY);
    } catch (e) {}
    var now = Date.now();
    var s = Object.assign({}, DEFAULT_STATE, { lastUpdate: now, born: now, day: todayStr() });
    save(s);
    this._expr = 'idle';
    this.toIdle(true);
    this.setData({ bubble: '已重置存档 · 回到 Lv.1' });
  },
  onTapRace() {
    var s = decay(load());
    if (s.level < 10) { this.setData({ bubble: 'Lv.10 才解锁种族切换哦' }); return; }
    s.race = ((s.race || 0) + 1) % RACES.length;
    save(s);
    this.setData(Object.assign(this.setAvatar(this._expr || 'idle', s.level, s.race), { bubble: '种族切换：' + RACES[s.race].label }));
  },
};
</script>

<page>
  <view class="card">
    <!-- 第一优先级：角色形象（让用户知道这是谁在说话） -->
    <view class="col col-left">
      <!-- 设计稿 3.5：AI 处理中 思考动画 + 头顶省略号闪烁（三点错峰） -->
      <view class="dotsrow {{ dotsOn }}">
        <text class="dot d1">•</text>
        <text class="dot d2">•</text>
        <text class="dot d3">•</text>
      </view>
      <!-- 多色像素矩阵：bright(█▓) 和 mid(░) 两个 text 叠放分别着色 -->
      <view class="avatar-wrap">
        <view class="avatar-bright" style="opacity: {{ avatarOpacity }}; transform: {{ avatarTransform }};">
          <text class="arow">{{ avatarBright0 }}</text>
          <text class="arow">{{ avatarBright1 }}</text>
          <text class="arow">{{ avatarBright2 }}</text>
          <text class="arow">{{ avatarBright3 }}</text>
          <text class="arow">{{ avatarBright4 }}</text>
          <text class="arow">{{ avatarBright5 }}</text>
          <text class="arow">{{ avatarBright6 }}</text>
          <text class="arow">{{ avatarBright7 }}</text>
        </view>
        <view class="avatar-mid" style="opacity: {{ avatarOpacity }}; transform: {{ avatarTransform }};">
          <text class="arow">{{ avatarMid0 }}</text>
          <text class="arow">{{ avatarMid1 }}</text>
          <text class="arow">{{ avatarMid2 }}</text>
          <text class="arow">{{ avatarMid3 }}</text>
          <text class="arow">{{ avatarMid4 }}</text>
          <text class="arow">{{ avatarMid5 }}</text>
          <text class="arow">{{ avatarMid6 }}</text>
          <text class="arow">{{ avatarMid7 }}</text>
        </view>
      </view>
      <text class="expr">{{ exprLabel }} {{ face }}</text>
      <text class="lvl">{{ name }} · Lv.{{ level }}</text>
      <text class="rank">{{ rank }}</text>
    </view>

    <!-- 第二优先级：核心数据 + 补充信息（卡片区，按设计稿 6.1 卡片类型渲染） -->
    <view class="col col-mid">
      <view class="cardbox {{ cardClass }}">
        <text class="ctitle">{{ cardTitle }}</text>
        <text class="cmain">{{ cardMain }}</text>
        <text class="cunit">{{ cardUnit }}</text>
        <text class="cline">{{ cardLine1 }}</text>
        <text class="cline">{{ cardLine2 }}</text>
        <text class="ctimeline">{{ cardTimeline }}</text>
        <text class="ctip">{{ cardTip }}</text>
      </view>
      <text class="bubble">{{ bubble }}</text>
    </view>

    <!-- 第三优先级：层级标识 + EXP + 操作按钮 -->
    <view class="col col-right">
      <text class="layer">{{ layerText }}</text>
      <view class="expwrap">
        <text class="explabel">EXP</text>
        <text class="expbar">{{ expBar }}</text>
        <text class="expnum">{{ expText }}</text>
      </view>
      <view class="actions">
        <view class="btn" bindtap="onTapA">{{ btnA }}</view>
        <view class="btn" bindtap="onTapB">{{ btnB }}</view>
        <view class="btn" bindtap="onTapC">{{ btnC }}</view>
        <view class="btn" bindtap="onTapD">{{ btnD }}</view>
        <view class="btn" bindtap="onTapE">{{ btnE }}</view>
        <view class="btn" bindtap="onTapF">{{ btnF }}</view>
        <view class="btn btn-op" bindtap="onTapG">{{ btnG }}</view>
        <view class="btn btn-op" bindtap="onTapH">{{ btnH }}</view>
        <view class="btn btn-op" bindtap="onTapI">{{ btnI }}</view>
      </view>
      <text class="hint">{{ hint }}</text>
    </view>
  </view>
</page>

<style>
/* ===== WXSS 禁用 animation/@keyframes/white-space/letter-spacing/visibility =====
   动画改用 JS setInterval 驱动 transform/opacity（wxss.md 确认支持） ===== */

.card {
  display: flex;
  flex-direction: row;
  align-items: stretch;
  justify-content: center;
  padding: 4px 8px;
  width: 100%;
  min-height: 100vh;
  box-sizing: border-box;
}
.col { display: flex; flex-direction: column; align-items: center; justify-content: flex-start; }
.col-left { width: 26%; }
.col-mid { width: 44%; padding: 0 6px; }
.col-right { width: 30%; }

/* 头顶省略号（AI 处理中显示） */
.dotsrow { display: flex; flex-direction: row; justify-content: center; height: 9px; }
.dotsrow.off { opacity: 0; }
.dot { color: #00ff88; font-size: 9px; line-height: 9px; margin: 0 1px; opacity: 0.2; }
.dotsrow.on .d1 { opacity: 1; }
.dotsrow.on .d2 { opacity: 0.6; }
.dotsrow.on .d3 { opacity: 0.3; }

/* 多色像素矩阵：两个 text 叠放 */
.avatar-wrap {
  position: relative;
  width: 100%;
  min-height: 88px;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: flex-start;
}
.avatar-bright {
  display: block;
  position: absolute;
  top: 0;
  left: 0;
  width: 100%;
  color: #00ff88;
  font-family: "Courier New", monospace;
  font-size: 11px;
  line-height: 11px;
  text-align: center;
  z-index: 2;
  transform-origin: center center;
  transition: opacity 0.3s ease;
}
.avatar-mid {
  display: block;
  position: absolute;
  top: 0;
  left: 0;
  width: 100%;
  color: #00aa55;
  font-family: "Courier New", monospace;
  font-size: 11px;
  line-height: 11px;
  text-align: center;
  z-index: 1;
  transform-origin: center center;
  transition: opacity 0.3s ease;
}
.arow {
  display: block;
  font-family: "Courier New", monospace;
  font-size: 11px;
  line-height: 11px;
  text-align: center;
}

.expr { color: #00aa55; font-size: 12px; margin-top: 2px; }
.lvl { color: #00ff88; font-size: 12px; margin-top: 1px; }
.rank { color: #006633; font-size: 9px; margin-top: 0; text-align: center; }

/* 设计稿 6.1 卡片类型 */
.cardbox {
  width: 100%;
  border: 1px solid #006633;
  border-radius: 10px;
  padding: 5px 8px;
  background: rgba(0, 255, 136, 0.04);
  box-sizing: border-box;
}
.cardbox.status { border-color: transparent; background: transparent; padding: 2px 4px; }
.cardbox.levelup { border-color: #00ff88; background: rgba(0, 255, 136, 0.12); }
.ctitle { color: #00ff88; font-size: 13px; font-weight: 600; }
.cmain { color: #00ff88; font-size: 15px; font-weight: 700; line-height: 19px; margin-top: 1px; }
.cunit { color: #00aa55; font-size: 11px; }
.cline { color: #00aa55; font-size: 11px; line-height: 16px; }
.ctimeline { color: #00ff88; font-size: 11px; line-height: 16px; margin-top: 2px; }
.ctip { color: #00ff88; font-size: 11px; margin-top: 2px; }
.bubble {
  color: #00aa55;
  font-size: 11px;
  line-height: 15px;
  margin-top: 3px;
  border-left: 2px solid #006633;
  padding-left: 5px;
  width: 100%;
}

.layer {
  color: #00ff88;
  font-size: 11px;
  border: 1px solid #006633;
  border-radius: 999px;
  padding: 1px 8px;
}
.expwrap { display: flex; flex-direction: row; align-items: center; width: 100%; margin-top: 4px; }
.explabel { color: #00aa55; font-size: 11px; width: 30px; }
.expbar { color: #00ff88; font-size: 11px; flex: 1; }
.expnum { color: #00aa55; font-size: 10px; width: 56px; text-align: right; }
.actions { display: flex; flex-direction: row; flex-wrap: wrap; justify-content: center; gap: 4px; width: 100%; margin-top: 5px; }
.btn {
  color: #00ff88;
  border: 1px solid #006633;
  border-radius: 999px;
  padding: 2px 8px;
  font-size: 11px;
}
.btn-op { color: #00aa55; border-color: rgba(0, 102, 51, 0.6); }
.hint { color: #006633; font-size: 10px; margin-top: 4px; text-align: center; line-height: 14px; }
</style>