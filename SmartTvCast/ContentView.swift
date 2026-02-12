//
//  ContentView.swift
//  SmartTvCast
//
//  Created by Erdinç Yılmaz on 12.02.2026.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var sender = SmartViewSenderManager()
    private let todYellow = Color(red: 1.00, green: 0.84, blue: 0.05)
    private let todCyan = Color(red: 0.02, green: 0.76, blue: 0.96)
    private let todDark = Color(red: 0.04, green: 0.05, blue: 0.10)
    private let todCard = Color(red: 0.10, green: 0.12, blue: 0.18)

    private let quickDeepLinks: [(title: String, url: String)] = [
        ("Home", "tod://home"),
        ("Canlı TV", "tod://live"),
        ("Spor", "tod://category/sports"),
        ("Film", "tod://film"),
        ("Film Detay", "tod://contentdetail/movie/PT0000446313"),
        ("Dizi", "tod://dizi"),
        ("Dizi Detay", "tod://contentdetail/series/PZ0000008346"),
        ("Cocuk", "tod://cocuk"),
        ("Arama", "tod://search"),
        ("Account", "tod://settings")
    ]

    private var connectedDevice: SmartTvDevice? {
        sender.devices.first { $0.id == sender.connectedDeviceID }
    }

    private var selectedDevice: SmartTvDevice? {
        sender.devices.first { $0.id == sender.selectedDeviceID }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [todDark, Color.black, Color(red: 0.07, green: 0.08, blue: 0.13)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 14) {
                        statusCard

                        if let deviceForCard = connectedDevice ?? selectedDevice {
                            connectedDeviceCard(deviceForCard)
                        }

                        tvListCard
                        deepLinkCard
                        remoteCard
                        debugStatusCard
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("SmartTvCast")
            .preferredColorScheme(.dark)
        }
    }

    private var statusCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Samsung Smart View")
                            .font(.headline)
                        Text("App ID: \(SmartViewSenderManager.receiverAppID)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Label(sender.canUseSDK ? "SDK Hazır" : "SDK Eksik", systemImage: sender.canUseSDK ? "checkmark.seal.fill" : "xmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(sender.canUseSDK ? todYellow : .red)
                }

                HStack(spacing: 10) {
                    Button {
                        sender.isSearching ? sender.stopDiscovery() : sender.startDiscovery()
                    } label: {
                        Label(sender.isSearching ? "Aramayı Durdur" : "TV Ara", systemImage: sender.isSearching ? "stop.fill" : "dot.radiowaves.left.and.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(todYellow)
                    .disabled(sender.isInstallingApp)

                    Button {
                        sender.disconnect()
                    } label: {
                        Label("Bağlantıyı Kes", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(todCyan)
                    .disabled(!sender.isConnected || sender.isInstallingApp)
                }

                HStack {
                    statusBadge(title: "Bulunan TV", value: "\(sender.devices.count)")
                    statusBadge(title: "Bağlantı", value: sender.isConnected ? "Bağlı" : "Pasif")
                    statusBadge(title: "Seçili", value: sender.selectedDeviceID == nil ? "-" : "Var")
                }

                if sender.isInstallingApp {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("TV market/yükleme akışı başlatılıyor...")
                            .font(.caption)
                    }
                }
            }
        }
    }

    private var tvListCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                Text("TV Cihazları")
                    .font(.headline)

                if sender.devices.isEmpty {
                    Text("Henüz cihaz bulunamadı.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(sender.devices) { device in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name)
                                        .font(.subheadline.weight(.semibold))
                                    Text(device.type)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if sender.connectedDeviceID == device.id {
                                    Label("Bağlı", systemImage: "checkmark.circle.fill")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(todYellow)
                                } else if sender.selectedDeviceID == device.id {
                                    Text("Seçili")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(todCyan)
                                }
                            }
                            Text(device.uri)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            HStack(spacing: 10) {
                                Button("Seç") {
                                    sender.selectedDeviceID = device.id
                                }
                                .buttonStyle(.bordered)
                                .tint(todCyan)

                                Button(sender.connectedDeviceID == device.id ? "Bağlı" : "Bağlan") {
                                    sender.selectedDeviceID = device.id
                                    sender.connect(to: device)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(todYellow)
                                .disabled(sender.connectedDeviceID == device.id)
                            }
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(todCard.opacity(0.95)))
                    }
                }
            }
        }
    }

    private func connectedDeviceCard(_ device: SmartTvDevice) -> some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Bağlı Cihaz", systemImage: "tv.and.hifispeaker.fill")
                        .font(.headline)
                    Spacer()
                    Text(sender.connectedDeviceID == device.id ? "Aktif" : "Hazır")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(sender.connectedDeviceID == device.id ? todYellow : todCyan)
                }
                deviceDetailRow("Ad", device.name)
                deviceDetailRow("ID", device.id)
                deviceDetailRow("Tür", device.type)
                deviceDetailRow("URI", device.uri)

                if !sender.deviceLogText.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cihaz Logu")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(sender.deviceLogText)
                            .font(.caption)
                            .foregroundStyle(todYellow)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(todDark.opacity(0.85)))
                }
            }
        }
    }

    private var deepLinkCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Deep Link")
                    .font(.headline)

                TextField("tod://content/movie/123", text: $sender.deepLinkText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.65)))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(quickDeepLinks.enumerated()), id: \.offset) { _, item in
                            Button(item.title) {
                                sender.deepLinkText = item.url
                                sender.sendDeepLink()
                            }
                            .buttonStyle(.bordered)
                            .tint(todCyan)
                        }
                    }
                    .padding(.vertical, 2)
                }

                Button {
                    sender.sendDeepLink()
                } label: {
                    Label("Deep Link Gönder", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(todYellow)
                .disabled(!sender.isConnected || sender.deepLinkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var remoteCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Kumanda")
                    .font(.headline)

                VStack(spacing: 10) {
                    Button {
                        sender.sendCommand(action: "up")
                    } label: {
                        Image(systemName: "arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(todYellow)
                    .disabled(!sender.isConnected)

                    HStack(spacing: 10) {
                        Button {
                            sender.sendCommand(action: "left")
                        } label: {
                            Image(systemName: "arrow.left")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(todYellow)
                        .disabled(!sender.isConnected)

                        Button("OK") {
                            sender.sendCommand(action: "select")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(todYellow)
                        .disabled(!sender.isConnected)

                        Button {
                            sender.sendCommand(action: "right")
                        } label: {
                            Image(systemName: "arrow.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(todYellow)
                        .disabled(!sender.isConnected)
                    }

                    Button {
                        sender.sendCommand(action: "down")
                    } label: {
                        Image(systemName: "arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(todYellow)
                    .disabled(!sender.isConnected)

                    HStack(spacing: 10) {
                        Button("Back") {
                            sender.sendCommand(action: "back")
                        }
                        .buttonStyle(.bordered)
                        .tint(todCyan)
                        .disabled(!sender.isConnected)

                        Button("Home") {
                            sender.sendCommand(action: "home")
                        }
                        .buttonStyle(.bordered)
                        .tint(todCyan)
                        .disabled(!sender.isConnected)
                    }
                }
            }
        }
    }

    private var debugStatusCard: some View {
        card {
            VStack(alignment: .leading, spacing: 6) {
                Text("Durum")
                    .font(.headline)
                Text(sender.statusText)
                    .font(.subheadline)
                if !sender.lastError.isEmpty {
                    Text(sender.lastError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8, content: content)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(todCard.opacity(0.86))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(todYellow.opacity(0.32), lineWidth: 1)
            )
    }

    private func statusBadge(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10).fill(todDark.opacity(0.75)))
    }

    private func deviceDetailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
