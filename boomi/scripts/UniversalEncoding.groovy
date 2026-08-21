/*
 * Prereq: attach a Custom Library component containing icu4j-77.1.jar
 * to this Custom Scripting step (Component > Custom Library).
 * Without that attachment, the com.ibm.icu import below will fail at runtime.
 */
import com.boomi.execution.ExecutionUtil
import com.ibm.icu.text.CharsetDetector
import com.ibm.icu.text.CharsetMatch
import java.nio.charset.Charset
import java.nio.charset.CodingErrorAction
import java.nio.ByteBuffer

def logger = ExecutionUtil.getBaseLogger()

// Confidence below this, we don't trust the statistical guess
final int MIN_CONFIDENCE = 50

for (int i = 0; i < dataContext.getDataCount(); i++) {
    InputStream is = dataContext.getStream(i)
    Properties props = dataContext.getProperties(i)

    byte[] raw = is.bytes
    String detectedName = null
    String text = null

    // 1. BOM check first — cheap and unambiguous when present
    if (raw.length >= 3 && raw[0] == (byte)0xEF && raw[1] == (byte)0xBB && raw[2] == (byte)0xBF) {
        detectedName = "UTF-8 (BOM)"
        text = new String(raw, 3, raw.length - 3, "UTF-8")
    } else if (raw.length >= 2 && raw[0] == (byte)0xFF && raw[1] == (byte)0xFE) {
        detectedName = "UTF-16LE (BOM)"
        text = new String(raw, 2, raw.length - 2, "UTF-16LE")
    } else if (raw.length >= 2 && raw[0] == (byte)0xFE && raw[1] == (byte)0xFF) {
        detectedName = "UTF-16BE (BOM)"
        text = new String(raw, 2, raw.length - 2, "UTF-16BE")
    } else {
        // 2. No BOM — ask ICU4J to detect
        CharsetDetector detector = new CharsetDetector()
        detector.setText(raw)
        CharsetMatch match = detector.detect()

        if (match != null && match.getConfidence() >= MIN_CONFIDENCE) {
            detectedName = "${match.getName()} (icu4j, confidence=${match.getConfidence()})"
            text = match.getString()
        } else {
            // 3. Low/no confidence — fall back rather than trust a weak guess
            detectedName = "windows-1252 (fallback, icu4j confidence too low)"
            text = new String(raw, "windows-1252")
        }
    }

    logger.info("Data Process encoding detection: doc[${i}] -> ${detectedName}")

    // Re-emit as UTF-16 for the downstream JSON profile
    byte[] outBytes = text.getBytes("UTF-16")

    // Record what we detected as a Dynamic Document Property for traceability
    props.setProperty("document.dynamic.userdefined.DetectedEncoding", detectedName)

    dataContext.storeStream(new ByteArrayInputStream(outBytes), props)
}
