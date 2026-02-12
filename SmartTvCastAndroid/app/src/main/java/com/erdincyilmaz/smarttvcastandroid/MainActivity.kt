package com.erdincyilmaz.smarttvcastandroid

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.samsung.multiscreen.Application as TVApplication
import com.samsung.multiscreen.Client
import com.samsung.multiscreen.Error as MSError
import com.samsung.multiscreen.Message
import com.samsung.multiscreen.Result
import com.samsung.multiscreen.Search
import com.samsung.multiscreen.Service
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

private const val APP_ID = "NDkFB1bFUn.ReactTOD"
private const val CHANNEL_ID = "com.tod.smartview"

private val QUICK_DEEP_LINKS = listOf(
    "Home" to "tod://home",
    "Canlı TV" to "tod://live",
    "Spor" to "tod://category/sports",
    "Film" to "tod://film",
    "Film Detay" to "tod://contentdetail/movie/PT0000446313",
    "Dizi" to "tod://dizi",
    "Dizi Detay" to "tod://contentdetail/series/PZ0000008346",
    "Cocuk" to "tod://cocuk",
    "Arama" to "tod://search",
    "Account" to "tod://settings"
)

data class TvDevice(
    val id: String,
    val name: String,
    val type: String,
    val uri: String,
    val raw: Service
)

data class UiState(
    val isSearching: Boolean = false,
    val isConnected: Boolean = false,
    val isInstalling: Boolean = false,
    val status: String = "Hazır",
    val lastError: String = "",
    val selectedDeviceId: String? = null,
    val connectedDeviceId: String? = null,
    val deepLink: String = "tod://home",
    val deviceLog: String = ""
)

class SmartViewViewModel : ViewModel() {
    private val _uiState = MutableStateFlow(UiState())
    val uiState: StateFlow<UiState> = _uiState.asStateFlow()

    val devices = mutableStateListOf<TvDevice>()

    private var search: Search? = null
    private var app: TVApplication? = null

    fun startDiscovery(context: android.content.Context) {
        stopDiscovery()
        devices.clear()

        _uiState.value = _uiState.value.copy(
            isSearching = true,
            status = "TV aranıyor...",
            lastError = ""
        )

        val s = Service.search(context)
        search = s

        s.setOnServiceFoundListener(object : Search.OnServiceFoundListener {
            override fun onFound(service: Service) {
                val existing = devices.indexOfFirst { it.id == service.id }
                val device = TvDevice(
                    id = service.id,
                    name = service.name ?: "Samsung TV",
                    type = service.type ?: "SMART_TV",
                    uri = service.uri?.toString() ?: "",
                    raw = service
                )
                if (existing >= 0) {
                    devices[existing] = device
                } else {
                    devices.add(device)
                }

                if (_uiState.value.selectedDeviceId == null) {
                    _uiState.value = _uiState.value.copy(selectedDeviceId = service.id)
                }

                _uiState.value = _uiState.value.copy(status = "${devices.size} TV bulundu")
            }
        })

        s.setOnServiceLostListener(object : Search.OnServiceLostListener {
            override fun onLost(service: Service) {
                devices.removeAll { it.id == service.id }
                _uiState.value = _uiState.value.copy(status = "TV listesi güncellendi")
            }
        })

        s.setOnStopListener(object : Search.OnStopListener {
            override fun onStop() {
                _uiState.value = _uiState.value.copy(isSearching = false)
            }
        })

        s.start()
    }

    fun stopDiscovery() {
        search?.stop()
        _uiState.value = _uiState.value.copy(isSearching = false)
    }

    fun selectDevice(id: String) {
        _uiState.value = _uiState.value.copy(selectedDeviceId = id)
    }

    fun setDeepLink(value: String) {
        _uiState.value = _uiState.value.copy(deepLink = value)
    }

    fun connectSelected() {
        val selected = devices.firstOrNull { it.id == _uiState.value.selectedDeviceId }
            ?: run {
                _uiState.value = _uiState.value.copy(lastError = "Önce bir TV seçin")
                return
            }

        connect(selected)
    }

