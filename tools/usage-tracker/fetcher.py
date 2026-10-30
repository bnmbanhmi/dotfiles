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
            return f"{days}d {hours}h"
        elif hours > 0:
            return f"{hours}h {minutes}m"
        else:
            return f"{minutes}m"
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

ACCOUNTS_PATH = os.path.expanduser("~/.gemini/antigravity_accounts.json")
JETSKI_TOKEN_PATH = os.path.expanduser("~/.gemini/jetski-standalone-oauth-token")

def get_or_harvest_antigravity_accounts():
    accounts = []
    if os.path.exists(ACCOUNTS_PATH):
        try:
            with open(ACCOUNTS_PATH, "r", encoding="utf-8") as f:
                data = json.load(f)
                accounts = data.get("accounts", [])
        except Exception:
            accounts = []

    # Check currently active token in jetski
    if os.path.exists(JETSKI_TOKEN_PATH):
        try:
            with open(JETSKI_TOKEN_PATH, "r", encoding="utf-8") as f:
                cur_data = json.load(f)
            cur_email = cur_data.get("id_token_email")
            if cur_email:
                found = False
                for acc in accounts:
                    if acc.get("email") == cur_email:
                        acc["token_data"] = cur_data
                        found = True
                        break
                if not found:
                    acc_id = "0" if "bachnhatminh" in cur_email or not accounts else str(len(accounts))
                    accounts.append({
                        "id": acc_id,
                        "email": cur_email,
                        "token_data": cur_data
                    })
                # Save back to ~/.gemini/antigravity_accounts.json
                try:
                    with open(ACCOUNTS_PATH, "w", encoding="utf-8") as f:
                        json.dump({"accounts": accounts}, f, indent=2)
                    os.chmod(ACCOUNTS_PATH, 0o600)
                except Exception:
                    pass
        except Exception:
            pass

    return accounts

