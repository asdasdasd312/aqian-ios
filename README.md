# 阿潜 · iOS 壳

一个最小的 WKWebView 壳：打开就是手机口那个页面，右上角齿轮可以换地址。

## 为什么要云构建

iOS 的包只能在 macOS 上用 Xcode 编。这台是 Windows，所以用 GitHub Actions 的
`macos-15` 免费额度构建，产出**未签名** `.ipa`，你用全能签自己签。

## 构建步骤

1. 新建一个 GitHub 仓库（Private 也行）。
2. 把这个目录里的东西全部推上去（保持目录结构，`.github/workflows/ios.yml` 必须在）。
3. 仓库 → Actions → 选 `build-ipa` → `Run workflow`。
4. 跑完在 Artifacts 里下载 `Aqian-unsigned-ipa`，得到 `Aqian-unsigned.ipa`。

## 签名（全能签）

- 需要你自己有证书：`.p12` + `.mobileprovision`。
- Bundle ID：`com.aqian.lamp`。如果你的描述文件不是通配符，**必须**新建一个
  `com.aqian.lamp` 的 App ID 并重新生成描述文件，否则签名会失败。
- 全能签里选「导入证书」→ 选 ipa → 签名 → 安装。
- 免费 Apple ID 证书 7 天过期，到期重签；付费证书一年。

## 改地址

- 临时隧道（trycloudflare）每次重启都会变。变了以后：
  - 在 App 里点右上角齿轮，把带 `?k=` 的整条地址换掉；或
  - 改 `Sources/ContentView.swift` 里的 `defaultURL` 重新构建。
- 想彻底不漂：需要 Cloudflare 账号 + 一个域名，做 named tunnel，地址就固定了。

## 文件

```
project.yml                  XcodeGen 工程描述（不用提交 .xcodeproj）
Sources/AqianApp.swift       入口
Sources/ContentView.swift    WebView + 刷新/设置
Sources/WebView.swift        WKWebView 容器
Sources/SettingsView.swift   改地址
Resources/Info.plist         中文名「阿潜」、允许任意加载
Resources/Assets.xcassets    图标（鲸）
.github/workflows/ios.yml    云构建
```
