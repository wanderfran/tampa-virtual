// tampa-virtual: o sensor da tampa deste Mac quebrou (AppleClamshellState fica em No).
// Usa o sensor de luz ambiente (CurrentLux = 0 com a tampa fechada) pra imitar a tampa:
//   fechou + monitor externo na tomada -> apaga só a tela interna (clamshell)
//   fechou sem monitor ou na bateria   -> repouso
//   abriu                              -> religa a tela interna
import CoreGraphics
import Foundation
import IOKit
import IOKit.ps

@_silgen_name("CGSConfigureDisplayEnabled")
func CGSConfigureDisplayEnabled(_ config: CGDisplayConfigRef?, _ display: CGDirectDisplayID, _ enabled: Bool) -> CGError

// Calibração: lux é inteiro; tampa fechada marcou 0, aberta 14-58 (02/10/2026).
let LUX_FECHADA = 0
let SEGUNDOS_PRA_CONFIRMAR = 1.0   // pedido dele: o mais rápido possível (mão na frente da câmera por 1 s já conta)
let SEGUNDOS_SEM_USO_PRA_DORMIR = 1.0 // proteção mínima: digitando no escuro não dorme
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

// sensor desligado (repouso) devolve UInt64 máximo = -1: tratar como "sem leitura"
func lux() -> Int? { (registro("AppleSPUVD6286", "CurrentLux") as? NSNumber).map { $0.intValue }.flatMap { $0 >= 0 ? $0 : nil } }
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
    print("lux=\(lux() ?? -1) semUso=\(Int(semUso()))s tomada=\(naTomada()) externa=\(temExterna()) interna=\(id)")
    print("apagar:", ligarInterna(id, false)); sleep(5)
    print("religar:", ligarInterna(id, true)); exit(0)
}

var idInterna = interna()
var apagada = false            // tela interna desligada por nós
var ultimoLux: Int? = nil
var escuroDesde: Date? = nil   // só começa numa BORDA (luz caiu de >0 pra 0): quarto escuro parado não conta
var tratada = false            // esta borda já virou ação
var tentativas = 0             // repouso abortado por toque no trackpad: tenta de novo
var tentouEm = Date.distantPast
var ultimaVolta = Date()
let MAX_TENTATIVAS = 3
let SEGUNDOS_PRA_REPOUSO_ENTRAR = 8.0 // pmset sleepnow leva ~5 s até dormir de fato
log("iniciado; interna=\(idInterna.map(String.init) ?? "?")")

func religar(_ motivo: String) {
    if let id = idInterna { _ = ligarInterna(id, true) }
    apagada = false
    log(motivo)
}

func podeDormir() -> Bool {
    CGDisplayIsAsleep(CGMainDisplayID()) == 0 && semUso() >= SEGUNDOS_SEM_USO_PRA_DORMIR
}

while true {
    let agora = Date()
    // salto no relógio = o Mac dormiu de verdade; ao acordar não insiste (pode ser ele abrindo)
    if agora.timeIntervalSince(ultimaVolta) > 3 { tentativas = 0 }
    ultimaVolta = agora

    if let atual = interna() { idInterna = atual }

    if let l = lux() {
        if l <= LUX_FECHADA {
            if let u = ultimoLux, u > LUX_FECHADA { escuroDesde = agora; tratada = false }
        } else {
            escuroDesde = nil; tratada = false; tentativas = 0
            if apagada { religar("tampa aberta: tela interna ligada") }
        }
        ultimoLux = l
    }

    let fechou = !tratada && (escuroDesde.map { agora.timeIntervalSince($0) >= SEGUNDOS_PRA_CONFIRMAR } ?? false)

    if fechou {
        if temExterna() && naTomada() {
            if let id = idInterna, ligarInterna(id, false) { apagada = true; tratada = true; log("tampa fechada: tela interna apagada") }
        } else if podeDormir() {
            log("tampa fechada: repouso"); tratada = true; tentativas = 1; tentouEm = agora; dormir()
        }
    } else if tentativas > 0 && tentativas < MAX_TENTATIVAS && escuroDesde != nil
                && agora.timeIntervalSince(tentouEm) >= SEGUNDOS_PRA_REPOUSO_ENTRAR && podeDormir() {
        tentativas += 1; tentouEm = agora
        log("repouso abortado (toque no trackpad?): tentativa \(tentativas)"); dormir()
    }

    // nunca deixar o Mac sem tela
    if apagada && !(temExterna() && naTomada()) { religar("sem monitor ou sem tomada: tela interna ligada"); tratada = false }

    Thread.sleep(forTimeInterval: INTERVALO)
}
