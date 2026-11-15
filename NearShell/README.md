# NearShell — 接「这边」的那只 App

这个目录是给 `m.aqian-lamp.cn` 用的外壳。跟同仓库的 `AqianClient/` 不是一回事：

| | 接哪边 | 出包工作流 | 产物 |
|---|---|---|---|
| `AqianClient/` | DSH 那套网关（`app.aqian-lamp.cn`） | `build-client.yml` | `AqianClient-unsigned.ipa` |
| `NearShell/`（这个） | 本机这边（`m.aqian-lamp.cn`） | `build-near.yml` | `AqianNear-unsigned.ipa` |

两个 App 的 bundle id 不一样，能同时装在手机上，互不覆盖。

## 它是什么

一个 WKWebView 壳。加载的就是手机网页那一页，所以**页面改了我这边改完，你刷新就有，不用重新出包**。

它自己多做的几件事（网页做不到的）：

- **钥匙存钥匙串**：第一次把带 `?k=…` 的链接贴进来（或从剪贴板一键填），钥匙存进 Keychain，不进包、不写日志。以后打开直接进。
- **下拉刷新**：网页在手机上没法下拉刷新，壳里加了。
- **失败说清楚**：接不上时不是一句"加载失败"，而是分开说——没网 / 域名解析不到 / 端口连不上（隧道断了）/ 超时 / 证书问题，各带错误码。
- **换钥匙不用重装**：右下角那个半透明按钮，改地址、换钥匙、清缓存。

## 它做不到（别指望）

- **切后台会断**。iOS 会挂起 WKWebView，长连接跟着断。回来要下拉刷新一次。
- **没有推送**。要 APNs 证书，这一版没做。
- **语音**：这一版没开麦克风入口。`Info.plist` 里权限描述已经写好，加功能时不用再改。
- 网页本身在小屏上的毛病，这个壳救不了——壳只是把网页装进去。

## 怎么出包

推 `main` 就会跑，或者手动点 `Actions → build-near → Run workflow`。
出来的是**无签名** ipa，要自己用证书签了才装得上。

工作流里工程名不写死：`xcodegen generate` 生成什么工程，就用那个名字去 archive。
（老的 `ios.yml` 就是死在写死了 `Aqian.xcodeproj` 上，而实际生成的是 `AqianClient.xcodeproj`。）

## 目录

```
NearShell/
├── project.yml                 工程定义（name: NearShell，bundle com.aqian.near）
├── Sources/
│   ├── NearApp.swift           入口
│   ├── RootView.swift          主界面、第一次引导页、设置
│   ├── NearWebView.swift       WKWebView 封装：下拉刷新、错误翻译
│   └── KeyStore.swift          钥匙（Keychain）
└── Resources/
    ├── Info.plist
    └── Assets.xcassets         图标（跟 AqianClient 同一套）
```
