#!/usr/bin/env python3
"""
Usage Tracker - Background Fetcher
Fetches and aggregates usage metrics for AI assistants (Antigravity, OpenCode, Gemini Web, ChatGPT).
Outputs normalized data into stats.json.
"""

import os
import sys
import json
import sqlite3
import datetime
import urllib.request
import urllib.error

SCRIPT_DIR = os.path.dirname(os.path.realpath(__file__))
STATS_FILE = os.path.join(SCRIPT_DIR, "stats.json")
CONFIG_FILE = os.path.join(SCRIPT_DIR, "config.json")

def format_relative_time(iso_time_str):
    if not iso_time_str:
        return ""
    try:
        # e.g. 2026-10-31T04:31:18Z
        iso_clean = iso_time_str.replace("Z", "+00:00")
        target = datetime.datetime.fromisoformat(iso_clean)
        now = datetime.datetime.now(datetime.timezone.utc)
        diff = target - now
        total_seconds = int(diff.total_seconds())
        if total_seconds <= 0:
            return "ready"
        days = total_seconds // 86400
        hours = (total_seconds % 86400) // 3600
        minutes = (total_seconds % 3600) // 60
        if days > 0:
            return f"resets in {days}d {hours}h"
        elif hours > 0:
            return f"resets in {hours}h {minutes}m"
        else:
            return f"resets in {minutes}m"
    except Exception:
        return ""

