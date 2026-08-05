package com.xiangshang.youth.core.model
data class RegionPolicy(
    val id: String,
    val region: String,
    val povertyAreaLabel: String? = null,
    val standardVersion: String = "",
    val effectiveDate: String = ""
)
