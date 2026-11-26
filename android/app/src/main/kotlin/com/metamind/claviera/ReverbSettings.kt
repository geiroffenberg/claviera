package com.metamind.claviera

internal data class ReverbSettings(
    val enabled: Boolean,
    val wet: Float,
    val feedback: Float,
    val damping: Float,
    val tailMs: Int,
) {
    companion object {
        fun fromMap(map: Map<String, Any>): ReverbSettings? {
            val enabled = map["enabled"] as? Boolean ?: return null
            val wet = (map["wet"] as? Double)?.toFloat() ?: return null
            val feedback = (map["feedback"] as? Double)?.toFloat() ?: return null
            val damping = (map["damping"] as? Double)?.toFloat() ?: return null
            val tailMs = map["tailMs"] as? Int ?: return null
            if (wet !in 0f..1f || feedback !in 0.5f..0.9f ||
                damping !in 0f..0.8f || tailMs !in 500..4000
            ) return null
            return ReverbSettings(enabled, wet, feedback, damping, tailMs)
        }
    }
}
