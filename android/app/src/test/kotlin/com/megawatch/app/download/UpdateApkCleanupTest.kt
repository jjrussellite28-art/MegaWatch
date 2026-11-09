package com.megawatch.app.download

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class UpdateApkCleanupTest {
    private fun eligible(version: Long = 52, modified: Long = 99,
                         pkg: String = "com.megawatch.app") =
        UpdateApkCleanup.eligible(pkg, "com.megawatch.app", version, 52, modified, 100_500)

    @Test fun installedAndOlderUpdatesAreRemoved() {
        assertTrue(eligible())
        assertTrue(eligible(version = 51))
    }
    @Test fun cancelledNewerUpdateIsRetained() {
        assertFalse(eligible(version = 53))
    }
    @Test fun downloadsAfterInstallationAndBoundarySecondAreRetained() {
        assertFalse(eligible(modified = 101))
        assertFalse(eligible(modified = 100))
    }
    @Test fun unrelatedAndUnknownArchivesAreRetained() {
        assertFalse(eligible(pkg = "com.megawatch.app.personal"))
        assertFalse(eligible(version = 0))
        assertFalse(eligible(modified = 0))
    }
}
