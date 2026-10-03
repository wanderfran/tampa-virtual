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
let SEGUNDOS_PRA_CONFIRMAR = 4.0   // o sensor demora a atualizar; evita disparar com mão na frente
let SEGUNDOS_SEM_USO_PRA_DORMIR = 5.0 // proteção: no escuro, com alguém digitando, não dorme
let INTERVALO = 1.0

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

func lux() -> Int? { (registro("AppleSPUVD6286", "CurrentLux") as? NSNumber)?.intValue }
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
var apagada = false          // tela interna desligada por nós
var escuroDesde: Date? = nil
var ultimoRepouso = Date.distantPast
let SEGUNDOS_ENTRE_TENTATIVAS = 15.0 // sem o sensor, o trackpad não desliga e um toque acorda o Mac
log("iniciado; interna=\(idInterna.map(String.init) ?? "?")")

func religar(_ motivo: String) {
    if let id = idInterna { _ = ligarInterna(id, true) }
    apagada = false
    log(motivo)
}

while true {
    if let atual = interna() { idInterna = atual }

    if let l = lux() {
        if l <= LUX_FECHADA { escuroDesde = escuroDesde ?? Date() }
        else {
            escuroDesde = nil
            if apagada { religar("tampa aberta: tela interna ligada") }
        }
    }

    let fechada = escuroDesde.map { Date().timeIntervalSince($0) >= SEGUNDOS_PRA_CONFIRMAR } ?? false

    if fechada {
        if temExterna() && naTomada() {
            if !apagada, let id = idInterna, ligarInterna(id, false) { apagada = true; log("tampa fechada: tela interna apagada") }
        } else {
            if apagada { religar("tampa fechada sem monitor/tomada: tela interna ligada") }
            // tela apagada = DarkWake (Power Nap): o próprio macOS volta a dormir
            if CGDisplayIsAsleep(CGMainDisplayID()) == 0 && semUso() >= SEGUNDOS_SEM_USO_PRA_DORMIR && Date().timeIntervalSince(ultimoRepouso) >= SEGUNDOS_ENTRE_TENTATIVAS {
                log("tampa fechada: repouso")
                ultimoRepouso = Date()
                dormir()
                escuroDesde = nil // ao acordar, exige escuro de novo antes de voltar a dormir
            }
        }
    }

    // nunca deixar o Mac sem tela
    if apagada && !temExterna() { religar("sem monitor externo: tela interna ligada") }

    Thread.sleep(forTimeInterval: INTERVALO)
}
