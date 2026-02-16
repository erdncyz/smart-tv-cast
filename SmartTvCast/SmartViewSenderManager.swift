//
//  SmartViewSenderManager.swift
//  SmartTvCast
//
//  Created by Codex on 12.02.2026.
//

import Foundation
import Combine
import UIKit
import Network

#if canImport(SmartView)
import SmartView
private let smartViewSDKLinked = true
#elseif canImport(SmartViewSDK)
import SmartViewSDK
private let smartViewSDKLinked = true
#else
private let smartViewSDKLinked = false
#endif

struct SmartTvDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let uri: String
    let type: String
}

@MainActor
final class SmartViewSenderManager: NSObject, ObservableObject {
    static let channelID = "com.tod.smartview"
    static let receiverAppID = "NDkFB1bFUn.ReactTOD"

    @Published var devices: [SmartTvDevice] = []
    @Published var statusText = "Hazir"
    @Published var lastError = ""
    @Published var isSearching = false
    @Published var isConnected = false
    @Published var isInstallingApp = false
    @Published var deviceLogText = ""
    @Published var receivedTVLogs: [String] = []
    @Published var sentLogs: [String] = []
    @Published var connectedDeviceID: String?
    @Published var selectedDeviceID: String?
    @Published var deepLinkText = "tod://home"
    @Published var playContentID = "PT0000465711"
    @Published var playStreamType = "movie"

    var canUseSDK: Bool {
        smartViewSDKLinked
    }

#if canImport(SmartView) || canImport(SmartViewSDK)
    private let serviceSearch = Service.search()
    private var servicesByID: [String: Service] = [:]
    private var application: Application?
    private var pendingDeepLinkURL: String?
    private var pendingPlayContent: (contentID: String, streamType: String)?
    private var permissionBrowser: NWBrowser?
    private var installAttemptedDeviceIDs: Set<String> = []
#endif

    override init() {
        super.init()
#if canImport(SmartView) || canImport(SmartViewSDK)
        serviceSearch.delegate = self
#endif
    }

