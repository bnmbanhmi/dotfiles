# ⌨️ macOS Keyboard Shortcuts Map

Bản đồ phím tắt hệ thống và phím tắt cá nhân trên macOS, được quản lý tập trung trong repo `dotfiles`.

---

## 🤖 AI Assistants & Quick Prompts
| Shortcut | Action / Target | Description / Scope |
| :--- | :--- | :--- |
| `Option + Space` | **Gemini** | Quick prompt / Gemini launcher |
| `Ctrl + G` | **Gemini in Chrome** | Mở nhanh tab / tiện ích Gemini trong Google Chrome |
| `Ctrl + M` | **Meta AI** | Mở nhanh Meta AI |
| `Ctrl + C` | **ChatGPT** | Mở nhanh ChatGPT |

---

## 🚀 System, Launchers & Terminals
| Shortcut | Action / Target | App |
| :--- | :--- | :--- |
| `Cmd + Space` | **Raycast** | Quick launcher, clipboard history, extension search |
| `Cmd + \`` | **Quake / Dropdown Terminal** | Toggle quick terminal của Ghostty hoặc Warp |

---

## 🌐 Slidepad Mini-Browser (`Hammerspoon`)
Cửa sổ web mini trượt từ cạnh phải màn hình, quản lý qua `config/hammerspoon/init.lua`.

| Shortcut | Action | Description |
| :--- | :--- | :--- |
| `Ctrl + Option + B` | **Bật / Tắt Slidepad** | Toggle hiển thị mini-browser (B = Browser) |
| `Ctrl + Option + T` | **Tab mới** | Mở tab Google mới và focus ô tìm kiếm |
| `Ctrl + Option + W` | **Đóng Tab** | Đóng tab web hiện tại |
| `Ctrl + Option + D` | **Ghim / Bỏ ghim Tab** | Star / Unstar tab đưa lên đầu danh sách |
| `Ctrl + Option + 1..9` | **Chuyển nhanh Tab 1..9** | Chuyển nhanh giữa các tab theo số thứ tự |

---

## ⏱️ Custom Menu Bar Utilities (`tools/`)
Các công cụ native Swift hiển thị trên thanh Menu Bar macOS.

| Tool | Trigger / Shortcut | Description |
| :--- | :--- | :--- |
| **MenuBar Notes** | Click icon Menu Bar | Notepad ghi chú nhanh với giao diện Liquid Glass |
| **Smart Pomodoro** | Apple Shortcut `Pomodoro` | Đếm lùi Pomodoro (mặc định 25 phút, tự nghỉ) |
| **Stopwatch Pomodoro** | Apple Shortcut / CLI | Đếm xuôi + lưu Lap định dạng giờ thập phân (`1.5h`) |

---

> [!TIP]
> **Quy tắc khi thêm phím tắt mới:**
> 1. Tra cứu bảng trên trước khi gán phím mới để tránh xung đột (Collision).
> 2. Ưu tiên tổ hợp phím có tính gợi nhớ (Mnemonic) và giữ nguyên modifier theo cụm chức năng (ví dụ `Ctrl + Option + <phím>` cho Slidepad).
