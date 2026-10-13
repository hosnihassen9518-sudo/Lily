package com.example.lily_mobile.widgets

import org.junit.Assert.*
import org.junit.Test

class WidgetPendingCommandsTest {
    @Test fun repeatedTapsCannotReplaceAnActiveCommand() {
        val tracker = WidgetPendingCommands()
        assertTrue(tracker.begin(1, WidgetCommandTicket("first", "account", 4, 1000), 1000))
        assertFalse(tracker.begin(1, WidgetCommandTicket("second", "account", 4, 1001), 1001))
        assertTrue(tracker.isCurrent(1, "first", "account", 4, 1002))
        assertFalse(tracker.isCurrent(1, "second", "account", 4, 1002))
    }
    @Test fun anotherDeviceDoesNotWaitForTheFirstDevice() {
        val tracker = WidgetPendingCommands()
        assertTrue(tracker.begin(1, WidgetCommandTicket("one", "account", 4, 1000), 1000))
        assertTrue(tracker.begin(2, WidgetCommandTicket("two", "account", 4, 1001), 1001))
    }
    @Test fun staleCompletionCannotClearANewerAccountCommand() {
        val tracker = WidgetPendingCommands()
        tracker.begin(1, WidgetCommandTicket("old", "old-account", 4, 1000), 1000)
        assertTrue(tracker.begin(1, WidgetCommandTicket("new", "new-account", 5, 1001), 1001))
        assertFalse(tracker.finish(1, "old"))
        assertTrue(tracker.isCurrent(1, "new", "new-account", 5, 1002))
        assertFalse(tracker.isCurrent(1, "old", "old-account", 4, 1002))
    }
    @Test fun expiredPendingCommandDoesNotLockControlsForever() {
        val tracker = WidgetPendingCommands()
        tracker.begin(1, WidgetCommandTicket("old", "account", 4, 1000), 1000)
        assertFalse(tracker.isCurrent(1, "old", "account", 4, 62000))
        assertTrue(tracker.begin(1, WidgetCommandTicket("new", "account", 4, 62000), 62000))
        assertTrue(tracker.finish(1, "new"))
        assertFalse(tracker.isCurrent(1, "new", "account", 4, 62001))
    }
}
