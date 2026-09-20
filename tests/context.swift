import Foundation

@main struct Tests {
    static func main() {
        let p = [BookParagraph(id: "a", chapter: "one", text: "Before this."),
                 BookParagraph(id: "b", chapter: "one", text: "You’re liable to smash it into pieces."),
                 BookParagraph(id: "c", chapter: "one", text: "After that."),
                 BookParagraph(id: "d", chapter: "two", text: "Different chapter.")]
        assert(ReadingContext.match("You're  liable to smash", in: p).paragraphs.map(\.id) == ["a", "b", "c"])
        assert(ReadingContext.match("pieces. After", in: p).paragraphs.map(\.id) == ["b", "c"])
        assert(ReadingContext.match("Different chapter", in: p).paragraphs.map(\.id) == ["d"])
        assert(ReadingContext.match("made up sentence", in: p).paragraphs.isEmpty)
        assert(ReadingContext.match("it", in: p).paragraphs.isEmpty)
        assert(ReadingContext.match("After that", in: p + [p[2]]).paragraphs.isEmpty)
        assert(ReadingContext.cleanBooksClipboard("“You're liable to smash it.”\n\n摘录来自\nThe Mom Test\n此材料受版权保护。") == "You're liable to smash it.")
        assert(ReadingContext.cleanBooksClipboard("\"Some text\"\n\nExcerpt From\nThe Mom Test") == "Some text")
        assert(ReadingContext.cleanBooksClipboard("Ordinary quoted 'word' stays.") == "Ordinary quoted 'word' stays.")
        print("9 context and Books clipboard assertions passed")
    }
}
