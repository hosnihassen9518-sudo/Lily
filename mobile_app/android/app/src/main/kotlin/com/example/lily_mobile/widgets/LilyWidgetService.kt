package com.example.lily_mobile.widgets
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import org.json.JSONArray
import com.example.lily_mobile.R
class LilyWidgetService:RemoteViewsService(){
 override fun onGetViewFactory(intent:Intent):RemoteViewsFactory=Factory(applicationContext)
 private class Factory(val context:Context):RemoteViewsFactory{
  var rows=JSONArray();var contextId=""
  override fun onCreate(){onDataSetChanged()}
  override fun onDataSetChanged(){val s=LilyWidgetStore.snapshot(context);rows=s.optJSONArray("devices") ?: JSONArray();contextId=s.optString("context_id")}
  override fun onDestroy(){}
  override fun getCount()=rows.length()
  override fun getViewAt(position:Int):RemoteViews{
   val row=rows.getJSONObject(position);val view=RemoteViews(context.packageName,R.layout.lily_widget_row)
   view.setTextViewText(R.id.device_name,row.optString("name","Lily device"));view.setTextViewText(R.id.device_status,row.optString("status","OFFLINE").replace('_',' '))
   val allowed=row.optBoolean("can_control") && contextId.isNotEmpty()
   for((button,enabled) in listOf(R.id.device_on to true,R.id.device_off to false)){
    view.setBoolean(button,"setEnabled",allowed)
    view.setOnClickFillInIntent(button,Intent().putExtra("device_id",row.getInt("id")).putExtra("enabled",enabled).putExtra("context_id",contextId).putExtra("generation",row.optInt("generation",-1)))
   }
   return view
  }
  override fun getLoadingView():RemoteViews?=null
  override fun getViewTypeCount()=1
  override fun getItemId(position:Int)=rows.getJSONObject(position).optLong("id",position.toLong())
  override fun hasStableIds()=true
 }
}
