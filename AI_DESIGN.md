# NotchDo AI 功能設計方案

> 狀態：M0–M5 已實作並通過測試。實作與原設計不同之處、已知限制見文末「13. 實作備註」。
> 基於 commit `de82a8f`（upstream v0.3.0 之後）。

## 1. 目標與範圍

**目標**

1. 按 `⌃⌥E`（Control–Option–E）從任何 app 叫出「AI Capture」面板，輸入一個要交給 Claude 的 todo。
2. Claude 在本機 `~/Desktop/NotchDo/` 這個 AI 工作區執行任務。
3. App 在本機開一個 port（僅 loopback），提供一個網頁顯示每個 AI 任務的即時進度與結果。
4. AI todo 顯示在 notch 展開面板的**右側**，與左側既有的 Apple Reminders 清單並存。
5. 只支援 Claude（呼叫本機的 `claude` CLI），不做多 provider 抽象。

**不做（v1）**

- 不支援 Claude 以外的 AI、不做雲端同步、不做帳號。
- 不把 AI todo 寫進 Apple Reminders（反之亦然），見 `AGENTS.md` 的例外條款。
- 網頁 v1 為唯讀，不能從網頁建立/修改任務（理由見 §7）。

## 2. 整體架構

```
 ⌃⌥R ──► QuickCapturePanel ──► RemindersStore ──► EventKit (既有，不動)
 ⌃⌥E ──► AICapturePanel ──► AITaskStore ──────────────┐
                                  │  (JSON，存在工作區)   │
                                  ▼                      │
                           AITaskScheduler ──► ClaudeRunner ──► `claude -p ...`
                                  │                      │        (cwd = ~/Desktop/NotchDo)
              ┌───────────────────┤                      │
              ▼                   ▼                      ▼
     Notch 右側 AI 面板    LocalProgressServer ──► http://127.0.0.1:<port>
     (SwiftUI)             (Network.framework)       (HTML + JSON + SSE)
```

新增的程式碼分成五塊：**資料與儲存**、**Claude 執行器**、**本地 HTTP 伺服器**、**Notch 右側 UI**、**全域快捷鍵與 Capture 面板**。

## 3. 實作前必須先處理的限制（讀程式碼後發現的）

| # | 發現 | 影響 | 處理 |
|---|------|------|------|
| 1 | `Support/NotchDo.entitlements` 開了 `com.apple.security.app-sandbox` | sandbox 內的 app 不能自由寫 `~/Desktop/NotchDo/`、不能開 listening socket（缺 `network.server`）、子行程 `claude` 會繼承 sandbox 而無法連網和讀寫專案 | **移除 app-sandbox**。EventKit 的存取仍由 TCC（隱私權提示）控管，不受影響。代價：不能再走 Mac App Store 路線；這是個人 fork，ad-hoc 簽署，可接受 |
| 2 | `CarbonGlobalShortcutRegistration` 寫死單一 `hotKeyID`（`NDQC`, id 1），`GlobalShortcutStore` 寫死單一 `defaultsKey` | 無法同時註冊第二組快捷鍵 | 把 `hotKeyID.id` 與 `defaultsKey` 參數化，各 store 一個實例；兩個 Carbon handler 各自依 id 過濾，不匹配時回傳 `eventNotHandledErr` |
| 3 | `NotchMetrics.expandedSize` 固定 440×470，面板置中對齊 notch，用 mask 做展開動畫 | 「在右側加東西」會動到幾何與 hover 判斷 | 見 §6 |
| 4 | `script/build_and_run.sh` 只複製可執行檔，不複製 SwiftPM resource bundle | 網頁 HTML 若用 `Bundle.module` 資源會在打包後找不到 | 網頁 HTML/JS/CSS 以 Swift 字串常數內嵌（`ProgressPageAssets.swift`） |
| 5 | `~/Desktop` 受 macOS TCC 保護 | 第一次存取會跳「桌面資料夾」授權；`claude` 子行程的存取歸屬於 NotchDo | `Info.plist` 加 `NSDesktopFolderUsageDescription`；簽署 identifier 已固定（`com.luku.NotchDo`），授權可持續 |
| 6 | GUI app 的 `PATH` 很精簡，找不到 `claude`（本機在 `~/.local/bin/claude`） | 直接 `Process` 執行 `claude` 會失敗 | 依序找：Settings 手動指定路徑 → `~/.local/bin/claude` → `/opt/homebrew/bin/claude` → `/usr/local/bin/claude` → `zsh -lc 'command -v claude'` |
| 7 | `AGENTS.md`：測試只能用 Swift Testing，且不可碰真實 Reminders；手動驗證要用 demo 模式 | AI 功能的測試與 demo 不能真的呼叫 `claude` | `ClaudeRunner` 走 protocol seam，demo/測試注入假的 runner |

