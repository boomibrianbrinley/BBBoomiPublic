# FWK-ENC Test Samples

19 files: 6 encodings × 3 formats (raw text, JSON, XML), plus one deliberately-ambiguous binary file.

Within a given encoding, all 3 format variants carry the *same* logical content — so a correct
run of the script should normalize all 3 to matching UTF-16 text, regardless of format, and
regardless of which encoding row they came from.

Content used (all rows except `ascii-plain`):
- customer: `René Müller`
- note: `Café order — total €42.50`
- quote: `She said "ok"` (curly quotes in the actual files)

`ascii-plain` uses plain ASCII content instead (`Jane Doe`, no special characters) as the trivial
baseline case.

**Note on the XML files:** the `<?xml version="1.0"?>` prolog deliberately has **no `encoding=`
attribute**. That's intentional, not an oversight — the whole point of this suite is testing
byte-level detection when you can't trust declared/absent metadata. Don't "fix" this by adding
`encoding="UTF-8"` etc.; a partner file lying about (or omitting) its own encoding is exactly the
real-world case `FWK-ENC` exists for.

## File matrix

| Encoding row | Raw (`.txt`) | JSON (`.json`) | XML (`.xml`) | Expected `DetectedEncoding` |
|---|---|---|---|---|
| UTF-8 with BOM | `sample-utf8-bom-raw.txt` | `sample-utf8-bom.json` | `sample-utf8-bom.xml` | `UTF-8 (BOM)` |
| UTF-8, no BOM | `sample-utf8-nobom-raw.txt` | `sample-utf8-nobom.json` | `sample-utf8-nobom.xml` | `UTF-8 (icu4j, confidence=...)` — high confidence |
| UTF-16LE with BOM | `sample-utf16le-bom-raw.txt` | `sample-utf16le-bom.json` | `sample-utf16le-bom.xml` | `UTF-16LE (BOM)` |
| UTF-16BE with BOM | `sample-utf16be-bom-raw.txt` | `sample-utf16be-bom.json` | `sample-utf16be-bom.xml` | `UTF-16BE (BOM)` |
| Windows-1252, no BOM | `sample-windows1252-raw.txt` | `sample-windows1252.json` | `sample-windows1252.xml` | `windows-1252` or `ISO-8859-1` (icu4j) — check confidence + decoded text either way |
| Plain ASCII | `sample-ascii-plain-raw.txt` | `sample-ascii-plain.json` | `sample-ascii-plain.xml` | `US-ASCII` or `UTF-8`, high confidence — either is correct, ASCII is a subset of both |

Plus, standalone (not expanded to json/xml — it's intentionally not structured text):

| File | What it is | Expected `DetectedEncoding` |
|---|---|---|
| `sample-ambiguous-binary.bin` | Random high-byte noise, not valid text in any encoding | `windows-1252 (fallback, icu4j confidence too low)` |

## What to check per file

1. **No `�` (U+FFFD) in the output** — confirms the source bytes were decoded with the right charset before re-encoding.
2. **`René Müller`, `Café`, em dash, `€`, curly quotes all render correctly** in the UTF-16 output — these are exactly the characters that get mangled when Windows-1252 is misread as UTF-8 or vice versa.
3. **The `DetectedEncoding` Dynamic Document Property** matches what's expected in the table above — this is your visibility into which code path actually fired, so you don't have to only trust the visible output.
4. **`sample-ambiguous-binary.bin` doesn't throw** — it should safely fall through to the Windows-1252 fallback rather than the process erroring.
5. **Format doesn't affect detection** — for a given encoding row, raw/JSON/XML should all report the same `DetectedEncoding` and normalize to equivalent UTF-16 content. If one format diverges from the other two on the same row, that's a bug worth chasing (e.g., the XML prolog's leading `<?xml` bytes throwing off statistical detection on short inputs).

## Suggested Boomi test process

1. Pull each file from git (raw HTTP GET on the file's Git provider URL, or via whatever connector you're already using to source them).
2. Route each through `FWK-ENC`.
3. Inspect the resulting document + the `DetectedEncoding` DDP in Process Reporting for each execution.
4. Confirm the JSON/XML profile downstream parses the normalized UTF-16 output without error for every file in that format group — that's the real acceptance bar, since it's the reason UTF-16 output was requested in the first place.
