async function sendTGMessage(message) {
  const botToken = ENV.TG_BOT_TOKEN;
  const chatId = ENV.TG_CHAT_ID;
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

async function loginKoyeb(email, password) {
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
      return [true, '登录成功'];
    } else {
      return [false, `登录失败: HTTP状态码 ${response.status}`];
    }
  } catch (e) {
    return [false, `登录失败: ${e.message}`];
  }
}

async function handleRequest(request) {
  // 从环境变量获取 Koyeb 账户信息（JSON 字符串格式）
  const koyebAccounts = JSON.parse(ENV.KOYEB_ACCOUNTS);

  const results = [];
  for (let account of koyebAccounts) {
    const email = account.email;
    const password = account.password;

    // 每次登录后等待 5 秒
    await new Promise(resolve => setTimeout(resolve, 5000));

    const [success, message] = await loginKoyeb(email, password);
    results.push(`账户: ${email}\n状态: ${success ? '成功' : '失败'}\n消息: ${message}`);
  }

  // 构建 Telegram 消息
  const tgMessage = `Koyeb 登录报告\n\n${results.join('\n')}`;

  // 发送 Telegram 消息
  await sendTGMessage(tgMessage);

  return new Response('Koyeb 登录保活已完成', { status: 200 });
}

addEventListener('fetch', event => {
  event.respondWith(handleRequest(event.request));
});