def fetch_antigravity():
    token_path = os.path.expanduser("~/.gemini/jetski-standalone-oauth-token")
    if not os.path.exists(token_path):
        return []

    try:
        with open(token_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        token = data.get("token", {}).get("access_token") or data.get("access_token")
        if not token:
            return []

        req = urllib.request.Request(
            "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary",
            data=b"{}",
            headers={
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/json",
                "User-Agent": "antigravity/2.24.0 (aidev_client; os_type=darwin; arch=arm64)"
            }
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            body = json.loads(resp.read().decode("utf-8"))

        gemini_weekly = None
        gemini_5h = None
        claude_weekly = None
        claude_5h = None
        argon_weekly = None

        for group in body.get("groups", []):
            group_name = group.get("displayName", "")
            for bucket in group.get("buckets", []):
                bid = bucket.get("bucketId")
                rem = bucket.get("remainingFraction", 1.0)
                used = max(0.0, min(100.0, round((1.0 - rem) * 100, 1)))
                reset_t = bucket.get("resetTime")
                rel_t = format_relative_time(reset_t)

                if bid == "gemini-weekly":
                    gemini_weekly = (used, rel_t)
                elif bid == "gemini-5h":
                    gemini_5h = (used, rel_t)
                elif bid == "3p-weekly":
                    claude_weekly = (used, rel_t)
                elif bid == "3p-5h":
                    claude_5h = (used, rel_t)
                elif "argon" in group_name.lower() or (bid and "argon" in bid.lower()):
                    if bucket.get("window") == "weekly":
                        argon_weekly = (used, rel_t)

        results = []

        # 1. Antigravity Gemini
        if gemini_weekly or gemini_5h:
            used_val = gemini_weekly[0] if gemini_weekly else (gemini_5h[0] if gemini_5h else 0)
            details = []
            if gemini_weekly:
                details.append(f"Weekly Limit: {gemini_weekly[0]}% used ({gemini_weekly[1]})")
            if gemini_5h:
                details.append(f"5-Hour Limit: {gemini_5h[0]}% used ({gemini_5h[1]})")

            results.append({
                "id": "AGY",
                "short": "AGY",
                "name": "Antigravity (Gemini)",
                "menu_text": f"AGY: {int(used_val)}%",
                "details": details
            })

        # 2. Antigravity Claude / 3P
        if claude_weekly or claude_5h:
            used_val = claude_weekly[0] if claude_weekly else (claude_5h[0] if claude_5h else 0)
            details = []
            if claude_weekly:
                details.append(f"Weekly Limit: {claude_weekly[0]}% used ({claude_weekly[1]})")
            if claude_5h:
                details.append(f"5-Hour Limit: {claude_5h[0]}% used ({claude_5h[1]})")

            results.append({
                "id": "AGY-Claude",
                "short": "AGY-Claude",
                "name": "Antigravity (Claude/GPT)",
                "menu_text": f"AGY-Claude: {int(used_val)}%",
                "details": details
            })

        # 3. Antigravity Argon (if exists)
        if argon_weekly:
            results.append({
                "id": "AGY-Argon",
                "short": "AGY-Argon",
                "name": "Antigravity (Argon)",
                "menu_text": f"AGY-Argon: {int(argon_weekly[0])}%",
                "details": [f"Weekly Limit: {argon_weekly[0]}% used ({argon_weekly[1]})"]
            })

        return results
    except Exception as e:
        return [{
            "id": "AGY",
            "short": "AGY",
            "name": "Antigravity",
            "menu_text": "AGY: err",
            "details": [f"Error: {str(e)[:40]}"]
        }]

def fetch_opencode():
    db_path = os.path.expanduser("~/.local/share/opencode/opencode.db")
    if not os.path.exists(db_path):
        return []

    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()

        now = datetime.datetime.now()
        start_of_today = datetime.datetime(now.year, now.month, now.day).timestamp() * 1000
        start_of_week = (now - datetime.timedelta(days=now.weekday())).replace(
            hour=0, minute=0, second=0, microsecond=0
        ).timestamp() * 1000

        cursor.execute("SELECT SUM(cost), SUM(tokens_input + tokens_output), COUNT(*) FROM session WHERE time_created >= ?", (start_of_today,))
        today_cost, today_tokens, today_sessions = cursor.fetchone()

        cursor.execute("SELECT SUM(cost), SUM(tokens_input + tokens_output), COUNT(*) FROM session WHERE time_created >= ?", (start_of_week,))
        week_cost, week_tokens, week_sessions = cursor.fetchone()

        # All time stats for reference if 0
        cursor.execute("SELECT SUM(cost), SUM(tokens_input + tokens_output), COUNT(*) FROM session")
        total_cost, total_tokens, total_sessions = cursor.fetchone()

        conn.close()

        today_cost = today_cost or 0.0
        today_tokens = today_tokens or 0
        today_sessions = today_sessions or 0

        week_cost = week_cost or 0.0
        week_tokens = week_tokens or 0
        week_sessions = week_sessions or 0

        # Menu text: show today's cost or tokens
        if today_cost > 0:
            menu_text = f"OpenCode: ${today_cost:.2f}"
        elif today_tokens > 0:
            menu_text = f"OpenCode: {today_tokens // 1000}k"
        else:
            menu_text = "OpenCode: 0"

        details = [
            f"Today: ${today_cost:.2f} ({today_tokens:,} tokens, {today_sessions} sessions)",
            f"This Week: ${week_cost:.2f} ({week_tokens:,} tokens, {week_sessions} sessions)",
            f"All Time: ${total_cost or 0:.2f} ({total_tokens or 0:,} tokens)"
        ]

        return [{
            "id": "OpenCode",
            "short": "OpenCode",
            "name": "OpenCode",
            "menu_text": menu_text,
            "details": details
        }]
    except Exception as e:
        return [{
            "id": "OpenCode",
            "short": "OpenCode",
            "name": "OpenCode",
            "menu_text": "OpenCode: err",
            "details": [f"Error: {str(e)[:40]}"]
        }]

def load_active_provider():
    if os.path.exists(STATS_FILE):
        try:
            with open(STATS_FILE, "r", encoding="utf-8") as f:
                d = json.load(f)
                return d.get("active", "AGY")
        except Exception:
            pass
    return "AGY"

def main():
    providers = []
    
    # 1. Antigravity (Gemini, Claude, Argon)
    providers.extend(fetch_antigravity())

    # 2. OpenCode
    providers.extend(fetch_opencode())

    # Load previously chosen active provider
    active_id = load_active_provider()
    # Ensure active_id exists in providers list
    existing_ids = [p["id"] for p in providers]
    if active_id not in existing_ids and existing_ids:
        active_id = existing_ids[0]

    now_str = datetime.datetime.now().strftime("%H:%M")
    output = {
        "active": active_id,
        "updated_at": int(datetime.datetime.now().timestamp()),
        "updated_text": now_str,
        "providers": providers
    }

    # Write atomic stats.json
    tmp_file = STATS_FILE + ".tmp"
    with open(tmp_file, "w", encoding="utf-8") as f:
        json.dump(output, f, indent=2, ensure_ascii=False)
    os.replace(tmp_file, STATS_FILE)

    print(f"Stats updated at {now_str}. Providers loaded: {', '.join(existing_ids)}")

if __name__ == "__main__":
    main()
