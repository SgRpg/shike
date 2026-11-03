package com.dexterous.flutterlocalnotifications;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** Package-local plugin API; no reflection or second scheduling database. */
public final class ShikeTimeChangeReceiver extends BroadcastReceiver {
  @Override public void onReceive(Context context, Intent intent) {
    String action = intent.getAction();
    if (Intent.ACTION_TIME_CHANGED.equals(action) || Intent.ACTION_TIMEZONE_CHANGED.equals(action)) {
      FlutterLocalNotificationsPlugin.rescheduleNotifications(context);
    }
  }
}
