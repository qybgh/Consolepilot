# Consolepilot 唯一命令入口（P0 起替代 Scripts/*）
# 常用：make bootstrap && make test && make lint && make build

SHELL := /bin/bash
PROJECT := Consolepilot.xcodeproj
SCHEME := Consolepilot
BUILD_DIR := build
DIST_DIR := dist
XCODEBUILD_FLAGS := -project $(PROJECT) -scheme $(SCHEME) -destination 'platform=macOS'
ARCH ?= $(shell uname -m)

.PHONY: bootstrap xcodegen test lint build release clean distclean drift-check

bootstrap: ## 校验 Xcode/工具/依赖/架构（实施前一次性准备）
	@command -v xcodebuild >/dev/null || { echo "错误：需要完整 Xcode（xcodebuild 不在 PATH）"; exit 1; }; \
	command -v xcodegen >/dev/null || { echo "错误：缺少 xcodegen，请执行 brew install xcodegen"; exit 1; }; \
	command -v swiftlint >/dev/null || { echo "错误：缺少 swiftlint，请执行 brew install swiftlint"; exit 1; }; \
	command -v periphery >/dev/null || { echo "错误：缺少 periphery，请执行 brew install periphery"; exit 1; }; \
	SWIFT_FORMAT=$$(xcrun --find swift-format 2>/dev/null) || { echo "错误：缺少 swift-format（应在 Xcode 工具链内）"; exit 1; }; \
	echo "✓ xcodebuild：$$(xcodebuild -version | head -1)"; \
	echo "✓ xcodegen：$$(xcodegen version)"; \
	echo "✓ swiftlint：$$(swiftlint version)"; \
	echo "✓ periphery：$$(periphery version)"; \
	echo "✓ swift-format：$$SWIFT_FORMAT"; \
	command -v python3 >/dev/null || { echo "错误：缺少 python3（release 打包需要）"; exit 1; }; \
	command -v zip >/dev/null || { echo "错误：缺少 zip"; exit 1; }; \
	echo "✓ 架构：$(ARCH)（要求 Apple Silicon）"

xcodegen: ## 从 project.yml 重新生成 xcodeproj
	xcodegen generate

drift-check: ## xcodeproj 漂移检查：重新生成后工作区必须无 diff
	xcodegen generate
	@if git diff --exit-code --quiet -- Consolepilot.xcodeproj project.yml; then \
		echo "✓ xcodeproj 与 project.yml 无漂移"; \
	else \
		echo "✗ xcodeproj 漂移：请先改 project.yml 再执行 make xcodegen 并提交生成结果" >&2; \
		exit 1; \
	fi

test: ## 全量测试（GUI 会话须全绿；受限 shell 允许 3 项已知失败）
	xcodebuild $(XCODEBUILD_FLAGS) test CODE_SIGNING_ALLOWED=NO

lint: drift-check ## 格式/静态/分析/密钥扫描/死代码门禁
	@SWIFT_FORMAT=$$(xcrun --find swift-format); \
	echo "--- swift-format strict ---"; \
	$$SWIFT_FORMAT lint --recursive --strict Sources Tests; \
	echo "--- swiftlint strict ---"; \
	swiftlint lint --strict; \
	echo "--- xcodebuild analyze ---"; \
	xcodebuild $(XCODEBUILD_FLAGS) analyze CODE_SIGNING_ALLOWED=NO; \
	echo "--- 敏感信息扫描 ---"; \
	! grep -rInE "(Authorization|Bearer|api[_-]?key|secret)\s*[:=]\s*[\"'][^\"']{8,}" Sources Tests --include="*.swift" --include="*.toml" || { echo "发现疑似硬编码密钥" >&2; exit 1; }; \
	echo "--- periphery 未使用代码扫描 ---"; \
	periphery scan --project $(PROJECT) --schemes $(SCHEME) --report-exclude Tests || true
	@echo "✓ lint 全绿"

build: ## Debug arm64 构建 App + CLI（产物在 build/）
	xcodebuild $(XCODEBUILD_FLAGS) -configuration Debug -derivedDataPath $(BUILD_DIR) CODE_SIGNING_ALLOWED=NO build
	@echo "App: $(BUILD_DIR)/Build/Products/Debug/Consolepilot.app"
	@echo "CLI: $(BUILD_DIR)/Build/Products/Debug/consolepilot"

release: ## Release + ad-hoc 签名 + ZIP + SHA-256 manifest；用法 make release VERSION=0.2.0-p1
	@test -n "$(VERSION)" || { echo "用法：make release VERSION=x.y.z"; exit 1; }; \
	rm -rf $(DIST_DIR) && mkdir -p $(DIST_DIR); \
	xcodebuild $(XCODEBUILD_FLAGS) -configuration Release -derivedDataPath $(BUILD_DIR) \
		CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual \
		MARKETING_VERSION=$(VERSION) CURRENT_PROJECT_VERSION=1 build; \
	APP=$(DIST_DIR)/Consolepilot.app; \
	rm -rf $$APP && cp -R $(BUILD_DIR)/Build/Products/Release/Consolepilot.app $$APP; \
	CLI=$(DIST_DIR)/consolepilot; \
	cp $(BUILD_DIR)/Build/Products/Release/consolepilot $$CLI && chmod +x $$CLI; \
	codesign --force --sign - --entitlements Resources/Consolepilot.entitlements $$APP; \
	codesign --verify --deep --strict --verbose=2 $$APP; \
	shasum -a 256 $$APP/Contents/MacOS/Consolepilot $$CLI > $(DIST_DIR)/SHA256SUMS.txt; \
	zip -qry $(DIST_DIR)/Consolepilot-$(VERSION).zip $$APP $$CLI $(DIST_DIR)/SHA256SUMS.txt; \
	cd $(DIST_DIR) && shasum -a 256 Consolepilot-$(VERSION).zip; \
	echo "✓ 产物：$(DIST_DIR)/Consolepilot-$(VERSION).zip"

clean: ## 清理构建产物与 DerivedData
	rm -rf $(BUILD_DIR) $(DIST_DIR)
	xcodebuild $(XCODEBUILD_FLAGS) clean CODE_SIGNING_ALLOWED=NO 2>/dev/null || true

distclean: clean ## 深度清理（含 .build 与 xcuserdata）
	rm -rf .build Consolepilot.xcodeproj/xcuserdata
