package local.freescene.freescene

import android.app.AlertDialog
import android.content.Context
import android.view.View
import androidx.media3.common.C
import androidx.media3.common.Player
import androidx.media3.common.TrackGroup
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.ui.PlayerView
import androidx.media3.ui.R as MediaR
import kotlin.math.abs

/** Media3's built-in settings do not expose a TrackNameProvider. Use public player APIs. */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class PlayerSettings(private val context: Context,
    private val opened: () -> Unit = {}, private val dismissed: () -> Unit = {},
    private val player: () -> Player?) {
    private var dialog: AlertDialog? = null
    private val names = PlayerTrackNames(context.resources)
    private val speeds = floatArrayOf(.25f, .5f, .75f, 1f, 1.25f, 1.5f, 2f)
    private data class Audio(val group: TrackGroup, val index: Int, val name: String, val selected: Boolean)

    fun bind(view: PlayerView) {
        view.findViewById<View>(MediaR.id.exo_settings)?.setOnClickListener { show() }
        view.findViewById<View>(MediaR.id.exo_audio_track)?.setOnClickListener { showAudio() }
        view.findViewById<View>(MediaR.id.exo_playback_speed)?.setOnClickListener { showSpeed() }
    }
    fun dismiss() {
        val current = dialog ?: return
        dialog = null
        current.dismiss()
        dismissed()
    }
    private fun show(builder: AlertDialog.Builder, selected: Int? = null) {
        dismiss()
        val next = builder.create()
        dialog = next
        opened()
        next.setOnDismissListener {
            if (dialog === next) { dialog = null; dismissed() }
        }
        next.show()
        next.listView?.let { list ->
            if (TvWindow.isTv(context)) list.requestFocus()
            selected?.takeIf { it >= 0 }?.let(list::setSelection)
        }
    }
    private fun builder(title: Int) = AlertDialog.Builder(context, android.R.style.Theme_Material_Dialog_Alert)
        .setTitle(title).setNegativeButton(android.R.string.cancel, null)

    fun show() {
        val current = player() ?: return
        val options = mutableListOf<Int>()
        if (current.isCommandAvailable(Player.COMMAND_SET_SPEED_AND_PITCH)) options += MediaR.string.exo_controls_playback_speed
        if (canSelectAudio(current)) options += MediaR.string.exo_track_selection_title_audio
        show(builder(MediaR.string.exo_controls_settings_description)
            .setItems(options.map(context::getString).toTypedArray()) { _, which ->
                if (player() === current) when (options[which]) {
                    MediaR.string.exo_controls_playback_speed -> showSpeed()
                    MediaR.string.exo_track_selection_title_audio -> showAudio()
                }
            })
    }
    private fun canSelectAudio(current: Player) = current.isCommandAvailable(Player.COMMAND_GET_TRACKS) &&
        current.isCommandAvailable(Player.COMMAND_SET_TRACK_SELECTION_PARAMETERS)

    fun showAudio() {
        val current = player() ?: return
        if (!canSelectAudio(current)) return
        val tracks = current.currentTracks.groups.filter { it.type == C.TRACK_TYPE_AUDIO }.flatMap { group ->
            (0 until group.length).filter { group.isTrackSupported(it) }.map { index ->
                Audio(group.mediaTrackGroup, index, names.getTrackName(group.getTrackFormat(index)), group.isTrackSelected(index))
            }
        }
        val automatic = current.trackSelectionParameters.overrides.keys.none { it.type == C.TRACK_TYPE_AUDIO }
        val selected = if (automatic) 0 else tracks.indexOfFirst { it.selected }.let { if (it < 0) -1 else it + 1 }
        val labels = listOf(context.getString(MediaR.string.exo_track_selection_auto)) + tracks.map { it.name }
        show(builder(MediaR.string.exo_track_selection_title_audio)
            .setSingleChoiceItems(labels.toTypedArray(), selected) { shown, which ->
                if (player() === current && canSelectAudio(current)) {
                    val chosen = tracks.getOrNull(which - 1)
                    // A live stream or another episode may have replaced the snapshot while the menu was open.
                    val available = chosen == null || current.currentTracks.groups.any { group ->
                        group.mediaTrackGroup == chosen.group && chosen.index < group.length && group.isTrackSupported(chosen.index)
                    }
                    if (available) {
                        val selection = current.trackSelectionParameters.buildUpon()
                            .clearOverridesOfType(C.TRACK_TYPE_AUDIO).setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, false)
                        if (chosen != null) selection.setOverrideForType(TrackSelectionOverride(chosen.group, chosen.index))
                        current.trackSelectionParameters = selection.build()
                    }
                }
                shown.dismiss()
            }, selected)
    }
    fun showSpeed() {
        val current = player() ?: return
        if (!current.isCommandAvailable(Player.COMMAND_SET_SPEED_AND_PITCH)) return
        val labels = context.resources.getStringArray(MediaR.array.exo_controls_playback_speeds)
        val selected = speeds.indices.minByOrNull { abs(speeds[it] - current.playbackParameters.speed) } ?: 3
        show(builder(MediaR.string.exo_controls_playback_speed)
            .setSingleChoiceItems(labels, selected) { shown, which ->
                if (player() === current && current.isCommandAvailable(Player.COMMAND_SET_SPEED_AND_PITCH)) current.setPlaybackSpeed(speeds[which])
                shown.dismiss()
            }, selected)
    }
}
