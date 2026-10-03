// tampa-virtual: o sensor da tampa deste Mac quebrou (AppleClamshellState fica em No).
// O trackpad imita a tampa: fechada, a tela deitada vira UM contato gigante (~67x42 mm) no centro;
// mão espalmada dá 9-11 contatos de no máximo ~48x30 mm (medido 02/10/2026). Funciona com luz ou no escuro.
// (O sensor de luz foi tentado e removido: no escuro oscila 0/1 e fazia o Mac dormir com gente usando.)
//   fechou + monitor externo na tomada -> apaga só a tela interna (clamshell)
//   fechou sem monitor ou na bateria   -> repouso
//   abriu                              -> religa a tela interna
import CoreGraphics
import Foundation
import IOKit
import IOKit.ps

@_silgen_name("CGSConfigureDisplayEnabled")
func CGSConfigureDisplayEnabled(_ config: CGDisplayConfigRef?, _ display: CGDirectDisplayID, _ enabled: Bool) -> CGError

// Calibração (02/10/2026)
let TAMPA_EIXO_MAIOR_MM: Float = 60   // trackpad: tampa mediu 66-77; mão no máximo 48
let TAMPA_EIXO_MENOR_MM: Float = 38   // trackpad: tampa mediu 42-45; mão no máximo 30
let INTERVALO = 0.25

func log(_ s: String) {
    let f = DateFormatter(); f.dateFormat = "dd/MM HH:mm:ss"
    print("\(f.string(from: Date())) \(s)"); fflush(stdout)
}

func registro(_ classe: String, _ chave: String) -> Any? {
    var it: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(classe), &it) == KERN_SUCCESS else { return nil }
    defer { IOObjectRelease(it) }
    var s = IOIteratorNext(it)
    while s != 0 {
        defer { IOObjectRelease(s) }
        if let v = IORegistryEntrySearchCFProperty(s, kIOServicePlane, chave as CFString, kCFAllocatorDefault,
                                                   IOOptionBits(kIORegistryIterateRecursively)) {
            return v
        }
        s = IOIteratorNext(it)
    }
    return nil
}

func semUso() -> Double { ((registro("IOHIDSystem", "HIDIdleTime") as? NSNumber)?.doubleValue ?? 0) / 1e9 }

func naTomada() -> Bool {
    let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
    return (IOPSGetProvidingPowerSourceType(info).takeRetainedValue() as String) == kIOPSACPowerValue
}

func telas() -> [CGDirectDisplayID] {
    var n: UInt32 = 0; CGGetOnlineDisplayList(0, nil, &n)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(n)); CGGetOnlineDisplayList(n, &ids, &n)
    return Array(ids.prefix(Int(n)))
}
func interna() -> CGDirectDisplayID? { telas().first { CGDisplayIsBuiltin($0) != 0 } }
func temExterna() -> Bool { telas().contains { CGDisplayIsBuiltin($0) == 0 } }

func ligarInterna(_ id: CGDirectDisplayID, _ ligar: Bool) -> Bool {
    var cfg: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&cfg) == .success else { return false }
    let e = CGSConfigureDisplayEnabled(cfg, id, ligar)
    guard e == .success else { CGCancelDisplayConfiguration(cfg); return false }
    return CGCompleteDisplayConfiguration(cfg, .permanently) == .success
}

func dormir() {
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset"); p.arguments = ["sleepnow"]
    try? p.run(); p.waitUntilExit()
}

// Modo teste: `tampa-virtual teste` apaga a tela interna por 5 s e religa.
if CommandLine.arguments.dropFirst().first == "teste" {
    guard let id = interna() else { print("tela interna não encontrada"); exit(1) }
    print("semUso=\(Int(semUso()))s tomada=\(naTomada()) externa=\(temExterna()) interna=\(id)")
    print("apagar:", ligarInterna(id, false)); sleep(5)
    print("religar:", ligarInterna(id, true)); exit(0)
}

// ---- trackpad (MultitouchSupport, privado) ----
typealias MTDeviceRef = UnsafeMutableRawPointer
typealias MTCallback = @convention(c) (MTDeviceRef?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
let mt = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW)
func mtFn<T>(_ nome: String, _ t: T.Type) -> T? { mt.flatMap { dlsym($0, nome) }.map { unsafeBitCast($0, to: t) } }
let MTCreateDefault = mtFn("MTDeviceCreateDefault", (@convention(c) () -> MTDeviceRef?).self)
let MTRegister = mtFn("MTRegisterContactFrameCallback", (@convention(c) (MTDeviceRef?, MTCallback) -> Void).self)
let MTStart = mtFn("MTDeviceStart", (@convention(c) (MTDeviceRef?, Int32) -> Int32).self)
let MTStop = mtFn("MTDeviceStop", (@convention(c) (MTDeviceRef?) -> Int32).self)

