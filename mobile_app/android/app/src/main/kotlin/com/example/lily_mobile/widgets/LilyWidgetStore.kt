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
    fun snapshot(c:Context):JSONObject=synchronized(lock){
        val current=config(c) ?: return@synchronized empty()
        try {
            val value=JSONObject(publicPrefs(c).getString("snapshot","{}") ?: "{}")
            if(value.optString("context_id")!=identity(current))empty() else value
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
        publicPrefs(c).edit().putString("snapshot",JSONObject().put("devices",org.json.JSONArray()).put("message","Open Lily and sign in to use widgets.").toString()).commit()
    }
}
