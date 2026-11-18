# Commons Compress registers ZIP extra fields through reflective constructors
# while unpacking the bundled Python/FFmpeg runtime. R8 cannot infer these calls.
-keep class * implements org.apache.commons.compress.archivers.zip.ZipExtraField { *; }
# Shell helper loaded from the APK by the authorized local ADB transport.
-keep class com.example.syncbeat.ZeppPermissionService { public <init>(); *; }
-keep class com.example.syncbeat.ZeppAdbLeaseServer { public static void main(java.lang.String[]); }
