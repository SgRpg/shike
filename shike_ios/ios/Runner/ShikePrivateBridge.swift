import Flutter
import UIKit
import CoreLocation
import CoreImage
import AVFoundation
import Network
import Security
import Darwin

/// Local-only facilities. No diary content is sent to the weather endpoints.
final class ShikePrivateBridge: NSObject, CLLocationManagerDelegate {
    private let channel: FlutterMethodChannel
    private let locations = CLLocationManager()
    private var locationResult: FlutterResult?
    private let nearby = ShikeNearbyTransfer()
    private var scanner: ShikeQRScanner?

    static func register(with registrar: FlutterPluginRegistrar) {
        let instance = ShikePrivateBridge(messenger: registrar.messenger())
        registrar.publish(instance)
    }
    private init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(name: "shike/private", binaryMessenger: messenger)
        super.init()
        locations.delegate = self
        locations.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        channel.setMethodCallHandler { [weak self] call, result in self?.handle(call, result) }
        nearby.received = { [weak self] path in
            DispatchQueue.main.async { self?.channel.invokeMethod("receivedBackup", arguments: path) }
        }
    }
    private func error(_ message: String, _ result: @escaping FlutterResult) {
        DispatchQueue.main.async { result(FlutterError(code: "SHIKE", message: message, details: nil)) }
    }
    private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "locate":
            guard locationResult == nil else { error("正在获取城市", result); return }
            locationResult = result
            if locations.authorizationStatus == .notDetermined { locations.requestWhenInUseAuthorization() }
            else { requestLocationIfAllowed() }
        case "weather":
            guard let lat = args["latitude"] as? Double, let lng = args["longitude"] as? Double else { error("城市坐标无效", result); return }
            // Round again at the boundary; precise location never reaches this service.
            let a = (lat * 10).rounded() / 10, b = (lng * 10).rounded() / 10
            request("https://api.open-meteo.com/v1/forecast", ["latitude":String(a),"longitude":String(b),"current":"temperature_2m,weather_code","timezone":"auto"], result) { $0["current"] ?? [:] }
        case "searchCity":
            request("https://geocoding-api.open-meteo.com/v1/search", ["name":args["name"] as? String ?? "","count":"8","language":"zh","format":"json"], result) { $0 }
        case "qrImage":
            let text = args["text"] as? String ?? ""
            guard let filter = CIFilter(name: "CIQRCodeGenerator") else { error("二维码暂不可用", result); return }
            filter.setValue(text.data(using: .utf8), forKey: "inputMessage")
            filter.setValue("M", forKey: "inputCorrectionLevel")
            guard let image = filter.outputImage?.transformed(by:CGAffineTransform(scaleX:8,y:8)),
                  let cg = CIContext().createCGImage(image, from:image.extent), let png = UIImage(cgImage:cg).pngData() else { error("二维码暂不可用", result); return }
            result(FlutterStandardTypedData(bytes:png))
        case "scanQR":
            guard let presenter = topController() else { error("无法打开相机", result); return }
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                DispatchQueue.main.async {
                    guard allowed else { self?.error("请允许相机权限以扫描配对码", result); return }
                    let scanner = ShikeQRScanner()
                    scanner.completed = { [weak self] text in self?.scanner = nil; result(text) }
                    self?.scanner = scanner; presenter.present(scanner, animated:true)
                }
            }
        case "receive": nearby.start(result)
        case "send":
            guard let pairing = args["pairing"] as? String, let bytes = args["bytes"] as? FlutterStandardTypedData else { error("发送参数无效", result); return }
            nearby.send(pairing:pairing, bytes:bytes.data, result:result)
        case "stopNearby": nearby.stop(); result(nil)
        default: result(FlutterMethodNotImplemented)
        }
    }
    private func request(_ base:String, _ query:[String:String], _ result:@escaping FlutterResult, transform:@escaping ([String:Any])->Any) {
        var url = URLComponents(string:base)!
        url.queryItems = query.map { URLQueryItem(name:$0.key,value:$0.value) }
        var request = URLRequest(url:url.url!); request.timeoutInterval = 3
        URLSession.shared.dataTask(with:request) { data, response, _ in
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let data = data, let value = try? JSONSerialization.jsonObject(with:data) as? [String:Any] else {
                self.error("天气暂时无法获取", result); return
            }
            DispatchQueue.main.async { result(transform(value)) }
        }.resume()
    }
    func locationManagerDidChangeAuthorization(_ manager:CLLocationManager) { if locationResult != nil { requestLocationIfAllowed() } }
    private func requestLocationIfAllowed() {
        if locations.authorizationStatus == .authorizedWhenInUse || locations.authorizationStatus == .authorizedAlways { locations.requestLocation() }
        else if locations.authorizationStatus != .notDetermined { finishLocation(nil,"定位权限未开启") }
    }
    func locationManager(_ manager:CLLocationManager, didFailWithError error:Error) { finishLocation(nil,"暂时无法获取城市") }
    func locationManager(_ manager:CLLocationManager, didUpdateLocations values:[CLLocation]) {
        guard let location = values.last else { finishLocation(nil,"暂时无法获取城市"); return }
        let latitude = (location.coordinate.latitude*10).rounded()/10
        let longitude = (location.coordinate.longitude*10).rounded()/10
        CLGeocoder().reverseGeocodeLocation(CLLocation(latitude:latitude,longitude:longitude)) { places, _ in
            self.finishLocation(["city":places?.first?.locality ?? places?.first?.administrativeArea ?? "",
                "latitude":latitude,
                "longitude":longitude],nil)
        }
    }
    private func finishLocation(_ value:[String:Any]?,_ message:String?) {
        DispatchQueue.main.async {
            guard let result = self.locationResult else { return }; self.locationResult = nil
            if let message = message { self.error(message,result) } else { result(value) }
        }
    }
    private func topController()->UIViewController? {
        var vc = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }.first { $0.isKeyWindow }?.rootViewController
        while let next = vc?.presentedViewController { vc = next }; return vc
    }
}

