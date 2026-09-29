#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Backtracking interpreter for `Program` bytecode, anchored at one position of one line.
///
/// One matcher belongs to one tokenizer and is reused for every rule attempt: its capture slots
/// and backtrack stack are raw buffers that grow once and are never reallocated per match. The
/// interpreter itself runs on a local `VM` value, so the inner loop touches no class properties
/// (no exclusivity checks, no reference counting).
///
/// Work is metered by `steps`; when a line exhausts its budget every attempt fails fast and the
/// tokenizer finishes the line unhighlighted, so no pattern can make highlighting superlinear.
final class Matcher {
    // A matcher is confined to one tokenizer on one thread, so the runtime's exclusivity
    // checks on these properties would only cost time on every attempt.
    @exclusivity(unchecked) private var stack: UnsafeMutablePointer<Choice>
    @exclusivity(unchecked) private var stackCapacity = 64
    @exclusivity(unchecked) private(set) var slots: UnsafeMutablePointer<Int>
    @exclusivity(unchecked) private var slotCapacity = 32
    @exclusivity(unchecked) private var delimiterBuffer: UnsafeMutablePointer<UInt8>
    @exclusivity(unchecked) private var delimiterCapacity = 16
    @exclusivity(unchecked) private var delimiterCount = 0

    // Per-line context.
    @exclusivity(unchecked) var input: UnsafePointer<UInt8> = UnsafePointer(bitPattern: 1)!
    @exclusivity(unchecked) var lineStart = 0
    @exclusivity(unchecked) var lineEnd = 0
    @exclusivity(unchecked) var steps = 0

    /// The scope of the keyword the last successful `words` match found.
    @exclusivity(unchecked) private(set) var wordScope: UInt32 = 0

    /// Set when the step budget ran out.
    var exhausted: Bool { steps < 0 }

    init() {
        stack = .allocate(capacity: stackCapacity)
        slots = .allocate(capacity: slotCapacity)
        delimiterBuffer = .allocate(capacity: delimiterCapacity)
    }

    deinit {
        stack.deallocate()
        slots.deallocate()
        delimiterBuffer.deallocate()
    }

    /// The text `\k` matches.
    var delimiter: [UInt8] {
        get { Array(UnsafeBufferPointer(start: delimiterBuffer, count: delimiterCount)) }
        set {
            if newValue.count > delimiterCapacity {
                delimiterBuffer.deallocate()
                delimiterCapacity = newValue.count
                delimiterBuffer = .allocate(capacity: delimiterCapacity)
            }
            newValue.withUnsafeBufferPointer { buffer in
                if let base = buffer.baseAddress { delimiterBuffer.update(from: base, count: buffer.count) }
            }
            delimiterCount = newValue.count
        }
    }

    /// Runs the program at `pc` from `pos`. Returns the end offset, or -1 on failure.
    /// Capture slots `0..<slotCount` are reset first and hold group positions afterwards.
    @inline(__always)
    func match(_ program: ProgramView, pc: Int32, at pos: Int, slotCount: Int) -> Int {
        if slotCount > slotCapacity { growSlots(slotCount) }
        var index = 0
        while index < slotCount {
            slots[index] = -1
            index &+= 1
        }
        var vm = VM(program: program, stack: stack, capacity: stackCapacity, depth: 0, slots: slots,
                    steps: steps, input: input, lineStart: lineStart, lineEnd: lineEnd, attemptStart: pos,
                    delimiter: delimiterBuffer, delimiterCount: delimiterCount, wordScope: 0)
        let end = vm.execute(pc: Int(pc), pos: pos, mustEnd: -1)
        stack = vm.stack
        stackCapacity = vm.capacity
        steps = vm.steps
        if end >= 0 {
            slots[0] = pos
            slots[1] = end
            wordScope = vm.wordScope
        }
        return end
    }

    private func growSlots(_ count: Int) {
        let newCapacity = max(count, slotCapacity * 2)
        let newSlots = UnsafeMutablePointer<Int>.allocate(capacity: newCapacity)
        newSlots.update(from: slots, count: slotCapacity)
        slots.deallocate()
        slots = newSlots
        slotCapacity = newCapacity
    }
}

struct Choice {
    var kind: Int32
    var pc: Int32
    var pos: Int
    var x: Int
    var y: Int

    static let branch: Int32 = 0
    static let restore: Int32 = 1
    static let greedy: Int32 = 2
    static let lazy: Int32 = 3
}

let notAKeyword = UInt32.max