## 4. 資料模型與工作區

### 4.1 工作區 `~/Desktop/NotchDo/`

```
~/Desktop/NotchDo/
├── CLAUDE.md            # App 首次啟動時產生，給 Claude 的工作規則（可由使用者編輯）
├── projects/            # AI 的工作區域；Claude 的 cwd 是整個 NotchDo/ 目錄
└── .notchdo/
    ├── port             # 目前伺服器 port（純文字，方便腳本讀取）
    └── tasks/
        └── <task-id>/
            ├── task.json      # 任務 metadata（原子寫入）
            ├── events.jsonl   # Claude stream-json 事件原始紀錄（append-only）
            └── result.md      # 最終回覆文字
```

`CLAUDE.md` 預設內容：說明這是 NotchDo 的 AI 工作區、成果放 `projects/<名稱>/`、完成時用簡短摘要回報、不要動工作區以外的檔案。

### 4.2 型別

```swift
struct AITask: Codable, Identifiable, Sendable {
    let id: UUID                 // 同時作為 claude 的 --session-id
    var title: String            // 取 prompt 第一行，最多 80 字
    var prompt: String
    var status: AITaskStatus
    var createdAt: Date
    var startedAt: Date?
    var finishedAt: Date?
    var summary: String?         // 最終回覆的前幾行，用於 UI 與網頁列表
    var lastActivity: String?    // 例如 "Editing projects/foo/main.swift"
    var artifactURLs: [URL] = []  // Claude 發布的 Artifact 連結
    var errorMessage: String?
    var turnCount: Int
    var costUSD: Double?         // 取自 result 事件，僅供顯示
}

enum AITaskStatus: String, Codable, Sendable {
    case queued, running, done, failed, cancelled
}
```

- 儲存：每個任務一個資料夾，`task.json` 以「寫暫存檔再 rename」做原子寫入；不引入 SQLite/CoreData。
- `AITaskStore`（`@MainActor @Observable`）持有記憶體中的任務列表，是 UI 和 HTTP server 的單一資料來源；啟動時從磁碟載入，載入時把殘留的 `running` 標為 `failed("App 結束時任務仍在執行")`。
- 保留策略：預設保留所有任務；UI 提供「清除已完成」。（待確認，見 §11）

## 5. Claude 執行器

### 5.1 指令

每個任務啟動一個 `claude` 子行程，**prompt 由 stdin 傳入**（避免參數長度與跳脫問題）：

```
claude -p \
  --output-format stream-json --verbose \
  --session-id <session-id> \
  --permission-mode <mode> \
  --allowedTools "<白名單，逗號分隔>" \
  --append-system-prompt "<任務 id 與輸出規則>"
# cwd = ~/Desktop/NotchDo/    追問時改用 --resume <session-id>
```

- 已在本機 `claude 2.1.302` 以真實執行確認以上旗標與輸出格式；不加 `--include-partial-messages`（輸出量會大很多，且只需要完整訊息）。
- 認證沿用使用者本機已登入的 Claude Code（移除 sandbox 後可直接使用）；NotchDo 不儲存任何 API key。

### 5.2 事件解析

`ClaudeStreamParser` 逐行解析 stdout 的 JSONL，對應：

| 事件 | 動作 |
|------|------|
| `system` / `init` | 記錄 session、model |
| `assistant` 的 text（含 partial） | 更新 `lastActivity` 與網頁串流文字 |
| `assistant` 的 `tool_use` | `lastActivity = "<tool> <目標>"`（例如 `Edit projects/x/a.swift`） |
| `result` | 寫入 `summary`、`costUSD`、`turnCount`，狀態設為 `done` 或 `failed` |

