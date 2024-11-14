import os
import requests
import json
import time

# 从环境变量获取 Koyeb 账户信息（以 JSON 字符串格式存储）
KOYEB_ACCOUNTS = json.loads(os.getenv("KOYEB_ACCOUNTS"))

def send_tg_message(message):
    bot_token = os.getenv("TG_BOT_TOKEN")
    chat_id = os.getenv("TG_CHAT_ID")
    url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
    data = {
        "chat_id": chat_id,
        "text": message,
        "parse_mode": "Markdown"
    }
    response = requests.post(url, data=data)
    return response.json()

def login_koyeb(email, password):
    login_url = "https://app.koyeb.com/v1/account/login"
    headers = {
        "Content-Type": "application/json",
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
    }
    data = {
        "email": email,
        "password": password
    }
    
    try:
        response = requests.post(login_url, headers=headers, json=data)
        response.raise_for_status()
        
        if response.status_code == 200:
            return True, "登录成功"
        else:
            return False, f"登录失败: HTTP状态码 {response.status_code}"
    except requests.RequestException as e:
        return False, f"登录失败: {str(e)}"

# 登录并记录所有账户的结果
results = []
for account in KOYEB_ACCOUNTS:
    email = account['email']
    password = account['password']
    
    # 每次登录后等待 5 秒
    time.sleep(5)
    
    success, message = login_koyeb(email, password)
    results.append(f"账户: {email}\n状态: {'成功' if success else '失败'}\n消息: {message}\n")

# 发送 Telegram 消息
tg_message = "Koyeb 登录报告\n\n" + "\n".join(results)
send_tg_message(tg_message)
