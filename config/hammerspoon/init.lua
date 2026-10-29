-- ============================================================================
-- SLIDEPAD CLONE PRO (SHORTCUT-ONLY + DYNAMIC TABS + STARRED PINNING)
-- ============================================================================

-- Bật IPC CLI (lệnh `hs`) và AppleScript để tiện điều khiển từ terminal
require("hs.ipc")
hs.allowAppleScript(true)

-- Tự động reload khi cấu hình init.lua thay đổi
local function reloadConfig(files)
    local doReload = false
    for _, file in ipairs(files) do
        if file:sub(-4) == ".lua" then
            doReload = true
            break
        end
    end
    if doReload then
        hs.reload()
    end
end
local configWatcher = hs.pathwatcher.new(os.getenv("HOME") .. "/Git/dotfiles/config/hammerspoon", reloadConfig):start()
local homeConfigWatcher = hs.pathwatcher.new(os.getenv("HOME") .. "/.hammerspoon", reloadConfig):start()

local slideWidth = 640
local sidebarWidth = 54
local topbarHeight = 40
local isShown = false
local activeTabIndex = 1

local padDock = hs.settings.get("slidepad_dock") or "right" -- "right", "left", "top", "bottom"

local defaultStore = hs.webview.datastore.default()
local windowMask = hs.drawing.windowBehaviors.canJoinAllSpaces + hs.drawing.windowBehaviors.fullScreenAuxiliary
local userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

-- Hàm tính toán khung hình (Frame) động cho Slidepad theo 4 hướng
local function getPadFrames()
    local s = hs.mouse.getCurrentScreen():fullFrame()
    local padX, padY, padW, padH

    if padDock == "left" then
        -- Cột dọc bên trái: giữ nguyên tỉ lệ 640px, cao 100%
        padW = slideWidth
        padH = s.h
        padX = s.x
        padY = s.y
    elseif padDock == "top" then
        -- Chiếm 1/2 nửa trên màn hình: rộng 100%, cao 50%
        padW = s.w
        padH = math.floor(s.h / 2)
        padX = s.x
        padY = s.y
    elseif padDock == "bottom" then
        -- Chiếm 1/2 nửa dưới màn hình: rộng 100%, cao 50%
        padW = s.w
        padH = math.floor(s.h / 2)
        padX = s.x
        padY = s.y + s.h - padH
    else -- "right" (mặc định)
        -- Cột dọc bên phải: giữ nguyên tỉ lệ 640px, cao 100%
        padW = slideWidth
        padH = s.h
        padX = s.x + s.w - padW
        padY = s.y
    end

    local uiRect = hs.geometry.rect(padX, padY, padW, padH)
    local tabRect = hs.geometry.rect(padX, padY + topbarHeight, padW - sidebarWidth, padH - topbarHeight)

    return uiRect, tabRect
end

-- 1. Khôi phục danh sách Tab đã lưu (Hoặc tạo mặc định nếu chạy lần đầu)
local savedTabs = hs.settings.get("slidepad_saved_tabs")
if not savedTabs or #savedTabs == 0 then
    savedTabs = {
        { url = "https://chatgpt.com", starred = true },
        { url = "https://keep.google.com", starred = true },
        { url = "https://www.google.com", starred = false }
    }
end

local tabs = {} -- Chứa { url, starred, wv, loading }
local addNewTab = nil -- Khai báo trước hàm addNewTab để các callback có thể gọi
local uiController = hs.webview.usercontent.new("slidepadUI")
local uiWebview = nil

-- Controller quản lý nội dung Webview trong các Tab (Bắt link mở tab mới)
local tabContentController = hs.webview.usercontent.new("slidepadTabContent")