所有原始行都 append 到 `events.jsonl`，解析失敗的行只記錄、不中斷任務。

### 5.3 排程與生命週期

- `AITaskScheduler`：預設**同時只跑 1 個**任務，其餘 `queued`（可設定上限，預設 1，最多 3，避免同時改同一個工作區造成衝突）。
- 取消：對子行程送 `SIGTERM`，2 秒後仍存活送 `SIGKILL`，狀態設為 `cancelled`。
- App 結束時（`applicationWillTerminate`）終止所有子行程。
- 非零結束碼且沒有 `result` 事件 → `failed`，`errorMessage` 取 stderr 最後 20 行。
- `ClaudeRunning` protocol 作為 seam：`start(task) -> AsyncStream<ClaudeEvent>` 與 `cancel()`，正式實作用 `Process`，測試與 demo 用假實作。

### 5.4 權限模式（需要你決定）

`claude -p` 是非互動模式，無法在執行中問你「要不要允許這個操作」，所以必須事先決定權限範圍：

| 選項 | 行為 | 風險 |
|------|------|------|
| **A. `acceptEdits` + `--allowedTools` 白名單（建議）** | 自動接受檔案編輯，Bash 只允許白名單（如 `git`, `swift`, `npm`, `python3`, `ls`…），不在名單內的操作直接失敗並在網頁標示 | 偶爾因缺權限失敗，需要調白名單 |
| B. `bypassPermissions` | 全部放行 | AI 可執行任意指令（含工作區外），prompt 中若混入不可信內容有被利用的風險 |
| C. `plan`（唯讀） | 只產出計畫，不改檔案 | 最安全，但不能真正「做事」 |

預設建議 A，並在 Settings 可切換；B 需要二次確認。

## 6. Notch 右側 UI

### 6.1 兩種做法

| 方案 | 做法 | 優點 | 缺點 |
|------|------|------|------|
| **A. 獨立的右側 drawer 面板（建議）** | 新增 `AIDrawerPanelController`，管理第二個 `NSPanel`，緊貼主面板右緣（x = 主面板 `maxX - 1pt` 重疊避免縫隙），高度與主面板相同；形狀用鏡像的 `NotchSurfaceShape` 變體（左邊平直、右側圓角） | 不動既有 440×470 幾何與 `NotchLayoutTests`；左側 Reminders UI 完全不受影響；rebase upstream 衝突最少 | 兩塊面板接縫處的視覺要在實機驗證（AGENTS.md 要求）；hover 判斷要改成「兩塊面板 frame 的聯集」 |
| B. 加寬主面板 | `expandedSize.width` 改為 440 + drawer 寬度，mask 做水平偏移，使收合時的 notch 形狀仍置中 | 單一面板、單一 mask，視覺一致 | 會動 `NotchMetrics`、mask 置中邏輯、多個既有測試；之後跟 upstream 合併容易衝突 |

建議 **A**。實作重點：

- `NotchPanelController.updatePointerLocation()` 展開時的 `activeRect` 改為「主面板 frame ∪ drawer frame」，指標移到 drawer 上不應觸發收合。
- drawer 與主面板共用 `NotchInteractionModel` 的展開狀態，以相同動畫曲線與 Reduce Motion 規則展開（延續既有的 `.smooth(duration: 0.28)` 與 `.easeOut(duration: 0.12)`）。
- drawer 預設寬度 300pt，高度與主面板相同（470pt）。

### 6.2 drawer 內容（SwiftUI）

```
┌───────────────────────────┐
│ AI                  ⌃⌥E ＋ │  標題列：新增按鈕、快捷鍵提示
├───────────────────────────┤
│ ● 重構 SettingsView        │  running：脈動圓點 + lastActivity
│   Editing Views/Settin…   │
│ ○ 寫 README 英文版         │  queued
│ ✓ 整理 docs 目錄           │  done：點擊展開摘要
│ ✕ 跑 benchmark             │  failed：顯示 errorMessage
├───────────────────────────┤
│ 開啟進度網頁  ↗            │  → http://127.0.0.1:<port>
└───────────────────────────┘
```

- 點任務列展開：完整 prompt、摘要、花費、操作（取消 / 重跑 / 在 Finder 顯示 / 開網頁詳情）。
- 狀態除了顏色外還要有圖示與 VoiceOver 文字（依 AGENTS.md 的 accessibility 要求）。