    func startDiscovery() {
        guard canUseSDK else {
            statusText = "SDK eksik"
            lastError = "Pod ile smart-view-sdk kurulu degil."
            return
        }

        lastError = ""
        isSearching = true
        statusText = "TV aranıyor..."

#if canImport(SmartView) || canImport(SmartViewSDK)
        triggerLocalNetworkPermissionPrompt()

        serviceSearch.delegate = self
        if serviceSearch.isSearching {
            serviceSearch.stop()
        }

        servicesByID.removeAll()
        devices = []
        serviceSearch.start(false)

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            let services = self.serviceSearch.getServices()
            if !services.isEmpty {
                for service in services {
                    self.servicesByID[service.id] = service
                }
                self.reloadDeviceList()
                self.statusText = "\(self.devices.count) TV bulundu"
                self.lastError = ""
                return
            }

            if self.devices.isEmpty {
                self.statusText = "TV bulunamadi"
                self.lastError = "Ayni Wi‑Fi'de oldugunuzdan ve iOS Local Network izninin acik oldugundan emin olun."
            }
        }
#endif
    }

    func stopDiscovery() {
        guard canUseSDK else { return }
        isSearching = false
        statusText = "Tarama durduruldu"

#if canImport(SmartView) || canImport(SmartViewSDK)
        serviceSearch.stop()
#endif
    }

    func connect(to device: SmartTvDevice) {
        guard canUseSDK else { return }

#if canImport(SmartView) || canImport(SmartViewSDK)
        guard let service = servicesByID[device.id] else {
            lastError = "Secilen TV servisi bulunamadi."
            return
        }

        selectedDeviceID = device.id
        statusText = "\(device.name) baglanıyor..."
        lastError = ""
        deviceLogText = "\(device.name): uygulama kontrol ediliyor..."

        let appID = Self.receiverAppID as AnyObject
        guard let app = service.createApplication(appID, channelURI: Self.channelID, args: nil) else {
            lastError = "Application olusturulamadi. App ID/channel kontrol edin."
            return
        }

        app.delegate = self
        app.connectionTimeout = 10
        application = app

        app.connect(["name": UIDevice.current.name]) { [weak self] client, error in
            guard let self else { return }
            Task { @MainActor in
                if client != nil {
                    self.isConnected = true
                    self.isInstallingApp = false
                    self.connectedDeviceID = device.id
                    self.installAttemptedDeviceIDs.remove(device.id)
                    self.statusText = "\(device.name) baglandi"
                    self.deviceLogText = "\(device.name): uygulama yuklu, baglanti kuruldu"
                    self.flushPendingDeepLinkIfNeeded()
                    self.flushPendingPlayContentIfNeeded()
                } else {
                    self.isConnected = false
                    self.connectedDeviceID = nil
                    let nsError = error as NSError?
                    if self.shouldAttemptInstall(for: nsError, deviceID: device.id) {
                        self.installAttemptedDeviceIDs.insert(device.id)
                        self.tryInstallReceiverApp(on: app, device: device)
                    } else {
                        self.statusText = "Baglanti hatasi"
                        self.lastError = nsError?.localizedDescription ?? "Bilinmeyen baglanti hatasi"
                        self.deviceLogText = "\(device.name): \(self.lastError)"
                    }
                }
            }
        }
#endif
    }

    func disconnect() {
        guard canUseSDK else { return }

#if canImport(SmartView) || canImport(SmartViewSDK)
        application?.disconnect()
        application = nil
#endif
        isConnected = false
        connectedDeviceID = nil
        statusText = "Baglanti kapatildi"
    }

    func sendDeepLink() {
        guard canUseSDK else { return }

        let url = deepLinkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            lastError = "Deep link bos olamaz."
            return
        }

#if canImport(SmartView) || canImport(SmartViewSDK)
        if let app = application, app.isConnected {
            publishDeepLink(url, with: app)
            return
        }

        guard let selectedDeviceID,
              let selectedDevice = devices.first(where: { $0.id == selectedDeviceID }) else {
            lastError = "Lutfen once bir TV secin."
            return
        }

        pendingDeepLinkURL = url
        connect(to: selectedDevice)
#endif
    }

    func sendCommand(action: String, payload: [String: Any]? = nil) {
        guard canUseSDK else { return }
#if canImport(SmartView) || canImport(SmartViewSDK)
        guard let app = application, app.isConnected else {
            lastError = "Once bir TV'ye baglanin."
            return
        }

        var message: [String: Any] = ["action": action]
        if let payload {
            message["payload"] = payload
        }

        app.publish(event: "command", message: message as AnyObject)
        appendSentLog("event=command action=\(action) payload=\(String(describing: payload ?? [:]))")
        statusText = "Komut gonderildi: \(action)"
        lastError = ""
#endif
    }

    func clearReceivedTVLogs() {
        receivedTVLogs.removeAll()
    }

    func clearSentLogs() {
        sentLogs.removeAll()
    }

    func sendPlayContent() {
        guard canUseSDK else { return }

        let contentID = playContentID.trimmingCharacters(in: .whitespacesAndNewlines)
        let streamType = playStreamType.trimmingCharacters(in: .whitespacesAndNewlines)
        print("[SmartView][iOS] sendPlayContent requested contentId=\(contentID) streamType=\(streamType)")

        guard !contentID.isEmpty else {
            lastError = "contentId bos olamaz."
            deviceLogText = "PlayContent hatasi: contentId bos"
            print("[SmartView][iOS] sendPlayContent failed: contentId is empty")
            return
        }

        guard !streamType.isEmpty else {
            lastError = "streamType bos olamaz."
            deviceLogText = "PlayContent hatasi: streamType bos"
            print("[SmartView][iOS] sendPlayContent failed: streamType is empty")
            return
        }

#if canImport(SmartView) || canImport(SmartViewSDK)
        if let app = application, app.isConnected {
            deviceLogText = "PlayContent gonderiliyor: \(contentID) (\(streamType))"
            print("[SmartView][iOS] sendPlayContent publishing immediately")
            publishPlayContent(contentID: contentID, streamType: streamType, with: app)
            return
        }

        guard let selectedDeviceID,
              let selectedDevice = devices.first(where: { $0.id == selectedDeviceID }) else {
            lastError = "Lutfen once bir TV secin."
            deviceLogText = "PlayContent hatasi: secili TV yok"
            print("[SmartView][iOS] sendPlayContent failed: no selected TV")
            return
        }

        pendingPlayContent = (contentID: contentID, streamType: streamType)
        deviceLogText = "PlayContent kuyruga alindi: \(contentID) (\(streamType))"
        print("[SmartView][iOS] sendPlayContent queued and connecting to device id=\(selectedDevice.id)")
        connect(to: selectedDevice)
#endif
    }