local tabContentScript = [[
(function() {
    // 1. Bắt click vào link có target="_blank", target="_new" hoặc giữ phím Cmd/Ctrl/chuột giữa
    document.addEventListener('click', function(e) {
        let el = e.target;
        while (el && el.tagName !== 'A') {
            el = el.parentElement;
        }
        if (!el || !el.href) return;

        const target = el.getAttribute('target') || el.target;
        const isBlank = target === '_blank' || target === '_new';
        const isModifier = e.metaKey || e.ctrlKey || e.button === 1;

        if ((isBlank || isModifier) && el.href.startsWith('http')) {
            e.preventDefault();
            e.stopPropagation();
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.slidepadTabContent) {
                window.webkit.messageHandlers.slidepadTabContent.postMessage({
                    action: "openNewTab",
                    url: el.href
                });
            }
        }
    }, true);

    // 2. Bắt chuột giữa (auxclick)
    document.addEventListener('auxclick', function(e) {
        if (e.button === 1) {
            let el = e.target;
            while (el && el.tagName !== 'A') {
                el = el.parentElement;
            }
            if (!el || !el.href) return;
            if (el.href.startsWith('http')) {
                e.preventDefault();
                e.stopPropagation();
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.slidepadTabContent) {
                    window.webkit.messageHandlers.slidepadTabContent.postMessage({
                        action: "openNewTab",
                        url: el.href
                    });
                }
            }
        }
    }, true);

    // 3. Bắt window.open() từ JavaScript
    const _origOpen = window.open;
    window.open = function(url, target, features) {
        if (url && typeof url === 'string') {
            try {
                const absUrl = new URL(url, window.location.href).href;
                if (absUrl.startsWith('http://') || absUrl.startsWith('https://')) {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.slidepadTabContent) {
                        window.webkit.messageHandlers.slidepadTabContent.postMessage({
                            action: "openNewTab",
                            url: absUrl
                        });
                    }
                    return null;
                }
            } catch(e) {}
        }
        return _origOpen ? _origOpen.apply(this, arguments) : null;
    };
})();
]]

tabContentController:injectScript({
    source = tabContentScript,
    mainFrame = false,
    injectionTime = "documentStart"
})

tabContentController:setCallback(function(msg)
    local data = msg.body
    if data and data.action == "openNewTab" and data.url then
        if addNewTab then
            addNewTab(data.url, false)
        end
    end
end)

-- Hàm lưu trạng thái các Tab vào ổ cứng để không bị mất khi Reload/Tắt máy
local function persistTabs()
    local dataToSave = {}
    for _, t in ipairs(tabs) do
        table.insert(dataToSave, {
            url = t.wv and t.wv:url() or t.url,
            starred = t.starred and true or false
        })
    end
    hs.settings.set("slidepad_saved_tabs", dataToSave)
end

-- Hàm lấy tên miền để tự động hiển thị Favicon chuẩn của trang web
local function getDomain(url)
    if not url then return "google.com" end
    local domain = string.match(url, "^https?://([^/]+)")
    return domain or "google.com"
end

-- 2. Đồng bộ dữ liệu sang giao diện HTML (Thanh địa chỉ + Cột Tab + Ngôi sao)
local function refreshUI()
    if not uiWebview then return end
    local currentTab = tabs[activeTabIndex]
    if not currentTab then return end

    local currentUrl = (currentTab.wv and currentTab.wv:url()) or currentTab.url or ""
    local isLoading = (currentTab.wv and currentTab.wv:loading()) or false
    local isStarred = currentTab.starred and true or false

    local tabsPayload = {}
    for i, t in ipairs(tabs) do
        local u = (t.wv and t.wv:url()) or t.url or "https://www.google.com"
        local title = (t.wv and t.wv:title()) or u
        table.insert(tabsPayload, {
            index = i,
            url = u,
            title = title,
            domain = getDomain(u),
            starred = t.starred and true or false,
            active = (i == activeTabIndex)
        })
    end

    local stateJson = hs.json.encode({
        url = currentUrl,
        loading = isLoading,
        starred = isStarred,
        tabs = tabsPayload,
        dock = padDock
    })

    uiWebview:evaluateJavaScript(string.format("window.renderState(%s);", stateJson))
end

-- 3. Hàm sắp xếp và hiển thị cửa sổ Webview
local function syncLayout(show)
    if show then
        local uiRect, tabRect = getPadFrames()
        uiWebview:show()
        uiWebview:frame(uiRect)
        uiWebview:bringToFront(true)

        for i, t in ipairs(tabs) do
            if i == activeTabIndex then
                t.wv:show()
                t.wv:frame(tabRect)
                t.wv:bringToFront(true)
                local win = t.wv:hswindow()
                if win then win:focus() end
            else
                t.wv:hide()
            end
        end
        isShown = true
        refreshUI()
    else
        -- Ẩn hoàn toàn khi đóng
        uiWebview:hide()
        for _, t in ipairs(tabs) do
            t.wv:hide()
        end
        isShown = false
    end
end

