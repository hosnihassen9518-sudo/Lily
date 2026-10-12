package com.example.lily_mobile.widgets

import android.content.Context
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

class WidgetHttpError(val code:Int):Exception("Widget HTTP $code")
object LilyWidgetApi {
    private fun request(config:JSONObject,path:String,payload:JSONObject?=null):JSONObject {
        val connection=URL(config.getString("backend_url").trimEnd('/')+"/widgets"+path).openConnection() as HttpURLConnection
        try{
            connection.connectTimeout=3000;connection.readTimeout=5000;connection.instanceFollowRedirects=false
            connection.setRequestProperty("Authorization","Bearer "+config.getString("token"))
            connection.setRequestProperty("Accept","application/json")
            if(payload!=null){connection.requestMethod="POST";connection.doOutput=true;connection.setRequestProperty("Content-Type","application/json");connection.outputStream.use{it.write(payload.toString().toByteArray())}}
            val code=connection.responseCode;if(code !in 200..299)throw WidgetHttpError(code)
            return JSONObject(connection.inputStream.bufferedReader().use{it.readText()})
        }finally{connection.disconnect()}
    }
    fun run(c:Context,deviceId:Int?=null,enabled:Boolean=false,expected:String?=null,generation:Int=-1){
        val config=LilyWidgetStore.config(c) ?: run{LilyWidgetStore.clear(c);return}
        val identity=LilyWidgetStore.identity(config)
        if(expected!=null && expected!=identity)return
        try{
            if(LilyWidgetStore.expired(config)){LilyWidgetStore.clear(c,identity);return}
            if(deviceId!=null){
                val items=LilyWidgetStore.snapshot(c).optJSONArray("devices")
                val item=(0 until (items?.length() ?: 0)).map{items!!.getJSONObject(it)}.firstOrNull{it.optInt("id")==deviceId}
                if(item==null || !item.optBoolean("can_control")){LilyWidgetStore.message(c,"Refresh before controlling this device.",identity);return}
                val result=request(config,"/devices/$deviceId/power",JSONObject().put("enabled",enabled).put("expected_generation",if(generation>=0)generation else JSONObject.NULL))
                LilyWidgetStore.update(c,result.getJSONObject("snapshot").put("message","Command sent. Refresh to see the device’s latest state."),identity)
            }else LilyWidgetStore.update(c,request(config,"/devices"),identity)
        }catch(error:WidgetHttpError){
            if(error.code==401)LilyWidgetStore.clear(c,identity)
            else LilyWidgetStore.message(c,if(error.code==409 || error.code==404)"Device unavailable. Tap Refresh." else "Command not sent. Tap Refresh to retry.",identity)
        }catch(_:Exception){LilyWidgetStore.message(c,"Could not connect. Tap Refresh to retry.",identity)}
    }
}