### 6.3 收合狀態的指示器

主面板收合時，notch 左側已有 `TaskCountBadge`（`x = center − collapsedWidth/2 − 18`）。對稱地在右側（`x = center + collapsedWidth/2 + 18`）加一個 `AITaskBadge`：

- 有任務執行中：脈動點；有佇列：顯示數字；全部完成且未看過：靜態勾勾。
- 沒有任何 AI 任務時不顯示，避免佔用選單列空間。

## 7. 本地 HTTP 伺服器

### 7.1 實作選擇

使用 **Network.framework（`NWListener`）自行處理 HTTP/1.1**，不新增第三方依賴。需求只有少數 GET 路由和 SSE，手寫解析器約 200 行即可，且 `Package.swift` 保持零依賴。

### 7.2 綁定與 port

- 只綁定 `127.0.0.1`（`requiredLocalEndpoint`），不監聽 `0.0.0.0`，區網其他裝置連不到。
- 預設 port `47821`；若被占用則讓系統挑一個暫時 port。實際 port 寫入 `~/Desktop/NotchDo/.notchdo/port`，並顯示在 Settings 與 drawer 底部連結。
- App 啟動時開啟、結束時關閉；Settings 可關閉伺服器。

### 7.3 路由

| 方法 | 路徑 | 說明 |
|------|------|------|
| GET | `/` | 單頁進度網頁（內嵌 HTML/CSS/JS） |
| GET | `/api/tasks` | 任務列表 JSON（不含完整事件） |
| GET | `/api/tasks/<id>` | 單一任務 metadata + `result.md` |
| GET | `/api/tasks/<id>/events` | `events.jsonl` 內容（可用 `?after=<n>` 增量取得） |
| GET | `/api/stream` | Server-Sent Events：任務狀態變化與新事件即時推送 |

網頁行為：任務列表依狀態分組；點進任務看即時串流的輸出（tool 呼叫、文字）、最終摘要與花費；用 SSE 自動更新，斷線自動重連。

### 7.4 安全

- **v1 唯讀**。不提供 POST：任何網站都可以讓使用者瀏覽器對 `localhost` 發請求（CSRF），如果能建立任務就等於讓網頁指揮 Claude 在你的電腦上執行指令。
- 驗證 `Host` 標頭必須是 `127.0.0.1:<port>` 或 `localhost:<port>`，防止 DNS rebinding 取得任務內容。
- 不設 CORS 標頭（拒絕跨來源讀取）。
- 若之後要從網頁操作（取消/重跑），需要每次啟動隨機產生的 token + `Origin` 檢查。

### 7.5 成果輸出：result.md + Claude Artifact 連結

每個任務完成時，Claude 同時產出兩份成果：

1. **`result.md`**：純文字摘要，寫在 `.notchdo/tasks/<id>/result.md`，離線可讀、方便 grep。
2. **Claude Artifact**：適合視覺化的成果（報告、比較表、圖表），由 Claude 直接呼叫 `Artifact` 工具發布成 claude.ai 上的頁面，並把連結回報。

實作方式：

- 已實測：本機 `claude -p` 的 headless 模式可用 `Artifact` 工具（工具清單包含 `Artifact`）。**尚未實測**在 headless 下實際發布是否需要額外授權，M3 第一件事就是驗證。
- 啟動時加入 `--allowedTools Artifact`，並用 `--append-system-prompt` 指示：完成任務後寫 `result.md`；成果適合視覺化時發布 Artifact，並在最後一行回報連結。
- `ClaudeStreamParser` 從 `tool_use`（`Artifact`）的 `tool_result` 中擷取 `https://claude.ai/artifact/...` 連結，存入 `task.json` 的 `artifactURLs`，不依賴 Claude 的文字回覆格式。
- drawer 的任務列顯示「Artifact ↗」，進度網頁的任務詳情頁列出連結，點擊用預設瀏覽器開啟。
- Artifact 預設為私人，只有你本人能開；要分享須在 claude.ai 頁面自行設定。
- **取捨**：任務內容與成果會上傳到 claude.ai（與使用 Claude 本身相同）。需要完全離線時，可在 Settings 關閉「發布 Artifact」，退回只寫 `result.md`。
- 若 Artifact 發布失敗（離線、未登入），任務仍標示 `done`，連結欄位為空並在詳情頁顯示原因。

