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
    @Published var connectedDeviceID: String?
    @Published var selectedDeviceID: String?
    @Published var deepLinkText = "tod://home"

    var canUseSDK: Bool {
        smartViewSDKLinked
    }

#if canImport(SmartView) || canImport(SmartViewSDK)
    private let serviceSearch = Service.search()
    private var servicesByID: [String: Service] = [:]
    private var application: Application?
    private var pendingDeepLinkURL: String?
    private var permissionBrowser: NWBrowser?
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
                    self.connectedDeviceID = device.id
                    self.statusText = "\(device.name) baglandi"
                    self.flushPendingDeepLinkIfNeeded()
                } else {
                    self.isConnected = false
                    self.connectedDeviceID = nil
                    self.statusText = "Baglanti hatasi"
                    self.lastError = error?.localizedDescription ?? "Bilinmeyen baglanti hatasi"
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
        statusText = "Komut gonderildi: \(action)"
        lastError = ""
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

    private func publishDeepLink(_ url: String, with app: Application) {
        let payload: [String: String] = ["url": url]
        app.publish(event: "deepLink", message: payload as AnyObject)
        statusText = "Deep link gonderildi"
        lastError = ""
    }

    private func flushPendingDeepLinkIfNeeded() {
        guard let pendingDeepLinkURL,
              let app = application,
              app.isConnected else { return }
        self.pendingDeepLinkURL = nil
        publishDeepLink(pendingDeepLinkURL, with: app)
    }

    private func reloadDeviceList() {
        devices = servicesByID.values
            .map { SmartTvDevice(id: $0.id, name: $0.name, uri: $0.uri, type: $0.type) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if selectedDeviceID == nil, let first = devices.first {
            selectedDeviceID = first.id
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
    }

    func onError(_ error: NSError) {
        lastError = error.localizedDescription
        statusText = "Kanal hatasi"
    }
}
#endif