def refresh_antigravity_token(token_data, token_path=None):
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
                if token_path:
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
    accounts = get_or_harvest_antigravity_accounts()
    if not accounts:
        return []

    results = []

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

    for acc in accounts:
        acc_id = acc.get("id", "0")
        token_data = acc.get("token_data", {})
        token = token_data.get("token", {}).get("access_token") or token_data.get("access_token")
        if not token:
            continue

        try:
            body = call_quota_api(token)
        except urllib.error.HTTPError as he:
            if he.code == 401:
                # Token expired, refresh it
                new_token = refresh_antigravity_token(token_data)
                if new_token:
                    # Update saved accounts file
                    try:
                        with open(ACCOUNTS_PATH, "w", encoding="utf-8") as f:
                            json.dump({"accounts": accounts}, f, indent=2)
                        os.chmod(ACCOUNTS_PATH, 0o600)
                    except Exception:
                        pass
                    # If this is the current active jetski token, update it too
                    if os.path.exists(JETSKI_TOKEN_PATH):
                        try:
                            with open(JETSKI_TOKEN_PATH, "r", encoding="utf-8") as jf:
                                jd = json.load(jf)
                            if jd.get("id_token_email") == acc.get("email"):
                                with open(JETSKI_TOKEN_PATH, "w", encoding="utf-8") as jf:
                                    json.dump(token_data, jf, indent=2)
                        except Exception:
                            pass
                    try:
                        body = call_quota_api(new_token)
                    except Exception:
                        continue
                else:
                    continue
            else:
                continue
        except Exception:
            continue

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

        # 1. Antigravity Gemini
        if gemini_weekly or gemini_5h:
            items = []
            if gemini_weekly:
                items.append({
                    "id": f"{acc_id}-AGY-G-W",
                    "label": f"Weekly: {gemini_weekly[0]}% ({gemini_weekly[1]})",
                    "menu_text": f"{acc_id}-AGY-G-W: {int(round(gemini_weekly[0]))}%"
                })
            if gemini_5h:
                items.append({
                    "id": f"{acc_id}-AGY-G-5h",
                    "label": f"5h: {gemini_5h[0]}% ({gemini_5h[1]})",
                    "menu_text": f"{acc_id}-AGY-G-5h: {int(round(gemini_5h[0]))}%"
                })
            if items:
                results.append({
                    "name": f"{acc_id} - Antigravity (Gemini)",
                    "items": items
                })

        # 2. Antigravity Claude / 3P
        if claude_weekly or claude_5h:
            items = []
            if claude_weekly:
                items.append({
                    "id": f"{acc_id}-AGY-C-W",
                    "label": f"Weekly: {claude_weekly[0]}% ({claude_weekly[1]})",
                    "menu_text": f"{acc_id}-AGY-C-W: {int(round(claude_weekly[0]))}%"
                })
            if claude_5h:
                items.append({
                    "id": f"{acc_id}-AGY-C-5h",
                    "label": f"5h: {claude_5h[0]}% ({claude_5h[1]})",
                    "menu_text": f"{acc_id}-AGY-C-5h: {int(round(claude_5h[0]))}%"
                })
            if items:
                results.append({
                    "name": f"{acc_id} - Antigravity (Claude/GPT)",
                    "items": items
                })

        # 3. Antigravity Argon
        if argon_weekly:
            results.append({
                "name": f"{acc_id} - Antigravity (Argon)",
                "items": [{
                    "id": f"{acc_id}-AGY-A-W",
                    "label": f"Weekly: {argon_weekly[0]}% ({argon_weekly[1]})",
                    "menu_text": f"{acc_id}-AGY-A-W: {int(round(argon_weekly[0]))}%"
                }]
            })
        else:
            results.append({
                "name": f"{acc_id} - Antigravity (Argon)",
                "items": [{
                    "id": f"{acc_id}-AGY-A-W",
                    "label": "Weekly: N/A (Pro/Ultra only)",
                    "menu_text": f"{acc_id}-AGY-A-W: N/A"
                }]
            })

    return results

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

        items = []
        if prim:
            p_used = prim.get("used_percent", 0)
            p_reset_sec = prim.get("reset_after_seconds", 0)
            win_sec = prim.get("limit_window_seconds", 0)
            dur_str = format_dur(p_reset_sec)
            tag = "5h" if win_sec <= 18000 else "P"
            lbl = "5h" if win_sec <= 18000 else "Primary"
            items.append({
                "id": f"GPT-{tag}",
                "label": f"{lbl}: {p_used}% ({dur_str})",
                "menu_text": f"GPT-{tag}: {int(round(p_used))}%"
            })

        if sec:
            s_used = sec.get("used_percent", 0)
            s_reset_sec = sec.get("reset_after_seconds", 0)
            dur_str = format_dur(s_reset_sec)
            items.append({
                "id": "GPT-W",
                "label": f"Weekly: {s_used}% ({dur_str})",
                "menu_text": f"GPT-W: {int(round(s_used))}%"
            })

        if items:
            return [{
                "name": f"ChatGPT ({plan})",
                "items": items
            }]
        return []
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

        def fmt_tok(n):
            if n >= 1_000_000:
                return f"{n / 1_000_000:.1f}M"
            if n >= 1_000:
                return f"{n / 1_000:.1f}k"
            return str(n)

        items = [
            {
                "id": "OC-Today",
                "label": f"Today: ${today_cost:.2f} ({fmt_tok(today_tokens)} tok)",
                "menu_text": f"OC-Today: ${today_cost:.2f}"
            },
            {
                "id": "OC-Week",
                "label": f"Week: ${week_cost:.2f} ({fmt_tok(week_tokens)} tok)",
                "menu_text": f"OC-Week: ${week_cost:.2f}"
            },
            {
                "id": "OC-All",
                "label": f"All-Time: {total_tokens or 0:,} tok",
                "menu_text": f"OC-All: {fmt_tok(total_tokens or 0)}"
            }
        ]

        return [{
            "name": "OpenCode",
            "items": items
        }]
    except Exception:
        return []

