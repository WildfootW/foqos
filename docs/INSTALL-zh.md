# 從零開始：無 Mac 編譯並安裝 Foqos（含每日用量上限功能）

這份指南假設你：沒有 Mac、用 Windows + WSL2、沒做過 iOS app。
編譯全部在 GitHub Actions 的雲端 macOS 上完成，你的電腦只負責設定與安裝。

## 0. 前置條件

- **付費 Apple Developer Program 帳號**（US$99/年，https://developer.apple.com/programs/enroll/ ）。
  Screen Time（Family Controls）與 NFC 權限免費帳號拿不到，這筆錢繞不開。
  註冊後審核通常幾小時到兩天。
- **iPhone**：建議 iOS 18.5 以上（擋板客製畫面的 extension 最低需求 18.5；
  低於此版本 app 能動，但鎖住時只會顯示系統預設畫面）。需支援 NFC（iPhone 7 以上都支援）。
- **NFC 標籤**（若要用 NFC 解鎖）：NTAG213 / NTAG215 空白標籤，網拍一片幾十元。
  只用 QR code 的話不用買。
- 你的 GitHub fork（WildfootW/foqos）。**repo 保持 public** 的話 GitHub Actions 的
  macOS 主機完全免費；private repo 的 macOS 分鐘數消耗是 10 倍計費，額度很快用完。

## 1. 取得 Team ID

登入 https://developer.apple.com/account → 右上角或 Membership details 頁
可看到 **Team ID**（10 碼英數，如 `AB12CD34EF`）。

## 2. 註冊 iPhone 的 UDID

開發版 app 只能裝在「已登記」的裝置上，**必須在編譯前完成**。

取得 UDID（WSL 內，先照第 7 節把 iPhone 接進 WSL）：

```bash
sudo apt install libimobiledevice-utils
idevicepair pair        # iPhone 上按「信任」
ideviceinfo -k UniqueDeviceID
```

（或 Windows 上裝 iTunes → 點裝置 → 點「序號」欄位切換到 UDID。）

然後到 https://developer.apple.com/account/resources/devices/list → 「+」→
Platform 選 iOS，貼上 UDID，隨便取個名字。

## 3. 產生開發憑證（.p12）— 全程在 WSL

```bash
# 產生私鑰與 CSR（-subj 內容隨意，Email 填你的）
openssl genrsa -out foqos-dev.key 2048
openssl req -new -key foqos-dev.key -out foqos-dev.csr \
  -subj "/emailAddress=wildfootw@wildfoo.tw/CN=Foqos Dev/C=TW"
```

到 https://developer.apple.com/account/resources/certificates/list → 「+」→
選 **Apple Development** → 上傳 `foqos-dev.csr` → 下載 `development.cer`。

```bash
# 合成 .p12（會要你設一組密碼，記下來）
openssl x509 -in development.cer -inform DER -out foqos-dev.pem
openssl pkcs12 -export -inkey foqos-dev.key -in foqos-dev.pem -out foqos-dev.p12

# 轉成 base64 給 GitHub secret 用
base64 -w0 foqos-dev.p12 > foqos-dev.p12.b64
```

## 4. 建立 App Store Connect API Key

https://appstoreconnect.apple.com → Users and Access → **Integrations** →
App Store Connect API → 「+」產生一把 key：

- Access 選 **Admin**（自己一個人的帳號，直接用 Admin 最省事）
- 記下 **Key ID** 與頁面上方的 **Issuer ID**
- 下載 `AuthKey_XXXXXXXX.p8`（只能下載一次）

這把 key 讓雲端的 xcodebuild 能自動建立/更新 App ID、App Group 與
provisioning profile，不用手動在 portal 點。

## 5. 設定 GitHub repo

到 fork 的 repo → Settings → Secrets and variables → Actions。

**Variables：**

| 名稱 | 值 |
|---|---|
| `APPLE_TEAM_ID` | 第 1 步的 Team ID |
| `BUNDLE_PREFIX` | `tw.wildfoo.foqos`（可省略，預設就是這個） |

**Secrets：**

| 名稱 | 值 |
|---|---|
| `ASC_KEY_ID` | API Key ID |
| `ASC_ISSUER_ID` | Issuer ID |
| `ASC_API_KEY_P8` | `AuthKey_XXXX.p8` 的完整文字內容 |
| `CERT_P12_BASE64` | `foqos-dev.p12.b64` 的內容 |
| `CERT_P12_PASSWORD` | .p12 的密碼 |

