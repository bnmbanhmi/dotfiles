#!/usr/bin/env python3
"""
Usage Tracker - Background Fetcher
Fetches and aggregates usage metrics for AI assistants:
- Antigravity (Gemini, Claude/GPT, Argon via CloudCode API)
- OpenCode (SQLite local database)
- Gemini Web (Account 0 and Account 1 via Google Chrome tab integration)
Outputs normalized data into stats.json.
"""

import os
import sys
import json
import sqlite3
import datetime
import subprocess
import re
import urllib.request
import urllib.error

SCRIPT_DIR = os.path.dirname(os.path.realpath(__file__))
STATS_FILE = os.path.join(SCRIPT_DIR, "stats.json")

def format_relative_time(iso_time_str):
    if not iso_time_str:
        return ""
    try:
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

def get_google_client_credentials():
    plugin_dirs = [
        os.path.expanduser("~/.gemini/config/plugins/gcalendar/auth.json"),
        os.path.expanduser("~/.gemini/config/plugins/gdrive/auth.json"),
        os.path.expanduser("~/.gemini/config/plugins/gdocs/auth.json"),
    ]
    for p in plugin_dirs:
        if os.path.exists(p):
            try:
                with open(p, "r", encoding="utf-8") as f:
                    d = json.load(f)
                oauth = d.get("providers", {}).get("google", {}).get("oauth2", {})
                cid = oauth.get("clientId")
                csec = oauth.get("clientSecret")
                if cid and csec:
                    return cid, csec
            except Exception:
                pass
    return None, None

OPENAI_CLIENT_ID = "app_EMoamEEZ73f0CkXaXp7hrann"

def refresh_antigravity_token(token_data, token_path):
    refresh_token = token_data.get("token", {}).get("refresh_token") or token_data.get("refresh_token")
    if not refresh_token:
        return None

    client_id, client_secret = get_google_client_credentials()
    if not client_id or not client_secret:
        return None

    import urllib.parse
    payload = urllib.parse.urlencode({
        "client_id": client_id,
        "client_secret": client_secret,
        "refresh_token": refresh_token,
        "grant_type": "refresh_token"
    }).encode("utf-8")

    req = urllib.request.Request("https://oauth2.googleapis.com/token", data=payload)
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            res = json.loads(resp.read().decode("utf-8"))
            new_access_token = res.get("access_token")
            if new_access_token:
                if "token" in token_data and isinstance(token_data["token"], dict):
                    token_data["token"]["access_token"] = new_access_token
                else:
                    token_data["access_token"] = new_access_token
                
                # Save updated token back
                try:
                    with open(token_path, "w", encoding="utf-8") as f:
                        json.dump(token_data, f, indent=2)
                except Exception:
                    pass
                return new_access_token
    except Exception:
        return None
    return None

def fetch_antigravity():
    token_path = os.path.expanduser("~/.gemini/jetski-standalone-oauth-token")
    if not os.path.exists(token_path):
        return []

    try:
        with open(token_path, "r", encoding="utf-8") as f:
            token_data = json.load(f)
        token = token_data.get("token", {}).get("access_token") or token_data.get("access_token")
        if not token:
            return []

        def call_quota_api(auth_token):
            req = urllib.request.Request(
                "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary",
                data=b"{}",
                headers={
                    "Authorization": f"Bearer {auth_token}",
                    "Content-Type": "application/json",
                    "User-Agent": "antigravity/2.24.0 (aidev_client; os_type=darwin; arch=arm64)"
                }
            )
            with urllib.request.urlopen(req, timeout=10) as resp:
                return json.loads(resp.read().decode("utf-8"))

        try:
            body = call_quota_api(token)
        except urllib.error.HTTPError as he:
            if he.code == 401:
                # Token expired, refresh it
                new_token = refresh_antigravity_token(token_data, token_path)
                if new_token:
                    body = call_quota_api(new_token)
                else:
                    raise he
            else:
                raise he

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

