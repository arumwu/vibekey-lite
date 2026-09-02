# VibeKey Lite

繁體中文｜[English](#english)

VibeKey Lite 是一個小型、原生的 macOS 選單列程式。它設計為把 VibeKey 的六個硬體動作同步成 `F13`–`F18`，再用兩組軟體設定控制 AI 導航與系統功能；不需要安裝或常駐 Ulanzi Studio。

> **測試狀態：** 這是非官方專案，與 Ulanzi 無關。封包已用已知向量驗證，但 `0.1.0` 的實際寫入、F13–F18 輸出、斷線保存與長短按仍需 AU05 實機驗收。

## 功能

- AI 設定：旋鈕左／右是 ↓／↑，上鍵是 Option，中鍵是 Return，下鍵是 Tab；旋鈕短按預設不動作。
- 系統設定：旋鈕左／右降低／提高音量，上鍵播放／暫停，中鍵靜音，下鍵是 ⌘Tab；旋鈕短按預設不動作。
- 旋鈕短按執行目前設定中「旋鈕短按」那一格；長按約 0.65 秒固定切換 AI／系統。
- 兩組各有完整 6 格，共 12 格；選項依基本、導航、編輯、系統、媒體分類。
- 支援 Space、Delete、Home/End、Page Up/Down、複製貼上、復原重做、Spotlight、截圖、Mission Control、亮度與曲目控制等動作。
- 選單列使用程式即時繪製的可愛迷你 VibeKey 圖示；AI 狀態有閃光，系統狀態有滑桿線條。
- 設定以 JSON 保存，不需要帳號或網路。

## 建置

需求：Apple Silicon Mac、macOS 13 或更新版本、Xcode Command Line Tools。目前只建置 `arm64`，不支援 Intel Mac。

```sh
swift test
./build-app.sh
open '.build/app/VibeKey Lite.app'
```

成品位於 `.build/app/VibeKey Lite.app`，建置流程不會自動安裝到 `/Applications`。

## 第一次使用

1. 完全結束 Ulanzi Studio。
2. 開啟 VibeKey Lite。
3. 在「系統設定 → 隱私權與安全性」允許「輸入監控」與「輔助使用」：前者用來讀取 VibeKey，後者用來發出你設定的鍵盤與系統動作。
4. 點選單列的 VibeKey Lite 圖示，按「同步到裝置」，再於確認視窗選「同步」。

同步會送出 6 筆覆寫命令，目標是：上鍵 `F16`、中鍵 `F17`、下鍵 `F18`、旋鈕按下 `F13`、旋鈕向右 `F15`、旋鈕向左 `F14`。程式啟動時不會自動寫入；只有按下「同步到裝置」才會寫。

若 `ulanzi.UlanziStudio` 仍在執行，VibeKey Lite 會拒絕同步，避免兩個程式同時寫入裝置。

## 設定檔

```text
~/Library/Application Support/VibeKey Lite/config.json
```

## 裝置讀取與原生協定

執行期的輸入監聽使用 macOS `IOHIDManager`，只配對 VibeKey 的 `VID 0xFFF1`、`PID 0x00DD`、`PrimaryUsagePage 0x0C`、`PrimaryUsage 1`。回呼再只接受 `usagePage 0x07`、`usage 0x68`–`0x6D`、`reportID 3` 的 F13–F18 輸入；不會全域監看或攔截其他鍵盤。

輸入裝置以 non-seize 模式開啟，所以 VibeKey 送出的 F13–F18 仍可能同時到達當前景 App。「輸入監控」權限用於讀取這台裝置；「輔助使用」權限用於發出設定後的動作。

只有你明確按下「同步到裝置」時，寫入器才會尋找 `usagePage 0xFFFC`、`usage 1` 的 custom HID 介面。它以 non-seize 模式開啟介面，每個 64-byte output report 間隔約 80 ms。

封包使用 32-round TEA 與 little-endian words。Core 內含已知向量測試，避免加密或 byte order 被改壞。

這是獨立的 Swift 實作，**不包含、不複製，也不連結** Ulanzi Studio 的專有 `kwdm.dylib` 或其他 vendor binary。沒有第三方套件；實際硬體行為仍待 AU05 實機驗收。

專案以 [MIT License](LICENSE) 發布。

---

## English

VibeKey Lite is a small native macOS menu bar app designed to program the VibeKey's six hardware actions as `F13`–`F18`, then provide two software profiles for AI navigation and system controls. Ulanzi Studio is not required or kept running.

> **Test status:** This is an unofficial project and is not affiliated with Ulanzi. Packet encoding is covered by known vectors, but version `0.1.0` still requires AU05 validation of device writes, F13–F18 output, reconnect persistence, and short/long presses.

### Features

- AI profile: knob left/right sends ↓/↑; top sends Option, middle Return, and bottom Tab. Short knob press defaults to no action.
- System profile: knob left/right changes volume; top is play/pause, middle mute, and bottom ⌘Tab. Short knob press defaults to no action.
- Short knob press runs the mapping labeled **Short knob press**. Hold it for about 0.65 seconds to switch AI/System.
- Both profiles expose all six mappings, for 12 configurable mappings in total.
- Actions are grouped as Basic, Navigation, Editing, System, and Media, including Delete, clipboard/editing shortcuts, Spotlight, screenshots, Mission Control, brightness, and track controls.
- The menu bar uses a cute, code-native mini VibeKey icon, with a sparkle for AI and slider lines for System.
- Configuration is local JSON; no account or network is required.

### Build

Requires an Apple Silicon Mac, macOS 13 or newer, and Xcode Command Line Tools. The current build is `arm64` only; Intel Macs are not supported.

```sh
swift test
./build-app.sh
open '.build/app/VibeKey Lite.app'
```

The bundle is written to `.build/app/VibeKey Lite.app`; the script does not install it into `/Applications`.

### First use

1. Quit Ulanzi Studio completely.
2. Open VibeKey Lite.
3. Grant Input Monitoring and Accessibility under System Settings → Privacy & Security. Input Monitoring reads the VibeKey; Accessibility emits the configured keyboard and system actions.
4. Open the VibeKey Lite menu bar icon and click **同步到裝置** (Sync to device).

Sync sends six overwrite commands targeting: top `F16`, middle `F17`, bottom `F18`, knob press `F13`, knob right `F15`, and knob left `F14`. Nothing is written automatically at launch, and a confirmation dialog appears before every sync. Sync is blocked while the `ulanzi.UlanziStudio` bundle is running.

Configuration is stored at:

```text
~/Library/Application Support/VibeKey Lite/config.json
```

### Device input, native protocol, and independence

At runtime, an `IOHIDManager` listener only matches the VibeKey at `VID 0xFFF1`, `PID 0x00DD`, `PrimaryUsagePage 0x0C`, `PrimaryUsage 1`. Its callback then accepts only F13–F18 input with `usagePage 0x07`, `usage 0x68`–`0x6D`, and `reportID 3`. It neither watches nor intercepts other keyboards globally.

The input device is opened in non-seize mode, so its F13–F18 events may still reach the foreground app. Input Monitoring is used to read this device; Accessibility is used to emit configured actions.

Only an explicit **同步到裝置** (Sync to device) action starts the writer. It matches the custom HID interface at `usagePage 0xFFFC`, `usage 1`, opens it in non-seize mode, and spaces 64-byte output reports by about 80 ms.

Packets use 32-round TEA with little-endian words. The Core target includes a known-vector test.

This is an independent Swift implementation. It **does not contain, copy, or link against** Ulanzi Studio's proprietary `kwdm.dylib` or any other vendor binary. There are no third-party packages, and real hardware behavior still requires AU05 validation.

License: [MIT](LICENSE)
