# Flutter's engine and plugin registrant are reached reflectively.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# flutter_local_notifications serialises scheduled notifications with Gson, so
# the model classes and their generic signatures must survive shrinking or
# pending reminders fail to deserialise after a reboot.
-keep class com.dexterous.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn com.dexterous.**

# Gson type tokens rely on generic signatures.
-keep class * extends com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
