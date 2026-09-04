# VibeKey Lite

繁體中文｜[English](#english)

VibeKey Lite 是 AU05／VibeKey 的輕量 macOS 選單列設定工具。它提供兩組完整六鍵設定，不需要 Ulanzi Studio、帳號或網路。

## 主要功能

- AI、系統兩組設定；每組六個原生單按動作都可自訂。
- 旋鈕單按保留原設定；雙按可另行設定（預設切組）；按住約 0.65 秒固定切組。
- 可錄製實體鍵盤按鍵或最多四鍵的組合鍵。
- 可分辨左／右 Option、Control、Shift、Command，並內建 F1–F12、Delete、Forward Delete、方向鍵、剪貼簿及媒體控制。
- 介面直接顯示 AU05 電量、充電狀態、待機時間與自動關機時間；這些資料只讀取，不會擅自改寫。
- 按「設為離線備用」會把目前完整六格寫進 AU05；App 正常結束後使用那一組。
- 不包含或載入 Ulanzi 的程式庫，也不會連線到雲端。

AU05 本身只有一組六格儲存空間。VibeKey Lite 保存兩組；日常切組只切 App 內的設定，不會反覆寫入裝置。只有明確按「設為離線備用」才會更新硬體內的六格。

## 單按、雙按與長按

AU05 韌體只會離線保存單按。為了同時分辨三種手勢，VibeKey Lite 執行時會啟用裝置的線上事件模式，接收六個實體控制的事件，再送出目前設定。

- 單按會等待約 0.28 秒，確認不是雙按後才執行。
- 雙按使用「旋鈕雙按」那一格；預設是切換 AI／系統。
- 長按達 0.65 秒後，放開時切換 AI／系統。
- 正常結束、Mac 睡眠、Ulanzi Studio 開啟或線上傳輸失敗時，App 會明確退出線上模式，讓 AU05 回到原生六鍵。
- Mac 關機前會強制交還原生模式；下次啟動會先清除可能殘留的線上狀態，再重新連線。若開機時 USB 尚未就緒，會自動重試三次；全程不會重寫六鍵設定。
- 裝置閒置達它保存的待機時間後，App 會停止線上心跳並交還原生模式，讓 AU05 自行待機與關機。
- 睡醒第一下使用離線備用的原生單按；App 偵測到該輸入後，後續單按、雙按與長按會自動恢復。
- 待機前後打開選單列設定只會查看狀態，不會喚醒 AU05，也不會重算閒置時間。
- App 意外終止後的韌體逾時回復曾實際觀察成功；精確回復時間仍需依裝置韌體驗證。

線上手勢需要 macOS 的「輸入監控」與「輔助使用」權限。權限不完整時不會啟用線上模式，AU05 仍直接執行原生六鍵。

## Fn 限制

Fn 不是一般 USB HID 按鍵，AU05 韌體無法把它保存成離線快捷鍵。錄製器遇到 Fn 會明確拒絕，不會偷換成別的按鍵；實機不會輸出的 `F19`、`F20` 也會被拒絕。Typeless 聽寫可直接使用「左 Option」。

## 使用方式

1. 完全結束 Ulanzi Studio。
2. 開啟 VibeKey Lite。
3. 在「系統設定 → 隱私權與安全性」允許 VibeKey Lite 的「輸入監控」與「輔助使用」。
4. 從選單列的小控制器圖示打開介面，設定兩組動作。

若要立即停用多重手勢，按「只用原生」；AU05 會回到硬體裡的離線備用六鍵。

設定檔位於：

```text
~/Library/Application Support/VibeKey Lite/config.json
```

## 建置

需求：Apple Silicon Mac、macOS 13 或更新版本、Xcode Command Line Tools。

```sh
swift test
./build-app.sh
open '.build/app/VibeKey Lite.app'
```

每次使用同一張有效簽章，macOS 才能沿用權限：

```sh
VIBEKEY_SIGNING_IDENTITY="Apple Development: Your Name (TEAMID)" ./build-app.sh
```

成品位於 `.build/app/VibeKey Lite.app`；建置不會自動安裝。

## 實作與安全

程式只配對 AU05 的 `VID 0xFFF1`、`PID 0x00DD`。原生設定與線上事件都走 custom usage page `0xFFFC`、usage `1`、report ID `0x55` 的 64-byte TEA 加密 report。

寫入前會先驗證完整六格。不支援的動作不會造成只寫一半；若裝置在實際 I/O 中途拔除，仍可能留下混合設定，此時重新寫入目前設定即可。

這是獨立製作的非官方相容實作，與 Ulanzi 無關。專案不包含、不複製、不載入，也不連結 Ulanzi Studio 的 `kwdm.dylib` 或其他專有檔案。

專案使用 [MIT License](LICENSE)。協定研究見 [docs/protocol.md](docs/protocol.md)。

---

## English

VibeKey Lite is a lightweight macOS menu bar configurator for the AU05/VibeKey. It provides two complete six-control profiles without Ulanzi Studio, an account, or a network connection.

### Features

- Two profiles with all six native single-press actions configurable.
- Encoder single press keeps its configured action; double press has a separate configurable action (profile switching by default); a 0.65-second hold switches profiles.
- Record a physical key or a chord of up to four keys.
- Left/right Option, Control, Shift, and Command remain distinct. F1–F12, Delete, Forward Delete, navigation, editing, and supported media actions are included.
- The UI shows battery, charging state, standby time, and automatic power-off time using read-only device queries.
- **Set as Offline Backup** writes the current six single-press mappings to the AU05. After a normal app exit, the device uses that profile.
- No vendor library, account, cloud connection, or third-party dependency.

The AU05 stores one six-slot profile. VibeKey Lite keeps two profiles; normal profile switching only changes the host-side selection and does not repeatedly write device flash. Hardware changes occur only when **Set as Offline Backup** is explicitly used.

### Single, double, and hold

The AU05 firmware stores only single-press actions offline. While VibeKey Lite runs, it enables the device's online event mode, receives all six physical controls, and emits the configured actions so it can distinguish all three gestures.

- A single press waits about 0.28 seconds to rule out a double press.
- A double press uses its own configurable row and switches profiles by default.
- A 0.65-second hold switches profiles when released.
- Normal quit, Mac sleep, vendor-app launch, or transport failure explicitly leaves online mode and restores native operation.
- Before Mac shutdown the app forces native mode; the next launch clears any stale online state before reconnecting. If USB is not ready yet, it retries three times without rewriting the six stored shortcuts.
- When the saved device standby delay elapses without AU05 input, the app stops host-online traffic and hands control back to native mode so firmware standby and power-off can run.
- The first wake input completes the offline backup's native single-press action, including key release; the app then restores all subsequent single-, double-, and long-press gestures.
- Opening the menu bar settings only shows status; it neither wakes the AU05 nor restarts the inactivity timer.
- Firmware timeout recovery after an unexpected app stop has been observed once; exact recovery timing still depends on controlled device testing.

Online gestures require both Input Monitoring and Accessibility permission. If either permission is unavailable, online mode is not enabled and the AU05 continues using its six native actions.

### Fn limitation

Fn is not a normal USB HID key and cannot be stored as an offline AU05 shortcut. The recorder explicitly rejects Fn instead of substituting another key. It also rejects `F19` and `F20`, which the tested AU05 did not emit. Typeless dictation can use **Left Option** directly.

### Usage

1. Quit Ulanzi Studio completely.
2. Open VibeKey Lite.
3. Allow both Input Monitoring and Accessibility under System Settings → Privacy & Security.
4. Open the small controller icon in the menu bar and configure both profiles.

Use **Native Only** for an immediate exit from enhanced gesture mode; the AU05 returns to its stored six-key offline backup.

Configuration is stored at:

```text
~/Library/Application Support/VibeKey Lite/config.json
```

### Build

Requires Apple Silicon, macOS 13 or newer, and Xcode Command Line Tools.

```sh
swift test
./build-app.sh
open '.build/app/VibeKey Lite.app'
```

Use the same valid signing identity for every build so macOS can preserve permissions:

```sh
VIBEKEY_SIGNING_IDENTITY="Apple Development: Your Name (TEAMID)" ./build-app.sh
```

The bundle is written to `.build/app/VibeKey Lite.app`; the build does not install it.

### Implementation and safety

The app only matches AU05 `VID 0xFFF1`, `PID 0x00DD`. Native settings and online events use custom usage page `0xFFFC`, usage `1`, report ID `0x55`, with encrypted 64-byte reports.

All six mappings are validated before a write begins. A physical disconnect during I/O can still leave a mixed profile; reconnect and rewrite the active profile if that happens.

This is an independent, unofficial compatibility implementation. It does not contain, copy, load, or link against Ulanzi Studio's `kwdm.dylib` or other proprietary files.

Licensed under the [MIT License](LICENSE). See [docs/protocol.md](docs/protocol.md) for protocol notes.
