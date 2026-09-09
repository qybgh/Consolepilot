#!/usr/bin/env python3
"""P1-F 残留门禁：确定性扫描本轮已删除/移出内容的零残留。

范围：Sources / Tests / Resources / Configs / project.yml / README.md。
策略：整词/整串命中即违规；测试与迁移错误中刻意保留的旧字段用例走显式
allowlist（这些是验证“删除字段被正确拒绝/迁移报错”的契约测试，不是残留）。
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCAN_DIRS = ("Sources", "Tests", "Resources", "Configs")
SCAN_FILES = ("project.yml", "README.md")

# (模式, 说明)。模式按整词/字符串语义预先写准，避免误伤合法标识符。
CHECKS = [
    (re.compile(r"ConsolepilotCore"), "旧模块名 ConsolepilotCore（P0 已拆分）"),
    (re.compile(r"\[String: Any\]"), "无类型 [String: Any] DTO（P1-D 已强类型化）"),
    (re.compile(r"\bFileTailWatcher\b"), "FileTailWatcher（tails 已移出本轮）"),
    (re.compile(r"\bTailConfig\b"), "TailConfig（tails 已移出本轮）"),
    (re.compile(r"\btoggleHotkey\b"), "toggleHotkey（D7 已删除）"),
    (re.compile(r"\blaunchAtLogin\b"), "launchAtLogin（D7 已删除）"),
    (re.compile(r"\battachTo\b"), "attachTo（D7 已废弃为 sessionMode，仅迁移报错允许出现）"),
]

# 刻意保留旧字段 token 的测试/错误文案（验证删除语义），命中行内含这些路径则豁免。
LEGACY_ALLOWLIST_PATHS = (
    "Sources/Infrastructure/Config/ConfigLoader.swift",   # attachTo 迁移报错
    "Tests/InfrastructureTests.swift",                    # 旧配置残留拒绝测试
)

def scan_file(path):
    rel = path.relative_to(ROOT).as_posix()
    allowed = any(rel == p for p in LEGACY_ALLOWLIST_PATHS)
    hits = []
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeDecodeError):
        return hits
    for lineno, line in enumerate(lines, 1):
        for pattern, desc in CHECKS:
            if pattern.search(line):
                if allowed and pattern.pattern in (
                    r"\btoggleHotkey\b", r"\blaunchAtLogin\b", r"\battachTo\b"
                ):
                    # 旧配置残留测试/迁移报错里整字段值也是契约断言的一部分；校验语义由单测覆盖。
                    continue
                hits.append((rel, lineno, desc, line.strip()))
    return hits

def main():
    files = []
    for d in SCAN_DIRS:
        root = ROOT / d
        if root.exists():
            files.extend(p for p in root.rglob("*") if p.is_file())
    for name in SCAN_FILES:
        p = ROOT / name
        if p.exists():
            files.append(p)
    violations = []
    for path in sorted(files):
        violations.extend(scan_file(path))
    if violations:
        for rel, lineno, desc, line in violations:
            print(f"{rel}:{lineno}: {desc}: {line}")
        print("✗ 残留扫描失败：存在 P0/P1 已删除内容的残留引用")
        sys.exit(1)
    print("✓ 残留扫描通过：旧模块名/旧字段/无类型 DTO/tails 代码零残留")

if __name__ == "__main__":
    main()