    private fun connect(device: TvDevice) {
        val application = device.raw.createApplication(APP_ID, CHANNEL_ID)
        app = application

        _uiState.value = _uiState.value.copy(
            status = "${device.name} bağlanıyor...",
            lastError = "",
            selectedDeviceId = device.id,
            deviceLog = "${device.name}: uygulama kontrol ediliyor..."
        )

        application.connect(object : Result<Client> {
            override fun onSuccess(client: Client?) {
                _uiState.value = _uiState.value.copy(
                    isConnected = true,
                    isInstalling = false,
                    connectedDeviceId = device.id,
                    status = "${device.name} bağlı",
                    deviceLog = "${device.name}: uygulama yüklü, bağlantı kuruldu"
                )
            }

            override fun onError(error: MSError) {
                if (error.code == 404L) {
                    installApp(application, device)
                    return
                }

                _uiState.value = _uiState.value.copy(
                    isConnected = false,
                    connectedDeviceId = null,
                    status = "Bağlantı hatası",
                    lastError = error.message ?: error.toString(),
                    deviceLog = "${device.name}: ${error.message ?: "hata"}"
                )
            }
        })
    }

    private fun installApp(application: TVApplication, device: TvDevice) {
        _uiState.value = _uiState.value.copy(
            isInstalling = true,
            status = "TV'de uygulama yüklü değil, markete yönlendiriliyor...",
            lastError = "",
            deviceLog = "${device.name}: uygulama yüklü değil, markete yönlendiriliyor..."
        )

        application.install(object : Result<Boolean> {
            override fun onSuccess(result: Boolean?) {
                _uiState.value = _uiState.value.copy(
                    isInstalling = false,
                    status = "TV market/yükleme ekranı açıldı",
                    deviceLog = "${device.name}: market/yükleme açıldı"
                )
            }

            override fun onError(error: MSError) {
                _uiState.value = _uiState.value.copy(
                    isInstalling = false,
                    status = "Markete yönlendirme başarısız",
                    lastError = error.message ?: error.toString(),
                    deviceLog = "${device.name}: ${error.message ?: "yükleme başlatılamadı"}"
                )
            }
        })
    }

    fun disconnect() {
        val currentApp = app ?: return
        currentApp.disconnect(object : Result<Client> {
            override fun onSuccess(client: Client?) {
                _uiState.value = _uiState.value.copy(
                    isConnected = false,
                    connectedDeviceId = null,
                    status = "Bağlantı kapatıldı"
                )
            }

            override fun onError(error: MSError) {
                _uiState.value = _uiState.value.copy(
                    isConnected = false,
                    connectedDeviceId = null,
                    status = "Bağlantı kesildi",
                    lastError = error.message ?: error.toString()
                )
            }
        })
    }

    fun sendDeepLink() {
        val currentApp = app
        val link = _uiState.value.deepLink.trim()
        if (currentApp == null || !_uiState.value.isConnected) {
            _uiState.value = _uiState.value.copy(lastError = "Önce TV'ye bağlanın")
            return
        }

        if (link.isEmpty()) {
            _uiState.value = _uiState.value.copy(lastError = "Deep link boş olamaz")
            return
        }

        val payload = "{\"url\":\"${escapeJson(link)}\"}"
        currentApp.publish("deepLink", payload, Message.TARGET_HOST)
        _uiState.value = _uiState.value.copy(status = "Deep link gönderildi")
    }

    fun sendCommand(action: String) {
        val currentApp = app
        if (currentApp == null || !_uiState.value.isConnected) {
            _uiState.value = _uiState.value.copy(lastError = "Önce TV'ye bağlanın")
            return
        }

        val payload = "{\"action\":\"${escapeJson(action)}\"}"
        currentApp.publish("command", payload, Message.TARGET_HOST)
        _uiState.value = _uiState.value.copy(status = "Komut gönderildi: $action")
    }

    private fun escapeJson(value: String): String =
        value.replace("\\", "\\\\").replace("\"", "\\\"")

    override fun onCleared() {
        super.onCleared()
        try {
            app?.disconnect()
            search?.stop()
        } catch (_: Throwable) {
        }
    }
}

class MainActivity : ComponentActivity() {
    private val vm by viewModels<SmartViewViewModel>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        setContent {
            MaterialTheme {
                SmartTvScreen(vm = vm)
            }
        }
    }
}

