# Sürüm derlemesinde R8 kodu küçültür. flutter_local_notifications zamanlanmış bildirimleri (sayaç alarmları,
# hatırlatıcılar) Gson ile saklar; R8 genel tür bilgisini silerse zonedSchedule "Missing type parameter" hatasıyla
# düşer. Kurallar eklentinin örnek uygulamasındakilerdir.
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn sun.misc.**

-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}

-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken
