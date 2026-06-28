# Welive Chat Export Helper

用于 `welive.exe` 的 PowerShell 辅助脚本。输入联系人的微信号，即 contacts JSON 中的 `alias`，自动找到对应 `username` / `wxid`，并导出该联系人的聊天记录 Markdown。

## 目录结构

脚本建议放在 `welive.exe` 同目录：

```text
welive-windows-x64/
  welive.exe
  Export-WeliveChat.ps1
  USAGE.md
  resources/
```

如果上传本仓库到 GitHub，可保留：

```text
README.md
tools/
  Export-WeliveChat.ps1
tests/
```

## 前置要求

- Windows
- PowerShell 5+
- 微信已运行并登录
- 已准备好 `welive.exe`
- 运行时需要管理员权限

## 安装

把 `tools/Export-WeliveChat.ps1` 复制到 `welive.exe` 所在目录：

```text
welive-windows-x64/
  welive.exe
  Export-WeliveChat.ps1
  resources/
```

脚本默认读取同目录下的：

```powershell
.\welive.exe
```

## 使用

进入 `welive.exe` 所在目录：

```powershell
cd "C:\path\to\welive-windows-x64"
```

按微信号导出：

```powershell
powershell -ExecutionPolicy Bypass -File .\Export-WeliveChat.ps1 -WechatId "XXX"
```

首次运行会执行：

```powershell
.\welive.exe init
```

按提示完成初始化后，脚本会继续导出联系人并生成聊天记录。

## 已初始化时

如果已经成功初始化过，可跳过 `welive init`：

```powershell
powershell -ExecutionPolicy Bypass -File .\Export-WeliveChat.ps1 -WechatId "XXX" -SkipInit
```

## 不传微信号

```powershell
powershell -ExecutionPolicy Bypass -File .\Export-WeliveChat.ps1
```

脚本会提示输入：

```text
Enter contact WeChat ID (alias): XXX
```

## 指定输出目录

```powershell
powershell -ExecutionPolicy Bypass -File .\Export-WeliveChat.ps1 `
  -WechatId "XXX" `
  -OutDir "C:\tmp\welive-export"
```

输出：

```text
C:\tmp\welive-export\contacts_raw.json
C:\tmp\welive-export\XXX_聊天记录.md
```

## 脚本不在 welive.exe 同目录时

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\Export-WeliveChat.ps1 `
  -WeliveDir "C:\path\to\welive-windows-x64" `
  -WechatId "XXX"
```

## 工作流程

脚本会执行以下步骤：

```powershell
.\welive.exe init
.\welive.exe contacts
```

然后在联系人数据中查找：

```json
{
  "alias": "XXX",
  "username": "wxid_XXXXXX"
}
```

最后导出：

```powershell
.\welive.exe export-session `
  --session-id "wxid_XXXXXX" `
  --readable `
  --parse-content `
  --asc `
  --lite `
  --out ".\XXX_聊天记录.md"
```

## 参数

| 参数 | 说明 |
| --- | --- |
| `-WechatId` | 联系人微信号，对应 contacts JSON 中的 `alias`。 |
| `-WeliveDir` | `welive.exe` 所在目录。脚本和 `welive.exe` 同目录时不用传。 |
| `-OutDir` | 输出目录，默认是 `welive.exe` 所在目录。 |
| `-SkipInit` | 跳过 `welive init`。 |
| `-NoElevate` | 不自动请求管理员权限，一般不建议使用。 |

## 输出文件

```text
contacts_raw.json
XXX_聊天记录.md
```

## 常见问题

### 卡在 `Running welive init...`

说明 `welive init` 正在等待输入或确认。查看管理员 PowerShell 窗口，按提示完成初始化。

### 找不到联系人

说明 `contacts_raw.json` 中没有 `alias` 等于 `XXX` 的联系人。请确认输入的是微信号，不是昵称或备注。

### PowerShell 禁止运行脚本

使用：

```powershell
powershell -ExecutionPolicy Bypass -File .\Export-WeliveChat.ps1 -WechatId "XXX"
```

## 不要上传的文件

不要上传以下文件到 GitHub：

```gitignore
welive.yaml
contacts_raw.json
*_聊天记录.md
*.jsonl
exports/
media/
logs/
```

这些文件可能包含聊天记录、联系人、密钥或本地路径。