@Composable
private fun SmartTvScreen(vm: SmartViewViewModel = viewModel()) {
    val ui by vm.uiState.collectAsStateWithLifecycle()
    val context = androidx.compose.ui.platform.LocalContext.current

    val todYellow = Color(0xFFFFD60A)
    val todCyan = Color(0xFF00C2F2)
    val todDark = Color(0xFF0B0D15)
    val todCard = Color(0xFF171B26)

    val connectedDevice = vm.devices.firstOrNull { it.id == ui.connectedDeviceId }
    val selectedDevice = vm.devices.firstOrNull { it.id == ui.selectedDeviceId }
    val currentDevice = connectedDevice ?: selectedDevice

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.linearGradient(
                    listOf(todDark, Color.Black, Color(0xFF101522))
                )
            )
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 14.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            SectionCard(todCard, todYellow) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Column {
                            Text("Samsung Smart View", color = Color.White, fontWeight = FontWeight.Bold)
                            Text("App ID: $APP_ID", color = Color(0xFFB9C0D0))
                            Text("Channel: $CHANNEL_ID", color = Color(0xFFB9C0D0))
                        }
                        Spacer(Modifier.weight(1f))
                        Text("SDK Hazır", color = todYellow, fontWeight = FontWeight.SemiBold)
                    }

                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Button(
                            onClick = { if (ui.isSearching) vm.stopDiscovery() else vm.startDiscovery(context) },
                            enabled = !ui.isInstalling,
                            modifier = Modifier.weight(1f)
                        ) {
                            Text(if (ui.isSearching) "Aramayı Durdur" else "TV Ara")
                        }

                        OutlinedButton(
                            onClick = vm::disconnect,
                            enabled = ui.isConnected && !ui.isInstalling,
                            modifier = Modifier.weight(1f)
                        ) {
                            Text("Bağlantıyı Kes", color = todCyan)
                        }
                    }

                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        StatusBadge("Bulunan TV", vm.devices.size.toString(), todDark, Modifier.weight(1f))
                        StatusBadge("Bağlantı", if (ui.isConnected) "Bağlı" else "Pasif", todDark, Modifier.weight(1f))
                        StatusBadge("Seçili", if (ui.selectedDeviceId == null) "-" else "Var", todDark, Modifier.weight(1f))
                    }

                    if (ui.isInstalling) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            CircularProgressIndicator(
                                modifier = Modifier.height(16.dp).width(16.dp),
                                color = todYellow,
                                strokeWidth = 2.dp
                            )
                            Spacer(Modifier.width(8.dp))
                            Text("TV market/yükleme akışı başlatılıyor...", color = todYellow)
                        }
                    }
                }
            }

            if (currentDevice != null) {
                SectionCard(todCard, todYellow) {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("Bağlı Cihaz", color = Color.White, fontWeight = FontWeight.SemiBold)
                            Spacer(Modifier.weight(1f))
                            Text(
                                if (ui.connectedDeviceId == currentDevice.id) "Aktif" else "Hazır",
                                color = if (ui.connectedDeviceId == currentDevice.id) todYellow else todCyan,
                                fontWeight = FontWeight.SemiBold
                            )
                        }

                        DeviceDetailRow("Ad", currentDevice.name)
                        DeviceDetailRow("ID", currentDevice.id)
                        DeviceDetailRow("Tür", currentDevice.type)
                        DeviceDetailRow("URI", currentDevice.uri)

                        if (ui.deviceLog.isNotBlank()) {
                            Column(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .background(todDark.copy(alpha = 0.85f), RoundedCornerShape(10.dp))
                                    .padding(10.dp),
                                verticalArrangement = Arrangement.spacedBy(4.dp)
                            ) {
                                Text("Cihaz Logu", color = Color(0xFFB9C0D0), fontWeight = FontWeight.SemiBold)
                                Text(ui.deviceLog, color = todYellow)
                            }
                        }
                    }
                }
            }

            SectionCard(todCard, todYellow) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("TV Cihazları", color = Color.White, fontWeight = FontWeight.SemiBold)

                    if (vm.devices.isEmpty()) {
                        Text("Henüz cihaz bulunamadı.", color = Color(0xFFB9C0D0))
                    } else {
                        vm.devices.forEach { device ->
                            Card(
                                colors = CardDefaults.cardColors(containerColor = Color(0xFF202635)),
                                shape = RoundedCornerShape(12.dp)
                            ) {
                                Column(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(10.dp),
                                    verticalArrangement = Arrangement.spacedBy(8.dp)
                                ) {
                                    Row(verticalAlignment = Alignment.CenterVertically) {
                                        Column {
                                            Text(device.name, color = Color.White, fontWeight = FontWeight.SemiBold)
                                            Text(device.type, color = Color(0xFFB9C0D0))
                                        }
                                        Spacer(Modifier.weight(1f))
                                        when {
                                            ui.connectedDeviceId == device.id -> Text("Bağlı", color = todYellow, fontWeight = FontWeight.SemiBold)
                                            ui.selectedDeviceId == device.id -> Text("Seçili", color = todCyan, fontWeight = FontWeight.SemiBold)
                                        }
                                    }

                                    Text(
                                        device.uri,
                                        color = Color(0xFF9CA8C7),
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis
                                    )

                                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                        OutlinedButton(onClick = { vm.selectDevice(device.id) }) {
                                            Text("Seç", color = todCyan)
                                        }
                                        Button(
                                            onClick = {
                                                vm.selectDevice(device.id)
                                                vm.connectSelected()
                                            },
                                            enabled = ui.connectedDeviceId != device.id
                                        ) {
                                            Text(if (ui.connectedDeviceId == device.id) "Bağlı" else "Bağlan")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            SectionCard(todCard, todYellow) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("Deep Link", color = Color.White, fontWeight = FontWeight.SemiBold)

                    OutlinedTextField(
                        value = ui.deepLink,
                        onValueChange = vm::setDeepLink,
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true,
                        placeholder = { Text("tod://content/movie/123") }
                    )

                    Row(
                        modifier = Modifier.horizontalScroll(rememberScrollState()),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        QUICK_DEEP_LINKS.forEach { (title, url) ->
                            OutlinedButton(onClick = {
                                vm.setDeepLink(url)
                                vm.sendDeepLink()
                            }) {
                                Text(title, color = todCyan)
                            }
                        }
                    }

                    Button(
                        onClick = vm::sendDeepLink,
                        enabled = ui.isConnected && ui.deepLink.trim().isNotEmpty(),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text("Deep Link Gönder")
                    }
                }
            }

            SectionCard(todCard, todYellow) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("Kumanda", color = Color.White, fontWeight = FontWeight.SemiBold)

                    Button(onClick = { vm.sendCommand("up") }, enabled = ui.isConnected, modifier = Modifier.fillMaxWidth()) {
                        Text("Yukarı")
                    }

                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Button(onClick = { vm.sendCommand("left") }, enabled = ui.isConnected, modifier = Modifier.weight(1f)) {
                            Text("Sol")
                        }
                        Button(onClick = { vm.sendCommand("select") }, enabled = ui.isConnected, modifier = Modifier.weight(1f)) {
                            Text("OK")
                        }
                        Button(onClick = { vm.sendCommand("right") }, enabled = ui.isConnected, modifier = Modifier.weight(1f)) {
                            Text("Sağ")
                        }
                    }

                    Button(onClick = { vm.sendCommand("down") }, enabled = ui.isConnected, modifier = Modifier.fillMaxWidth()) {
                        Text("Aşağı")
                    }

                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        OutlinedButton(onClick = { vm.sendCommand("back") }, enabled = ui.isConnected, modifier = Modifier.weight(1f)) {
                            Text("Back", color = todCyan)
                        }
                        OutlinedButton(onClick = { vm.sendCommand("home") }, enabled = ui.isConnected, modifier = Modifier.weight(1f)) {
                            Text("Home", color = todCyan)
                        }
                    }
                }
            }

            SectionCard(todCard, todYellow) {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("Durum", color = Color.White, fontWeight = FontWeight.SemiBold)
                    Text(ui.status, color = todYellow)
                    if (ui.lastError.isNotBlank()) {
                        Text(ui.lastError, color = Color(0xFFFF6B6B))
                    }
                }
            }
        }
    }
}

@Composable
private fun SectionCard(
    containerColor: Color,
    borderColor: Color,
    content: @Composable () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(containerColor.copy(alpha = 0.88f), RoundedCornerShape(18.dp))
            .border(1.dp, borderColor.copy(alpha = 0.30f), RoundedCornerShape(18.dp))
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        content()
    }
}

@Composable
private fun StatusBadge(title: String, value: String, bg: Color, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .background(bg.copy(alpha = 0.75f), RoundedCornerShape(10.dp))
            .padding(vertical = 6.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(title, color = Color(0xFFB9C0D0))
        Text(value, color = Color.White, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun DeviceDetailRow(title: String, value: String) {
    Row(verticalAlignment = Alignment.Top) {
        Text(
            title,
            color = Color(0xFFB9C0D0),
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.width(44.dp)
        )
        Text(
            value,
            color = Color.White,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis
        )
    }
}
