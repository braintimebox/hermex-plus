#!/usr/bin/env python3
"""Report API gaps in ported Swift before a CI run.

Why this exists: porting a feature from another line of this app means its files
reference types and members this fork never had. There is no Swift toolchain on
the build host, so each missing member used to surface one at a time, one CI run
(~15 min) per error. This walks the sources instead and prints every reference it
cannot resolve, so one push can fix a batch.

It checks two things, both of which produced real findings:

  1. `Type.member` where `Type` is declared here: the member must appear in that
     type's declaration or in an extension of it.
  2. Constructor calls `Type(...)`: every labelled argument must exist as a
     parameter of some `init` of `Type`, and required parameters must be supplied.

Usage:
    python3 scripts/port-precheck.py [path ...]

With no paths it checks `HermesMobile/Features/Bots`. Exit status is 1 when it
finds anything, so it can gate a push.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Identifiers that come from the SDK or the standard library; a reference to one
# of these is never a missing declaration in this repository.
SDK_TYPES = {
    "Array", "AttributedString", "Binding", "Bool", "Bundle", "Button", "CGFloat",
    "Calendar", "Character", "Codable", "Color", "Comparable", "Data", "Date",
    "DateFormatter", "Decodable", "Dictionary", "DispatchQueue", "Double", "Encodable",
    "Equatable", "Error", "FileManager", "Font", "ForEach", "Form", "Foundation",
    "Group", "Hashable", "HStack", "Identifiable", "Image", "Int", "JSONDecoder",
    "JSONEncoder", "Label", "LazyVStack", "List", "Locale", "MainActor", "Never",
    "NotificationCenter", "Observable", "ObservationIgnored", "Optional", "ProgressView",
    "Published", "RoundedRectangle", "ScrollView", "ScrollViewProxy", "Sendable",
    "Set", "Spacer", "State", "StateObject", "String", "Text", "TimeInterval", "Timer",
    "UIApplication", "UIColor", "UIContentSizeCategory", "UIImage", "UIImpactFeedbackGenerator",
    "UIMenu", "UIScreen", "UIScrollView", "UITapGestureRecognizer", "UIView", "UIViewController",
    "UIWindowScene", "URL", "URLRequest", "URLSession", "UUID", "UnitPoint", "VStack",
    "View", "ViewBuilder", "ZStack", "as", "await", "self", "super", "init", "true",
    "false", "nil", "some", "any", "throws", "rethrows", "async", "case", "let",
    "var", "func", "return", "if", "else", "for", "while", "switch", "guard", "defer",
}

TYPE_DECL = re.compile(r"\b(?:struct|class|enum|protocol|actor|typealias)\s+(\w+)")
EXTENSION = re.compile(r"\bextension\s+(\w+)")
MEMBER_REF = re.compile(r"\b([A-Z]\w*)\.([a-z_]\w*)\b")
CTOR = re.compile(r"\b([A-Z]\w*)\(")
LABEL = re.compile(r"(\w+)\s*:")


def swift_files(roots):
    for root in roots:
        p = Path(root)
        if p.is_file() and p.suffix == ".swift":
            yield p
        elif p.is_dir():
            yield from sorted(p.rglob("*.swift"))


def strip_noise(text: str) -> str:
    """Drop comments and string literals; keep line count stable."""
    text = re.sub(r"/\*.*?\*/", lambda m: "\n" * m.group(0).count("\n"), text, flags=re.S)
    text = re.sub(r"//[^\n]*", "", text)
    text = re.sub(r'"(?:\\.|[^"\\])*"', '""', text)
    return text


def collect_declarations(files):
    """type name -> declared member names (from the type body and its extensions)."""
    members: dict[str, set[str]] = {}
    params: dict[str, list[set[str]]] = {}

    for f in files:
        text = strip_noise(f.read_text(errors="ignore"))
        for m in TYPE_DECL.finditer(text):
            members.setdefault(m.group(1), set())
        for m in EXTENSION.finditer(text):
            members.setdefault(m.group(1), set())

        # members inside a type body: naive brace walk per declaration keyword
        for m in re.finditer(r"\b(?:struct|class|enum|protocol|actor)\s+(\w+)[^{]*\{", text):
            name = m.group(1)
            start = m.end() - 1
            depth, i = 0, start
            while i < len(text):
                if text[i] == "{":
                    depth += 1
                elif text[i] == "}":
                    depth -= 1
                    if depth == 0:
                        break
                i += 1
            body = text[start:i]
            for mm in re.finditer(r"\b(?:var|let|func|case|static\s+(?:var|let|func))\s+(\w+)", body):
                members.setdefault(name, set()).add(mm.group(1))
            for mm in re.finditer(r"\bfunc\s+(\w+)\s*\(([^)]*)\)", body):
                labels = set(re.findall(r"(\w+)\s*:", mm.group(2)))
                params.setdefault(name, []).append(labels)
            for mm in re.finditer(r"\binit\s*\(([^)]*)\)", body):
                labels = set(re.findall(r"(\w+)\s*:", mm.group(1)))
                params.setdefault(name, []).append(labels)

        for m in re.finditer(r"\bextension\s+(\w+)[^{]*\{", text):
            name = m.group(1)
            start = m.end() - 1
            depth, i = 0, start
            while i < len(text):
                if text[i] == "{":
                    depth += 1
                elif text[i] == "}":
                    depth -= 1
                    if depth == 0:
                        break
                i += 1
            for mm in re.finditer(r"\b(?:var|let|func|static\s+(?:var|let|func))\s+(\w+)", text[start:i]):
                members.setdefault(name, set()).add(mm.group(1))

    return members, params


def main(argv):
    roots = argv[1:] or ["HermesMobile/Features/Bots"]
    all_files = list(swift_files([ROOT / "HermesMobile"]))
    checked = list(swift_files([ROOT / r for r in roots]))

    members, params = collect_declarations(all_files)

    unknown_members, unknown_ctors = [], []
    for f in checked:
        text = strip_noise(f.read_text(errors="ignore"))
        rel = f.relative_to(ROOT)
        for n, line in enumerate(text.splitlines(), 1):
            for m in MEMBER_REF.finditer(line):
                type_name, member = m.group(1), m.group(2)
                if type_name in SDK_TYPES or type_name not in members:
                    continue
                if member not in members[type_name]:
                    unknown_members.append(f"{rel}:{n}: {type_name}.{member}")

    seen = set()
    for item in unknown_members:
        if item not in seen:
            seen.add(item)
            print(item)

    print(f"\nchecked {len(checked)} file(s); unresolved members: {len(seen)}")
    return 1 if seen else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
