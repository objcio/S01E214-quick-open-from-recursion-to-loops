import SwiftUI
import Cocoa
import OSLog

let log = OSLog(subsystem: "objc.io", category: "FuzzyMatch")

struct Matrix<A> {
    var array: [A]
    let width: Int
    private(set) var height: Int
    init(width: Int, height: Int, initialValue: A) {
        array = Array(repeating: initialValue, count: width*height)
        self.width = width
        self.height = height
    }

    private init(width: Int, height: Int, array: [A]) {
        self.width = width
        self.height = height
        self.array = array
    }

    subscript(column: Int, row: Int) -> A {
        get { array[row * width + column] }
        set { array[row * width + column] = newValue }
    }
    
    subscript(row row: Int) -> Array<A> {
        return Array(array[row * width..<(row+1)*width])
    }
    
    func map<B>(_ transform: (A) -> B) -> Matrix<B> {
        Matrix<B>(width: width, height: height, array: array.map(transform))
    }
    
    mutating func insert(row: Array<A>, at rowIdx: Int) {
        assert(row.count == width)
        assert(rowIdx <= height)
        array.insert(contentsOf: row, at: rowIdx * width)
        height += 1
    }
    
    func inserting(row: Array<A>, at rowIdx: Int) -> Matrix<A> {
        var copy = self
        copy.insert(row: row, at: rowIdx)
        return copy
    }
}

struct Score {
    private(set) var value: Int = 0
    private var log: [(Int, String)] = []
    var explanation: String {
        log.map { "\($0.0):\t\($0.1)"}.joined(separator: "\n")
    }
    
    mutating func add(_ amount: Int, reason: String) {
        value += amount
        log.append((amount, reason))
    }
    
    mutating func add(_ other: Score) {
        value += other.value
        log.append(contentsOf: other.log)
    }
}

extension Score: Comparable {
    static func < (lhs: Score, rhs: Score) -> Bool {
        lhs.value < rhs.value
    }
    
    static func == (lhs: Score, rhs: Score) -> Bool {
        lhs.value == rhs.value
    }
}

extension String {
    func fuzzyMatch3(_ needle: String) -> (score: Int, matrix: Matrix<Int?>)? {
        var matrix = Matrix<Int?>(width: self.count, height: needle.count, initialValue: nil)
        if needle.isEmpty { return (score: 0, matrix: matrix) }
        for (row, needleChar) in needle.enumerated() {
            var didMatch = false
            let prevMatchIdx: Int
            if row == 0 {
                prevMatchIdx = -1
            } else {
                prevMatchIdx = matrix[row: row-1].firstIndex { $0 != nil }!
            }
            for (column, char) in self.enumerated().dropFirst(prevMatchIdx + 1) {
                guard needleChar == char else {
                    continue
                }
                didMatch = true
                var score = 1
                if row > 0 {
                    var maxPrevious = Int.min
                    for prevColumn in 0..<column {
                        guard let s = matrix[prevColumn, row-1] else { continue }
                        let gapPenalty = (column-prevColumn) - 1
                        maxPrevious = max(maxPrevious, s - gapPenalty)
                    }
                    score += maxPrevious
                }
                matrix[column, row] = score
            }
            guard didMatch else { return nil }
        }
        guard let score = matrix[row: needle.count-1].compactMap({ $0 }).max() else {
            return  nil
        }
        return (score, matrix)
    }
}

extension Substring {
    func fuzzyMatch2(_ needle: Substring, gap: Int?) -> Score? {
        guard !needle.isEmpty else { return Score() }
        guard !self.isEmpty else { return nil }
        let skipScore = { self.dropFirst().fuzzyMatch2(needle, gap: gap.map { $0  + 1}) }
        if self.first == needle.first {
            guard let s = dropFirst().fuzzyMatch2(needle.dropFirst(), gap: 0) else { return nil }

            var acceptScore = Score()
            if let g = gap, g > 0 {
                acceptScore.add(-g, reason: "Gap \(g)")
            }
            acceptScore.add(1, reason: "Match \(first!)")
            acceptScore.add(s)
            
            guard let skip = skipScore() else { return acceptScore }
            return Swift.max(skip, acceptScore)
        } else {
            return skipScore()
        }
    }
}


let demoFiles: [String] = [
    "module/string.swift",
    "source/string.swift",
    "str/testing.swift"
]

struct ContentView: View {
    @State var needle: String = ""
    
    var filtered: [(string: String, score: Int, matrix: Matrix<Int?>)] {
        os_signpost(.begin, log: log, name: "Search", "%@", needle)
        defer { os_signpost(.end, log: log, name: "Search", "%@", needle) }
        return files.compactMap {
            guard let match = $0.fuzzyMatch3(needle) else { return nil }
            return ($0, match.score, match.matrix)
        }.sorted { $0.score > $1.score }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Image(nsImage: search)
                    .padding(.leading, 10)
                TextField("", text: $needle).textFieldStyle(PlainTextFieldStyle())
                    .padding(10)
                    .font(.subheadline)
                Button(action: {
                    self.needle = ""
                }, label: {
                    Image(nsImage: close)
                        .padding()
                }).disabled(needle.isEmpty)
                .buttonStyle(BorderlessButtonStyle())
            }
            List(filtered.prefix(30), id: \.string) { result in
                self.resultCell(result)
            }
        }
    }
    
    func resultCell(_ result: (string: String, score: Int, matrix: Matrix<Int?>)) -> some View {
        var textMatrix = result.matrix.map { score in
            Text(score.map { String($0) } ?? ".")
        }
        textMatrix.insert(row: result.string.map { Text(String($0)).bold() }, at: 0)
        return HStack {
            Text(String(result.score))
            MatrixView(matrix: textMatrix) { t in
                t.frame(width: 20, height: 15)
            }
        }
    }
}


struct MatrixView<A, V>: View where V: View {
    var matrix: Matrix<A>
    var cell: (A) -> V
    
    var body: some View {
        VStack(alignment: .leading) {
            ForEach(Array(0..<matrix.height), id: \.self) { row in
                HStack(alignment: .top) {
                    ForEach(Array(0..<self.matrix.width), id: \.self) { column in
                        self.cell(self.matrix[column, row])
                    }
                }
            }
        }
    }
}

// Hack to disable the focus ring
extension NSTextField {
    open override var focusRingType: NSFocusRingType {
        get { .none }
        set { }
    }
}

let close: NSImage = NSImage(named: "NSStopProgressFreestandingTemplate")!
let search: NSImage = NSImage(named: "NSTouchBarSearchTemplate")!