#if canImport(SmartView) || canImport(SmartViewSDK)
    private func triggerLocalNetworkPermissionPrompt() {
        let params = NWParameters.tcp
        let browser = NWBrowser(
            for: .bonjour(type: "_samsungmsf._tcp", domain: nil),
            using: params
        )
        permissionBrowser = browser

        browser.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .failed(let error):
                Task { @MainActor in
                    self.lastError = "Local network izni hatasi: \(error.localizedDescription)"
                    browser.cancel()
                    self.permissionBrowser = nil
                }
            case .ready:
                Task { @MainActor in
                    browser.cancel()
                    self.permissionBrowser = nil
                }
            default:
                break
            }
        }
        browser.start(queue: .main)

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            Task { @MainActor in
                self?.permissionBrowser?.cancel()
                self?.permissionBrowser = nil
            }
        }
    }

    private func shouldAttemptInstall(for error: NSError?, deviceID: String) -> Bool {
        guard !installAttemptedDeviceIDs.contains(deviceID) else { return false }
        guard let error else { return false }

        let lower = error.localizedDescription.lowercased()
        return lower.contains("not installed")
            || lower.contains("app is not installed")
            || lower.contains("application not found")
            || lower.contains("not found")
    }

    private func tryInstallReceiverApp(on app: Application, device: SmartTvDevice) {
        isInstallingApp = true
        statusText = "\(device.name): TV'de uygulama yüklü değil, markete yönlendiriliyor..."
        deviceLogText = "\(device.name): uygulama yuklu degil, markete yonlendiriliyor..."
        lastError = ""

        app.install { [weak self] success, error in
            guard let self else { return }
            Task { @MainActor in
                self.isInstallingApp = false
                if success {
                    self.statusText = "\(device.name): market/yukleme acildi. TV'den onaylayin."
                    self.deviceLogText = "\(device.name): market/yukleme acildi"
                    self.lastError = ""
                } else {
                    self.statusText = "\(device.name): markete yonlendirme basarisiz"
                    self.lastError = error?.localizedDescription ?? "Yukleme baslatilamadi"
                    self.deviceLogText = "\(device.name): \(self.lastError)"
                }
            }
        }
    }

    private func publishDeepLink(_ url: String, with app: Application) {
        let payload: [String: String] = ["url": url]
        app.publish(event: "deepLink", message: payload as AnyObject)
        appendSentLog("event=deepLink payload=\(payload)")
        statusText = "Deep link gonderildi"
        lastError = ""
    }

    private func publishPlayContent(contentID: String, streamType: String, with app: Application) {
        let payload: [String: String] = [
            "contentId": contentID,
            "streamType": streamType
        ]
        print("[SmartView][iOS] publish event=playContent payload=\(payload)")
        app.publish(event: "playContent", message: payload as AnyObject)
        appendSentLog("event=playContent payload=\(payload)")
        statusText = "PlayContent gonderildi: \(contentID) (\(streamType))"
        deviceLogText = "PlayContent gonderildi: \(contentID) (\(streamType))"
        lastError = ""
    }

    private func flushPendingDeepLinkIfNeeded() {
        guard let pendingDeepLinkURL,
              let app = application,
              app.isConnected else { return }
        self.pendingDeepLinkURL = nil
        publishDeepLink(pendingDeepLinkURL, with: app)
    }

    private func flushPendingPlayContentIfNeeded() {
        guard let pendingPlayContent,
              let app = application,
              app.isConnected else { return }
        print("[SmartView][iOS] flushing pending playContent contentId=\(pendingPlayContent.contentID) streamType=\(pendingPlayContent.streamType)")
        self.pendingPlayContent = nil
        publishPlayContent(
            contentID: pendingPlayContent.contentID,
            streamType: pendingPlayContent.streamType,
            with: app
        )
    }

    private func reloadDeviceList() {
        devices = servicesByID.values
            .map { SmartTvDevice(id: $0.id, name: $0.name, uri: $0.uri, type: $0.type) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if selectedDeviceID == nil, let first = devices.first {
            selectedDeviceID = first.id
        }
    }

    private func appendIncomingTVLog(_ text: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let stamped = "[\(formatter.string(from: Date()))] \(text)"
        receivedTVLogs.append(stamped)
        if receivedTVLogs.count > 200 {
            receivedTVLogs.removeFirst(receivedTVLogs.count - 200)
        }
    }

    private func appendSentLog(_ text: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let stamped = "[\(formatter.string(from: Date()))] \(text)"
        sentLogs.append(stamped)
        if sentLogs.count > 200 {
            sentLogs.removeFirst(sentLogs.count - 200)
        }
    }
#endif
}