def refresh_chatgpt_token(auth_data, auth_path):
    tokens = auth_data.get("tokens", {})
    refresh_token = tokens.get("refresh_token")
    if not refresh_token:
        return None
    try:
        data = urllib.parse.urlencode({
            "grant_type": "refresh_token",
            "client_id": OPENAI_CLIENT_ID,
            "refresh_token": refresh_token
        }).encode("utf-8")
        req = urllib.request.Request(
            "https://auth.openai.com/oauth/token",
            data=data,
            headers={"Content-Type": "application/x-www-form-urlencoded"}
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            new_tokens = json.loads(resp.read().decode("utf-8"))
            if "access_token" in new_tokens:
                tokens["access_token"] = new_tokens["access_token"]
                if "refresh_token" in new_tokens:
                    tokens["refresh_token"] = new_tokens["refresh_token"]
                if "id_token" in new_tokens:
                    tokens["id_token"] = new_tokens["id_token"]
                auth_data["tokens"] = tokens
                auth_data["last_refresh"] = int(time.time())
                try:
                    with open(auth_path, "w", encoding="utf-8") as f:
                        json.dump(auth_data, f, indent=2)
                except Exception:
                    pass
                return new_tokens["access_token"]
    except Exception:
        return None
    return None

def fetch_chatgpt():
    auth_path = os.path.expanduser("~/.codex/auth.json")
    if not os.path.exists(auth_path):
        return []
    try:
        with open(auth_path, "r", encoding="utf-8") as f:
            auth_data = json.load(f)
        tokens = auth_data.get("tokens", {})
        access_token = tokens.get("access_token")
        account_id = tokens.get("account_id")
        if not access_token:
            return []

        def call_chatgpt_api(token):
            headers = {
                "Authorization": f"Bearer {token}",
                "Accept": "application/json",
                "User-Agent": "OpenUsage"
            }
            if account_id:
                headers["ChatGPT-Account-Id"] = account_id
            req = urllib.request.Request(
                "https://chatgpt.com/backend-api/wham/usage",
                headers=headers
            )
            with urllib.request.urlopen(req, timeout=10) as resp:
                return json.loads(resp.read().decode("utf-8"))

        try:
            body = call_chatgpt_api(access_token)
        except urllib.error.HTTPError as he:
            if he.code == 401:
                new_token = refresh_chatgpt_token(auth_data, auth_path)
                if new_token:
                    body = call_chatgpt_api(new_token)
                else:
                    return []
            else:
                return []

        plan = body.get("plan_type", "Free").capitalize()
        rl = body.get("rate_limit", {}) or {}
        prim = rl.get("primary_window")
        sec = rl.get("secondary_window")

        def format_dur(secs):
            if not secs or secs <= 0:
                return "now"
            hrs = secs // 3600
            mins = (secs % 3600) // 60
            days = hrs // 24
            if days > 0:
                return f"{days}d {hrs%24}h"
            if hrs > 0:
                return f"{hrs}h {mins}m"
            return f"{mins}m"

        used_val = 0
        details = [f"Plan: {plan}"]

        if prim:
            p_used = prim.get("used_percent", 0)
            p_reset_sec = prim.get("reset_after_seconds", 0)
            used_val = max(used_val, p_used)
            win_sec = prim.get("limit_window_seconds", 0)
            label = "Session (5h)" if win_sec <= 18000 else "Primary Window"
            details.append(f"{label}: {p_used}% used (resets in {format_dur(p_reset_sec)})")

        if sec:
            s_used = sec.get("used_percent", 0)
            s_reset_sec = sec.get("reset_after_seconds", 0)
            used_val = max(used_val, s_used)
            details.append(f"Weekly Limit: {s_used}% used (resets in {format_dur(s_reset_sec)})")

        credits = body.get("credits", {})
        if credits.get("has_credits") and credits.get("balance") is not None:
            details.append(f"Credits Balance: {credits.get('balance')}")

        return [{
            "id": "ChatGPT",
            "short": "ChatGPT",
            "name": f"ChatGPT ({plan})",
            "menu_text": f"ChatGPT: {int(used_val)}%",
            "details": details
        }]
    except Exception:
        return []

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

        cursor.execute("SELECT SUM(cost), SUM(tokens_input + tokens_output), COUNT(*) FROM session")
        total_cost, total_tokens, total_sessions = cursor.fetchone()

        conn.close()

        today_cost = today_cost or 0.0
        today_tokens = today_tokens or 0
        today_sessions = today_sessions or 0

        week_cost = week_cost or 0.0
        week_tokens = week_tokens or 0
        week_sessions = week_sessions or 0

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

def fetch_gemini_web(cached_providers=None):
    """
    Extracts usage metrics from active Google Chrome tabs:
    - https://gemini.google.com/usage (Account 0)
    - https://gemini.google.com/u/1/usage (Account 1)
    """
    apple_script = """
tell application "System Events"
    set isRunning to (name of processes) contains "Google Chrome"
end tell
if isRunning then
    tell application "Google Chrome"
        set outText to ""
        repeat with w in windows
            repeat with t in tabs of w
                set u to (URL of t)
                if u contains "gemini.google.com" and u contains "usage" then
                    set txt to (execute t javascript "document.body.innerText")
                    set outText to outText & "===TAB_START===" & linefeed & u & linefeed & "---" & linefeed & txt & linefeed & "===TAB_END===" & linefeed
                end if
            end repeat
        end repeat
        return outText
    end tell
else
    return ""
end if
"""
    try:
        proc = subprocess.run(["osascript", "-e", apple_script], capture_output=True, text=True, timeout=5)
        raw = proc.stdout
    except Exception:
        raw = ""

    parsed_accounts = {}

    if "===TAB_START===" in raw:
        tabs = raw.split("===TAB_START===")
        for tab in tabs:
            if "===TAB_END===" not in tab:
                continue
            content = tab.split("===TAB_END===")[0].strip()
            if "---" not in content:
                continue
            url_line, text = content.split("---", 1)
            url = url_line.strip()

            acc_match = re.search(r"/u/(\d+)/", url)
            acc_idx = acc_match.group(1) if acc_match else "0"

            current_used = None
            current_reset = None
            weekly_used = None
            weekly_reset = None

            # Current usage (5h)
            m_curr = re.search(r"Current usage.*?\n(?:info\n)?(\d+)%\s*used\s*\nResets\s+(?:at\s+)?([^\n]+)", text, re.IGNORECASE)
            if m_curr:
                current_used = m_curr.group(1)
                current_reset = m_curr.group(2).strip()

            # Weekly limit
            m_week = re.search(r"Weekly limit.*?\nResets\s+([^\n]+)\n(\d+)%\s*used", text, re.IGNORECASE)
            if not m_week:
                m_week = re.search(r"Weekly limit.*?\n(\d+)%\s*used\s*\nResets\s+([^\n]+)", text, re.IGNORECASE)
                if m_week:
                    weekly_used = m_week.group(1)
                    weekly_reset = m_week.group(2).strip()
            else:
                weekly_reset = m_week.group(1).strip()
                weekly_used = m_week.group(2).strip()

            if current_used is not None or weekly_used is not None:
                parsed_accounts[acc_idx] = {
                    "current_used": current_used or "0",
                    "current_reset": current_reset or "",
                    "weekly_used": weekly_used or "0",
                    "weekly_reset": weekly_reset or ""
                }

    results = []
    old_cache = {}
    if cached_providers:
        for p in cached_providers:
            if p.get("id") in ("Gemini-0", "Gemini-1"):
                old_cache[p.get("id")] = p

    for idx in ["0", "1"]:
        pid = f"Gemini-{idx}"
        if idx in parsed_accounts:
            acc = parsed_accounts[idx]
            main_pct = acc["weekly_used"]
            details = [
                f"Weekly Limit: {acc['weekly_used']}% used ({acc['weekly_reset']})",
                f"Current (5h): {acc['current_used']}% used (Resets: {acc['current_reset']})"
            ]
            results.append({
                "id": pid,
                "short": pid,
                "name": f"Gemini Web (Acc {idx})",
                "menu_text": f"{pid}: {main_pct}%",
                "details": details
            })
        elif pid in old_cache:
            results.append(old_cache[pid])

    return results

def load_existing_stats():
    if os.path.exists(STATS_FILE):
        try:
            with open(STATS_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return {}

def main():
    old_stats = load_existing_stats()
    cached_providers = old_stats.get("providers", [])

    providers = []
    
    # 1. Antigravity (Gemini, Claude/GPT, Argon)
    providers.extend(fetch_antigravity())

    # 2. ChatGPT (Codex account)
    providers.extend(fetch_chatgpt())

    # 3. Gemini Web (Account 0 and Account 1 from Chrome)
    providers.extend(fetch_gemini_web(cached_providers))

    # 4. OpenCode
    providers.extend(fetch_opencode())

    # Active selection
    active_id = old_stats.get("active", "AGY")
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
