import AppKit
import CoreText

/// Registers bundled .ttf fonts so `Font.custom(...)` can use them.
enum FontRegistrar {
    static func registerBundledFonts() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
