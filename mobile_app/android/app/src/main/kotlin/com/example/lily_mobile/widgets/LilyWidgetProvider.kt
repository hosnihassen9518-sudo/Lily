package com.example.lily_mobile.widgets
import android.app.PendingIntent
import android.appwidget.AppWidgetProvider
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.ComponentName
import android.net.Uri
import android.widget.RemoteViews
import com.example.lily_mobile.MainActivity
import com.example.lily_mobile.R
import java.util.concurrent.Executors
class LilyWidgetProvider:AppWidgetProvider(){
 override fun onUpdate(c:Context,manager:AppWidgetManager,ids:IntArray){updateAll(c);LilyWidgetWorker.enqueue(c)}
 override fun onReceive(c:Context,intent:Intent){
  if(intent.action!=REFRESH && intent.action!=POWER){super.onReceive(c,intent);return}
  val pending=goAsync()
  background.execute {
   try {
    if(intent.action==REFRESH)LilyWidgetWorker.enqueue(c.applicationContext)
    else LilyWidgetWorker.enqueue(c.applicationContext,intent.getIntExtra("device_id",-1),intent.getBooleanExtra("enabled",false),intent.getStringExtra("context_id"),intent.getIntExtra("generation",-1))
   }catch(_:Exception){/* A storage or launcher failure must not crash Lily. */}
   finally{pending.finish()}
  }
 }
 companion object {
  private val background=Executors.newFixedThreadPool(2)
  const val REFRESH="com.example.lily_mobile.WIDGET_REFRESH"
  const val POWER="com.example.lily_mobile.WIDGET_POWER"
  @Suppress("DEPRECATION")
  fun updateAll(c:Context){
   val manager=AppWidgetManager.getInstance(c);val ids=manager.getAppWidgetIds(ComponentName(c,LilyWidgetProvider::class.java))
   if(ids.isEmpty())return
   val message=LilyWidgetStore.snapshot(c).optString("message","")
   for(id in ids){
    val views=RemoteViews(c.packageName,R.layout.lily_widget)
    val adapter=Intent(c,LilyWidgetService::class.java).putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID,id).apply{data=Uri.parse("lily://widget/$id")}
    views.setRemoteAdapter(R.id.widget_devices,adapter);views.setEmptyView(R.id.widget_devices,R.id.widget_empty)
    views.setTextViewText(R.id.widget_message,message)
    val refresh=PendingIntent.getBroadcast(c,id,Intent(c,LilyWidgetProvider::class.java).setAction(REFRESH),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    views.setOnClickPendingIntent(R.id.widget_refresh,refresh)
    val power=PendingIntent.getBroadcast(c,id+10000,Intent(c,LilyWidgetProvider::class.java).setAction(POWER),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE)
    views.setPendingIntentTemplate(R.id.widget_devices,power)
    val open=PendingIntent.getActivity(c,id,Intent(c,MainActivity::class.java),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    views.setOnClickPendingIntent(R.id.widget_title,open)
    manager.updateAppWidget(id,views)
   }
   manager.notifyAppWidgetViewDataChanged(ids,R.id.widget_devices)
  }
 }
}