/// The scope of the keyword `input[start..<end]` in keyword table `table`, or `notAKeyword`.
@inline(__always)
func lookupKeyword(_ program: ProgramView, table index: Int, input: UnsafePointer<UInt8>, start: Int, end: Int) -> UInt32 {
    let table = program.keywordTables[index]
    let fold = table.caseInsensitive
    let length = end &- start
    let mask = Int(table.mask)
    var slot = Int(keywordHash(input, start, end, fold: fold)) & mask
    let slots = program.keywordSlots + Int(table.slotOffset)
    while true {
        let entryIndex = slots[slot]
        if entryIndex < 0 { return notAKeyword }
        let entry = program.keywordEntries[Int(entryIndex)]
        if Int(entry.length) == length {
            let word = program.literals + Int(entry.offset)
            var offset = 0
            if fold {
                while offset < length, foldASCII(input[start &+ offset]) == word[offset] { offset &+= 1 }
            } else {
                while offset < length, input[start &+ offset] == word[offset] { offset &+= 1 }
            }
            if offset == length { return entry.scope }
        }
        slot = (slot &+ 1) & mask
    }
}

/// `\w` membership without touching a lazily-initialized global.
@inline(__always)
func isWordByte(_ byte: UInt8) -> Bool {
    if byte >= 0x80 { return true }
    if byte < 64 { return 0x03FF_0000_0000_0000 & (UInt64(1) &<< UInt64(byte)) != 0 }
    return 0x07FF_FFFE_87FF_FFFE & (UInt64(1) &<< UInt64(byte &- 64)) != 0
}

/// The interpreter's registers. Lives on the stack for one top-level attempt.
struct VM {
    let program: ProgramView
    var stack: UnsafeMutablePointer<Choice>
    var capacity: Int
    var depth: Int
    let slots: UnsafeMutablePointer<Int>
    var steps: Int
    let input: UnsafePointer<UInt8>
    let lineStart: Int
    let lineEnd: Int
    let attemptStart: Int
    let delimiter: UnsafeMutablePointer<UInt8>
    let delimiterCount: Int
    var wordScope: UInt32

    @inline(__always)
    mutating func push(_ choice: Choice) {
        if depth == capacity {
            let newCapacity = capacity * 2
            let newStack = UnsafeMutablePointer<Choice>.allocate(capacity: newCapacity)
            newStack.moveInitialize(from: stack, count: depth)
            stack.deallocate()
            stack = newStack
            capacity = newCapacity
        }
        stack[depth] = choice
        depth &+= 1
    }

    /// Consumes one scalar in `set` at `pos`, returning the new position or -1.
    @inline(__always)
    func step(_ set: ByteSet, at pos: Int) -> Int {
        guard pos < lineEnd else { return -1 }
        let byte = input[pos]
        if byte < 0x80 {
            return set.contains(byte) ? pos &+ 1 : -1
        }
        guard set.nonASCII else { return -1 }
        return min(pos &+ scalarLength(byte), lineEnd)
    }