let trava = NSLock()
var tampaNoTrackpad = false  // escrito pela thread do trackpad
var trackpadMudou = false

// struct Finger tem 96 bytes: estado +20, eixo maior +60, eixo menor +64 (mm)
let aoTocar: MTCallback = { _, dados, n, _, _ in
    var gigante = false
    if let p = dados {
        for i in 0..<Int(n) {
            let b = p + i * 96
            let estado = b.load(fromByteOffset: 20, as: Int32.self)
            if (1...6).contains(estado),
               b.load(fromByteOffset: 60, as: Float.self) >= TAMPA_EIXO_MAIOR_MM,
               b.load(fromByteOffset: 64, as: Float.self) >= TAMPA_EIXO_MENOR_MM { gigante = true }
        }
    }
    trava.lock(); if gigante != tampaNoTrackpad { tampaNoTrackpad = gigante; trackpadMudou = true }; trava.unlock()
    return 0
}

var trackpad: MTDeviceRef? = nil
var proximoTrackpad = Date.distantPast
// logo depois de acordar o trackpad ainda não existe: tenta de novo a cada 2 s
func ligarTrackpad() {
    if let d = trackpad { _ = MTStop?(d); trackpad = nil }
    proximoTrackpad = Date().addingTimeInterval(2)
    guard let d = MTCreateDefault?() else { return }
    trackpad = d
    MTRegister?(d, aoTocar); _ = MTStart?(d, 0)
}

// ---- estado ----
var idInterna = interna()
var apagada = false
var fechadaAntes = false
var tentativas = 0
var tentouEm = Date.distantPast
var ultimaVolta = Date()
let MAX_TENTATIVAS = 3
let SEGUNDOS_PRA_REPOUSO_ENTRAR = 8.0

func religar(_ motivo: String) {
    if let id = idInterna { _ = ligarInterna(id, true) }
    apagada = false
    log(motivo)
}
func telaAcesa() -> Bool { CGDisplayIsAsleep(CGMainDisplayID()) == 0 }

ligarTrackpad()
log("iniciado; interna=\(idInterna.map(String.init) ?? "?") trackpad=\(trackpad != nil)")

func passo() {
    let agora = Date()
    if agora.timeIntervalSince(ultimaVolta) > 1 { // o relógio pula 0,25 s; mais que 1 s = o Mac dormiu
        // acordou de repouso: o trackpad pode ter parado; religa e esquece estado velho
        tentativas = 0
        trava.lock(); tampaNoTrackpad = false; trava.unlock()
        ligarTrackpad()
    }
    ultimaVolta = agora
    if trackpad == nil && agora >= proximoTrackpad { ligarTrackpad(); if trackpad != nil { log("trackpad ligado") } }
    if let atual = interna() { idInterna = atual }

    trava.lock(); let fechada = tampaNoTrackpad; trava.unlock()

    if fechada && !fechadaAntes {
        if temExterna() && naTomada() {
            if let id = idInterna, ligarInterna(id, false) { apagada = true; log("tampa fechada: tela interna apagada") }
        } else if telaAcesa() {
            log("tampa fechada: repouso"); tentativas = 1; tentouEm = agora; dormir()
        } else {
            return // tela já apagada (Power Nap): tenta no próximo passo
        }
    } else if fechada && tentativas > 0 && tentativas < MAX_TENTATIVAS
                && agora.timeIntervalSince(tentouEm) >= SEGUNDOS_PRA_REPOUSO_ENTRAR && telaAcesa()
                && semUso() >= 2 { // só insiste com a tampa AINDA no trackpad e ninguém mexendo
        tentativas += 1; tentouEm = agora
        log("repouso abortado: tentativa \(tentativas)"); dormir()
    } else if !fechada && fechadaAntes {
        tentativas = 0
        if apagada { religar("tampa aberta: tela interna ligada") } else { log("tampa aberta") }
    }
    fechadaAntes = fechada

    // nunca deixar o Mac sem tela; se tirou monitor/tomada com a tampa fechada, vai dormir
    if apagada && !(temExterna() && naTomada()) { religar("sem monitor ou sem tomada: tela interna ligada"); fechadaAntes = false }
}

let relogio = Timer(timeInterval: INTERVALO, repeats: true) { _ in passo() }
RunLoop.main.add(relogio, forMode: .default)
RunLoop.main.run()