-- 4. Hàm khởi tạo một Webview cho Tab
local function createWebviewForTab(tabObj)
    local _, tabRect = getPadFrames()
    local wv = hs.webview.new(tabRect, {
        developerExtrasEnabled = true,
        datastore = defaultStore
    }, tabContentController)
    wv:behavior(windowMask)
    wv:level(hs.drawing.windowLevels.floating + 1)
    wv:allowTextEntry(true)
    wv:allowNewWindows(true)
    wv:allowGestures(true)
    wv:windowStyle({"borderless", "utility", "nonactivating"})
    wv:userAgent(userAgent)

    -- Bắt sự kiện newWindow cấp hệ thống (dự phòng cho link native)
    wv:policyCallback(function(action, newView, navAction)
        if action == "newWindow" then
            local targetUrl = nil
            if navAction and navAction.request and navAction.request.URL then
                targetUrl = navAction.request.URL
            end
            if targetUrl and targetUrl ~= "" and targetUrl ~= "about:blank" then
                if addNewTab then
                    addNewTab(targetUrl, false)
                end
            end
            return false -- Chặn mở cửa sổ rời của hệ thống
        end
        return true
    end)

    wv:navigationCallback(function(action, webviewObj)
        if action == "didStartProvisionalNavigation" or action == "didFinishNavigation" or action == "didFailNavigation" then
            persistTabs()
            refreshUI()
        end
    end)

    wv:url(tabObj.url)
    tabObj.wv = wv
end

-- 5. Các hàm thao tác Tab (Thêm mới, Đóng, Gắn sao đưa lên đầu)
addNewTab = function(url, starred)
    local isDefault = (url == nil or url == "" or url == "https://www.google.com")
    local targetUrl = (not isDefault and url) or "https://www.google.com"
    local newTab = {
        url = targetUrl,
        starred = starred or false
    }
    createWebviewForTab(newTab)
    table.insert(tabs, newTab)
    activeTabIndex = #tabs
    persistTabs()
    syncLayout(true)

    -- Chỉ đưa con trỏ vào thanh địa chỉ nếu là Tab trắng mặc định
    if isDefault then
        uiWebview:evaluateJavaScript("setTimeout(() => { const el = document.getElementById('url-bar'); if(el){ el.focus(); el.select(); } }, 80);")
    end
end

local function closeTab(index)
    if #tabs <= 1 then
        -- Nếu chỉ còn 1 tab cuối cùng thì reset về Google thay vì xoá trắng
        tabs[1].wv:url("https://www.google.com")
        tabs[1].starred = false
        persistTabs()
        refreshUI()
        return
    end

    local target = tabs[index]
    if target and target.wv then
        target.wv:delete()
    end
    table.remove(tabs, index)

    if activeTabIndex >= index and activeTabIndex > 1 then
        activeTabIndex = activeTabIndex - 1
    end
    persistTabs()
    syncLayout(isShown)
end

local function toggleStarCurrentTab()
    local currentTab = tabs[activeTabIndex]
    if not currentTab then return end

    currentTab.starred = not currentTab.starred
    currentTab.url = currentTab.wv:url() or currentTab.url

    -- Rút tab hiện tại ra để sắp xếp lại vị trí
    table.remove(tabs, activeTabIndex)

    if currentTab.starred then
        -- Nếu vừa gắn Sao (★): Đẩy lên trên cùng (nằm ngay cuối nhóm các tab đã có sao)
        local insertPos = 1
        for i, t in ipairs(tabs) do
            if t.starred then
                insertPos = i + 1
            else
                break
            end
        end
        table.insert(tabs, insertPos, currentTab)
        activeTabIndex = insertPos
    else
        -- Nếu bỏ Sao (☆): Đưa xuống ngay bên dưới nhóm các tab có sao
        local insertPos = 1
        for i, t in ipairs(tabs) do
            if t.starred then
                insertPos = i + 1
            else
                break
            end
        end
        table.insert(tabs, insertPos, currentTab)
        activeTabIndex = insertPos
    end

    persistTabs()
    syncLayout(isShown)
end

-- Khởi tạo các Tab ban đầu từ bộ nhớ
for _, item in ipairs(savedTabs) do
    local t = { url = item.url, starred = item.starred }
    createWebviewForTab(t)
    table.insert(tabs, t)
end

