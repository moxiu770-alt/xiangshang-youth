package com.xiangshang.youth

import com.xiangshang.youth.core.model.LegalPolicy
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class LegalPolicyTest {
    @Test fun consentVersionsAreConcreteAndCameraWordingMatchesLocalProcessing() {
        assertNotEquals("v1", LegalPolicy.PRIVACY_POLICY_VERSION)
        assertNotEquals("v1", LegalPolicy.CAMERA_CONSENT_VERSION)
        assertTrue(LegalPolicy.document("隐私政策").contains("不保存原始照片或视频"))
        assertTrue(LegalPolicy.document("隐私政策").contains("发送匿名使用情况"))

        val reader: (String) -> String = { name ->
            val asset = listOf(File("src/main/assets/$name"), File("app/src/main/assets/$name")).first { it.isFile }
            asset.readText()
        }
        val terms = LegalPolicy.document(LegalPolicy.USER_AGREEMENT_TITLE, reader)
        val childStatement = LegalPolicy.document(LegalPolicy.CHILD_PRIVACY_TITLE, reader)
        assertTrue(terms.startsWith("向上少年身心健康用户服务协议"))
        assertTrue(terms.contains("十八、联系我们"))
        assertTrue(childStatement.startsWith("向上少年身心健康儿童个人信息保护声明"))
        assertTrue(childStatement.contains("十、联系我们"))
        assertTrue(childStatement.contains("不保存身份证照片及人脸原始图像"))
        assertFalse(childStatement.contains("原始影像按学校配置"))
    }
}
