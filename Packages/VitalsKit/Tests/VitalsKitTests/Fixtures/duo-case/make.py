"""Builds the Duo regression case (plan §4a item 10, §4c) as synthetic, redacted files.

Record names and field names are the real ones seen on an iPhone Duo (iOS 27.2.1, 15 Nov 2026). Values follow
the diagnosis of that phone (the report itself is private). Nothing personal: no device ids, incident ids, names, serials
or app lists beyond what the case needs. Run: python3 make.py
"""
import json

def rec(name, msg):
    return json.dumps({"aggregationPeriod": "Daily", "deviceId": "REDACTED", "message": msg, "name": name, "numDaysAggregated": 1, "sampling": 100.0, "uuid": "REDACTED"})

def header(ts):
    return json.dumps({"bug_type": "211", "timestamp": ts, "os_version": "iPhone OS 27.2.1 (24B91034)", "roots_installed": 0, "incident_id": "REDACTED"})

def writes(proc, b):
    return rec("massStorage_power_coalitionInfo", {"Count": 1, "process_name": proc, "sum_of_bytes_read": 1000000, "sum_of_bytes_written": b, "sum_of_fs_metadata_writes": 0, "sum_of_logical_writes": b, "sum_of_pm_writes": 0, "version": "unknown"})

day1 = [header("2026-11-15 08:00:00.00 +0800"),
    json.dumps({"_marker": "<metadata>", "appStoreCountry": "XX"}),
    rec("ExpressSetup", {"Count": 1, "customizedSettings": False, "dataSource": "iCloud", "presented": True}),
    rec("Datamigrator_Completion_Duration_4", {"Count": 1, "isFromFactory": True, "previousBuildVersion": "24A94232", "daily_maximum_durationInSeconds": 49}),
    rec("InstallationResult", {"Count": 92, "success": True, "error": None, "sum_of_duration": 1600}),
    rec("PowerModesDailyEngagement", {"Count": 15, "PowerMode": "InUseChargingMode", "daily_total_Duration": 7076, "thermalPressureLevel": "Nominal"}),
    rec("PowerModesDailyEngagement", {"Count": 9, "PowerMode": "RestrictedPerfMode", "daily_total_Duration": 7056, "thermalPressureLevel": "Light"}),
    rec("PowerModesDailyEngagement", {"Count": 6, "PowerMode": "RestrictedPerfMode", "daily_total_Duration": 4839, "thermalPressureLevel": "Moderate"}),
    writes("com.apple.cloudd", 58000000000), writes("com.apple.bird", 39000000000), writes("com.apple.appstored", 27000000000),
    writes("com.apple.nsurlsessiond", 15000000000), writes("com.example.chatapp", 14000000000), writes("com.apple.mobileassetd", 12000000000),
    rec("PowerExceptionsDetectionEvents", {"Count": 3, "IssueType": 2, "LaunchdName": "com.apple.appstored", "ProcessName": "appstored", "Unit": 0, "sum_of_Value": 1200.0}),
    rec("PowerExceptionsDetectionEvents", {"Count": 3, "IssueType": 2, "LaunchdName": "com.apple.appstored", "ProcessName": "com.apple.StreamingUnzipService", "Unit": 0, "sum_of_Value": 1200.0}),
    rec("deviceShutdownReasonDaily", {"Count": 1, "ShutdownReason": " rst wdog,reset_in_1 ap_restart"}),
    rec("deviceShutdownReasonDaily", {"Count": 1, "ShutdownReason": " rst wdog,reset_in_1 timeout,dblclick_timeout ap_restart"}),
    rec("ResetTelemetry2", {"Count": 1, "resetType": "sys watchdog", "wdog": True, "cpu_therm": False, "gpu_therm": False, "sochot": False, "ot": False}),
    rec("RebootAndRollover", {"Count": 2, "reason": "reboot"}),
    rec("SpotlightIndexRebuild_Daily", {"Count": 1, "trigger": 3}), rec("SpotlightIndexRebuild_Daily", {"Count": 1, "trigger": 1}),
    rec("HealthKit_CloudSync_Restore_DurationV3", {"Count": 1, "bucketed_duration": 9, "dbSize": 600, "finishedJournalMerge": False}),
    rec("OBCNoRotationBatteryHealthMetricsv2", {"Count": 1, "last_value_CycleCount": 1}),
    rec("OBC_Battery_Health_v3", {"Count": 1, "CycleCountBucket": 0, "sum_of_CycleCount": 1}),
    rec("BatteryLevelReportView5", {"Count": 1, "currentBatteryCapacity": 24, "deviceScreenOn": False}),
    rec("BatteryLevelReportView5", {"Count": 1, "currentBatteryCapacity": 17, "deviceScreenOn": True}),
    rec("UnpluggedDurationEnergyViewNew", {"Count": 54, "daily_total_Duration": 28056, "daily_total_Energy": 2699, "daily_total_unplugged_count": 1}),
    json.dumps({"_marker": "<end-of-file>"})]
