#!/usr/bin/env python3
"""P1-A 依赖方向门禁：逐文件校验 Consolepilot 模块族 import 不得向上/越层依赖。

模块归属（路径前缀 -> 模块）：
  Sources/Domain       -> ConsolepilotDomain
  Sources/Application  -> ConsolepilotApplication
  Sources/Infrastructure, Sources/Transport -> ConsolepilotInfrastructure
  Sources/LegacyUI     -> ConsolepilotLegacyUI
  Sources/App          -> Consolepilot (App)
  Sources/CLI          -> ConsolepilotCLI
  Tests                -> ConsolepilotTests

规则：任何文件 import 的模块不在该模块的允许集合内即违规。
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
ALLOWED = {
    "ConsolepilotDomain": {"ConsolepilotDomain"},
    "ConsolepilotApplication": {"ConsolepilotApplication", "ConsolepilotDomain"},
    "ConsolepilotInfrastructure": {
        "ConsolepilotInfrastructure", "ConsolepilotDomain"},
    "ConsolepilotLegacyUI": {
        "ConsolepilotLegacyUI", "ConsolepilotInfrastructure", "ConsolepilotDomain"},
    "Consolepilot": {"Consolepilot", "ConsolepilotLegacyUI",
                     "ConsolepilotInfrastructure", "ConsolepilotApplication",
                     "ConsolepilotDomain"},
    "ConsolepilotCLI": {"ConsolepilotCLI", "ConsolepilotApplication",
                        "ConsolepilotInfrastructure", "ConsolepilotDomain"},
    "ConsolepilotTests": set(),
}

# 仅关注本工程模块族：跨模块边界由 Swift 编译期保证，这里只盯依赖方向。
MODULE_FAMILY = re.compile(r"^Consolepilot(?:Core|Domain|Application|Infrastructure|LegacyUI|CLI)?$")

def module_for(path):
    rel = path.relative_to(ROOT).as_posix()
    for prefix, module in (
        ("Sources/Domain/", "ConsolepilotDomain"),
        ("Sources/Application/", "ConsolepilotApplication"),
        ("Sources/Transport/", "ConsolepilotInfrastructure"),
        ("Sources/Infrastructure/", "ConsolepilotInfrastructure"),
        ("Sources/LegacyUI/", "ConsolepilotLegacyUI"),
        ("Sources/App/", "Consolepilot"),
        ("Sources/CLI/", "ConsolepilotCLI"),
        ("Tests/", "ConsolepilotTests"),
    ):
        if rel.startswith(prefix):
            return module
    return None

def main():
    violations = []
    for swift in sorted((ROOT / "Sources").rglob("*.swift")) + sorted((ROOT / "Tests").rglob("*.swift")):
        module = module_for(swift)
        if module is None:
            continue
        text = swift.read_text(encoding="utf-8")
        imports = re.findall(r"^\s*(?:@testable\s+)?import\s+(\w+)", text, flags=re.MULTILINE)
        for name in imports:
            if not MODULE_FAMILY.match(name):
                continue
            allowed = ALLOWED[module]
            if name != module and name not in allowed and allowed:
                violations.append(f"{swift.relative_to(ROOT)}: import {name} 违反 {module} 依赖方向")
    if violations:
        print("✗ 模块依赖方向违规：")
        for v in violations:
            print("  " + v)
        sys.exit(1)
    print("✓ 模块 import 方向检查通过")

if __name__ == "__main__":
    main()