final class ShikeQRScanner:UIViewController,AVCaptureMetadataOutputObjectsDelegate,UIAdaptivePresentationControllerDelegate {
    let session = AVCaptureSession()
    var completed:((String?)->Void)?
    private var done = false
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .black
        presentationController?.delegate = self
        guard let device = AVCaptureDevice.default(for:.video), let input = try? AVCaptureDeviceInput(device:device), session.canAddInput(input) else { finish(nil); return }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { finish(nil); return }
        session.addOutput(output); output.setMetadataObjectsDelegate(self,queue:.main); output.metadataObjectTypes = [.qr]
        let preview = AVCaptureVideoPreviewLayer(session:session); preview.videoGravity = .resizeAspectFill; preview.frame = view.bounds; view.layer.addSublayer(preview)
        let button = UIButton(type:.system); button.setTitle("取消",for:.normal); button.tintColor = .white
        button.frame = CGRect(x:20,y:50,width:60,height:44); button.addTarget(self,action:#selector(cancel),for:.touchUpInside); view.addSubview(button)
        DispatchQueue.global(qos:.userInitiated).async { self.session.startRunning() }
    }
    @objc private func cancel() { finish(nil) }
    func presentationControllerDidDismiss(_ presentationController:UIPresentationController) { finish(nil) }
    func metadataOutput(_ output:AVCaptureMetadataOutput,didOutput objects:[AVMetadataObject],from connection:AVCaptureConnection) {
        if let text = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue { finish(text) }
    }
    private func finish(_ text:String?) {
        guard !done else { return }; done = true
        DispatchQueue.global(qos:.utility).async { self.session.stopRunning() }
        dismiss(animated:true) { self.completed?(text) }
    }
}

/// TLS-PSK uses TLS 1.2 as required by Apple's Network framework API.
/// One foreground transfer per pairing, with a ten-minute expiry.
final class ShikeNearbyTransfer {
    private var listener:NWListener?
    private var connection:NWConnection?
    private let queue = DispatchQueue(label:"shike.nearby")
    private var expiry:Date?
    private var timer:DispatchWorkItem?
    private var data = Data()
    private var expected:Int?
    var received:((String)->Void)?