open("Analytics-2026-11-15-080003.ips.ca.synced", "w").write("\n".join(day1) + "\n")

# Day two, phone-only: no setup records; the sync is still writing tens of GB.
day2 = [header("2026-11-16 08:00:00.00 +0800"),
    rec("PowerModesDailyEngagement", {"Count": 9, "daily_total_Duration": 5200, "thermalPressureLevel": "Light"}),
    rec("PowerModesDailyEngagement", {"Count": 2, "daily_total_Duration": 900, "thermalPressureLevel": "Moderate"}),
    writes("com.apple.cloudd", 45000000000), writes("com.apple.bird", 40000000000), writes("com.apple.nsurlsessiond", 900000000),
    rec("OBCNoRotationBatteryHealthMetricsv2", {"Count": 1, "last_value_CycleCount": 2})]
open("Analytics-2026-11-16-080001.ips.ca.synced", "w").write("\n".join(day2) + "\n")

# A real-format diskwrites report (iOS 27.2.1 layout), redacted.
open("bird.diskwrites_resource-2026-11-15-004146.ips", "w").write(json.dumps({"bug_type": "145", "timestamp": "2026-11-15 00:41:46.00 +0800", "app_name": "bird", "name": "bird", "incident_id": "REDACTED", "os_version": "iPhone OS 27.2.1 (24B91034)"}) + """
Date/Time:        2026-11-14 22:40:28.941 +0800
End time:         2026-11-15 00:41:42.641 +0800
OS Version:       iPhone OS 27.2.1 (Build 24B91034)
Command:          bird
Path:             /System/Library/PrivateFrameworks/iCloudDriveCore.framework/bird
Event:            disk writes
Action taken:     none
Writes:           17.18 GB of file backed memory dirtied over 7274 seconds (2361.92 KB per second average), exceeding limit of 198.84 KB per second over 86400 seconds
Writes limit:     17.18 GB
Limit duration:   86400s
Writes caused:    17.18 GB
Writes duration:  7274s
""")
open("StocksWidget.cpu_resource-2026-11-14-215449.ips", "w").write(json.dumps({"bug_type": "202", "app_name": "StocksWidget", "timestamp": "2026-11-14 21:54:49.00 +0800", "name": "StocksWidget", "incident_id": "REDACTED"}) + """
Date/Time:        2026-11-14 21:52:56.655 +0800
End time:         2026-11-14 21:54:48.138 +0800
Command:          StocksWidget
Event:            cpu usage
CPU:              90 seconds cpu time over 111 seconds (81% cpu average), exceeding limit of 50% cpu over 180 seconds
""")
open("ota_patch.txt", "w").write("[13:40:00.0000-GMT]{3>6} CHECKPOINT NOTICE: start\n[13:46:57.1000-GMT]{3>6} CHECKPOINT NOTICE: update engine finished with SUCCESS\n")
print("ok")
