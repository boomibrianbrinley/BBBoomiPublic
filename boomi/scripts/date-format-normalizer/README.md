# Date Format Normalizer

[`UpdatedDateFormat.js`](UpdatedDateFormat.js) is a JavaScript snippet meant to run inside a Boomi **Data Process** shape's custom scripting step (Type: JavaScript).

## What it does

Given an input date string (`date_in`), it checks the string against a table of known date formats (ISO 8601 with/without milliseconds, with `Z` or numeric offset, `yyyyMMdd HHmmss`, etc.) and, on a match, sets:

- `date_out` — the original date string, unchanged
- `date_mask` — the Java-style date mask (e.g. `"yyyy-MM-dd'T'HH:mm:ss'Z'"`) that describes its format

This is useful upstream of a **Date Conversion** or **Set Properties** step that needs to know the format mask of an incoming date string before it can parse it, when the source system doesn't reliably send dates in one consistent format.

## Usage

1. Add a Data Process shape to your process, with a custom scripting step (JavaScript).
2. Ensure `date_in` is set as an input document property before this step runs.
3. Paste the contents of `UpdatedDateFormat.js` into the script step.
4. Downstream shapes can read `date_out` and `date_mask` as output document properties.

If the input doesn't match any known pattern, neither `date_out` nor `date_mask` is set — no date is passed through.
