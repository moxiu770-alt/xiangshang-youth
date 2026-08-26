package com.xiangshang.youth

import com.xiangshang.youth.core.model.LegalPolicy
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LegalPolicyTest {
    @Test fun consentVersionsAreConcreteAndCameraWordingMatchesLocalProcessing() {
        assertNotEquals("v1", LegalPolicy.PRIVACY_POLICY_VERSION)
        assertNotEquals("v1", LegalPolicy.CAMERA_CONSENT_VERSION)
        assertTrue(LegalPolicy.document("隐私政策").contains("不保存原始照片或视频"))
        assertTrue(LegalPolicy.document("儿童隐私").contains("照片、视频和帧不保存、不上传"))
        assertFalse(LegalPolicy.document("儿童隐私").contains("原始影像按学校配置"))
        assertTrue(LegalPolicy.document("隐私政策").contains("发送匿名使用情况"))
    }
}
