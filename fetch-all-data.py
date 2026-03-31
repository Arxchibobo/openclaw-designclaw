#!/usr/bin/env python3
"""
DesignClaw - MyShell DesignManager 数据爬取脚本
用法:
  python3 fetch-all-data.py                  # 爬取全部数据并打印
  python3 fetch-all-data.py --stats-only     # 仅打印统计
  python3 fetch-all-data.py --output ./data  # 保存为 JSON 文件
"""

import argparse
import json
import os
import sys
from datetime import datetime
from urllib.request import urlopen, Request
from urllib.error import URLError

BASE_URL = os.environ.get("DESIGNCLAW_API_URL", "http://103.207.68.10:9970/api")

def api_get(endpoint):
    """GET request to the DesignManager API."""
    url = f"{BASE_URL}{endpoint}"
    try:
        req = Request(url, headers={"Accept": "application/json"})
        with urlopen(req, timeout=15) as resp:
            return json.loads(resp.read().decode())
    except URLError as e:
        print(f"❌ 无法连接 {url}: {e}", file=sys.stderr)
        sys.exit(1)

def fetch_all():
    """Fetch all data from DesignManager."""
    print("🔄 正在爬取 DesignManager 数据...")
    
    users = api_get("/users")
    print(f"  ✅ 用户: {len(users)} 条")
    
    tasks = api_get("/tasks")
    print(f"  ✅ 任务: {len(tasks)} 条")
    
    assignments = api_get("/assignments")
    print(f"  ✅ 接单记录: {len(assignments)} 条")
    
    # Fetch messages for each assignment
    all_messages = {}
    for a in assignments:
        msgs = api_get(f"/messages/{a['id']}")
        if msgs:
            all_messages[a['id']] = msgs
    total_msgs = sum(len(v) for v in all_messages.values())
    print(f"  ✅ 消息: {total_msgs} 条 (across {len(all_messages)} 工单)")
    
    return {
        "fetched_at": datetime.utcnow().isoformat() + "Z",
        "users": users,
        "tasks": tasks,
        "assignments": assignments,
        "messages": all_messages,
    }

def print_stats(data):
    """Print summary statistics."""
    users = data["users"]
    tasks = data["tasks"]
    assignments = data["assignments"]
    
    print("\n" + "=" * 50)
    print("📊 DesignManager 数据统计")
    print("=" * 50)
    
    # Users
    roles = {}
    for u in users:
        roles[u.get("role", "UNKNOWN")] = roles.get(u.get("role", "UNKNOWN"), 0) + 1
    print(f"\n👥 用户总数: {len(users)}")
    for role, cnt in roles.items():
        print(f"   {role}: {cnt}")
    
    # Tasks
    statuses = {}
    total_budget = 0
    for t in tasks:
        s = t.get("status", "UNKNOWN")
        statuses[s] = statuses.get(s, 0) + 1
        total_budget += t.get("budget", 0)
    print(f"\n📋 任务总数: {len(tasks)} | 总预算: ¥{total_budget:,.0f}")
    for s, cnt in statuses.items():
        print(f"   {s}: {cnt}")
    
    # Assignments
    a_statuses = {}
    ratings = []
    for a in assignments:
        s = a.get("status", "UNKNOWN")
        a_statuses[s] = a_statuses.get(s, 0) + 1
        if a.get("rating"):
            ratings.append(a["rating"])
    print(f"\n💼 接单记录: {len(assignments)}")
    for s, cnt in a_statuses.items():
        print(f"   {s}: {cnt}")
    if ratings:
        print(f"   平均评分: {sum(ratings)/len(ratings):.2f} ({len(ratings)} 条评分)")
    
    # Messages
    msgs = data.get("messages", {})
    total_msgs = sum(len(v) for v in msgs.values())
    print(f"\n💬 消息总数: {total_msgs}")
    print("=" * 50)

def save_data(data, output_dir):
    """Save data as JSON files."""
    os.makedirs(output_dir, exist_ok=True)
    
    # Save complete dump
    path = os.path.join(output_dir, "designmanager-dump.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"💾 完整数据已保存: {path}")
    
    # Save individual tables
    for key in ["users", "tasks", "assignments"]:
        path = os.path.join(output_dir, f"{key}.json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data[key], f, ensure_ascii=False, indent=2)
    print(f"💾 分表数据已保存到: {output_dir}/")

def main():
    parser = argparse.ArgumentParser(description="DesignClaw 数据爬取工具")
    parser.add_argument("--stats-only", action="store_true", help="仅显示统计")
    parser.add_argument("--output", "-o", type=str, help="输出目录")
    parser.add_argument("--api-url", type=str, help="API地址 (默认: http://103.207.68.10:9970/api)")
    args = parser.parse_args()
    
    if args.api_url:
        global BASE_URL
        BASE_URL = args.api_url
    
    data = fetch_all()
    print_stats(data)
    
    if args.output:
        save_data(data, args.output)
    elif not args.stats_only:
        # Print raw JSON to stdout
        print("\n📝 完整数据 (JSON):")
        print(json.dumps(data, ensure_ascii=False, indent=2))

if __name__ == "__main__":
    main()
