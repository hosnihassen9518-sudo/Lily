package com.example.lily_mobile.widgets
import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
object LilyWidgetBridge{
 fun install(engine:FlutterEngine,c:Context){
  MethodChannel(engine.dartExecutor.binaryMessenger,"lily/widgets").setMethodCallHandler{call,result->
   try{
    when(call.method){
     "supported"->result.success(true)
     "configure"->{LilyWidgetStore.configure(c,JSONObject(call.arguments as Map<*,*>));LilyWidgetProvider.updateAll(c);result.success(null)}
     "update"->{LilyWidgetStore.update(c,JSONObject(call.arguments as Map<*,*>));LilyWidgetProvider.updateAll(c);result.success(null)}
     "clear"->{LilyWidgetStore.clear(c);LilyWidgetProvider.updateAll(c);result.success(null)}
     else->result.notImplemented()
    }
   }catch(error:Exception){result.error("WIDGET_SETUP","Could not update widget configuration",null)}
  }
 }
}
