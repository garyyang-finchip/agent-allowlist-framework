#!/usr/bin/env python3
# SPDX-License-Identifier: CC0-1.0
"""Checks the specification against the files it quotes and builds the ERCs filing package.

    python3 scripts/make-filing-package.py           checks, then writes the package
    python3 scripts/make-filing-package.py --check   checks only, writes nothing

The package is written to ercs-pr-package/, which is not kept in the repository, and holds
exactly what goes to the ERCs repository: ERCS/erc-8507.md and assets/erc-8507/.

Before anything is written the script verifies that

  * the preamble satisfies the limits the ERCs repository enforces;
  * every interface quoted in the specification is identical to its file;
  * every identifier, hash and address quoted in the specification is in the vectors;
  * the tables of thresholds and of undetermined sides are what the rules compute;
  * every asset is linked from the specification and every link resolves;
  * the text avoids the forms the ERCs validator rejects;
  * every file is plain ASCII and non-empty.
"""

import argparse
import hashlib
import json
import pathlib
import re
import shutil
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
NUMBER = "8507"
SPEC = ROOT / "ERCS" / f"erc-{NUMBER}.md"
ASSETS = ROOT / "assets" / f"erc-{NUMBER}"
DISCUSSION = re.compile(r"^https://ethereum-magicians\.org/t/[^/\s]+/[0-9]+$")
SECTIONS = [
    "Abstract",
    "Motivation",
    "Specification",
    "Rationale",
    "Backwards Compatibility",
    "Test Cases",
    "Reference Implementation",
    "Security Considerations",
    "Copyright",
]
KEYWORDS = re.compile(r"\b(MUST|SHALL|SHOULD|REQUIRED|RECOMMENDED|OPTIONAL|MAY)\b")

problems = []


def problem(message):
    problems.append(message)


def preamble(text):
    match = re.match(r"---\n(.*?)\n---\n", text, re.S)
    if not match:
        problem("the specification has no preamble")
        return {}
    fields = {}
    for line in match.group(1).splitlines():
        key, _, value = line.partition(":")
        fields[key.strip()] = value.strip()
    return fields


def check_preamble(text):
    fields = preamble(text)
    order = ["eip", "title", "description", "author", "discussions-to", "status", "type", "category", "created", "requires"]
    if list(fields) != order:
        problem(f"preamble headers are {list(fields)}, expected {order}")
    if fields.get("eip") != NUMBER:
        problem(f"the preamble does not carry the number {NUMBER}")
    if len(fields.get("title", "")) > 44:
        problem("title is longer than 44 characters")
    description = fields.get("description", "")
    if len(description) > 140:
        problem("description is longer than 140 characters")
    if ":" in description:
        problem("description contains a colon")
    if re.search(r"standar\w*", description + fields.get("title", ""), re.I):
        problem("title or description contains the word standard")
    if not DISCUSSION.match(fields.get("discussions-to", "")):
        problem("discussions-to is not an ethereum-magicians.org topic link")
    if fields.get("author") != "Gary Yang (@garyyang-finchip)":
        problem("the author line changed")
    return fields


def check_sections(text):
    found = re.findall(r"^## (.+)$", text, re.M)
    if found != SECTIONS:
        problem(f"sections are {found}, expected {SECTIONS}")
    security = text.split("## Security Considerations", 1)[-1].split("## Copyright", 1)[0]
    used = sorted(set(KEYWORDS.findall(security)))
    if used:
        problem(f"Security Considerations uses requirement keywords: {', '.join(used)}")


def interface_body(path):
    """The file without licence line, pragma and imports, as the specification quotes it."""
    kept, in_import = [], False
    for line in path.read_text().splitlines():
        if line.startswith("// SPDX") or line.startswith("pragma "):
            continue
        if in_import or line.startswith("import"):
            in_import = not line.rstrip().endswith(";")
            continue
        kept.append(line)
    return "\n".join(kept).strip("\n")


def check_interfaces(text):
    blocks = re.findall(r"```solidity\n(.*?)\n```", text, re.S)
    files = sorted((ASSETS / "contracts" / "interfaces").glob("*.sol"))
    for path in files:
        if interface_body(path) not in blocks:
            problem(f"{path.name}: the specification does not quote this file as it is")
    if len(blocks) != len(files):
        problem(f"the specification has {len(blocks)} Solidity blocks for {len(files)} interface files")


