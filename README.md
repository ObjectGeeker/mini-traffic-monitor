# MiniTrafficMonitor

macOS 状态栏常驻的极致轻量资源监控：CPU 占用率、内存占用率（或内存压力）、上下行网速。
对标 Windows TrafficMonitor，但常驻内存预算 ≤ 25 MB、自身 CPU ≤ 0.3%、零第三方依赖。

需求与全部技术验证记录见 [docs/requirements.md](docs/requirements.md)。

## 使用

```bash
./build.sh          # 构建 + 组装 .app + ad-hoc 签名
./tools/install.sh  # 安装到 /Applications 并启动
```

或直接 `open MiniTrafficMonitor.app`。

菜单栏读数默认形如 `C 24% M 50% ↓ 4.0K ↑ 1.0K`（全等宽字体，宽度恒定不抖动）。
点击图标展开面板：完整四指标、栏内显示开关、内存内容（占用率/压力）切换、预设、开机自启、退出。
悬停图标显示全量 tooltip。

菜单栏空间不足（刘海机型拥挤）时会自动降档精简（只降不升），面板中会提示当前精简结果；
改偏好或点预设会重新尝试全开。

## 验证 / 自测

```bash
MTM_SELFTEST=1 ./MiniTrafficMonitor.app/Contents/MacOS/MiniTrafficMonitor   # 20 项无 UI 自测
MTM_DEBUG=1    ./MiniTrafficMonitor.app/Contents/MacOS/MiniTrafficMonitor   # 每秒读数 + 内存分解 + 布局诊断
MTM_LOGIN_TEST=1 ./MiniTrafficMonitor.app/Contents/MacOS/MiniTrafficMonitor # 开机自启注册往返测试
./tools/measure-lightweight.sh 86400 30    # 24h 轻量性验收（NFR-1/2/3），输出 CSV 与摘要
```

## 环境要求

- macOS 13.0+（Apple Silicon / Intel）
- 仅 Command Line Tools 即可构建，**不需要 Xcode**（SPM + 手工 bundle + ad-hoc 签名）
- 不需 root / 沙盒 / 特殊权限

## 目录

```
Package.swift                 SPM 工程（swiftLanguageMode v5，链接 SystemConfiguration）
build.sh                      构建 + .app 组装 + 签名
Sources/MiniTrafficMonitor/   全部源码（单线程，1Hz Timer）
tools/                        install.sh / measure-lightweight.sh / make_icon.swift
spike/                        需求阶段的 API 可行性验证代码
docs/requirements.md          需求文档 + 技术验证记录（FR/NFR/决策/踩坑）
```
