package com.example.lily_mobile.widgets

import android.content.Context
import android.os.Build
import androidx.work.*
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class LilyWidgetWorker(context:Context,params:WorkerParameters):Worker(context,params){
 override fun doWork():Result {
  val id=inputData.getInt("device_id",-1)
  val request=inputData.getString("request_id")
  val context=inputData.getString("context_id")
  val generation=inputData.getInt("generation",-1)
  if(inputData.getBoolean("timeout",false)) {
   if(request!=null && context!=null && !LilyWidgetStore.currentCommand(applicationContext,id,request,context,generation)) {
    failCommand(applicationContext,id,request,context,"Command timed out. Tap again.")
   }
   return Result.success()
  }
  try {
   if(id>=0 && (request==null || context==null || !LilyWidgetStore.currentCommand(applicationContext,id,request,context,generation))) {
    if(request!=null && LilyWidgetStore.finishCommand(applicationContext,id,request) && context!=null)
     LilyWidgetStore.message(applicationContext,"Command timed out. Tap again.",context)
    return Result.success()
   }
   LilyWidgetApi.run(applicationContext,if(id>=0)id else null,inputData.getBoolean("enabled",false),context,generation)
   return Result.success()
  } finally {
   try {if(id>=0 && request!=null)LilyWidgetStore.finishCommand(applicationContext,id,request)}
   catch(_:Exception){/* The timeout worker or manual refresh can recover pending state. */}
   finally {try{LilyWidgetProvider.updateAll(applicationContext)}catch(_:Exception){}}
  }
 }
 companion object {
  private val callbacks=Executors.newSingleThreadExecutor()
  private fun failCommand(c:Context,id:Int,ticket:String,contextId:String?,message:String){
   try {
    if(LilyWidgetStore.finishCommand(c,id,ticket) && contextId!=null)LilyWidgetStore.message(c,message,contextId)
   } catch(_:Exception){/* Preserve crash safety even if preference storage fails. */}
   finally {try{LilyWidgetProvider.updateAll(c)}catch(_:Exception){}}
  }
  fun enqueue(c:Context,id:Int=-1,enabled:Boolean=false,contextId:String?=null,generation:Int=-1){
   var ticket:String?=null
   try {
    if(id>=0) {
     ticket=LilyWidgetStore.beginCommand(c,id,contextId,generation) ?: return
     LilyWidgetProvider.updateAll(c)
    }
    val builder=OneTimeWorkRequestBuilder<LilyWidgetWorker>().setInputData(workDataOf("device_id" to id,"enabled" to enabled,"context_id" to contextId,"generation" to generation,"request_id" to ticket))
    // Tap commands bypass refresh queues; expedited jobs avoid scheduler delays.
    // Android <12 uses normal work to avoid foreground-service startup requirements.
    if(id>=0 && Build.VERSION.SDK_INT>=31)builder.setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
    val manager=WorkManager.getInstance(c)
    if(ticket!=null) {
     val timeout=OneTimeWorkRequestBuilder<LilyWidgetWorker>().setInitialDelay(60,TimeUnit.SECONDS)
      .setInputData(workDataOf("device_id" to id,"context_id" to contextId,"generation" to generation,"request_id" to ticket,"timeout" to true)).build()
     manager.enqueueUniqueWork("lily-widget-timeout-$id",ExistingWorkPolicy.REPLACE,timeout)
    }
    val operation=manager.enqueueUniqueWork(
     if(id>=0)"lily-widget-command-$id" else "lily-widget-refresh",
     if(id>=0)ExistingWorkPolicy.APPEND_OR_REPLACE else ExistingWorkPolicy.KEEP,
     builder.build())
    val acceptedTicket=ticket
    operation.result.addListener({
     try {operation.result.get()}catch(_:Exception){
      if(acceptedTicket!=null)failCommand(c,id,acceptedTicket,contextId,"Could not send command. Try again.")
     }
    },callbacks)
   } catch(_:Exception) {
    if(ticket!=null)failCommand(c,id,ticket,contextId,"Could not send command. Try again.")
   }
  }
 }
}
