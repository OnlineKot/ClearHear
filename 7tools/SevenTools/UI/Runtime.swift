import Foundation

// Gdzie apka dziala: zwykla instalacja (SideStore / AltStore) czy w LiveContainerze.
// W LiveContainerze nie ma rozszerzen, a ekran blokady i powiadomienia nalezą do LiveContainera.
enum Runtime {
    static var isLiveContainer: Bool {
        let env = ProcessInfo.processInfo.environment
        if env.keys.contains(where: { $0.hasPrefix("LC_") }) { return true }
        if Bundle.main.bundlePath.contains("/Documents/Applications/") { return true }
        return false
    }
}
