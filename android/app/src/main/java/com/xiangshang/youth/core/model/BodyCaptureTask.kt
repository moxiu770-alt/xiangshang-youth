package com.xiangshang.youth.core.model

enum class BodyCaptureTask(val title: String, val guide: String, val apiCode: String) {
    StandingFront("正面自然站立观察", "面向镜头赤足站立，双脚与髋同宽，双臂自然下垂。", "standingFront"),
    StandingBack("静态站姿对称观察", "赤足站在足印位置，双眼平视，双臂自然下垂，全身放松，不刻意挺胸。", "standingBack"),
    StandingSide("左右侧位姿态观察", "先左侧站稳，按提示转为右侧，两侧都保持全身入镜。", "standingSide"),
    ForwardBend("亚当斯前屈试验", "双脚并拢，膝关节完全伸直，双手合十自然下垂，缓慢前屈至躯干接近水平，头部自然放松。", "forwardBend"),
    DynamicKneeControl("动态下肢力线观察", "面向镜头完成 3 次缓慢自重下蹲，膝盖朝向第二足趾，脚跟不离地。", "dynamicKneeControl"),
    Seated("无靠背坐姿脊柱直立测试", "坐满硬质无靠背凳面，双手平放膝盖，双脚落地，自然放松并保持直立坐姿。", "seatedPosture"),
    GaitVideo("动态步态姿态观察", "沿 3 米直线通道自然往返行走 1 次，保持日常步速，不刻意纠正姿势。", "gaitVideo"),
    FootArch("足弓与足跟对齐观察", "双足赤足平行站立，在距双脚约 1–1.2 米处按提示记录双侧足弓与足跟。", "footArch")
}
