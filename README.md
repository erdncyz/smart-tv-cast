# SmartTvCast (Samsung Smart View Sender)

Bu iOS uygulamasi, Samsung Smart View SDK kullanarak ayni agdaki Samsung TV'leri bulur, TV receiver app'e baglanir ve `deepLink` eventi gonderir.

TV tarafindaki receiver koduna uygun kanal:
- `com.tod.smartview`

## 1. Samsung iOS Sender SDK kurulumu

Projede SDK yoksa uygulama "SDK Eksik" gosterir. Kurulum icin:

1. `Podfile` olusturun:

```ruby
platform :ios, '13.0'
use_frameworks!

target 'SmartTvCast' do
  pod 'smart-view-sdk'
end
```

2. Pod kurun:

```bash
pod install
```

3. Sonrasinda `.xcworkspace` dosyasini acin ve derleyin.

Not: Modul adi surume gore `SmartView` veya `SmartViewSDK` olabilir. Kod her iki isim icin de `canImport` ile desteklenmistir.

## 2. Receiver App ID

Uygulama App ID'yi sabit kullanir:

- `NDkFB1bFUn.ReactTOD`

Bu deger TV tarafinda `createApplication(..., channelURI: "com.tod.smartview")` akisinda kullanilir.

## 3. Deep link gonderimi

Deep Link gonder tusunda davranis:

1. Secili TV'de app acik ve bagliysa direkt mesaji gonderir.
2. Acik degilse app'i acip baglanir ve baglanti tamamlaninca ayni mesaji otomatik yollar.

Deep Link alaniyla:

```text
tod://home
tod://content/movie/123
tod://content/series/456?episodeId=99
tod://search?q=spor
```

gibi URL'ler gonderilebilir.

Gonderilen payload:

```json
{
  "url": "tod://content/movie/123"
}
```

event adi:
- `deepLink`

## 4. iOS Local Network izni

Proje build ayarlarina `NSLocalNetworkUsageDescription` eklendi. Ilk taramada iOS yerel ag izni isteyecektir.
