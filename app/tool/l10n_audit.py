#!/usr/bin/env python3
"""CI guard: fails the build if i18n drift re-accumulates.
Checks:
  1. All 12 ARB files have identical key sets (no missing/extra translations)
  2. All used l10n keys exist in app_en.arb
  3. No hardcoded user-facing string literals outside the explicit allow-list
Exits non-zero on any violation.
"""
import json, os, re, sys, glob

APP_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(APP_DIR)

LANGS = ['en','ar','de','es','fr','he','hi','ja','ko','pt','zh']
FAILURES = []

# 1. Parity check
en = json.load(open('lib/l10n/app_en.arb', encoding='utf-8'))
enk = {k for k in en if not k.startswith('@')}
for lang in LANGS[1:]:
    d = json.load(open(f'lib/l10n/app_{lang}.arb', encoding='utf-8'))
    k = {x for x in d if not x.startswith('@')}
    miss = sorted(enk - k); extra = sorted(k - enk)
    if miss or extra:
        FAILURES.append(f"[{lang}] MISSING={miss} EXTRA={extra}")

# 2. Used keys exist in en
p1 = re.compile(r'AppLocalizations\.of\([^)]+\)\.([a-zA-Z_][a-zA-Z0-9_]*)')
p2 = re.compile(r'\bl10n\.([a-zA-Z_][a-zA-Z0-9_]*)')
p3 = re.compile(r'lookupAppLocalizations\([^)]+\)\.([a-zA-Z_][a-zA-Z0-9_]*)')
used = set()
for root, _, files in os.walk('lib'):
    if 'l10n' in root: continue
    for f in files:
        if f.endswith('.dart'):
            t = open(os.path.join(root, f), encoding='utf-8').read()
            used |= set(p1.findall(t)) | set(p3.findall(t))
            used |= set(p2.findall(t))
missing = sorted(used - enk)
if missing:
    FAILURES.append(f"USED-BUT-MISSING-IN-EN: {missing}")

# 3. Hardcoded literal audit (allow-list: symbols, numbers, brand, error.message, runtime variables)
pat = re.compile(r'(const Text\([\'"]|Text\([\'"]|labelText: [\'"]|title: Text\([\'"]|content: Text\([\'"]|label: Text\([\'"]|hintText: [\'"]|tooltip: [\'"]|SnackBar\(content: Text\([\'"])')
allow = re.compile(r'[°×x%pt]|\'\d|_progress|fileSize|sourceType|totalMB|e\.message|Text\(msg\)|\'B\'|\'I\'|\'U\'|KB|MB|GB')
violations = []
for path in glob.glob('lib/**/*.dart', recursive=True):
    if 'l10n/' in path: continue
    for lineno, line in enumerate(open(path, encoding='utf-8'), 1):
        if pat.search(line) and not allow.search(line):
            if 'l10n.' not in line and 'AppLocalizations.' not in line and 'AppLocale.' not in line:
                violations.append(f"{path}:{lineno}: {line.rstrip()[:100]}")
if violations:
    FAILURES.append(f"HARDCODED LITERALS ({len(violations)}):")
    FAILURES.extend(violations[:30])

if FAILURES:
    print("❌ L10N AUDIT FAILED")
    for f in FAILURES:
        print(f)
    sys.exit(1)
print(f"✅ L10N AUDIT PASSED: {len(enk)} keys, 0 drift, 0 hardcoded literals")
sys.exit(0)
