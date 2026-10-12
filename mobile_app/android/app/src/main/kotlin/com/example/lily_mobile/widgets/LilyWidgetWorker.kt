package com.example.lily_mobile.widgets
import android.content.Context
import androidx.work.Worker
import androidx.work.WorkerParameters
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.ExistingWorkPolicy
import androidx.work.workDataOf
class LilyWidgetWorker(context:Context,params:WorkerParameters):Worker(context,params){
 override fun doWork():Result {
  val id=inputData.getInt("device_id",-1)
  LilyWidgetApi.run(applicationContext,if(id>=0)id else null,inputData.getBoolean("enabled",false),inputData.getString("context_id"),inputData.getInt("generation",-1))
  LilyWidgetProvider.updateAll(applicationContext);return Result.success()
 }
 companion object {
  fun enqueue(c:Context,id:Int=-1,enabled:Boolean=false,contextId:String?=null,generation:Int=-1){
   val request=OneTimeWorkRequestBuilder<LilyWidgetWorker>().setInputData(workDataOf("device_id" to id,"enabled" to enabled,"context_id" to contextId,"generation" to generation)).build()
   WorkManager.getInstance(c).enqueueUniqueWork("lily-widget-network",ExistingWorkPolicy.APPEND_OR_REPLACE,request)
  }
 }
}