**不再需要**先前規劃的本機 HTML 伺服器路由、iframe sandbox 與 CSP，伺服器因此維持唯讀、只回 JSON 與 SSE，更簡單。

## 8. 全域快捷鍵與 AI Capture 面板

- `⌃⌥E`：`GlobalShortcut(keyCode: kVK_ANSI_E, modifiers: [.control, .option])`，在 Settings 可重新錄製（沿用 `ShortcutRecorderView`），衝突時沿用既有的錯誤提示與回復舊值機制。
- 兩個快捷鍵不可設成相同組合：`setShortcut` 時檢查另一個 store 的目前值。
- `AICapturePanelController`（參考 `QuickCapturePanelController`）：
  - 浮動、半透明、Spotlight 風格，在目前滑鼠所在螢幕出現。
  - 多行文字輸入（`⏎` 送出、`⇧⏎` 換行、`Esc` 關閉）。
  - 一個「立即執行 / 只加入佇列」切換（預設立即執行）。
  - 送出後建立 `AITask` → 面板關閉 → drawer 若已展開則該任務出現並高亮。
- 與既有 `AppActions` 一致，新增 `AppActions.aiCaptureRequested` notification，讓選單列選項也能觸發。

## 9. 檔案配置

沿用 `Sources/NotchDo/{App,Models,Stores,Support,Views,Windowing}`，只新增一個目錄 `Services/`（放有行程與網路副作用的元件）。每個檔案一個主要型別（AGENTS.md 規定）。

```
Models/      AITask.swift, AITaskStatus.swift, ClaudeEvent.swift, AIPermissionMode.swift
Stores/      AITaskStore.swift, AITaskFileStore.swift, AISettingsStore.swift
Services/    ClaudeRunner.swift, ClaudeRunning.swift, ClaudeStreamParser.swift,
             ClaudeExecutableLocator.swift, AITaskScheduler.swift,
             LocalProgressServer.swift, HTTPRequestParser.swift,
             ProgressPageAssets.swift, AIWorkspace.swift
Views/       AIDrawerView.swift, AITaskRow.swift, AITaskBadge.swift,
             AICaptureView.swift, (SettingsView 新增 AI 區塊)
Windowing/   AIDrawerPanelController.swift, AICapturePanelController.swift
Support/     CarbonGlobalShortcutRegistration.swift（參數化 id）
```

## 10. 測試與驗證

全部使用 Swift Testing，並依 AGENTS.md 不碰真實 Reminders 與真實 `claude`：

| 測試 | 內容 |
|------|------|
| `ClaudeStreamParserTests` | 以 fixture JSONL 驗證 init / text / tool_use / result / 壞行 |
| `AITaskFileStoreTests` | 暫存目錄：原子寫入、載入、殘留 `running` 轉 `failed` |
| `AITaskSchedulerTests` | 注入假 `ClaudeRunning`：併發上限、取消、失敗、順序 |
| `HTTPRequestParserTests` | 路由、壞請求、`Host` 驗證、`?after` 參數 |
| `LocalProgressServerTests` | 綁定 loopback、port 占用時 fallback、SSE 推送 |
| `GlobalShortcutStoreTests`（擴充） | 兩個 store 互不覆蓋、互相衝突被拒 |
| `ClaudeExecutableLocatorTests` | 候選路徑順序 |

UI 部分依 AGENTS.md，在實機驗證收合/展開、drawer 接縫、focus、hover 進出 drawer、Reduce Motion；demo 模式使用假 runner 產生虛構任務，不會真的呼叫 Claude。每個階段結束時跑：

```bash
swift test --configuration release
swift build --configuration release
```

## 11. 開發階段

每個階段都可獨立編譯、測試、使用：

