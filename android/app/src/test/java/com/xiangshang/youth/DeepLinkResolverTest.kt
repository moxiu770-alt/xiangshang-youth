package com.xiangshang.youth

import com.xiangshang.youth.core.util.DeepLinkResolver
import com.xiangshang.youth.core.util.DeepLinkTarget
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class DeepLinkResolverTest {
    @Test fun parsesReportAndDecodesStudentId() {
        val link = DeepLinkResolver.parse("xiangshang-youth://open?target=report&studentId=s%2002")
        assertEquals(DeepLinkTarget.Report, link?.target)
        assertEquals("s 02", link?.studentId)
    }

    @Test fun rejectsUnknownHostsAndTargets() {
        assertNull(DeepLinkResolver.parse("xiangshang-youth://other?target=report"))
        assertNull(DeepLinkResolver.parse("xiangshang-youth://open?target=unknown"))
    }

    @Test fun parsesAllSupportedDashboardTargets() {
        mapOf(
            "report" to DeepLinkTarget.Report,
            "review" to DeepLinkTarget.Review,
            "tasks" to DeepLinkTarget.Tasks,
            "risk" to DeepLinkTarget.Risk
        ).forEach { (target, expected) ->
            assertEquals(expected, DeepLinkResolver.parse("xiangshang-youth://open?target=$target")?.target)
        }
    }

    @Test fun reportAccessRequiresAnExistingFamilyBinding() {
        val boundChildren = setOf("s01", "s02")

        assertEquals(true, DeepLinkResolver.isBoundFamilyStudent("s02", boundChildren))
        assertEquals(false, DeepLinkResolver.isBoundFamilyStudent("s03", boundChildren))
        assertEquals(false, DeepLinkResolver.isBoundFamilyStudent(null, boundChildren))
    }
}
