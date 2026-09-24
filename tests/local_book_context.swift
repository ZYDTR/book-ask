import Foundation

@main struct LocalContextTests {
    static func main() async throws {
        func check(_ ok: Bool, _ message: String) {
            if !ok { fputs("FAIL: \(message)\n", stderr); exit(1) }
        }
        let words = (0...2000).map { "word\($0)" }
        let long = words.joined(separator: " ")
        let index = LocalBookIndex(version: 1, sections: [IndexedSection(title: "Long chapter", text: long)])
        let selected = "word1000"
        let visible = words[950...1050].joined(separator: " ")
        let result = index.locate(selection: selected, page: ReadingPageSnapshot(bookTitle: "Test", visibleText: visible, selectedRange: nil))
        check(result.text == words[800...1200].joined(separator: " "), "200 nearest words per side in a 2001-word paragraph")
        let duplicate = "one two three four five six seven eight common first nine common second ten eleven"
        let repeated = LocalBookIndex(version: 1, sections: [IndexedSection(title: "Repeat", text: duplicate)])
        check(repeated.locate(selection: "common", page: .init(bookTitle: "Test", visibleText: duplicate, selectedRange: nil)).text.isEmpty, "ambiguous occurrence must not guess")
        let range = (duplicate as NSString).range(of: "common", options: .backwards)
        check(!repeated.locate(selection: "common", page: .init(bookTitle: "Test", visibleText: duplicate, selectedRange: range)).text.isEmpty, "verified second occurrence can resolve")
        let ambiguousPage = LocalBookIndex(version: 1, sections: [IndexedSection(title: "A", text: duplicate), IndexedSection(title: "B", text: duplicate)])
        check(ambiguousPage.locate(selection: "common", page: .init(bookTitle: "Test", visibleText: duplicate, selectedRange: range)).text.isEmpty, "same page text in two chapters must reject")
        if CommandLine.arguments.count > 1 {
            let evidence = URL(fileURLWithPath: CommandLine.arguments[1])
            let book = evidence.appendingPathComponent("The Wonderful Wizard of Oz.epub")
            let built = try NativeEPUB.build(at: book)
            let chapters = built.sections.filter { $0.title.contains("Chapter") }
            check(chapters.count == 24, "native parser must resolve all 24 actual chapters (got \(chapters.count), sections \(built.sections.map(\.title)))")
            let rows = try JSONSerialization.jsonObject(with: Data(contentsOf: evidence.appendingPathComponent("actual-books-passages.json"))) as! [[String: Any]]
            for row in rows {
                let page = ReadingPageSnapshot(bookTitle: "The Wonderful Wizard of Oz", visibleText: row["visiblePassage"] as! String, selectedRange: nil)
                let located = built.locate(selection: row["selection"] as! String, page: page)
                check(located.chapter == row["expectedChapter"] as! String, "real Books page maps to expected chapter: \(located.status), chapter \(located.chapter)")
                check(!located.text.isEmpty, "actual page context available")
                print("PASS page \(row["page"]!): \(located.chapter), \(located.status)")
            }
            // Read-only discovery against the actual imported Books copy; fresh isolated index folder.
            let cache = FileManager.default.temporaryDirectory.appendingPathComponent("book-index-test-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: cache) }
            let library = LocalBookContext(indexDirectory: cache)
            let page = ReadingPageSnapshot(bookTitle: "The Wonderful Wizard of Oz", visibleText: rows[1]["visiblePassage"] as! String, selectedRange: nil)
            let first = await library.resolve(selection: "sad plight", page: page)
            let second = await library.resolve(selection: "sad plight", page: page)
            check(!first.text.isEmpty && !first.indexReused && second.indexReused && first.text == second.text, "fresh native Books discovery/index then persistent reuse")
        }
        print("PASS: bounded context, repeated selection offsets, ambiguous page rejection, native EPUB integration")
    }
}
