package local.freescene.freescene

import android.app.Activity
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowAlertDialog

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class WebPlayerSettingsTest {
    @Test fun webTrackMenusSendOnlySelectedIndicesAndSubtitleOff() {
        val controller = Robolectric.buildActivity(Activity::class.java).setup()
        val commands = mutableListOf<JSONObject>()
        val settings = WebPlayerSettings(controller.get(), commands::add, {}, {}, {})
        settings.request("audio")
        assertEquals("settings", commands.last().getString("action"))
        settings.received(JSONObject("""{"audio":[{"label":"Original","selected":true},{"label":"Dub","selected":false}]}"""))
        val audio = ShadowAlertDialog.getLatestAlertDialog()
        assertEquals(0, audio.listView.checkedItemPosition)
        shadowOf(audio).clickOnItem(1)
        assertEquals("audio", commands.last().getString("action"))
        assertEquals(1, commands.last().getInt("value"))
        settings.request("text")
        settings.received(JSONObject("""{"text":[{"label":"English","selected":true}]}"""))
        val subtitles = ShadowAlertDialog.getLatestAlertDialog()
        assertEquals(1, subtitles.listView.checkedItemPosition)
        shadowOf(subtitles).clickOnItem(0)
        assertEquals(-1, commands.last().getInt("value"))
        settings.dismiss(); controller.pause().stop().destroy()
    }
    @Test fun malformedOrUnavailableTracksNeverBecomeASelectionCommand() {
        val controller = Robolectric.buildActivity(Activity::class.java).setup()
        val commands = mutableListOf<JSONObject>()
        val settings = WebPlayerSettings(controller.get(), commands::add, {}, {}, {})
        for (data in listOf("{}", "{\"audio\":[null]}", "{\"audio\":[]}")) {
            settings.request("audio"); settings.received(JSONObject(data))
            assertTrue(ShadowAlertDialog.getLatestAlertDialog().isShowing)
            settings.dismiss()
        }
        assertTrue(commands.all { it.getString("action") == "settings" })
        controller.pause().stop().destroy()
    }
}
