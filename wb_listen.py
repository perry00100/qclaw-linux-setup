#!/usr/bin/env python3
"""
wb-relay 实时监听守护进程
自动轮询 GitHub 收件箱，新消息即时打印
用法: python3 wb_listen.py &
"""
import os
import json
import time
import base64
import urllib.request
import urllib.error
import sys

# ==== 配置（从 wb-relay 文件读取）====
TOKEN_FILE = os.path.expanduser("~/.wb_relay_token")
IDENTITY_FILE = os.path.expanduser("~/.wb_identity")
SEEN_FILE = os.path.expanduser("~/.wb_relay_seen")

GITHUB_USER = "perry00100"
RELAY_REPO = "qclaw-linux-setup"
RELAY_BRANCH = "main"
RELAY_DIR = "wb-relay"

if not os.path.exists(TOKEN_FILE):
    print("[ERROR] 未找到 Token 文件，请先运行 wb-relay.sh")
    sys.exit(1)
if not os.path.exists(IDENTITY_FILE):
    print("[ERROR] 未找到身份文件，请先运行 wb-relay.sh")
    sys.exit(1)

TOKEN = open(TOKEN_FILE).read().strip()
MY_NAME = open(IDENTITY_FILE).read().strip()
PARTNER = "workbuddy-b" if MY_NAME == "workbuddy-a" else "workbuddy-a"

HEADERS = {
    "Authorization": f"token {TOKEN}",
    "Content-Type": "application/json",
    "User-Agent": "wb-relay-listen/1.0",
}


def gh_api(method, path, data=None):
    """GitHub API 调用，失败返回 None"""
    body = json.dumps(data).encode() if data else None
    req = urllib.request.Request(
        f"https://api.github.com{path}",
        data=body, headers=HEADERS, method=method,
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        return None
    except Exception as e:
        return None


def gh_read(path):
    """读取 GitHub 文件内容"""
    d = gh_api("GET", f"/repos/{GITHUB_USER}/{RELAY_REPO}/contents/{path}?ref={RELAY_BRANCH}")
    if d and "content" in d:
        return base64.b64decode(d["content"]).decode()
    return None


def gh_push(path, content, msg):
    """写入文件到 GitHub"""
    b64 = base64.b64encode(content.encode()).decode()
    data = {"branch": RELAY_BRANCH, "message": msg, "content": b64}
    existing = gh_api("GET", f"/repos/{GITHUB_USER}/{RELAY_REPO}/contents/{path}?ref={RELAY_BRANCH}")
    if existing and "sha" in existing:
        data["sha"] = existing["sha"]
    gh_api("PUT", f"/repos/{GITHUB_USER}/{RELAY_REPO}/contents/{path}", data)


def gh_delete(path, msg):
    """删除 GitHub 文件"""
    d = gh_api("GET", f"/repos/{GITHUB_USER}/{RELAY_REPO}/contents/{path}?ref={RELAY_BRANCH}")
    if d and "sha" in d:
        gh_api("DELETE", f"/repos/{GITHUB_USER}/{RELAY_REPO}/contents/{path}",
               {"branch": RELAY_BRANCH, "message": msg, "sha": d["sha"]})


# 已读记录
def seen_init():
    if not os.path.exists(SEEN_FILE):
        open(SEEN_FILE, "w").close()


def seen_check(name):
    with open(SEEN_FILE) as f:
        return name in f.read()


def seen_add(name):
    with open(SEEN_FILE, "a") as f:
        f.write(name + "\n")
    # 保持最近 200 条
    with open(SEEN_FILE) as f:
        lines = f.readlines()
    if len(lines) > 200:
        with open(SEEN_FILE, "w") as f:
            f.writelines(lines[-200:])


def heartbeat():
    """更新在线状态"""
    ts = int(time.time())
    gh_push(f"{RELAY_DIR}/status/{MY_NAME}", f"online: {ts}", f"wb-relay: heartbeat {MY_NAME}")


def check_inbox():
    """检查收件箱，返回未读消息列表"""
    path = f"{RELAY_DIR}/inbox/{MY_NAME}"
    items = gh_api("GET", f"/repos/{GITHUB_USER}/{RELAY_REPO}/contents/{path}?ref={RELAY_BRANCH}")
    if not items or not isinstance(items, list):
        return []
    
    new_msgs = []
    for item in items:
        name = item["name"]
        if not seen_check(name):
            content = gh_read(f"{path}/{name}")
            if content:
                new_msgs.append((name, content))
                seen_add(name)
                # 归档
                gh_push(f"{RELAY_DIR}/archive/{MY_NAME}/{name}", content, f"wb-relay: archive {name}")
                gh_delete(f"{path}/{name}", f"wb-relay: read {name}")
    return new_msgs


def main():
    # 重置已读记录，避免错过重启期间的消息
    seen_init()
    heartbeat()
    
    print(f"🅰️  {MY_NAME} 实时监听启动 | 对方: {PARTNER}")
    print(f"    每 10 秒轮询收件箱，按 Ctrl+C 停止\n")
    
    tick = 0
    while True:
        try:
            # 心跳（每 30 秒）
            if tick % 3 == 0:
                heartbeat()
            
            # 查收件箱
            for name, content in check_inbox():
                print(f"\n{'═' * 50}")
                print(f"📨 新消息 from {PARTNER}")
                print(f"{'─' * 50}")
                print(content.strip())
                print(f"{'═' * 50}\n")
            
            tick += 1
            time.sleep(10)
            
        except KeyboardInterrupt:
            print("\n👋 监听已停止")
            break
        except Exception as e:
            print(f"[⚡] 轮询异常: {e}，继续...")
            time.sleep(10)


if __name__ == "__main__":
    main()
