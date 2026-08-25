package com.xiangshang.youth.core.model

import com.squareup.moshi.Json

enum class TestItem(val label: String) {
    @Json(name = "连续双脚障碍跳") ObstacleJump("连续双脚障碍跳"),
    @Json(name = "侧向滑步") LateralStep("侧向滑步"),
    @Json(name = "倒退平衡") BackwardBalance("倒退平衡"),
    @Json(name = "接球-上手掷准") CatchThrow("接球-上手掷准"),
    @Json(name = "手运球绕杆") HandDribble("手运球绕杆"),
    @Json(name = "脚运球变向") FootDribble("脚运球变向"),
    @Json(name = "定点踢准") TargetKick("定点踢准")
}