def check_values(text):
    prose = re.sub(r"```solidity\n.*?\n```", "", text, flags=re.S)
    vectors = "\n".join(p.read_text() for p in sorted((ASSETS / "vectors").glob("*.json"))).lower()
    quoted = set(re.findall(r"0x[0-9a-fA-F]{64}\b|0x[0-9a-fA-F]{40}\b|0x[0-9a-fA-F]{8}\b", prose))
    for value in sorted(quoted):
        if value.lower() not in vectors:
            problem(f"{value} is quoted in the specification and is in no vector file")
    if len(quoted) < 30:
        problem("fewer quoted values than expected; the check may have stopped matching")


def side(results, threshold):
    matched = results.count("MATCH")
    undetermined = results.count("UNDETERMINED")
    if matched >= threshold:
        return "MATCH"
    if matched + undetermined < threshold:
        return "NO_MATCH"
    return "UNDETERMINED"


def combine(allow, deny, on_conflict, on_no_match):
    ways = lambda s: [True, False] if s == "UNDETERMINED" else [s == "MATCH"]
    seen = set()
    for a in ways(allow):
        for d in ways(deny):
            seen.add(on_conflict if a and d else "ALLOW" if a else "DENY" if d else on_no_match)
    return next(iter(seen)) if len(seen) == 1 and "INDETERMINATE" not in seen else "INDETERMINATE"


def check_tables(text):
    """The two tables that are worked out in the text are recomputed from the rules."""
    rows = re.findall(r"^\| ((?:`[A-Z_]+`, ){2}`[A-Z_]+`) \| `([A-Z_]+)` \| `([A-Z_]+)` \| `([A-Z_]+)` \|$", text, re.M)
    if len(rows) != 5:
        problem(f"the threshold table has {len(rows)} rows, expected 5")
    for results, *sides in rows:
        results = re.findall(r"[A-Z_]+", results)
        expected = [side(results, k) for k in (1, 2, 3)]
        if sides != expected:
            problem(f"threshold table row {results}: text says {sides}, the rule gives {expected}")

    rules = re.findall(
        r"^\| `([A-Z_]+)` \| `([A-Z_]+)` \| `(ALLOW|DENY)` if `(onConflict|onNoMatch)` is `(ALLOW|DENY)`, else `INDETERMINATE` \|$",
        text,
        re.M,
    )
    if len(rules) != 4:
        problem(f"the table of undetermined sides has {len(rules)} conditional rows, expected 4")
    for allow, deny, outcome, rule, value in rules:
        for on_conflict in ("ALLOW", "DENY", "INDETERMINATE"):
            for on_no_match in ("ALLOW", "DENY", "NOT_APPLICABLE"):
                actual = on_conflict if rule == "onConflict" else on_no_match
                expected = outcome if actual == value else "INDETERMINATE"
                if combine(allow, deny, on_conflict, on_no_match) != expected:
                    problem(f"undetermined sides ({allow}, {deny}) under {on_conflict}/{on_no_match}: the text is wrong")

    # The same rules have to be what the vectors hold.
    vectors = json.loads((ASSETS / "vectors" / "outcomes.json").read_text())
    names = {v: k for k, v in vectors["enums"]["match"].items()}
    outcomes = {v: k for k, v in vectors["enums"]["outcome"].items()}
    for i in range(vectors["count"]):
        expected = combine(
            names[vectors["allowSide"][i]],
            names[vectors["denySide"][i]],
            outcomes[vectors["onConflict"][i]],
            outcomes[vectors["onNoMatch"][i]],
        )
        if outcomes[vectors["outcome"][i]] != expected:
            problem(f"outcome vector {i} differs from the rule")
    t = vectors["thresholds"]
    for i in range(vectors["thresholdCount"]):
        results = [names[t[k][i]] for k in ("first", "second", "third")]
        if names[t["side"][i]] != side(results, t["threshold"][i]):
            problem(f"threshold vector {i} differs from the rule")


