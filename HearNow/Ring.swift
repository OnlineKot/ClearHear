import Foundation
import Synchronization

// Bufor kolowy miedzy wejsciem (tu liczy sie obrobka) a wyjsciem (tu gra dzwiek).
// Jeden pisze, jeden czyta, bez blokad, wiec nadaje sie do watku audio.
final class Ring {
    private let buf: UnsafeMutablePointer<Float>
    private let cap: Int
    private let mask: Int
    private let head = Atomic<Int>(0)   // ile zapisano w sumie
    private let tail = Atomic<Int>(0)   // ile odczytano w sumie

    // pojemnosc musi byc potega dwojki
    init(capacity: Int) {
        precondition(capacity > 0 && capacity & (capacity - 1) == 0)
        cap = capacity
        mask = capacity - 1
        buf = .allocate(capacity: capacity)
        buf.initialize(repeating: 0, count: capacity)
    }

    deinit { buf.deallocate() }

    var available: Int {
        head.load(ordering: .acquiring) - tail.load(ordering: .acquiring)
    }

    // pisze producent
    func write(_ src: UnsafePointer<Float>, _ n: Int) {
        let h = head.load(ordering: .relaxed)
        let t = tail.load(ordering: .acquiring)
        let m = min(n, cap - (h - t))
        for i in 0..<m { buf[(h + i) & mask] = src[i] }
        head.store(h + m, ordering: .releasing)
    }

    // pisze producent, na starcie: troche ciszy, zeby wyjscie nie glodowalo
    func prefill(_ n: Int) {
        let zeros = UnsafeMutablePointer<Float>.allocate(capacity: n)
        zeros.initialize(repeating: 0, count: n)
        write(zeros, n)
        zeros.deallocate()
    }

    // czyta konsument, zwraca ile naprawde oddal
    @discardableResult
    func read(_ dst: UnsafeMutablePointer<Float>, _ n: Int) -> Int {
        let t = tail.load(ordering: .relaxed)
        let h = head.load(ordering: .acquiring)
        let m = min(n, h - t)
        for i in 0..<m { dst[i] = buf[(t + i) & mask] }
        tail.store(t + m, ordering: .releasing)
        return m
    }

    // czyta konsument: wyrzuca najstarsze probki, zeby opoznienie nie rosło
    func skip(_ n: Int) {
        let t = tail.load(ordering: .relaxed)
        let h = head.load(ordering: .acquiring)
        tail.store(t + min(n, h - t), ordering: .releasing)
    }
}