    /// The start of the scalar before `pos`.
    @inline(__always)
    func stepBack(_ pos: Int) -> Int {
        var back = pos &- 1
        while back > lineStart, input[back] & 0xC0 == 0x80 { back &-= 1 }
        return back
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    mutating func execute(pc startPC: Int, pos startPos: Int, mustEnd: Int) -> Int {
        let base = depth
        let code = program.instructions
        var pc = startPC
        var pos = startPos

        while true {
            steps &-= 1
            if steps < 0 {
                depth = base
                return -1
            }
            let instruction = code[pc]
            var ok = true

            switch instruction.op {
            case .match:
                if mustEnd >= 0, pos != mustEnd {
                    ok = false
                } else {
                    depth = base
                    return pos
                }

            case .byte:
                if pos < lineEnd, input[pos] == UInt8(truncatingIfNeeded: instruction.a) {
                    pos &+= 1
                    pc &+= 1
                } else {
                    ok = false
                }

            case .literal:
                let length = Int(instruction.b)
                if lineEnd &- pos >= length {
                    let literal = program.literals + Int(instruction.a)
                    var index = 0
                    if instruction.flag == 1 {
                        while index < length, foldASCII(input[pos &+ index]) == literal[index] { index &+= 1 }
                    } else {
                        while index < length, input[pos &+ index] == literal[index] { index &+= 1 }
                    }
                    if index == length {
                        pos &+= length
                        pc &+= 1
                    } else {
                        ok = false
                    }
                } else {
                    ok = false
                }

            case .set:
                let next = step(program.sets[Int(instruction.a)], at: pos)
                if next >= 0 {
                    pos = next
                    pc &+= 1
                } else {
                    ok = false
                }

            case .any:
                if pos < lineEnd {
                    pos = min(pos &+ scalarLength(input[pos]), lineEnd)
                    pc &+= 1
                } else {
                    ok = false
                }

            case .repeatSet:
                let set = program.sets[Int(instruction.a)]
                let minimum = Int(instruction.b)
                let maximum = instruction.c < 0 ? Int.max : Int(instruction.c)
                var count = 0
                while count < minimum {
                    let next = step(set, at: pos)
                    if next < 0 { break }
                    pos = next
                    count &+= 1
                }
                if count < minimum {
                    ok = false
                    break
                }
                if instruction.flag == 1 {
                    if maximum > count {
                        push(Choice(kind: Choice.lazy, pc: Int32(pc &+ 1), pos: pos, x: Int(instruction.a),
                                    y: maximum == Int.max ? -1 : maximum &- count))
                    }
                } else {
                    let floor = pos
                    // ASCII fast path: most repeats run over plain ASCII text.
                    while count < maximum, pos < lineEnd {
                        let byte = input[pos]
                        if byte < 0x80 {
                            guard set.contains(byte) else { break }
                            pos &+= 1
                        } else {
                            guard set.nonASCII else { break }
                            pos = min(pos &+ scalarLength(byte), lineEnd)
                        }
                        count &+= 1
                    }
                    if instruction.flag == 0, pos > floor {
                        push(Choice(kind: Choice.greedy, pc: Int32(pc &+ 1), pos: pos, x: floor, y: 0))
                    }
                }
                pc &+= 1

            case .split:
                push(Choice(kind: Choice.branch, pc: instruction.b, pos: pos, x: 0, y: 0))
                pc = Int(instruction.a)

            case .jump:
                pc = Int(instruction.a)

            case .save:
                let slot = Int(instruction.a)
                push(Choice(kind: Choice.restore, pc: 0, pos: 0, x: slot, y: slots[slot]))
                slots[slot] = pos
                pc &+= 1

            case .progress:
                if slots[Int(instruction.a)] == pos {
                    ok = false
                } else {
                    pc &+= 1
                }

            case .anchor:
                switch instruction.flag {
                case AnchorKind.lineStart.rawValue:
                    ok = pos == lineStart
                case AnchorKind.lineEnd.rawValue:
                    ok = pos == lineEnd
                default:
                    let before = pos > lineStart && isWordByte(input[pos &- 1])
                    let after = pos < lineEnd && isWordByte(input[pos])
                    ok = (before != after) == (instruction.flag == AnchorKind.wordBoundary.rawValue)
                }
                if ok { pc &+= 1 }

            case .look:
                let negated = instruction.flag & 1 != 0
                var found = false
                if instruction.flag & 2 == 0 {
                    found = execute(pc: Int(instruction.a), pos: pos, mustEnd: -1) >= 0
                } else {
                    let bounds = program.lookbehindBounds[Int(instruction.c)]
                    var length = Int(bounds.0)
                    let longest = min(Int(bounds.1), pos &- lineStart)
                    while !found, length <= longest, steps >= 0 {
                        let start = pos &- length
                        if start == lineStart || input[start] & 0xC0 != 0x80 {
                            found = execute(pc: Int(instruction.a), pos: start, mustEnd: pos) >= 0
                        }
                        length &+= 1
                    }
                }
                if steps < 0 {
                    depth = base
                    return -1
                }
                if found != negated {
                    pc = Int(instruction.b)
                } else {
                    ok = false
                }

            case .atomic:
                let end = execute(pc: Int(instruction.a), pos: pos, mustEnd: -1)
                if steps < 0 {
                    depth = base
                    return -1
                }
                if end >= 0 {
                    pos = end
                    pc = Int(instruction.b)
                } else {
                    ok = false
                }

            case .backreference:
                let start = slots[Int(instruction.a) * 2]
                let end = slots[Int(instruction.a) * 2 + 1]
                if start < 0 || end < start {
                    ok = false
                } else {
                    let length = end &- start
                    if lineEnd &- pos >= length, memcmp(input + start, input + pos, length) == 0 {
                        pos &+= length
                        pc &+= 1
                    } else {
                        ok = false
                    }
                }

            case .delimiter:
                let length = delimiterCount
                if lineEnd &- pos >= length, memcmp(delimiter, input + pos, length) == 0 {
                    pos &+= length
                    pc &+= 1
                } else {
                    ok = false
                }

            case .words:
                let scope = lookupKeyword(program, table: Int(instruction.a), input: input, start: attemptStart, end: pos)
                if scope != notAKeyword {
                    wordScope = scope
                    pc &+= 1
                } else {
                    ok = false
                }
            }

            if ok { continue }

            // Backtrack.
            var resumed = false
            while depth > base {
                depth &-= 1
                let choice = stack[depth]
                switch choice.kind {
                case Choice.branch:
                    pc = Int(choice.pc)
                    pos = choice.pos
                    resumed = true
                case Choice.restore:
                    slots[choice.x] = choice.y
                case Choice.greedy:
                    let next = stepBack(choice.pos)
                    guard next >= choice.x else { continue }
                    if next > choice.x {
                        stack[depth].pos = next
                        depth &+= 1
                    }
                    pc = Int(choice.pc)
                    pos = next
                    resumed = true
                default: // lazy
                    guard choice.y != 0 else { continue }
                    let next = step(program.sets[choice.x], at: choice.pos)
                    guard next >= 0 else { continue }
                    let remaining = choice.y < 0 ? -1 : choice.y &- 1
                    if remaining != 0 {
                        stack[depth].pos = next
                        stack[depth].y = remaining
                        depth &+= 1
                    }
                    pc = Int(choice.pc)
                    pos = next
                    resumed = true
                }
                if resumed { break }
            }
            if !resumed { return -1 }
        }
    }
}