| 階段 | 內容 | 完成標準 |
|------|------|----------|
| **M0 基礎** | 移除 sandbox、`AIWorkspace`（建立資料夾與 `CLAUDE.md`）、Carbon 快捷鍵參數化、`Info.plist` 加 Desktop 說明 | 既有 118 個測試仍通過；Reminders 功能與 `⌃⌥R` 實機正常 |
| **M1 Capture + 儲存** | `AITask`、`AITaskStore`、`AICapturePanel`、`⌃⌥E` | 按 `⌃⌥E` 輸入文字後，`task.json` 出現在工作區 |
| **M2 Notch 右側 UI** | drawer 面板、任務列表、收合 badge | 實機看到任務列於 notch 右側，hover 進出不誤收合 |
| **M3 Claude 執行** | runner、parser、scheduler、取消 | 任務自動執行，drawer 即時顯示 `lastActivity`，完成後有摘要 |
| **M4 進度網頁** | HTTP server、SSE、網頁 | 瀏覽器開 `http://127.0.0.1:<port>` 即時看到進度 |
| **M5 打磨** | 追問（`--resume`）、完成通知、Settings（權限模式、併發數、port、claude 路徑）、README 補充 | 日常可用 |

## 12. 需要你確認的決定

1. **權限模式**（§5.4）：預設 A（`acceptEdits` + 白名單）可以嗎？
2. **UI 方案**（§6.1）：採用 A（獨立 drawer）可以嗎？
3. **併發數**（§5.3）：預設同時只跑 1 個任務可以嗎？
4. **網頁是否要能操作**（§7.4）：v1 唯讀可以嗎？
5. **保留策略**（§4.2）：已完成任務是否永久保留？還是 30 天後自動清除？
6. **完成通知**：任務完成/失敗時是否要 macOS 系統通知？（M5 預設會加）
7. **成果輸出**（§7.5）：預設同時寫 `result.md` 並發布 Artifact 連結（可在 Settings 關閉 Artifact）？

> 同內容的網頁版：https://claude.ai/artifact/4nW6QNF4DCDvTu9tnL6aZY（私人連結）

## 13. 實作備註

**與原設計不同之處**

- `result.md` 由 NotchDo 從 `result` 事件寫入，而不是要求 Claude 自己寫檔，比較可靠。
- 擷取 Artifact 連結時，只接受「`Artifact` 工具以 publish 動作呼叫」之後的 tool_result；`list` 的結果會列出帳號裡其他頁面的連結，不能算進任務。已實測 headless 下 `list` 可用且不被權限擋住。
- 每個任務有獨立的 `sessionID`：重試用新的 session，追問用 `--resume` 接續原 session。
- 任務完成後可在 drawer 的展開列直接輸入追問（需要任務為 done 或 failed）。
- 保留策略：預設永久保留；Settings 的「Delete Finished Tasks…」手動清除（只刪任務記錄，`projects/` 內成果保留）。
- 新增 `AIServices`（`App/`）作為組合根，持有 workspace、store、scheduler、server、notifier，避免 `AppDelegate` 堆滿 AI 程式碼。
- Demo build 使用 `DemoClaudeRunner`（回放虛構任務）與暫存資料夾，不碰真實 Desktop、不啟動真實 `claude`、不發通知。
- 進度伺服器在被占用時會自動改用系統挑選的 port；若 loopback 綁定失敗則在 Settings 顯示錯誤。

**測試**

- 223 個測試，含真實 `Process`（以假 shell script 取代 claude）、真實 loopback socket、SSE。
- 另有需手動開啟的真實 Claude 測試，會花幾美分：

```bash
NOTCHDO_LIVE_CLAUDE=1 swift test --configuration release --filter LiveClaudeSmokeTests
```

**已知限制與尚未驗證**

- **UI 沒有在真實 notch 螢幕上驗證**：drawer 與主面板的接縫、hover 進出兩塊面板、drawer 內輸入框的焦點、收合 badge 位置，都只靠程式碼與 `ImageRenderer` 離屏渲染檢查，需要實機確認。
- 取消任務只會終止 `claude` 本身；它啟動的子行程可能繼續存活，pipe 在 1 秒寬限後被放棄。
- Artifact 的實際 **publish** 尚未在 headless 下端對端測試（只測過 `list`），第一次真正發布時請留意結果。
- 系統通知與 Settings 視窗版面未在實機驗證。
- 每個任務都有成本：最小的任務（一次 list + 寫一個檔案）實測約 US$0.19，主要來自載入設定與系統提示；成本會顯示在網頁與任務記錄中。

