package com.opencapture.openinstacine.monitor.multiview

import android.content.Context
import androidx.core.content.edit
import com.opencapture.opencine.appkit.MultiviewJournalStorage
import com.opencapture.opencine.appkit.MultiviewStageJournal
import com.opencapture.opencine.multicam.ResourceBudget

/** This app's four-camera qualification (Pocket's). Stage validation and admission share it. */
internal object MultiviewQualificationPolicy {
    val budget = ResourceBudget(qualifiedEntries = 4)
    val tileCount: Int = requireNotNull(budget.qualifiedEntries) { "Multiview requires a finite app qualification budget" }
}

/**
 * Device-only Multiview stage metadata and the camera Wi-Fi cleanup record. The stage types and
 * codec are OpenCine's [MultiviewStageJournal]; network passwords stay with the Luna setups' store.
 */
object MultiviewStageStore {
    fun storage(context: Context): MultiviewJournalStorage =
        MultiviewJournalStorage(load = { load(context) }, save = { save(context, it) })

    fun load(context: Context): MultiviewStageJournal.Stage? = prefs(context).getString(KEY, null)?.let(::decode)

    fun save(context: Context, stage: MultiviewStageJournal.Stage?): Boolean {
        if (stage == null) {
            prefs(context).edit { remove(KEY) }
            return true
        }
        val raw = encode(stage) ?: return false
        prefs(context).edit(commit = true) { putString(KEY, raw) }
        return true
    }

    /** The stored text of a stage valid for this app's tile count; null otherwise. */
    fun encode(stage: MultiviewStageJournal.Stage): String? =
        stage.validated(MultiviewQualificationPolicy.tileCount)?.let { MultiviewStageJournal.encode(stage) }

    /** The stage stored text holds when it reads and is valid for this app's tile count. */
    fun decode(raw: String): MultiviewStageJournal.Stage? =
        MultiviewStageJournal.decode(raw)?.validated(MultiviewQualificationPolicy.tileCount)

    private fun prefs(context: Context) = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private const val PREFS = "openinstacine.multiview-stage"
    private const val KEY = "stage"
}
