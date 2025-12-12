// Optimized date pattern matching using a lookup table approach
const DATE_PATTERNS = [
    { regex: /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})Z$/, mask: "yyyy-MM-dd'T'HH:mm:ss'Z'" },
    { regex: /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{2})Z$/, mask: "yyyy-MM-dd'T'HH:mm:ss.SS'Z'" },
    { regex: /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3})Z$/, mask: "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'" },
    { regex: /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}-\d{4})$/, mask: "yyyy-MM-dd'T'HH:mm:ssZ" },
    { regex: /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}-\d{4})$/, mask: "yyyy-MM-dd'T'HH:mm:ss.SSSZ" },
    { regex: /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}-\d{2}:\d{2})$/, mask: "yyyy-MM-dd'T'HH:mm:ssZZ" },
    { regex: /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}-\d{2}:\d{2})$/, mask: "yyyy-MM-dd'T'HH:mm:ss.SSSZZ" },
    { regex: /^(\d{8}\s\d{6})$/, mask: "yyyyMMdd HHmmss" },
    { regex: /^(\d{8}\s\d{6}\.\d{3})$/, mask: "yyyyMMdd HHmmss.SSS" },
    { regex: /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{1})Z$/, mask: "yyyy-MM-dd'T'HH:mm:s'Z'" },
    { regex: /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{3})Z$/, mask: "yyyy-MM-dd'T'HH:mm:sss'Z'" },
    { regex: /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{4})Z$/, mask: "yyyy-MM-dd'T'HH:mm:ss.SSSS'Z'" },
    { regex: /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{5})Z$/, mask: "yyyy-MM-dd'T'HH:mm:ss.SSSSS'Z'" },
    { regex: /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6})Z$/, mask: "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'" },
    { regex: /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{7})Z$/, mask: "yyyy-MM-dd'T'HH:mm:ss.SSSSSSS'Z'" },
    { regex: /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{8})Z$/, mask: "yyyy-MM-dd'T'HH:mm:ss.SSSSSSSS'Z'" },
    { regex: /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{9})Z$/, mask: "yyyy-MM-dd'T'HH:mm:ss.SSSSSSSSS'Z'" },
    { regex: /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{10})Z$/, mask: "yyyy-MM-dd'T'HH:mm:ss.SSSSSSSSSS'Z'" }
];

// Optimized pattern matching function
function getDateFormat(dateString) {
    for (const pattern of DATE_PATTERNS) {
        if (pattern.regex.test(dateString)) {
            return {
                date_out: dateString,
                date_mask: pattern.mask
            };
        }
    }
    // No matching pattern found
    return null;
}

// No date will be passed if the data does not match one of the prescribed date formats.
const result = getDateFormat(date_in);
if (result) {
    date_out = result.date_out;
    date_mask = result.date_mask;
}

