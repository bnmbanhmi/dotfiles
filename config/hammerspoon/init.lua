-- ============================================================================
-- SLIDEPAD CLONE PRO (SHORTCUT-ONLY + DYNAMIC TABS + STARRED PINNING)
-- ============================================================================

local slideWidth = 640
local sidebarWidth = 54
local topbarHeight = 40
local isShown = false
local activeTabIndex = 1

local defaultStore = hs.webview.datastore.default()
local windowMask = hs.drawing.windowBehaviors.canJoinAllSpaces + hs.drawing.windowBehaviors.fullScreenAuxiliary
local userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

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
local uiController = hs.webview.usercontent.new("slidepadUI")
local uiWebview = nil

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
        tabs = tabsPayload
    })

    uiWebview:evaluateJavaScript(string.format("window.renderState(%s);", stateJson))
end

-- 3. Hàm sắp xếp và hiển thị cửa sổ Webview
local function syncLayout(show)
    local s = hs.mouse.getCurrentScreen():fullFrame()
    if show then
        uiWebview:show()
        uiWebview:frame(hs.geometry.rect(s.x + s.w - slideWidth, s.y, slideWidth, s.h))
        uiWebview:bringToFront(true)

        for i, t in ipairs(tabs) do
            if i == activeTabIndex then
                t.wv:show()
                t.wv:frame(hs.geometry.rect(s.x + s.w - slideWidth, s.y + topbarHeight, slideWidth - sidebarWidth, s.h - topbarHeight))
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
    local s = hs.screen.mainScreen():fullFrame()
    local wv = hs.webview.new(hs.geometry.rect(s.x + s.w - slideWidth, s.y + topbarHeight, slideWidth - sidebarWidth, s.h - topbarHeight), {
        developerExtrasEnabled = true,
        datastore = defaultStore
    })
    wv:behavior(windowMask)
    wv:level(hs.drawing.windowLevels.floating + 1)
    wv:allowTextEntry(true)
    wv:allowNewWindows(false)
    wv:allowGestures(true)
    wv:windowStyle({"borderless", "utility", "nonactivating"})
    wv:userAgent(userAgent)

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
local function addNewTab(url, starred)
    local newTab = {
        url = url or "https://www.google.com",
        starred = starred or false
    }
    createWebviewForTab(newTab)
    table.insert(tabs, newTab)
    activeTabIndex = #tabs
    persistTabs()
    syncLayout(true)
    -- Đưa con trỏ chuột vào thẳng thanh địa chỉ để gõ web mới luôn
    uiWebview:evaluateJavaScript("setTimeout(() => { const el = document.getElementById('url-bar'); el.focus(); el.select(); }, 80);")
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
local sFrame = hs.screen.mainScreen():fullFrame()
uiWebview = hs.webview.new(hs.geometry.rect(sFrame.x + sFrame.w - slideWidth, sFrame.y, slideWidth, sFrame.h), {
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
    body { margin: 0; padding: 0; background: #18181b; color: #fff; overflow: hidden; height: 100vh; display: flex; flex-direction: column; border-left: 1px solid #2e2e36; }
    
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

-- 1. [Ctrl + Option + S]: Bật / Tắt nhanh cửa sổ Slidepad
hs.hotkey.bind({"ctrl", "alt"}, "S", function()
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