    private func parameters(_ key:Data,_ identity:String)->NWParameters {
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(options,.TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(options,.TLSv12)
        sec_protocol_options_append_tls_ciphersuite(options,
            tls_ciphersuite_t(rawValue:UInt16(TLS_PSK_WITH_AES_256_GCM_SHA384))!)
        let psk = key.withUnsafeBytes { DispatchData(bytes:$0) }
        let identityData = identity.data(using:.utf8)!.withUnsafeBytes { DispatchData(bytes:$0) }
        sec_protocol_options_add_pre_shared_key(options,psk as __DispatchData,identityData as __DispatchData)
        let parameters = NWParameters(tls:tls,tcp:NWProtocolTCP.Options())
        parameters.includePeerToPeer = false
        return parameters
    }
    func start(_ result:@escaping FlutterResult) { queue.async { self.startOnQueue(result) } }
    private func startOnQueue(_ result:@escaping FlutterResult) {
        stopOnQueue()
        var key = Data(count:32)
        let status = key.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault,32,$0.baseAddress!) }
        guard status == errSecSuccess, let host = wifiAddress() else { result(FlutterError(code:"NEARBY",message:"请连接同一个 Wi-Fi",details:nil)); return }
        let id = UUID().uuidString
        let end = Date().addingTimeInterval(600); expiry = end
        do {
            let server = try NWListener(using:parameters(key,id),on:.any)
            listener = server
            server.service = NWListener.Service(name:"拾刻-\(id.prefix(6))",type:"_shike-xfer._tcp")
            var replied = false
            server.stateUpdateHandler = { state in
                if case .ready = state, !replied, let port = server.port {
                    replied = true
                    let payload:[String:Any] = ["version":1,"session":id,"host":host,"port":port.rawValue,"key":key.base64EncodedString(),"expires":ISO8601DateFormatter().string(from:end)]
                    let json = String(data:try! JSONSerialization.data(withJSONObject:payload),encoding:.utf8)!
                    DispatchQueue.main.async { result(json) }
                } else if case .failed(let error) = state, !replied {
                    replied = true; DispatchQueue.main.async { result(FlutterError(code:"NEARBY",message:error.localizedDescription,details:nil)) }
                }
            }
            server.newConnectionHandler = { [weak self] client in
                guard let self = self, self.connection == nil, end > Date() else { client.cancel(); return }
                client.stateUpdateHandler = { [weak client] state in
                    guard let client = client else { return }
                    if case .ready = state {
                        guard self.connection == nil else { client.cancel(); return }
                        client.stateUpdateHandler = nil
                        self.connection = client;server.newConnectionHandler = nil;server.stateUpdateHandler = nil; server.cancel();self.listener = nil
                        self.data = Data();self.expected = nil;self.receive(client)
                    }
                    if case .failed = state { client.stateUpdateHandler = nil; client.cancel() }
                }
                client.start(queue:self.queue)
            }
            server.start(queue:queue)
            let timeout = DispatchWorkItem { [weak self] in self?.stopOnQueue() }; timer = timeout
            queue.asyncAfter(deadline:.now()+600,execute:timeout)
        } catch { result(FlutterError(code:"NEARBY",message:error.localizedDescription,details:nil)) }
    }
    private func receive(_ client:NWConnection) {
        client.receive(minimumIncompleteLength:1,maximumLength:65536) { chunk,_,closed,error in
            guard error == nil, self.expiry.map({$0>Date()}) == true else { self.stopOnQueue(); return }
            if let chunk = chunk { self.data.append(chunk) }
            if self.expected == nil && self.data.count >= 16 {
                guard String(data:self.data.prefix(4),encoding:.ascii) == "SHK2" else { self.stopOnQueue(); return }
                let count = self.data[4..<12].reduce(UInt64(0)) { ($0<<8)|UInt64($1) }
                guard count <= 512*1024*1024 else { self.stopOnQueue(); return }; self.expected = Int(count)+16
            }
            guard self.data.count <= 512*1024*1024+16 else { self.stopOnQueue();return }
            if let expected = self.expected, self.data.count == expected {
                let body = self.data.subdata(in:16..<expected)
                let crc = self.data[12..<16].reduce(UInt32(0)) { ($0<<8)|UInt32($1) }
                guard self.crc32(body) == crc else { self.stopOnQueue();return }
                let file = FileManager.default.temporaryDirectory.appendingPathComponent("shike-\(UUID().uuidString).zip")
                do {
                    try body.write(to:file,options:.atomic)
                    client.send(content:Data("OK".utf8),completion:.contentProcessed { _ in self.stopOnQueue() })
                    self.received?(file.path)
                } catch { self.stopOnQueue() }
            } else if closed { self.stopOnQueue() }
            else { self.receive(client) }
        }
    }
    func send(pairing:String,bytes:Data,result:@escaping FlutterResult) {
        queue.async { self.sendOnQueue(pairing:pairing,bytes:bytes,result:result) }
    }
    private func sendOnQueue(pairing:String,bytes:Data,result:@escaping FlutterResult) {
        guard let encoded = pairing.data(using:.utf8), let j = try? JSONSerialization.jsonObject(with:encoded) as? [String:Any],
              j["version"] as? Int == 1, let keyString = j["key"] as? String, let key = Data(base64Encoded:keyString),key.count == 32,
              let host = j["host"] as? String, let port = j["port"] as? UInt16, let session = j["session"] as? String,
              let expires = j["expires"] as? String, let end = parseISO(expires),end>Date(),end.timeIntervalSinceNow <= 600,
              bytes.count <= 512*1024*1024+16 else { result(FlutterError(code:"NEARBY",message:"配对码无效或已过期",details:nil));return }
        stopOnQueue();expiry = end
        let client = NWConnection(host:NWEndpoint.Host(host),port:NWEndpoint.Port(rawValue:port)!,using:parameters(key,session))
        connection = client
        var finished = false
        func finish(_ error:String?) {
            guard !finished else { return };finished = true; self.stopOnQueue()
            DispatchQueue.main.async { if let error = error { result(FlutterError(code:"NEARBY",message:error,details:nil)) } else { result(nil) } }
        }
        func sendChunk(_ offset:Int) {
            guard end>Date() else { finish("配对已过期，请重新发送");return }
            if offset == bytes.count {
                client.receive(minimumIncompleteLength:2,maximumLength:2) { ack,_,_,_ in
                    finish(ack == Data("OK".utf8) ? nil : "传输中断，请重新发送")
                };return
            }
            let next = min(offset+65536,bytes.count)
            client.send(content:bytes.subdata(in:offset..<next),completion:.contentProcessed { error in
                if error != nil { finish("传输中断，请重新发送") } else { sendChunk(next) }
            })
        }
        client.stateUpdateHandler = { state in
            if case .ready = state { sendChunk(0) }
            if case .failed = state { finish("连接失败，请检查同一 Wi-Fi 并重新配对") }
        }
        client.start(queue:queue)
        let timeout = DispatchWorkItem { finish("传输超时，请重新发送") };timer = timeout
        queue.asyncAfter(deadline:.now()+min(600,end.timeIntervalSinceNow),execute:timeout)
    }
    func stop() { queue.async { self.stopOnQueue() } }
    private func stopOnQueue() { timer?.cancel();timer = nil;listener?.newConnectionHandler = nil;listener?.stateUpdateHandler = nil;listener?.cancel();listener = nil;connection?.stateUpdateHandler = nil;connection?.cancel();connection = nil;data = Data();expected = nil;expiry = nil }
    private func parseISO(_ value:String)->Date? {
        let fractional = ISO8601DateFormatter();fractional.formatOptions = [.withInternetDateTime,.withFractionalSeconds]
        return fractional.date(from:value) ?? ISO8601DateFormatter().date(from:value)
    }
    private func crc32(_ bytes:Data)->UInt32 {
        var crc:UInt32 = 0xffffffff
        for byte in bytes {crc ^= UInt32(byte);for _ in 0..<8 {crc = (crc>>1) ^ ((crc&1)==1 ? 0xedb88320 : 0)}}
        return crc ^ 0xffffffff
    }
    private func wifiAddress()->String? {
        var addresses:UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses)==0,let first = addresses else { return nil };defer {freeifaddrs(addresses)}
        var current:UnsafeMutablePointer<ifaddrs>? = first
        while let item = current {
            if String(cString:item.pointee.ifa_name)=="en0",let address = item.pointee.ifa_addr,address.pointee.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating:0,count:Int(NI_MAXHOST))
                if getnameinfo(address,socklen_t(address.pointee.sa_len),&host,socklen_t(host.count),nil,0,NI_NUMERICHOST)==0 {return String(cString:host)}
            }
            current = item.pointee.ifa_next
        };return nil
    }
}