> 為什麼要換 bundle ID？原作者的 `dev.ambitionsoftware.foqos` 已在他的
> 團隊註冊且上架，你的團隊不能再用，所以 CI 會在編譯前執行
> `scripts/configure-signing.sh` 把識別碼換成你自己的。

## 6. 雲端編譯

1. push 程式碼後，**Build Check** workflow 會自動跑（模擬器編譯、不簽名），
   先確認程式能編譯過。紅了就把錯誤訊息貼回來修。
2. Actions → **Build IPA** → Run workflow。約 15–25 分鐘。
3. 成功後在該次 run 的 **Artifacts** 下載 `foqos-ipa`（解壓得到 `.ipa`）。

第一次跑 Build IPA 時 xcodebuild 會自動在你的帳號註冊 App ID 與 App Group；
若因權限失敗，到 portal 手動建立（Identifiers → App IDs 五個、App Groups 一個，
名稱見 workflow log 或 `scripts/configure-signing.sh` 結尾輸出），
App ID 記得勾 Family Controls (Development)、App Groups，主 app 另勾 NFC Tag Reading。

## 7. 從 WSL 安裝 IPA 到 iPhone

一次性設定（Windows 端，用系統管理員 PowerShell）：

```powershell
winget install usbipd
```

iPhone 用線接上電腦後：

```powershell
usbipd list                # 找到 Apple iPhone 的 BUSID
usbipd bind --busid <BUSID>
usbipd attach --wsl --busid <BUSID>
```

WSL 內：

```bash
sudo apt install usbmuxd libimobiledevice-utils ideviceinstaller
sudo usbmuxd            # 若沒自動啟動
idevicepair pair        # iPhone 上按「信任」
ideviceinstaller -i foqos.ipa
```

安裝後在 iPhone 上：

1. **設定 → 一般 → VPN 與裝置管理**：信任你的開發者憑證（若有出現）。
2. **設定 → 隱私權與安全性 → 開發者模式**：打開並重開機
   （這個開關要裝了開發版 app 之後才會出現）。
3. 打開 Foqos，同意 **Screen Time 權限**。

開發憑證簽的 app 效期一年，到期前重跑 Build IPA 再裝一次即可。

## 8. 使用新功能：每日用量上限

1. Foqos 內建立 Profile，選要管的 app（例如 IG、YouTube 一組）。
2. Profile 設定裡的 **Physical Unlocks** 區：登記 NFC 標籤或 QR code
   （QR 可以是任何內容的 QR，掃描登記後印出來貼在遠處）。
3. 同頁 **Daily Usage Limit** 區：打開開關，選每日額度（X 分鐘）與
   解鎖時長（預設 5 分鐘）。存檔。
4. 之後不需要手動開 session：這組 app 每天合計用滿 X 分鐘就會自動鎖上，
   主畫面的 **Daily Limits** 卡片會顯示鎖定狀態。
5. 被鎖住時：打開 Foqos → Daily Limits 卡片 → **Scan** → 掃登記過的
   NFC 標籤或 QR code → 解鎖 5 分鐘，時間到自動重新鎖上。次數不限。
6. 額度每天午夜重置。多個 Profile 可各自設定、同時運作。

## 9. 已知限制

- Apple 的用量偵測（DeviceActivity）觸發可能有一至數分鐘延遲，
  不是秒級精準；重開機後偶爾需要打開一次 Foqos 讓它重新同步排程。
- 「解鎖 5 分鐘」到期的重新上鎖同樣由系統排程觸發，可能晚一點點。
- Allow Mode（只允許選定 app）的 profile 不支援每日上限。
- 手機日期改掉可以繞過每日重置——這功能防的是自己滑手機的慣性，不是防駭。

## 10. 出問題時

- **Build Check 紅**：Swift 編譯錯誤，把 log 貼給 Claude 修。
- **Build IPA 在 archive 步驟失敗**：多半是簽名/識別碼問題，看 log 中
  `error:` 行；常見原因是 App ID 尚未建立（見第 6 節）或裝置 UDID 沒登記。
- **ideviceinstaller 報 ApplicationVerificationFailed**：憑證/描述檔沒涵蓋
  這台裝置 → 確認 UDID 已登記後重跑 Build IPA。
- **app 開了但擋不住**：確認 Screen Time 權限已授權；到 profile 重新存檔一次。
