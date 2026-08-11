package com.radiomix.ralma

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private val fmChannelName = "com.radiomix.ralma/fm"
    private val fmEventsChannelName = "com.radiomix.ralma/fm_events"
    private var antennaReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, fmChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAntennaConnected" -> result.success(isWiredHeadsetConnected())
                    else -> result.notImplemented()
                }
            }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, fmEventsChannelName)
            .setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                        events?.success(isWiredHeadsetConnected())
                        startAntennaReceiver(events)
                    }

                    override fun onCancel(arguments: Any?) {
                        stopAntennaReceiver()
                    }
                },
            )
    }

    override fun onDestroy() {
        stopAntennaReceiver()
        super.onDestroy()
    }

    private fun isWiredHeadsetConnected(): Boolean {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        return devices.any { device ->
            device.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES ||
                device.type == AudioDeviceInfo.TYPE_WIRED_HEADSET
        }
    }

    private fun startAntennaReceiver(events: EventChannel.EventSink?) {
        stopAntennaReceiver()
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == AudioManager.ACTION_HEADSET_PLUG) {
                    events?.success(isWiredHeadsetConnected())
                }
            }
        }
        antennaReceiver = receiver
        val filter = IntentFilter(AudioManager.ACTION_HEADSET_PLUG)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(receiver, filter)
        }
    }

    private fun stopAntennaReceiver() {
        antennaReceiver?.let { receiver ->
            try {
                unregisterReceiver(receiver)
            } catch (_: IllegalArgumentException) {
            }
        }
        antennaReceiver = null
    }
}