#if canImport(SmartView) || canImport(SmartViewSDK)
extension SmartViewSenderManager: ServiceSearchDelegate {
    func onStart() {
        statusText = "TV aramasi basladi"
    }

    func onStop() {
        isSearching = false
        if devices.isEmpty {
            statusText = "TV aramasi durdu"
        }
    }

    func onServiceFound(_ service: Service) {
        servicesByID[service.id] = service
        reloadDeviceList()
        statusText = "\(devices.count) TV bulundu"
    }

    func onServiceLost(_ service: Service) {
        servicesByID.removeValue(forKey: service.id)
        reloadDeviceList()
        statusText = "TV listesi guncellendi"
    }

    func onFoundOtherNetwork(_ msg: String) {
        lastError = msg
    }
}

extension SmartViewSenderManager: ChannelDelegate {
    func onConnect(_ client: ChannelClient?, error: NSError?) {
        if let error {
            lastError = error.localizedDescription
        }
    }

    func onReady() {
        statusText = "Kanal hazir"
    }

    func onDisconnect(_ client: ChannelClient?, error: NSError?) {
        isConnected = false
        connectedDeviceID = nil
        if let error {
            lastError = error.localizedDescription
        }
        statusText = "Baglanti kesildi"
    }

    func onMessage(_ message: Message) {
        let eventName = message.event ?? "unknown"
        statusText = "TV'den mesaj alindi: \(eventName)"
        let fromID = message.from ?? "unknown"
        let dataText = message.data.map { String(describing: $0) } ?? "nil"
        appendIncomingTVLog("event=\(eventName) from=\(fromID) data=\(dataText)")
    }

    func onData(_ message: Message, payload: Data) {
        let eventName = message.event ?? "binary"
        let fromID = message.from ?? "unknown"
        appendIncomingTVLog("binary event=\(eventName) from=\(fromID) bytes=\(payload.count)")
    }

    func onError(_ error: NSError) {
        lastError = error.localizedDescription
        statusText = "Kanal hatasi"
    }
}
#endif
