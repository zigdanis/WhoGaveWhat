import SwiftUI
import CoreText

@main
struct WhoGaveWhatApp: App {
    private let persistence = PersistenceController.shared
    @StateObject private var store: AppStore

    init() {
        Self.registerFonts()
        let ctx = PersistenceController.shared.container.viewContext
        _store = StateObject(wrappedValue: AppStore(context: ctx))
    }

    /// Register the bundled Archivo faces so `Font.custom("Archivo-…")` resolves.
    private static func registerFonts() {
        let faces = ["Archivo-Regular", "Archivo-Medium", "Archivo-SemiBold",
                     "Archivo-Bold", "Archivo-ExtraBold", "Archivo-Black"]
        for face in faces {
            guard let url = Bundle.main.url(forResource: face, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environment(\.managedObjectContext, persistence.container.viewContext)
        }
    }
}
