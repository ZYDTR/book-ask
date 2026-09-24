import Foundation

enum InputLengthLimit {
    static let maximum = 5000

    // Count visible characters, including whitespace, rather than UTF-8/16 units.
    static func allows(_ text: String) -> Bool { text.count <= maximum }
    static func counter(_ text: String) -> String { "\(text.count) / \(maximum)" }
    static func rejection(_ field: String, action: String) -> String {
        "\(field)超过 \(maximum) 字符，未\(action)"
    }
    static func detail(_ text: String, field: String) -> String {
        let count = text.count
        return count > maximum
            ? "\(field)最多 \(maximum) 字符，当前 \(count)，超出 \(count - maximum)。内容已保留，请缩短后重试。"
            : "\(field)最多 \(maximum) 字符，当前 \(count)；空格与换行也计入。"
    }
}
