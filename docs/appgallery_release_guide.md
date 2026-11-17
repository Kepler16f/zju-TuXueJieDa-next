# 鸿蒙 AppGallery 上架指南（v0.1.6+）

本文档记录从「代码就绪」到「AppGallery 上架通过」的完整流程。所有能在 CI 完成的步骤已自动化，需要你本人操作的部分用 👤 标注。

---

## 当前状态（自动化已完成）

| 项目 | 状态 | 位置 |
|---|---|---|
| 鸿蒙 HAP 构建（未签名） | ✅ 已完成并发布 | Release v0.1.6 |
| 发布密钥库 `.p12` | ✅ 已生成 | `ohos_signing/ohos_release.p12`（已入 Secrets，不在 Git） |
| 证书请求 `.csr` | ✅ 已生成 | `ohos_signing/app.csr` |
| 密钥库密码 | ✅ 已入 Secrets | `OHOS_KEYSTORE_PASSWORD`（备份在 `build/ohos_keystore_password.txt`） |
| 签名构建 `.app` 工作流 | ✅ 就绪 | `.github/workflows/build-ohos-release.yml` |

---

## 👤 你需要完成的部分（按顺序）

### 1. 华为开发者账号（立即）
- 注册 <https://developer.huawei.com> → 实名认证（个人开发者即可）
- 进入 [AppGallery Connect](https://developer.huawei.com/consumer/cn/service/josp/agc/index.html)

### 2. 创建应用与 APP ID
1. AGC → 「我的应用」→ 创建应用
   - 应用名称：**图学习题解答**
   - 应用分类：教育 / 工具
   - 应用语言：简体中文
2. 进入应用 → 「证书」→ 「应用内证书」→ **创建**
   - 类型：**发布证书**（不是调试证书）
   - **上传 `ohos_signing/app.csr`**（文件在本仓库 `ohos_signing/app.csr`）
   - 系统会下载 **`.cer` 发布证书** → 存到 `ohos_signing/app.cer`
3. AGC → 「证书」→ **Profile** → 创建
   - 类型：发布 Profile
   - 关联刚才的发布证书
   - 下载 **`.p7b`** → 存到 `ohos_signing/app.p7b`

### 3. 把证书材料交给 CI
```bash
# 在仓库根目录执行（Windows PowerShell 亦可，用 base64 命令）
base64 -w0 ohos_signing/app.cer | gh secret set OHOS_CERT_BASE64 --repo Kepler16f/zju-TuXueJieDa-next
base64 -w0 ohos_signing/app.p7b | gh secret set OHOS_PROFILE_BASE64 --repo Kepler16f/zju-TuXueJieDa-next
```

### 4. 软著登记（最耗时，1-2 个月，立即启动）
- 中国版权保护中心 <https://www.ccopyright.com.cn> → 计算机软件著作权登记
- 软件名称：**图学习题解答**，版本：V0.1.6
- 完成后拿到**登记证书**（AppGallery 上架资质要求）

### 5. ICP 备案（最耗时，1-20 天，立即启动）
- 依据工信部规定，国内分发的 App 需要完成 ICP 备案
- 需要：域名（可用备案域名）+ 国内云服务器（用于备案核验）
- 备案完成拿到**备案号**后，填入 AGC 应用信息（应用内「版本信息 → 备案号」）

### 6. 生成签名版 .app（CI 一条命令）
```bash
gh workflow run build-ohos-release.yml -f version=0.1.7 -f build_number=9
# 产物：tuxuejieda-HarmonyOS-0.1.7-release.app（Actions artifacts）
```

### 7. 上架资料（我可以代拟，你审核）
- 应用截图：≥3 张 1080p（可从 Windows 版逐页自动截取，我可以写脚本生成）
- 应用图标：1024×1024 PNG（`tools/app_icon_master.png` 已是 1024px，可直接用）
- 隐私政策 / 用户协议：需要可公开访问的 URL（建议放到你的备案域名下）

### 8. 提交审核
- AGC → 应用 → 「版本管理」→ 创建版本 → 上传 `.app` → 填写版本信息与素材 → 提交审核
- 首次审核通常 1-3 个工作日

---

## ⚠️ 关键提醒

1. **密钥库（.p12）丢失 = 无法更新已上架应用**。请把 `ohos_signing/ohos_release.p12` 和密码**离线备份**（密码管理器 + U 盘），仓库 Secrets 不是唯一副本。
2. `.app` 包 = 签名后的 HAP 集合包（含 `.cer`/`.p7b`），不是我们发布的未签名 `.hap`；两者不要混淆。
3. 每次上架新版本必须用**同一个** `.p12` + `.cer` 签名，否则视为新应用。
4. 软著证书上的名称与版本号要与 AGC 填写的一致，建议统一为「图学习题解答」。

---

## 附：仓库中相关文件

- `.github/workflows/gen-ohos-keystore.yml` — 一次性生成密钥库与 CSR
- `.github/workflows/build-ohos-release.yml` — 签名构建 .app
- `.github/workflows/release.yml` — 全平台构建 + GitHub Release
- `scripts/setup_ohos.sh` — 鸿蒙宿主工程初始化（bundleName / 应用名 / 图标 / 版本号 / 插件适配）
- `scripts/strip_hap_libs.py` — 剥离引擎符号，HAP 从 52.8MB → 30.3MB
