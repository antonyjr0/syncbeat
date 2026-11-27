package com.example.syncbeat

/** Bounded discovery state; callbacks from a lost registration cannot revive it. */
internal class AdbDiscoveryEntries {
    data class Ticket(val name: String, val generation: Long)
    private var generation = 0L
    private val active = linkedMapOf<String, Ticket>()
    private val pending = mutableSetOf<Ticket>()
    private val failed = mutableSetOf<Ticket>()
    private val values = linkedMapOf<Ticket, Map<String, Any>>()
    val size get() = active.size
    val pendingResolution get() = pending.isNotEmpty()
    val resolutionFailed get() = failed.isNotEmpty()
    val resolvedCount get() = values.size

    fun found(name: String): Ticket? {
        if (name in active) return null
        return Ticket(name, ++generation).also { active[name] = it; pending.add(it) }
    }
    fun ticket(name: String) = active[name]
    fun update(ticket: Ticket, value: Map<String, Any>): Boolean {
        if (active[ticket.name] != ticket) return false
        pending.remove(ticket); failed.remove(ticket)
        values[ticket] = value.toMap()
        return true
    }
    fun fail(ticket: Ticket) {
        if (active[ticket.name] != ticket) return
        pending.remove(ticket); values.remove(ticket); failed.add(ticket)
    }
    fun invalidate(ticket: Ticket) {
        if (active[ticket.name] != ticket) return
        values.remove(ticket); failed.remove(ticket); pending.add(ticket)
    }
    fun lost(name: String) {
        val ticket = active.remove(name) ?: return
        pending.remove(ticket); failed.remove(ticket); values.remove(ticket)
    }
    fun snapshot() = values.values.toList()
}
