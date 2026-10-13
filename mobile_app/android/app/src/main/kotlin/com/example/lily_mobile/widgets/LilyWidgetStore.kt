package com.example.lily_mobile.widgets

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONObject
import java.security.KeyStore
import java.security.MessageDigest
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone
import java.util.UUID

object LilyWidgetStore {
    private val lock=Any()
    private const val alias="lily-widget-credentials-v1"
    private fun publicPrefs(c:Context)=c.getSharedPreferences("lily_widget_public",Context.MODE_PRIVATE)
    private fun privatePrefs(c:Context)=c.getSharedPreferences("lily_widget_secure",Context.MODE_PRIVATE)
    private fun key():SecretKey {
        val store=KeyStore.getInstance("AndroidKeyStore").apply{load(null)}
        (store.getKey(alias,null) as? SecretKey)?.let{return it}
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,"AndroidKeyStore").apply{
            init(KeyGenParameterSpec.Builder(alias,KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    fun identity(config:JSONObject):String=MessageDigest.getInstance("SHA-256").digest(
        (config.getString("backend_url")+"|"+config.getString("token")).toByteArray()).joinToString(""){"%02x".format(it)}
    fun expired(config:JSONObject):Boolean {
        val value=config.getString("expires_at").replace(Regex("\\.\\d+"),"").replace("Z","+00:00")
        val date=SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX",Locale.US).apply{timeZone=TimeZone.getTimeZone("UTC")}.parse(value)
        return date==null || date.time<=System.currentTimeMillis()
    }
    fun config(c:Context):JSONObject?=synchronized(lock){
        try {
            val encoded=privatePrefs(c).getString("sealed",null) ?: return@synchronized null
            val raw=Base64.decode(encoded,Base64.NO_WRAP)
            val cipher=Cipher.getInstance("AES/GCM/NoPadding");cipher.init(Cipher.DECRYPT_MODE,key(),GCMParameterSpec(128,raw.copyOfRange(0,12)))
            JSONObject(String(cipher.doFinal(raw.copyOfRange(12,raw.size)),Charsets.UTF_8))
        }catch(_:Exception){null}
    }
    fun configure(c:Context,value:JSONObject)=synchronized(lock){
        val snapshot=value.getJSONObject("snapshot");val config=JSONObject(value.toString()).apply{remove("snapshot")}
        val cipher=Cipher.getInstance("AES/GCM/NoPadding");cipher.init(Cipher.ENCRYPT_MODE,key())
        val sealed=Base64.encodeToString(cipher.iv+cipher.doFinal(config.toString().toByteArray()),Base64.NO_WRAP)
        check(privatePrefs(c).edit().putString("sealed",sealed).commit()){"Could not save widget credentials"}
        save(c,snapshot,identity(config))
    }
    private fun empty()=JSONObject().put("devices",org.json.JSONArray()).put("message","Open Lily and sign in to use widgets.")
    private fun pending(c:Context):WidgetPendingCommands {
        val entries=mutableMapOf<Int,WidgetCommandTicket>()
        try {
            val data=JSONObject(publicPrefs(c).getString("pending_commands","{}") ?: "{}")
            for(key in data.keys()) {
                val value=data.getJSONObject(key)
                entries[key.toInt()]=WidgetCommandTicket(value.getString("request"),value.getString("context"),value.getInt("generation"),value.getLong("created"))
            }
        }catch(_:Exception){entries.clear()}
        return WidgetPendingCommands(entries)
    }
    private fun savePending(c:Context,commands:WidgetPendingCommands) {
        val data=JSONObject()
        for((id,ticket) in commands.entries) data.put(id.toString(),JSONObject().put("request",ticket.requestId).put("context",ticket.contextId).put("generation",ticket.generation).put("created",ticket.createdAtMs))
        check(publicPrefs(c).edit().putString("pending_commands",data.toString()).commit()) { "Could not save pending widget command" }
    }
    fun beginCommand(c:Context,id:Int,expected:String?,generation:Int):String?=synchronized(lock){
        val current=config(c) ?: return@synchronized null
        val context=identity(current)
        if(expected!=context || expired(current))return@synchronized null
        val rows=snapshot(c).optJSONArray("devices") ?: return@synchronized null
        val row=(0 until rows.length()).map{rows.getJSONObject(it)}.firstOrNull{it.optInt("id")==id}
        if(row==null || !row.optBoolean("can_control") || row.optInt("generation",-1)!=generation)return@synchronized null
        val commands=pending(c);val ticket=WidgetCommandTicket(UUID.randomUUID().toString(),context,generation,System.currentTimeMillis())
        if(!commands.begin(id,ticket,System.currentTimeMillis()))return@synchronized null
        savePending(c,commands);message(c,"Sending command…",context)
        ticket.requestId
    }
    fun currentCommand(c:Context,id:Int,request:String,context:String,generation:Int):Boolean=synchronized(lock){
        config(c)?.let{identity(it)}==context && pending(c).isCurrent(id,request,context,generation,System.currentTimeMillis())
    }
    fun finishCommand(c:Context,id:Int,request:String):Boolean=synchronized(lock){
        val commands=pending(c)
        if(!commands.finish(id,request))return@synchronized false
        savePending(c,commands);true
    }
    fun snapshot(c:Context):JSONObject=synchronized(lock){
        val current=config(c) ?: return@synchronized empty()
        try {
            val value=JSONObject(publicPrefs(c).getString("snapshot","{}") ?: "{}")
            if(value.optString("context_id")!=identity(current))empty() else {
                val commands=pending(c);val rows=value.optJSONArray("devices")
                for(i in 0 until (rows?.length() ?: 0)) {
                    val row=rows!!.getJSONObject(i);val ticket=commands.entries[row.optInt("id")]
                    row.put("pending",ticket?.activeFor(identity(current),row.optInt("generation",-1),System.currentTimeMillis())==true)
                }
                value
            }
        }catch(_:Exception){empty()}
    }
    private fun save(c:Context,value:JSONObject,contextId:String){
        val copy=JSONObject(value.toString()).put("context_id",contextId)
        check(publicPrefs(c).edit().putString("snapshot",copy.toString()).commit()){"Could not save widget snapshot"}
    }
    fun update(c:Context,value:JSONObject,expected:String?=null)=synchronized(lock){
        val config=config(c) ?: return@synchronized
        val id=identity(config);if(expected!=null && id!=expected)return@synchronized
        save(c,value,id)
    }
    fun message(c:Context,text:String,expected:String?=null)=synchronized(lock){
        if(expected!=null && config(c)?.let{identity(it)}!=expected)return@synchronized
        val value=snapshot(c).put("message",text)
        publicPrefs(c).edit().putString("snapshot",value.toString()).commit()
    }
    fun clear(c:Context,expected:String?=null)=synchronized(lock){
        if(expected!=null && config(c)?.let{identity(it)}!=expected)return@synchronized
        privatePrefs(c).edit().clear().commit()
        publicPrefs(c).edit().remove("pending_commands").putString("snapshot",JSONObject().put("devices",org.json.JSONArray()).put("message","Open Lily and sign in to use widgets.").toString()).commit()
    }
}
