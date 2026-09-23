import java.util.regex.Pattern

fun main(args: Array<String>) {
    var clean = ".pending-1790659846-Call_7880048800_20260922_110046.m4a"
    val regex1 = Regex("^\\.?pending[-_]?[a-zA-Z0-9]*[-_]?", RegexOption.IGNORE_CASE)
    clean = clean.replace(regex1, "")
    println(clean)
}