def fetch_gemini_web(cached_groups=None):
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
    if cached_groups:
        for g in cached_groups:
            if "Gemini Web" in g.get("name", ""):
                for i in ["0", "1", "2", "3"]:
                    if f"Acc {i}" in g.get("name", "") or g.get("name", "").startswith(f"{i} -"):
                        old_cache[i] = g

    for idx in ["0", "1"]:
        gname = f"{idx} - Gemini Web"
        if idx in parsed_accounts:
            acc = parsed_accounts[idx]
            clean_curr_reset = re.sub(r"^(?:Resets\s+)?(?:at\s+|on\s+)?", "", acc["current_reset"], flags=re.IGNORECASE).strip()
            clean_week_reset = re.sub(r"^(?:Resets\s+)?(?:at\s+|on\s+)?", "", acc["weekly_reset"], flags=re.IGNORECASE).strip()

            items = [
                {
                    "id": f"{idx}-Gem-W",
                    "label": f"Weekly: {acc['weekly_used']}% ({clean_week_reset})" if clean_week_reset else f"Weekly: {acc['weekly_used']}%",
                    "menu_text": f"{idx}-Gem-W: {acc['weekly_used']}%"
                },
                {
                    "id": f"{idx}-Gem-5h",
                    "label": f"5h: {acc['current_used']}% ({clean_curr_reset})" if clean_curr_reset else f"5h: {acc['current_used']}%",
                    "menu_text": f"{idx}-Gem-5h: {acc['current_used']}%"
                }
            ]
            results.append({
                "name": gname,
                "items": items
            })
        elif idx in old_cache:
            cached_g = old_cache[idx]
            cached_g["name"] = gname
            for item in cached_g.get("items", []):
                if "Weekly" in item["id"] or "-W" in item["id"]:
                    item["id"] = f"{idx}-Gem-W"
                    m = re.search(r"(\d+)%", item.get("label", ""))
                    pct = m.group(1) if m else "0"
                    item["menu_text"] = f"{idx}-Gem-W: {pct}%"
                elif "5h" in item["id"] or "Current" in item["id"]:
                    item["id"] = f"{idx}-Gem-5h"
                    m = re.search(r"(\d+)%", item.get("label", ""))
                    pct = m.group(1) if m else "0"
                    item["menu_text"] = f"{idx}-Gem-5h: {pct}%"
            results.append(cached_g)

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
    cached_groups = old_stats.get("groups", [])

    groups = []
    
    # 1. Antigravity (Gemini, Claude/GPT, Argon for each account)
    groups.extend(fetch_antigravity())

    # 2. ChatGPT (Codex account)
    groups.extend(fetch_chatgpt())

    # 3. Gemini Web (Account 0 and Account 1 from Chrome)
    groups.extend(fetch_gemini_web(cached_groups))

    # 4. OpenCode
    groups.extend(fetch_opencode())

    # Collect all available item IDs
    all_item_ids = []
    for g in groups:
        for it in g.get("items", []):
            all_item_ids.append(it["id"])

    # Active selection
    active_id = old_stats.get("active", "0-AGY-G-W")
    if active_id not in all_item_ids:
        mig_map = {
            "0-AGY-Gemini-Weekly": "0-AGY-G-W",
            "0-AGY-Gemini-5h": "0-AGY-G-5h",
            "0-AGY-Claude-Weekly": "0-AGY-C-W",
            "0-AGY-Claude-5h": "0-AGY-C-5h",
            "AGY": "0-AGY-G-W",
            "AGY-Gemini-5h": "0-AGY-G-5h",
            "AGY-Gemini-Weekly": "0-AGY-G-W",
            "AGY-Claude": "0-AGY-C-5h",
            "AGY-Claude-5h": "0-AGY-C-5h",
            "AGY-Claude-Weekly": "0-AGY-C-W",
            "ChatGPT": "GPT-P",
            "ChatGPT-Primary": "GPT-P",
            "ChatGPT-5h": "GPT-5h",
            "ChatGPT-Weekly": "GPT-W",
            "Gemini-0": "0-Gem-W",
            "0-Gemini-Weekly": "0-Gem-W",
            "0-Gemini-5h": "0-Gem-5h",
            "Gemini-Acc0-Weekly": "0-Gem-W",
            "Gemini-Acc0-5h": "0-Gem-5h",
            "Gemini-1": "1-Gem-W",
            "1-Gemini-Weekly": "1-Gem-W",
            "1-Gemini-5h": "1-Gem-5h",
            "Gemini-Acc1-Weekly": "1-Gem-W",
            "Gemini-Acc1-5h": "1-Gem-5h",
            "OpenCode": "OC-Today",
            "OpenCode-Today": "OC-Today",
            "OpenCode-Week": "OC-Week",
            "OpenCode-All": "OC-All"
        }
        active_id = mig_map.get(active_id)
        if not active_id or active_id not in all_item_ids:
            active_id = "0-AGY-G-W" if "0-AGY-G-W" in all_item_ids else (all_item_ids[0] if all_item_ids else "0-AGY-G-W")

    now_str = datetime.datetime.now().strftime("%H:%M")
    output = {
        "active": active_id,
        "updated_at": int(datetime.datetime.now().timestamp()),
        "updated_text": now_str,
        "groups": groups
    }

    # Write atomic stats.json
    tmp_file = STATS_FILE + ".tmp"
    with open(tmp_file, "w", encoding="utf-8") as f:
        json.dump(output, f, indent=2, ensure_ascii=False)
    os.replace(tmp_file, STATS_FILE)

    print(f"Stats updated at {now_str}. Groups: {len(groups)}, Total metrics: {len(all_item_ids)}")

if __name__ == "__main__":
    main()