def check_links(text):
    linked = set(re.findall(rf"\]\(\.\./assets/eip-{NUMBER}/([^)]+)\)", text))
    present = {p.relative_to(ASSETS).as_posix() for p in ASSETS.rglob("*") if p.is_file()}
    for missing in sorted(linked - present):
        problem(f"link to assets/{missing} does not resolve")
    for orphan in sorted(present - linked):
        problem(f"assets/{orphan} is not linked from the specification")
    for target in re.findall(r"\]\(([^)]+)\)", text):
        if target.startswith(f"../assets/eip-{NUMBER}/") or target == "../LICENSE.md":
            continue
        if re.fullmatch(r"\./eip-[0-9]+\.md", target) or target.startswith("https://www.rfc-editor.org/rfc/"):
            continue
        problem(f"link target {target} is not one the ERCs repository accepts")


def check_validator_forms(text, fields):
    """Forms the ERCs validator rejects and that are easy to write by accident."""
    body = text.split("---\n", 2)[2]
    for match in re.finditer(r"`[^`\n]*\b(?:eip|erc)-[0-9]+[^`\n]*`", body, re.I):
        problem(f"proposal number inside a code span: {match.group(0)}")
    for match in re.finditer(r"(?i)\b(?:eip|erc)[ ]*[0-9]+", body):
        problem(f"proposal reference not of the form ERC-N: {match.group(0)}")
    mentioned = set(re.findall(r"\b((?:ERC|EIP)-[0-9]+)\b", body))
    for name in sorted(mentioned):
        number = name.split("-")[1]
        link = body.find(f"[{name}](./eip-{number}.md)")
        if link < 0:
            problem(f"{name} is mentioned and never linked")
        elif link != re.search(rf"\b{name}\b", body).start() - 1:
            problem(f"the first mention of {name} is not the linked one")
    numbers = {name.split("-")[1] for name in mentioned}
    for number in re.findall(r"[0-9]+", fields.get("requires", "")):
        if number not in numbers:
            problem(f"requires lists {number}, which the text never mentions")
    if re.search("[\u2018\u2019\u201c\u201d]", text):
        problem("smart quotes")


def check_plain(path, data):
    if not data:
        problem(f"{path} is empty")
    try:
        data.decode("ascii")
    except UnicodeDecodeError as error:
        problem(f"{path} is not plain ASCII (byte {error.start})")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--out", default=str(ROOT / "ercs-pr-package"), help="output directory")
    parser.add_argument("--check", action="store_true", help="check only")
    args = parser.parse_args()

    text = SPEC.read_text()
    fields = check_preamble(text)
    check_sections(text)
    check_interfaces(text)
    check_values(text)
    check_tables(text)
    check_links(text)
    check_validator_forms(text, fields)

    sources = {SPEC: pathlib.Path("ERCS") / SPEC.name}
    for path in sorted(ASSETS.rglob("*")):
        if path.is_file():
            sources[path] = pathlib.Path("assets") / ASSETS.name / path.relative_to(ASSETS)
    for path in sources:
        data = path.read_bytes()
        check_plain(path.relative_to(ROOT), data)
        if b"9999" in data and path.suffix in (".md", ".sol"):
            problem(f"{path.relative_to(ROOT)} still carries the placeholder number")

    if problems:
        for message in problems:
            print("FAIL " + message)
        sys.exit(f"{len(problems)} problem(s); nothing was written")
    print(f"checks passed: {len(sources)} files, number {fields['eip']}, title \"{fields['title']}\", requires {fields['requires']}")
    if args.check:
        return

    out = pathlib.Path(args.out)
    if out.exists():
        shutil.rmtree(out)
    for source, relative in sources.items():
        data = source.read_bytes()
        target = out / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        if target.read_bytes() != data:
            sys.exit(f"{relative} was not written correctly")
        print(f"{hashlib.sha256(data).hexdigest()[:16]}  {len(data):>7}  {relative.as_posix()}")
    print(f"wrote {len(sources)} files to {out.relative_to(ROOT) if out.is_relative_to(ROOT) else out}")
    print(f"discussions-to {fields['discussions-to']}")


if __name__ == "__main__":
    main()
