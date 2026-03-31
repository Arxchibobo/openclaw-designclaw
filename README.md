# DesignClaw Skill - MyShell 开发者接单系统数据查询

![OpenClaw Skill](https://img.shields.io/badge/OpenClaw-Skill-blue)

> 查询 MyShell DesignManager 接单系统的月度统计数据（设计师工作量、接单/交付数、评分等）。通过 Playwright 浏览器访问 Web UI 抓取数据。Use when asked about designer tasks, assignments, monthly stats, or DesignClaw/接单系统.

## 概述
查询 MyShell DesignManager 接单系统的月度统计数据，包括设计师工作量、接单/交付数、评分等。

## ⭐ 推荐方案：浏览器访问（Browser Use）

> **经验教训：** 该项目尝试过 SSH 端口转发、nginx 反向代理、API 直连等多种 CLI 方案，均因云防火墙/nginx 配置问题失败。最终通过 Playwright 浏览器直接访问 Web UI，**一次成功**。这是一个典型案例——当目标是 Web 应用时，Browser Use 往往比 CLI 更快更可靠。

### 工作流程

1. **启动 Playwright + Chromium**（headless）
2. **打开** `http://myshell.penguinpebbling.com/`
3. **登录超管账号**（MyShell / MyShell@Bobo）
4. **点击「月度统计」** 进入统计页面
5. **切换月份**（`input[type="month"]` → `YYYY-MM` 格式）
6. **抓取页面文本**，解析设计师数据

### 环境要求

```bash
# 安装 Playwright + Chromium（首次）
npm install playwright        # 在 /tmp 或项目目录
npx playwright install chromium
```

### 核心脚本

```javascript
// scripts/fetch-monthly-stats.js
const {chromium} = require('playwright');

async function fetchMonthlyStats(month) {
  // month 格式: 'YYYY-MM'，默认上个月
  if (!month) {
    const d = new Date();
    d.setMonth(d.getMonth() - 1);
    month = d.toISOString().slice(0, 7);
  }

  const browser = await chromium.launch({
    headless: true,
    args: ['--no-sandbox', '--disable-dev-shm-usage']
  });
  const page = await browser.newPage({viewport: {width: 1920, height: 1080}});

  // 1. 打开页面
  await page.goto('http://myshell.penguinpebbling.com/', {
    waitUntil: 'networkidle', timeout: 30000
  });

  // 2. 登录
  const inputs = await page.$$('input');
  await inputs[0].fill('MyShell');
  await inputs[1].fill('MyShell@Bobo');
  await page.click('button >> nth=-1');
  await page.waitForTimeout(3000);
  await page.waitForLoadState('networkidle').catch(() => {});

  // 3. 进入月度统计
  await page.click('text=月度统计');
  await page.waitForTimeout(2000);

  // 4. 切换月份
  const monthInput = await page.$('input[type="month"]');
  if (monthInput) {
    await monthInput.fill(month);
    await page.waitForTimeout(3000);
  }

  await page.waitForLoadState('networkidle').catch(() => {});

  // 5. 抓取数据
  const body = await page.textContent('body');

  // 6. 截图
  const screenshotPath = `/tmp/dm-stats-${month}.png`;
  await page.screenshot({path: screenshotPath, fullPage: true});

  await browser.close();

  // 7. 解析数据
  return parseStats(body, month);
}

function parseStats(body, month) {
  // 提取总览数据
  const overview = {};
  const overviewMatch = body.match(/本月接单(\d+)进行中(\d+)待审核(\d+)本月交付(\d+)/);
  if (overviewMatch) {
    overview.totalOrders = parseInt(overviewMatch[1]);
    overview.inProgress = parseInt(overviewMatch[2]);
    overview.pendingReview = parseInt(overviewMatch[3]);
    overview.delivered = parseInt(overviewMatch[4]);
  }

  // 提取设计师数据
  const designers = [];
  const pattern = /(\d+)(.+?)累计完成 (\d+) 单接单(\d+)进行中(\d+)待审核(\d+)交付(\d+)(?:评分([\d.]+))?/g;
  let m;
  while ((m = pattern.exec(body)) !== null) {
    const d = {
      rank: parseInt(m[1]),
      name: m[2].trim(),
      totalCompleted: parseInt(m[3]),
      orders: parseInt(m[4]),
      inProgress: parseInt(m[5]),
      pendingReview: parseInt(m[6]),
      delivered: parseInt(m[7]),
    };
    if (m[8]) d.rating = parseFloat(m[8]);
    if (d.orders > 0) designers.push(d);
  }

  return { month, overview, activeDesigners: designers };
}

// CLI 入口
if (require.main === module) {
  const month = process.argv[2]; // e.g., '2026-02'
  fetchMonthlyStats(month).then(data => {
    console.log(JSON.stringify(data, null, 2));
  }).catch(console.error);
}

module.exports = { fetchMonthlyStats };
```

### 使用方法

```bash
# 查看上个月统计（默认）
node scripts/fetch-monthly-stats.js

# 查看指定月份
node scripts/fetch-monthly-stats.js 2026-02

# 输出示例
{
  "month": "2026-02",
  "overview": { "totalOrders": 104, "inProgress": 8, "pendingReview": 52, "delivered": 43 },
  "activeDesigners": [
    { "rank": 1, "name": "leonGong", "totalCompleted": 24, "orders": 19, ... },
    ...
  ]
}
```

## 备选方案：API 直连

> ⚠️ 需要服务器端口 9969/9970 对外开放（雨云安全组放行），目前不可用。

### API 端点

```
Base URL: http://103.207.68.10:9969/api  (服务器本地)
Base URL: http://103.207.68.10:9970/api  (nginx 反代，需端口开放)

GET  /api/users                          — 所有用户
GET  /api/tasks                          — 所有任务（?publisherId= 可筛选）
GET  /api/assignments                    — 所有接单（?taskId= 或 ?workerId= 可筛选）
GET  /api/messages/:assignmentId         — 工单消息
POST /api/auth/login                     — 登录 {username, password}
```

### 数据库 4 张表

1. **users** — id, name, role(PUBLISHER/WORKER/SUPER_ADMIN), avatar, blockchainHash
2. **tasks** — id, title, description, budget, deadline, status(OPEN/CLOSED), publisherId
3. **assignments** — id, taskId, workerId, status(IN_PROGRESS/SUBMITTED/COMPLETED/REJECTED), rating, feedback
4. **messages** — id, assignmentId, senderId, content, createdAt, isRead

## 服务器信息

- **Web UI:** http://myshell.penguinpebbling.com/
- **服务器:** 103.207.68.10（雨云 RainYun + 宝塔面板）
- **应用端口:** 9969（PM2）
- **DB 路径:** `/root/.myshell-data/data.db`（SQLite）
- **超管账号:** `MyShell` / `MyShell@Bobo`

## 关键经验

1. **Browser Use 优先**：当目标是 Web 应用且 CLI 方案受阻时，直接用 Playwright/Browser Use
2. **云防火墙 ≠ iptables**：雨云等云平台有独立的安全组，服务器层面的 iptables 生效不代表外部可访问
3. **nginx vhost 调试困难**：宝塔面板的 nginx 配置分散在多个 vhost 文件中，server_name 匹配逻辑复杂

## 📁 File Structure

```
openclaw-designclaw/
├── SKILL.md
├── design-manager-setup.sh
├── fetch-all-data.py
└── scripts/fetch-monthly-stats.js
```

## 🚀 Installation

### Via OpenClaw CLI

```bash
openclaw skill install github:Arxchibobo/openclaw-designclaw
```

### Manual Installation

```bash
cd ~/.openclaw/workspace/skills/
git clone https://github.com/Arxchibobo/openclaw-designclaw.git designclaw
```

## 📄 License

MIT

---

*This is an [OpenClaw](https://github.com/openclaw/openclaw) AgentSkill. Learn more at [docs.openclaw.ai](https://docs.openclaw.ai).*