-- 6. Giao diện Thanh Địa chỉ + Cột Sidebar động
local uiRect, _ = getPadFrames()
uiWebview = hs.webview.new(uiRect, {
    developerExtrasEnabled = false
}, uiController)
uiWebview:behavior(windowMask)
uiWebview:level(hs.drawing.windowLevels.floating)
uiWebview:allowTextEntry(true)
uiWebview:windowStyle({"borderless", "utility", "nonactivating"})

local uiHtml = string.format([[
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
    * { box-sizing: border-box; user-select: none; font-family: -apple-system, BlinkMacSystemFont, sans-serif; }
    body { margin: 0; padding: 0; background: #18181b; color: #fff; overflow: hidden; height: 100vh; display: flex; flex-direction: column; }
    body.dock-right { border-left: 1px solid #2e2e36; border-right: none; }
    body.dock-left { border-right: 1px solid #2e2e36; border-left: none; }
    body.dock-top { border-bottom: 1px solid #2e2e36; }
    body.dock-bottom { border-top: 1px solid #2e2e36; }
    
    /* Thanh địa chỉ phía trên */
    .topbar { height: %dpx; display: flex; align-items: center; padding: 0 8px; gap: 5px; background: #202026; border-bottom: 1px solid #2e2e36; position: relative; }
    .nav-btn { background: transparent; border: none; color: #a1a1aa; font-size: 14px; width: 28px; height: 28px; border-radius: 6px; cursor: pointer; display: flex; align-items: center; justify-content: center; transition: 0.15s; }
    .nav-btn:hover { background: #32323c; color: #fff; }
    .star-btn { font-size: 16px; color: #71717a; }
    .star-btn.starred { color: #facc15; text-shadow: 0 0 8px rgba(250, 204, 21, 0.4); }
    
    .url-input { flex: 1; height: 28px; background: #121216; border: 1px solid #32323c; border-radius: 6px; color: #e4e4e7; padding: 0 10px; font-size: 12px; outline: none; user-select: text; }
    .url-input:focus { border-color: #3b82f6; background: #09090b; }

    /* Thanh Loading */
    .loader { position: absolute; bottom: 0; left: 0; height: 2px; background: #3b82f6; width: 0%%; transition: width 0.3s ease, opacity 0.3s; opacity: 0; }
    .loader.loading { width: 85%%; opacity: 1; animation: pulse 1.2s infinite ease-in-out; }
    @keyframes pulse { 0%% { opacity: 0.4; } 50%% { opacity: 1; } 100%% { opacity: 0.4; } }

    /* Khu vực bên dưới & Cột Sidebar */
    .main-area { flex: 1; display: flex; justify-content: flex-end; overflow: hidden; }
    .sidebar { width: %dpx; background: #18181b; border-left: 1px solid #2e2e36; display: flex; flex-direction: column; align-items: center; padding: 10px 0; gap: 8px; overflow-y: auto; }
    .sidebar::-webkit-scrollbar { display: none; }

    .divider { width: 28px; height: 1px; background: #32323c; margin: 2px 0; flex-shrink: 0; }

    /* Nút Tab trên Sidebar */
    .tab-item { width: 38px; height: 38px; border-radius: 10px; display: flex; align-items: center; justify-content: center; cursor: pointer; background: #27272f; transition: all 0.15s; position: relative; flex-shrink: 0; }
    .tab-item:hover { background: #363642; }
    .tab-item.active { background: #2563eb; box-shadow: 0 0 0 2px rgba(59, 130, 246, 0.4); }
    .tab-item img { width: 20px; height: 20px; border-radius: 4px; }

    /* Huy hiệu ngôi sao nhỏ cho Tab được ghim */
    .star-badge { position: absolute; bottom: -2px; right: -2px; font-size: 9px; background: #18181b; border-radius: 50%%; padding: 1px; line-height: 1; }

    /* Nút Xoá Tab khi rê chuột vào */
    .close-badge { position: absolute; top: -4px; right: -4px; width: 16px; height: 16px; border-radius: 50%%; background: #ef4444; color: #fff; font-size: 10px; font-weight: bold; display: none; align-items: center; justify-content: center; line-height: 1; box-shadow: 0 1px 3px rgba(0,0,0,0.5); }
    .tab-item:hover .close-badge { display: flex; }
    .close-badge:hover { transform: scale(1.15); background: #dc2626; }

    /* Nút Thêm Tab (+) */
    .add-btn { width: 36px; height: 36px; border-radius: 10px; border: 1px dashed #52525b; background: transparent; color: #a1a1aa; font-size: 20px; cursor: pointer; display: flex; align-items: center; justify-content: center; flex-shrink: 0; transition: 0.15s; margin-top: 2px; }
    .add-btn:hover { border-color: #3b82f6; color: #fff; background: #27272f; }
</style>
</head>
<body>
    <div class="topbar">
        <button class="nav-btn" onclick="sendCmd('back')" title="Quay lại">◀</button>
        <button class="nav-btn" onclick="sendCmd('forward')" title="Tiến tới">▶</button>
        <button class="nav-btn" id="reload-btn" onclick="sendCmd('reload')" title="Tải lại">↻</button>
        <input type="text" id="url-bar" class="url-input" placeholder="Nhập địa chỉ web hoặc tìm kiếm Google..." onkeydown="if(event.key==='Enter') sendCmd('navigate', this.value)" onfocus="this.select()">
        <button class="nav-btn star-btn" id="star-btn" onclick="sendCmd('toggleStar')" title="Yêu thích & Ghim lên đầu cột Tab">☆</button>
        <div id="loader" class="loader"></div>
    </div>
    <div class="main-area">
        <div class="sidebar" id="sidebar-list"></div>
    </div>
    <script>
        function sendCmd(action, val) {
            webkit.messageHandlers.slidepadUI.postMessage({ action: action, value: val });
        }

        window.renderState = function(state) {
            document.body.className = 'dock-' + (state.dock || 'right');
            const urlBar = document.getElementById('url-bar');
            if (document.activeElement !== urlBar && state.url) {
                urlBar.value = state.url;
            }
            const loader = document.getElementById('loader');
            const reloadBtn = document.getElementById('reload-btn');
            if (state.loading) {
                loader.classList.add('loading');
                reloadBtn.innerText = '✕';
            } else {
                loader.classList.remove('loading');
                reloadBtn.innerText = '↻';
            }

            const starBtn = document.getElementById('star-btn');
            if (state.starred) {
                starBtn.classList.add('starred');
                starBtn.innerText = '★';
            } else {
                starBtn.classList.remove('starred');
                starBtn.innerText = '☆';
            }

            const sidebar = document.getElementById('sidebar-list');
            sidebar.innerHTML = '';

            let hasStarred = false;
            let dividerInserted = false;

            state.tabs.forEach((t) => {
                if (t.starred) hasStarred = true;
                if (!t.starred && hasStarred && !dividerInserted) {
                    const div = document.createElement('div');
                    div.className = 'divider';
                    sidebar.appendChild(div);
                    dividerInserted = true;
                }

                const item = document.createElement('div');
                item.className = 'tab-item' + (t.active ? ' active' : '');
                item.title = t.title || t.url;
                item.onclick = () => sendCmd('switchTab', t.index);

                const img = document.createElement('img');
                img.src = 'https://www.google.com/s2/favicons?sz=64&domain=' + encodeURIComponent(t.domain);
                item.appendChild(img);

                if (t.starred) {
                    const badge = document.createElement('span');
                    badge.className = 'star-badge';
                    badge.innerText = '⭐';
                    item.appendChild(badge);
                }

                const closeBtn = document.createElement('div');
                closeBtn.className = 'close-badge';
                closeBtn.innerText = '×';
                closeBtn.title = 'Đóng Tab';
                closeBtn.onclick = (e) => {
                    e.stopPropagation();
                    sendCmd('closeTab', t.index);
                };
                item.appendChild(closeBtn);

                sidebar.appendChild(item);
            });

            const addBtn = document.createElement('button');
            addBtn.className = 'add-btn';
            addBtn.innerText = '+';
            addBtn.title = 'Mở Tab mới (Ctrl+Opt+T)';
            addBtn.onclick = () => sendCmd('addTab');
            sidebar.appendChild(addBtn);
        };
    </script>
</body>
</html>
]], topbarHeight, sidebarWidth)

uiWebview:html(uiHtml)

-- 7. Xử lý các tương tác từ giao diện HTML gửi về
uiController:setCallback(function(msg)
    local data = msg.body
    local currentTab = tabs[activeTabIndex]
    if not currentTab then return end

    if data.action == "switchTab" then
        activeTabIndex = tonumber(data.value)
        syncLayout(true)
    elseif data.action == "addTab" then
        addNewTab("https://www.google.com", false)
    elseif data.action == "closeTab" then
        closeTab(tonumber(data.value))
    elseif data.action == "toggleStar" then
        toggleStarCurrentTab()
    elseif data.action == "navigate" then
        local input = data.value or ""
        if not string.match(input, "^https?://") then
            if string.find(input, "%.") and not string.find(input, " ") then
                input = "https://" .. input
            else
                input = "https://www.google.com/search?q=" .. hs.http.encodeForQuery(input)
            end
        end
        currentTab.url = input
        currentTab.wv:url(input)
        persistTabs()
        local win = currentTab.wv:hswindow()
        if win then win:focus() end
    elseif data.action == "back" then currentTab.wv:goBack()
    elseif data.action == "forward" then currentTab.wv:goForward()
    elseif data.action == "reload" then
        if currentTab.wv:loading() then
            currentTab.wv:stopLoading()
        else
            currentTab.wv:reload()
        end
        refreshUI()
    end
end)

-- Mặc định giấu đi khi mới khởi động
syncLayout(false)

-- ============================================================================
-- HỆ THỐNG PHÍM TẮT ĐIỀU KHIỂN (SHORTCUT-ONLY)
-- ============================================================================

-- 1. [Ctrl + Option + B]: Bật / Tắt nhanh cửa sổ Slidepad
hs.hotkey.bind({"ctrl", "alt"}, "B", function()
    syncLayout(not isShown)
end)

-- 2. [Ctrl + Option + T]: Mở nhanh một Tab mới và trỏ sẵn vào ô nhập địa chỉ
hs.hotkey.bind({"ctrl", "alt"}, "T", function()
    addNewTab("https://www.google.com", false)
end)

-- 3. [Ctrl + Option + W]: Đóng Tab hiện tại
hs.hotkey.bind({"ctrl", "alt"}, "W", function()
    if isShown then
        closeTab(activeTabIndex)
    end
end)

-- 4. [Ctrl + Option + D]: Gắn sao / Bỏ sao nhanh cho trang hiện tại (Đẩy lên đầu cột Tab)
hs.hotkey.bind({"ctrl", "alt"}, "D", function()
    if isShown then
        toggleStarCurrentTab()
    end
end)

-- 5. [Ctrl + Option + 1..9]: Chuyển nhanh tới Tab theo thứ tự từ trên xuống dưới
for i = 1, 9 do
    hs.hotkey.bind({"ctrl", "alt"}, tostring(i), function()
        if tabs[i] then
            activeTabIndex = i
            syncLayout(true)
        end
    end)
end

-- ============================================================================
-- ĐIỀU HƯỚNG VỊ TRÍ SLIDEPAD (4 HƯỚNG)
-- ============================================================================

-- 6. [Ctrl + Option + Left]: Đưa Slidepad sang dải dọc mép Trái (tỉ lệ chuẩn 640px)
hs.hotkey.bind({"ctrl", "alt"}, "Left", function()
    padDock = "left"
    hs.settings.set("slidepad_dock", "left")
    syncLayout(true)
    hs.alert.show("Slidepad: Cột Trái ⬅️", 0.6)
end)

-- 7. [Ctrl + Option + Right]: Đưa Slidepad sang dải dọc mép Phải (tỉ lệ chuẩn 640px)
hs.hotkey.bind({"ctrl", "alt"}, "Right", function()
    padDock = "right"
    hs.settings.set("slidepad_dock", "right")
    syncLayout(true)
    hs.alert.show("Slidepad: Cột Phải ➡️", 0.6)
end)

-- 8. [Ctrl + Option + Up]: Đưa Slidepad chiếm trọn 1/2 nửa Trên màn hình
hs.hotkey.bind({"ctrl", "alt"}, "Up", function()
    padDock = "top"
    hs.settings.set("slidepad_dock", "top")
    syncLayout(true)
    hs.alert.show("Slidepad: 1/2 Trên ⬆️", 0.6)
end)

-- 9. [Ctrl + Option + Down]: Đưa Slidepad chiếm trọn 1/2 nửa Dưới màn hình
hs.hotkey.bind({"ctrl", "alt"}, "Down", function()
    padDock = "bottom"
    hs.settings.set("slidepad_dock", "bottom")
    syncLayout(true)
    hs.alert.show("Slidepad: 1/2 Dưới ⬇️", 0.6)
end)