const {chromium} = require('playwright');

async function fetchMonthlyStats(month) {
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

  await page.goto('http://myshell.penguinpebbling.com/', {
    waitUntil: 'networkidle', timeout: 30000
  });

  // Login
  const inputs = await page.$$('input');
  await inputs[0].fill('MyShell');
  await inputs[1].fill('MyShell@Bobo');
  await page.click('button >> nth=-1');
  await page.waitForTimeout(3000);
  await page.waitForLoadState('networkidle').catch(() => {});

  // Navigate to monthly stats
  await page.click('text=月度统计');
  await page.waitForTimeout(2000);

  // Switch month
  const monthInput = await page.$('input[type="month"]');
  if (monthInput) {
    await monthInput.fill(month);
    await page.waitForTimeout(3000);
  }
  await page.waitForLoadState('networkidle').catch(() => {});

  // Get raw textContent and parse with a reliable approach
  const rawText = await page.evaluate(() => document.body.textContent);
  
  // Overview
  const overview = {};
  const ovMatch = rawText.match(/本月接单(\d+)进行中(\d+)待审核(\d+)本月交付(\d+)/);
  if (ovMatch) {
    overview.totalOrders = parseInt(ovMatch[1]);
    overview.inProgress = parseInt(ovMatch[2]);
    overview.pendingReview = parseInt(ovMatch[3]);
    overview.delivered = parseInt(ovMatch[4]);
  }

  // Extract designer section: after "排序: 接单数 ↓" 
  const section = rawText.split(/排序.*?[↓↑]/)[1] || '';
  
  // Each designer entry looks like: "1leonGong累计完成 24 单接单19进行中0待审核10交付9评分5.0"
  // Split on "累计完成" boundaries
  const parts = section.split(/(?=累计完成)/);
  
  // Pair them: text before "累计完成" has rank+name, text after has stats
  const designers = [];
  let prevTail = parts[0] || ''; // text before first "累计完成"
  
  for (let i = 0; i < parts.length; i++) {
    if (!parts[i].startsWith('累计完成')) {
      prevTail = parts[i];
      continue;
    }
    
    // Parse stats from current part
    const statsMatch = parts[i].match(/累计完成 (\d+) 单接单(\d+)进行中(\d+)待审核(\d+)交付(\d+)(?:评分([\d.]+))?/);
    if (!statsMatch) { prevTail = parts[i]; continue; }
    
    // Parse name from prevTail: find the last rank number + name
    // prevTail ends with something like "...评分5.02我是火火" or "排序: 接单数 ↓1leonGong"
    // The name is after the last rating or after a rank number
    let nameStr = prevTail;
    // Remove trailing from previous entry's stats
    nameStr = nameStr.replace(/.*评分[\d.]+/, '');
    nameStr = nameStr.replace(/.*交付\d+/, '');
    // Now should have "RankName" like "2我是火火" or "1leonGong"
    const nameMatch = nameStr.match(/(\d+)([^\d].+?)$/);
    
    const d = {
      rank: nameMatch ? parseInt(nameMatch[1]) : i,
      name: nameMatch ? nameMatch[2].trim() : nameStr.trim(),
      totalCompleted: parseInt(statsMatch[1]),
      orders: parseInt(statsMatch[2]),
      inProgress: parseInt(statsMatch[3]),
      pendingReview: parseInt(statsMatch[4]),
      delivered: parseInt(statsMatch[5]),
    };
    if (statsMatch[6]) d.rating = parseFloat(statsMatch[6]);
    designers.push(d);
    
    prevTail = parts[i];
  }

  await browser.close();

  return {
    month,
    overview,
    activeDesigners: designers.filter(d => d.orders > 0),
    allDesigners: designers
  };
}

if (require.main === module) {
  const month = process.argv[2];
  fetchMonthlyStats(month).then(data => {
    // Print summary
    console.log(JSON.stringify({
      month: data.month,
      overview: data.overview,
      activeDesigners: data.activeDesigners
    }, null, 2));
  }).catch(console.error);
}

module.exports = { fetchMonthlyStats };
