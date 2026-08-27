fun main() {
    val lowerPath = "/data/user/0/com.example.crm_mobile/files/recordings/rec_outgoing_1234_romi.m4a".lowercase()
    val lowerName = "rec_outgoing_1234_romi.m4a".lowercase()
    
    val isInbound = lowerPath.contains("inbound") || lowerPath.contains("incoming") || lowerPath.contains("call_in") || lowerPath.contains("rec_in") || lowerPath.contains("call/in") || lowerPath.contains("sound_recorder/call_rec/in") ||
            lowerName.contains("inbound") || lowerName.contains("incoming") || lowerName.contains("_in_") || lowerName.contains("_inc_") ||
            lowerName.contains("callin") || lowerName.contains("recv") || lowerName.contains("received") || lowerName.contains("(in)") ||
            lowerName.startsWith("in_") || lowerName.startsWith("inc_") || lowerName.startsWith("in-") || lowerName.startsWith("inc-") || lowerName.startsWith("1_")
            
    println("isInbound: $isInbound")
}
