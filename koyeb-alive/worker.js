async function sendTGMessage(message, env) {
  const botToken = env.TG_BOT_TOKEN;
  const chatId = env.TG_CHAT_ID;
  const url = `https://api.telegram.org/bot${botToken}/sendMessage`;

  const payload = {
    chat_id: chatId,
    text: message,
    parse_mode: 'Markdown',
  };

  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
  });

  return await response.json();
}

async function loginKoyeb(email, password, env) {
  const loginUrl = 'https://app.koyeb.com/v1/account/login';
  const headers = {
    'Content-Type': 'application/json',
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
  };

  const data = {
    email: email,
    password: password,
  };

  try {
    const response = await fetch(loginUrl, {
      method: 'POST',
      headers: headers,
      body: JSON.stringify(data),
    });

    if (response.ok) {
      return [true, `HTTP状态码 ${response.status}`]; 
    } else {
      return [false, `HTTP状态码 ${response.status}`];
    }
  } catch (e) {
    return [false, `${e.message}`];
  }
}

// 定时触发器执行的函数
async function scheduledEventHandler(event, env) {
  // 从环境变量获取 Koyeb 账户信息（JSON 字符串格式）
  const koyebAccounts = JSON.parse(env.KOYEB_ACCOUNTS);
  const results = [];
  for (let account of koyebAccounts) {
    const email = account.email;
    const password = account.password;
    // 每次登录后等待 3 秒再登录下一个账号
    await new Promise(resolve => setTimeout(resolve, 3000));
    const [success, message] = await loginKoyeb(email, password, env);
    results.push(`账户: ${email}\n状态: ${success ? '登录成功' : '登录失败'}\n消息: ${message}`);
  }

  // 构建和发送 Telegram 消息
  const tgMessage = `Koyeb 登录报告\n\n${results.join('\n')}`;
  await sendTGMessage(tgMessage, env);
}

// Cron Trigger 事件监听器
addEventListener('scheduled', event => {
  event.waitUntil(scheduledEventHandler(event, event.environment));
});
