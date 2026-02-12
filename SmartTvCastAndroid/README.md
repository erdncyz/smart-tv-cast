# SmartTvCastAndroid (Compose)

Samsung Smart View Android Sender app (Compose) proje iskeleti.

## Özellikler
- Aynı ağdaki Samsung TV cihazlarını keşfetme
- `APP_ID = NDkFB1bFUn.ReactTOD` ile receiver app'e bağlanma
- Uygulama TV'de yüklü değilse `install()` ile market/yükleme akışını tetikleme
- `deepLink` ve `command` mesaj gönderimi
- Ok tuşlu kumanda arayüzü
- Cihaz logları ve bağlantı durumu

## Kurulum
1. Android Studio ile `SmartTvCastAndroid` klasörünü açın.
2. Samsung Smart View Android SDK jar dosyasını şu yola koyun:
   - `app/libs/smart-view-sdk.jar`
3. Gradle Sync yapın ve cihazda çalıştırın.

## Not
- TV ve telefon aynı Wi-Fi ağında olmalı.
- Receiver channel ID: `com.tod.smartview`

## Doküman
- Android Sender App: https://developer.samsung.com/smarttv/develop/extension-libraries/smart-view-sdk/android-sender-app.html
