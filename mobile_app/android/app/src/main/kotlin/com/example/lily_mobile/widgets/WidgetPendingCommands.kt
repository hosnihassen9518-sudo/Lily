package com.example.lily_mobile.widgets

data class WidgetCommandTicket(val requestId: String, val contextId: String, val generation: Int, val createdAtMs: Long) {
    fun activeFor(context: String, version: Int, now: Long): Boolean =
        contextId == context && generation == version && now - createdAtMs in 0 until 60_000L
}

class WidgetPendingCommands(val entries: MutableMap<Int, WidgetCommandTicket> = mutableMapOf()) {
    fun begin(deviceId: Int, ticket: WidgetCommandTicket, now: Long): Boolean {
        if (entries[deviceId]?.activeFor(ticket.contextId, ticket.generation, now) == true) return false
        entries[deviceId] = ticket
        return true
    }
    fun isCurrent(deviceId: Int, requestId: String, context: String, generation: Int, now: Long): Boolean =
        entries[deviceId]?.let { it.requestId == requestId && it.activeFor(context, generation, now) } == true
    fun finish(deviceId: Int, requestId: String): Boolean {
        if (entries[deviceId]?.requestId != requestId) return false
        entries.remove(deviceId)
        return true
    }
}
