import SwiftUI
import Combine
import LocalAuthentication
import CoreImage.CIFilterBuiltins
import CoreLocation
import Network

#if os(iOS)
import UIKit
import AVFoundation
import CoreNFC
import PassKit
import PhotosUI
#endif

#if os(macOS)
import AppKit
#endif

// MARK: - Platform Image Helpers

#if os(iOS)
typealias PlatformImage = UIImage
#elseif os(macOS)
typealias PlatformImage = NSImage
#endif

struct PlatformImageView: View {
    let image: PlatformImage

    var body: some View {
        #if os(iOS)
        if image.size.width > 1 && image.size.height > 1 {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "xmark.circle")
        }
        #elseif os(macOS)
        if image.size.width > 1 && image.size.height > 1 {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "xmark.circle")
        }
        #endif
    }
}

// MARK: - Models

enum TascherlCardType: String, Codable, CaseIterable, Identifiable {
    case qr = "QR"
    case barcode = "Barcode"
    case nfc = "NFC"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .qr:
            return "qrcode"
        case .barcode:
            return "barcode"
        case .nfc:
            return "wave.3.right.circle.fill"
        }
    }
}

enum AppTab: Int, CaseIterable, Identifiable, Hashable {
    case cards = 0
    case add = 1
    case settings = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .cards:
            return "Karten"
        case .add:
            return "Hinzufügen"
        case .settings:
            return "Setup"
        }
    }

    var icon: String {
        switch self {
        case .cards:
            return "creditcard.fill"
        case .add:
            return "plus.circle.fill"
        case .settings:
            return "gearshape.fill"
        }
    }
}

enum AddCardMode: String, CaseIterable, Identifiable {
    case barcode
    case qr
    case nfc
    case screenshot

    var id: String { rawValue }

    var title: String {
        switch self {
        case .barcode:
            return "Barcode"
        case .qr:
            return "QR"
        case .nfc:
            return "NFC"
        case .screenshot:
            return "Screenshot"
        }
    }

    var icon: String {
        switch self {
        case .barcode:
            return "barcode"
        case .qr:
            return "qrcode"
        case .nfc:
            return "wave.3.right.circle.fill"
        case .screenshot:
            return "photo"
        }
    }
}

struct TascherlCard: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var company: String
    var brand: String
    var type: TascherlCardType
    var category: String
    var info: String
    var code: String
    var locationHint: String
    var favorite: Bool
    var gradientStartHex: String
    var gradientEndHex: String
    var walletPassURL: String?
    var renderType: CardRenderType
    var imageData: Data?

    enum CardRenderType: String, Codable, CaseIterable, Identifiable {
        case barcode
        case qr
        case image

        var id: String { rawValue }

        var title: String {
            switch self {
            case .barcode:
                return "Barcode"
            case .qr:
                return "QR"
            case .image:
                return "Screenshot"
            }
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        company: String,
        brand: String,
        type: TascherlCardType,
        category: String,
        info: String,
        code: String,
        locationHint: String,
        favorite: Bool,
        gradientStartHex: String,
        gradientEndHex: String,
        walletPassURL: String? = nil,
        renderType: CardRenderType = .barcode,
        imageData: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.company = company
        self.brand = brand
        self.type = type
        self.category = category
        self.info = info
        self.code = code
        self.locationHint = locationHint
        self.favorite = favorite
        self.gradientStartHex = gradientStartHex
        self.gradientEndHex = gradientEndHex
        self.walletPassURL = walletPassURL
        self.renderType = renderType
        self.imageData = imageData
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case company
        case brand
        case type
        case category
        case info
        case code
        case locationHint
        case favorite
        case gradientStartHex
        case gradientEndHex
        case walletPassURL
        case renderType
        case imageData
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        company = try container.decode(String.self, forKey: .company)
        brand = try container.decode(String.self, forKey: .brand)
        type = try container.decode(TascherlCardType.self, forKey: .type)
        category = try container.decode(String.self, forKey: .category)
        info = try container.decode(String.self, forKey: .info)
        code = try container.decode(String.self, forKey: .code)
        locationHint = try container.decode(String.self, forKey: .locationHint)
        favorite = try container.decode(Bool.self, forKey: .favorite)
        gradientStartHex = try container.decode(String.self, forKey: .gradientStartHex)
        gradientEndHex = try container.decode(String.self, forKey: .gradientEndHex)
        walletPassURL = try container.decodeIfPresent(String.self, forKey: .walletPassURL)

        // Wichtig: alte gespeicherte Karten ohne renderType sollen nicht crashen
        renderType = try container.decodeIfPresent(CardRenderType.self, forKey: .renderType) ?? Self.defaultRenderType(for: type)

        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
    }

    private static func defaultRenderType(for type: TascherlCardType) -> CardRenderType {
        switch type {
        case .qr:
            return .qr
        case .barcode:
            return .barcode
        case .nfc:
            return .barcode
        }
    }
}

// MARK: - Helpers

func normalizeBrand(_ input: String) -> String {
    input
        .lowercased()
        .replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: "-", with: "")
        .replacingOccurrences(of: "_", with: "")
        .replacingOccurrences(of: "ö", with: "oe")
        .replacingOccurrences(of: "ä", with: "ae")
        .replacingOccurrences(of: "ü", with: "ue")
        .replacingOccurrences(of: "ß", with: "ss")
}

extension Color {
    init(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(of: "#", with: "")

        guard text.count == 6 else {
            self = .gray
            return
        }

        var value: UInt64 = 0
        Scanner(string: text).scanHexInt64(&value)

        let r = Double((value >> 16) & 0xff) / 255
        let g = Double((value >> 8) & 0xff) / 255
        let b = Double(value & 0xff) / 255

        self.init(red: r, green: g, blue: b)
    }
}

func impact() {
    #if os(iOS)
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    #endif
}
enum TascherlTheme {
    static let matteYellow = Color(red: 0.78, green: 0.62, blue: 0.28)
}

struct AppTLogo: View {
    var size: CGFloat = 56

    private let matteYellow = TascherlTheme.matteYellow

    var body: some View {
        #if os(iOS)
        if let image = UIImage(named: "AppT"),
           image.size.width > 1,
           image.size.height > 1 {
            Image(uiImage: image)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(matteYellow)
                .frame(width: size, height: size)
        } else {
            fallback
        }
        #elseif os(macOS)
        if let image = NSImage(named: NSImage.Name("AppT")),
           image.size.width > 1,
           image.size.height > 1 {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(matteYellow)
                .frame(width: size, height: size)
        } else {
            fallback
        }
        #endif
    }

    private var fallback: some View {
        Text("T")
            .font(.system(size: size * 0.78, weight: .black))
            .foregroundStyle(matteYellow)
            .frame(width: size, height: size)
    }
}
// MARK: - Store
struct StoreRelations {
    static func usableStores(for brand: String) -> [String] {
        let normalized = normalizeBrand(brand)

        switch normalized {
        case "jo", "joe", "jö":
            return [
                "BILLA",
                "BILLA Plus",
                "Penny",
                "OMV",
                "ADEG"
            ]

        default:
            return []
        }
    }
}


final class CardStore: ObservableObject {
    @Published var cards: [TascherlCard] = [] {
        didSet {
            save()
        }
    }

    @Published var selectedCard: TascherlCard?
    @Published var smartSuggestion: TascherlCard?
    @Published var smartSuggestionText: String = ""

    private let storageKey = "tascherl_cards"
    private let lastSuggestionKey = "tascherl_last_suggestion"

    init() {
        load()
    }

    // MARK: - Add

    func add(_ card: TascherlCard) {
        cards.append(card)
    }

    // Kompatibilität mit deinem bestehenden AddCardHostView
    func addCard(_ card: TascherlCard) {
        add(card)
    }

    // MARK: - Delete

    func delete(_ card: TascherlCard) {
        cards.removeAll { $0.id == card.id }

        if selectedCard?.id == card.id {
            selectedCard = nil
        }

        if smartSuggestion?.id == card.id {
            clearSmartSuggestion()
        }
    }

    // MARK: - Reset / Clear

    func resetDemo() {
        // Weil du keine Beispielkarten mehr willst:
        // Reset bedeutet ab jetzt: alle Karten löschen.
        cards.removeAll()
        clearSmartSuggestion()
        UserDefaults.standard.removeObject(forKey: lastSuggestionKey)
    }

    // MARK: - Smart Suggestion

    func clearSmartSuggestion() {
        smartSuggestion = nil
        smartSuggestionText = ""
    }

    func setSmartSuggestion(card: TascherlCard, distanceMeters: Double?, online: Bool) {
        smartSuggestion = card

        if let distanceMeters {
            let rounded = Int(distanceMeters.rounded())
            smartSuggestionText = online
                ? "\(card.company) ist ca. \(rounded)m entfernt"
                : "\(card.company) ist laut Offline-Daten ca. \(rounded)m entfernt"
        } else {
            smartSuggestionText = "Zuletzt in deiner Nähe: \(card.company)"
        }

        saveLastSuggestion(card)
    }

    func saveLastSuggestion(_ card: TascherlCard) {
        if let data = try? JSONEncoder().encode(card) {
            UserDefaults.standard.set(data, forKey: lastSuggestionKey)
        }
    }

    func loadLastSuggestion() -> TascherlCard? {
        guard let data = UserDefaults.standard.data(forKey: lastSuggestionKey),
              let decoded = try? JSONDecoder().decode(TascherlCard.self, from: data)
        else {
            return nil
        }

        return decoded
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(cards) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([TascherlCard].self, from: data)
        else {
            cards = []
            return
        }

        cards = decoded
    }
}


struct StorePOI: Codable, Identifiable {
    var id: String
    var brand: String
    var name: String
    var latitude: Double
    var longitude: Double
}

final class NearbyCardManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var isOnline: Bool = true
    @Published var statusText: String = ""

    private let locationManager = CLLocationManager()
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "Tascherl.NetworkMonitor")

    private weak var store: CardStore?

    private var locationEnabled: Bool = true
    private var offlineStoreDataEnabled: Bool = false

    private var lastRefreshDate: Date = .distantPast
    private var isRefreshing = false

    private let cacheKey = "tascherl_cached_store_pois"

    override init() {
        super.init()

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 100

        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isOnline = path.status == .satisfied
            }
        }

        monitor.start(queue: monitorQueue)
    }

    func refresh(
        store: CardStore,
        locationEnabled: Bool,
        offlineStoreDataEnabled: Bool,
        force: Bool = false
    ) {
        self.store = store
        self.locationEnabled = locationEnabled
        self.offlineStoreDataEnabled = offlineStoreDataEnabled

        // ✅ Wenn ausgeschaltet → alles löschen
        guard locationEnabled else {
            store.clearSmartSuggestion()
            statusText = "Standortvorschläge deaktiviert"
            return
        }

        // ✅ 1. SOFORT letzten Vorschlag anzeigen (wichtig für Offline & Speed!)
        if let last = store.loadLastSuggestion() {
            store.smartSuggestion = last
            store.smartSuggestionText = "Zuletzt in deiner Nähe: \(last.company)"
        }

        // ✅ 2. Cache sofort nutzen wenn erlaubt
        if offlineStoreDataEnabled, let lastLocation = locationManager.location {
            findNearestFromCache(currentLocation: lastLocation, store: store)
        }

        // ✅ 3. Refresh throttling (verhindert Spam)
        let now = Date()
        if !force && now.timeIntervalSince(lastRefreshDate) < 12 {
            return
        }

        lastRefreshDate = now

        // ✅ 4. Wenn iOS schon Location hat → sofort verwenden
        if let cachedLocation = locationManager.location {
            if isOnline {
                if !isRefreshing {
                    isRefreshing = true
                    fetchNearbyStoresOnline(currentLocation: cachedLocation, store: store)
                }
            } else {
                // ✅ Offline fallback
                if offlineStoreDataEnabled {
                    findNearestFromCache(currentLocation: cachedLocation, store: store)
                }
                // ❌ KEIN clear hier → sonst verschwindet dein letzter Vorschlag!
            }
        }

        // ✅ 5. Frische Location im Hintergrund holen
        locationManager.requestWhenInUseAuthorization()
        locationManager.requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let currentLocation = locations.last,
              let store
        else { return }

        if isRefreshing {
            return
        }

        isRefreshing = true

        if isOnline {
            statusText = "Online: Suche nahe Filialen"
            fetchNearbyStoresOnline(currentLocation: currentLocation, store: store)
        } else {
            statusText = "Offline"

            if offlineStoreDataEnabled {
                findNearestFromCache(currentLocation: currentLocation, store: store)
            } else {
                store.clearSmartSuggestion()
                statusText = "Offline: keine lokalen Standortdaten aktiviert"
            }

            isRefreshing = false
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.store?.clearSmartSuggestion()
            self.statusText = "Standort konnte nicht geladen werden"
            self.isRefreshing = false
        }

        print("Location error:", error.localizedDescription)
    }

    private func fetchNearbyStoresOnline(currentLocation: CLLocation, store: CardStore) {
        let lat = currentLocation.coordinate.latitude
        let lon = currentLocation.coordinate.longitude

        let brandRegex = buildBrandRegex(from: store.cards)

        guard !brandRegex.isEmpty else {
            store.clearSmartSuggestion()
            statusText = "Keine Kartenmarken für Standortsuche"
            isRefreshing = false
            return
        }

        let query = """
        [out:json][timeout:8];
        (
          node(around:900,\(lat),\(lon))["brand"~"\(brandRegex)",i];
          way(around:900,\(lat),\(lon))["brand"~"\(brandRegex)",i];
          relation(around:900,\(lat),\(lon))["brand"~"\(brandRegex)",i];

          node(around:900,\(lat),\(lon))["name"~"\(brandRegex)",i];
          way(around:900,\(lat),\(lon))["name"~"\(brandRegex)",i];
          relation(around:900,\(lat),\(lon))["name"~"\(brandRegex)",i];
        );
        out center tags;
        """

        guard let url = URL(string: "https://overpass-api.de/api/interpreter") else {
            isRefreshing = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")

        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        request.httpBody = "data=\(encodedQuery)".data(using: .utf8)

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }

            if let error {
                DispatchQueue.main.async {
                    print("Overpass error:", error.localizedDescription)

                    if self.offlineStoreDataEnabled {
                        self.findNearestFromCache(currentLocation: currentLocation, store: store)
                    } else {
                        store.clearSmartSuggestion()
                        self.statusText = "Online-Suche fehlgeschlagen"
                    }

                    self.isRefreshing = false
                }

                return
            }

            guard let data else {
                DispatchQueue.main.async {
                    store.clearSmartSuggestion()
                    self.statusText = "Keine Online-Daten erhalten"
                    self.isRefreshing = false
                }

                return
            }

            do {
                let response = try JSONDecoder().decode(OverpassResponse.self, from: data)

                let pois = response.elements.compactMap { element -> StorePOI? in
                    let brand = element.tags?.brand ?? element.tags?.name ?? ""
                    let name = element.tags?.name ?? brand

                    let resolvedLat = element.lat ?? element.center?.lat
                    let resolvedLon = element.lon ?? element.center?.lon

                    guard let resolvedLat,
                          let resolvedLon,
                          !brand.isEmpty
                    else {
                        return nil
                    }

                    return StorePOI(
                        id: "\(element.type)-\(element.id)",
                        brand: brand,
                        name: name,
                        latitude: resolvedLat,
                        longitude: resolvedLon
                    )
                }

                DispatchQueue.main.async {
                    self.saveCachedPOIs(pois)

                    self.applyNearestPOI(
                        pois,
                        currentLocation: currentLocation,
                        store: store,
                        online: true
                    )

                    self.isRefreshing = false
                }
            } catch {
                DispatchQueue.main.async {
                    print("Decode error:", error.localizedDescription)

                    if self.offlineStoreDataEnabled {
                        self.findNearestFromCache(currentLocation: currentLocation, store: store)
                    } else {
                        store.clearSmartSuggestion()
                        self.statusText = "Online-Daten konnten nicht gelesen werden"
                    }

                    self.isRefreshing = false
                }
            }
        }.resume()
    }

    private func findNearestFromCache(currentLocation: CLLocation, store: CardStore) {
        let pois = loadCachedPOIs()
        applyNearestPOI(pois, currentLocation: currentLocation, store: store, online: false)
    }

    private func applyNearestPOI(
        _ pois: [StorePOI],
        currentLocation: CLLocation,
        store: CardStore,
        online: Bool
    ) {
        guard !pois.isEmpty else {
            store.clearSmartSuggestion()
            statusText = online ? "Keine nahe Filiale gefunden" : "Keine Offline-Daten gefunden"
            return
        }

        let nearest = pois
            .map { poi -> (poi: StorePOI, distance: Double) in
                let poiLocation = CLLocation(latitude: poi.latitude, longitude: poi.longitude)
                return (poi, currentLocation.distance(from: poiLocation))
            }
            .sorted { $0.distance < $1.distance }
            .first

        guard let nearest else {
            store.clearSmartSuggestion()
            return
        }

        guard nearest.distance <= 1500 else {
            store.clearSmartSuggestion()
            statusText = "Keine passende Karte in der Nähe"
            return
        }

        let matchedBrand = normalizeBrand(nearest.poi.brand)

        if let matchedCard = store.cards.first(where: {
            let cardBrand = normalizeBrand($0.brand)
            let cardCompany = normalizeBrand($0.company)
            let cardName = normalizeBrand($0.name)

            return matchedBrand.contains(cardBrand)
                || cardBrand.contains(matchedBrand)
                || matchedBrand.contains(cardCompany)
                || cardCompany.contains(matchedBrand)
                || matchedBrand.contains(cardName)
                || cardName.contains(matchedBrand)
        }) {
            store.setSmartSuggestion(
                card: matchedCard,
                distanceMeters: nearest.distance,
                online: online
            )
        } else {
            store.clearSmartSuggestion()
            statusText = "Filiale erkannt, aber keine passende Karte gespeichert"
        }
    }

    private func saveCachedPOIs(_ pois: [StorePOI]) {
        guard offlineStoreDataEnabled else { return }

        var existing = loadCachedPOIs()

        for poi in pois {
            if !existing.contains(where: { $0.id == poi.id }) {
                existing.append(poi)
            }
        }

        guard let data = try? JSONEncoder().encode(existing) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }

    private func loadCachedPOIs() -> [StorePOI] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let decoded = try? JSONDecoder().decode([StorePOI].self, from: data)
        else {
            return []
        }

        return decoded
    }

    private func buildBrandRegex(from cards: [TascherlCard]) -> String {
        let names = cards.flatMap { card in
            [
                card.brand,
                card.company,
                card.name
            ]
        }
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .map { escapeRegex($0) }

        let unique = Array(Set(names))

        return unique.joined(separator: "|")
    }

    private func escapeRegex(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ".", with: "\\.")
            .replacingOccurrences(of: "+", with: "\\+")
            .replacingOccurrences(of: "*", with: "\\*")
            .replacingOccurrences(of: "?", with: "\\?")
            .replacingOccurrences(of: "^", with: "\\^")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "(", with: "\\(")
            .replacingOccurrences(of: ")", with: "\\)")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
            .replacingOccurrences(of: "{", with: "\\{")
            .replacingOccurrences(of: "}", with: "\\}")
            .replacingOccurrences(of: "|", with: "\\|")
    }
}

struct OverpassResponse: Codable {
    let elements: [OverpassElement]
}

struct OverpassElement: Codable {
    let type: String
    let id: Int
    let lat: Double?
    let lon: Double?
    let center: OverpassCenter?
    let tags: OverpassTags?
}

struct OverpassCenter: Codable {
    let lat: Double
    let lon: Double
}

struct OverpassTags: Codable {
    let name: String?
    let brand: String?
}
// MARK: - App Entry

@main
struct TascherlApp: App {
    @StateObject private var store = CardStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
    }
}

// MARK: - Root

struct RootView: View {
    @AppStorage("tascherl_darkMode") private var darkMode = true
    @AppStorage("tascherl_faceIdEnabled") private var faceIdEnabled = false

    @State private var booting = true
    @State private var unlocked = false

    var body: some View {
        ZStack {
            if booting {
                SplashView()
                    .transition(.opacity)
            } else {
                if faceIdEnabled && !unlocked {
                    UnlockView {
                        unlocked = true
                    }
                } else {
                    MainShellView()
                        .preferredColorScheme(darkMode ? .dark : .light)
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
                withAnimation(.easeOut(duration: 0.45)) {
                    booting = false
                }
            }
        }
    }
}
// MARK: - Splash

struct SplashView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: "#050505"),
                    Color(hex: "#111111"),
                    Color(hex: "#050505")
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                ZStack {
                    RoundedRectangle(cornerRadius: 34)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.10),
                                    Color.white.opacity(0.035)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 108, height: 108)
                        .overlay {
                            RoundedRectangle(cornerRadius: 34)
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.20),
                                            Color.white.opacity(0.04)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        }
                        .shadow(color: .black.opacity(0.35), radius: 24, y: 14)

                    AppTLogo(size: 62)
                }

                Text("Tascherl")
                    .font(.system(size: 42, weight: .black))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.86, green: 0.70, blue: 0.32),
                                Color(red: 0.68, green: 0.52, blue: 0.22)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
    }
}
// MARK: - Unlock / Face ID

struct UnlockView: View {
    var onUnlock: () -> Void

    @State private var errorText = ""

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black,
                    Color(hex: "#11100B"),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                ZStack {
                    RoundedRectangle(cornerRadius: 32)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.10),
                                    Color.white.opacity(0.035)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 104, height: 104)
                        .overlay {
                            RoundedRectangle(cornerRadius: 32)
                                .stroke(TascherlTheme.matteYellow.opacity(0.22), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.35), radius: 24, y: 14)

                    AppTLogo(size: 58)
                }

                Text("Tascherl ist gesperrt")
                    .font(.title.bold())
                    .foregroundStyle(.primary)

                Text("Nutze Face ID, Touch ID oder den Gerätecode.")
                    .multilineTextAlignment(.center)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 32)

                if !errorText.isEmpty {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.red.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Button {
                    authenticate()
                } label: {
                    Label("Entsperren", systemImage: "lock.open.fill")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(TascherlTheme.matteYellow)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }
            }
        }
        .onAppear {
            authenticate()
        }
    }

    private func authenticate() {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Tascherl entsperren"
            ) { success, authError in
                DispatchQueue.main.async {
                    if success {
                        impact()
                        onUnlock()
                    } else {
                        errorText = authError?.localizedDescription ?? "Entsperren fehlgeschlagen."
                    }
                }
            }
        } else {
            errorText = "Biometrie oder Gerätecode ist auf diesem Gerät nicht verfügbar."
        }
    }
}

// MARK: - Main Shell with Swipe

// MARK: - Main Shell

struct MainShellView: View {
    @EnvironmentObject var store: CardStore
    @State private var selectedTab: AppTab = .cards

    private var animatedTabSelection: Binding<AppTab> {
        Binding(
            get: {
                selectedTab
            },
            set: { newValue in
                guard newValue != selectedTab else { return }

                withAnimation(.easeInOut(duration: 0.24)) {
                    selectedTab = newValue
                }

                impact()
            }
        )
    }

    var body: some View {
        TabView(selection: animatedTabSelection) {
            SwipeableTabScreen(selectedTab: $selectedTab) {
                CardsHomeView()
            }
            .tag(AppTab.cards)
            .tabItem {
                Label(AppTab.cards.title, systemImage: AppTab.cards.icon)
            }

            SwipeableTabScreen(selectedTab: $selectedTab) {
                AddCardHostView()
            }
            .tag(AppTab.add)
            .tabItem {
                Label(AppTab.add.title, systemImage: AppTab.add.icon)
            }

            SwipeableTabScreen(selectedTab: $selectedTab) {
                SettingsView()
            }
            .tag(AppTab.settings)
            .tabItem {
                Label(AppTab.settings.title, systemImage: AppTab.settings.icon)
            }
        }
        .tint(TascherlTheme.matteYellow)
        .animation(.easeInOut(duration: 0.24), value: selectedTab)
        #if os(iOS)
        .toolbarBackground(.automatic, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        #endif
    }
}
struct SwipeableTabScreen<Content: View>: View {
    @Binding var selectedTab: AppTab
    let content: Content

    init(
        selectedTab: Binding<AppTab>,
        @ViewBuilder content: () -> Content
    ) {
        self._selectedTab = selectedTab
        self.content = content()
    }

    var body: some View {
        content
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 65, coordinateSpace: .local)
                    .onEnded { value in
                        handleSwipe(value)
                    },
                including: .gesture
            )
    }

    private func handleSwipe(_ value: DragGesture.Value) {
        let horizontal = value.translation.width
        let vertical = value.translation.height

        // Nur wirklich horizontale Swipes akzeptieren
        guard abs(horizontal) > abs(vertical) * 2.2 else { return }

        // Kleine Bewegungen ignorieren
        guard abs(horizontal) > 95 else { return }

        if horizontal < 0 {
            goNext()
        } else {
            goPrevious()
        }
    }

    private func goNext() {
        guard let currentIndex = AppTab.allCases.firstIndex(of: selectedTab),
              currentIndex < AppTab.allCases.count - 1
        else { return }

        withAnimation(.easeInOut(duration: 0.24)) {
            selectedTab = AppTab.allCases[currentIndex + 1]
        }

        impact()
    }

    private func goPrevious() {
        guard let currentIndex = AppTab.allCases.firstIndex(of: selectedTab),
              currentIndex > 0
        else { return }

        withAnimation(.easeInOut(duration: 0.24)) {
            selectedTab = AppTab.allCases[currentIndex - 1]
        }

        impact()
    }
}

// MARK: - Home
struct CardsHomeView: View {
    @EnvironmentObject var store: CardStore

    @AppStorage("tascherl_locationEnabled") private var locationEnabled = true
    @AppStorage("tascherl_offlineStoreDataEnabled") private var offlineStoreDataEnabled = false

    @StateObject private var nearbyManager = NearbyCardManager()

    var body: some View {
        NavigationStack {
            ZStack {
                BackgroundView()

                ScrollView {
                    VStack(spacing: 18) {
                        CompactHeaderView(cardCount: store.cards.count)

                        if locationEnabled, let suggestion = store.smartSuggestion {
                            SmartSuggestionView(
                                card: suggestion,
                                subtitle: store.smartSuggestionText
                            ) {
                                openCard(suggestion)
                            }
                            .zIndex(10)
                            .padding(.bottom, 6)
                        }

                        VStack(spacing: 14) {
                            ForEach(store.cards) { card in
                                Button {
                                    openCard(card)
                                } label: {
                                    WalletCardView(card: card)
                                        .contentShape(RoundedRectangle(cornerRadius: 30))
                                }
                                .buttonStyle(.plain)
                                .frame(height: 142)
                                .contentShape(RoundedRectangle(cornerRadius: 30))
                                .contextMenu {
                                    Button(role: .destructive) {
                                        store.delete(card)
                                    } label: {
                                        Label("Karte löschen", systemImage: "trash")
                                    }
                                }
                                .zIndex(1)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                nearbyManager.refresh(
                    store: store,
                    locationEnabled: locationEnabled,
                    offlineStoreDataEnabled: offlineStoreDataEnabled,
                    force: true
                )
            }
            .onChange(of: locationEnabled) {
                nearbyManager.refresh(
                    store: store,
                    locationEnabled: locationEnabled,   // ✅ FIX
                    offlineStoreDataEnabled: offlineStoreDataEnabled,
                    force: true
                )
            }

            .onChange(of: offlineStoreDataEnabled) {
                nearbyManager.refresh(
                    store: store,
                    locationEnabled: locationEnabled,
                    offlineStoreDataEnabled: offlineStoreDataEnabled, // ✅ FIX
                    force: true
                )
            }

            .sheet(item: $store.selectedCard) { card in
                CardDetailView(card: card)
                    .presentationDetentsIfAvailable()
            }
        }
    }

    private func openCard(_ card: TascherlCard) {
        impact()

        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            store.selectedCard = card
        }
    }
}
extension View {
    @ViewBuilder
    func presentationDetentsIfAvailable() -> some View {
        #if os(iOS)
        self
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        #else
        self
        #endif
    }
}

struct BackgroundView: View {
    var body: some View {
        Color(.systemBackground)
            .ignoresSafeArea()
    }
}

struct CompactHeaderView: View {
    let cardCount: Int

    var body: some View {
        HStack {
            AppTLogo(size: 34)

            Spacer()

            Text("\(cardCount) Karten")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }
}

struct SmartSuggestionView: View {
    let card: TascherlCard
    let subtitle: String
    var onOpen: () -> Void

    @State private var pressed = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                pressed = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                    pressed = false
                }

                onOpen()
            }
        } label: {
            HStack(spacing: 12) {
                BrandLogoView(brand: card.brand, company: card.company)
                    .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 3) {
                    Text("In deiner Nähe")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)

                    Text("\(card.company) Karte schnell öffnen")
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)

                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 2)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .contentShape(RoundedRectangle(cornerRadius: 24))
            .scaleEffect(pressed ? 0.97 : 1.0)
            .opacity(pressed ? 0.86 : 1.0)
        }
        .buttonStyle(.plain)
        .frame(height: 72)
        .contentShape(RoundedRectangle(cornerRadius: 24))
    }
}
// MARK: - Wallet Card

struct WalletCardView: View {
    let card: TascherlCard

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: card.gradientStartHex), Color(hex: card.gradientEndHex)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(.white.opacity(0.18))
                .frame(width: 140, height: 140)
                .blur(radius: 30)
                .offset(x: 130, y: -60)

            VStack(spacing: 22) {
                HStack(alignment: .top) {
                    BrandLogoView(brand: card.brand, company: card.company)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.company)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))

                        Text(card.name)
                            .font(.title3.bold())
                            .foregroundStyle(.white)

                        Text(card.category)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))
                    }

                    Spacer()

                    HStack(spacing: 5) {
                        Image(systemName: card.type.icon)
                        Text(card.type.rawValue)
                    }
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.22))
                    .clipShape(Capsule())
                }

                HStack {
                    Text(card.info)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.84))
                        .lineLimit(1)

                    Spacer()
                }
            }
            .padding()
        }
        .frame(height: 142)
        .clipShape(RoundedRectangle(cornerRadius: 30))
        .shadow(color: .black.opacity(0.20), radius: 14, y: 10)
        .contentShape(RoundedRectangle(cornerRadius: 30))
    }
}

struct BrandLogoView: View {
    let brand: String
    let company: String

    var normalized: String {
        normalizeBrand(brand.isEmpty ? company : brand)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white)
                .frame(width: 58, height: 58)

            logoView
        }
    }

    @ViewBuilder
    var logoView: some View {
        #if os(iOS)
        if let image = UIImage(named: normalized),
           image.size.width > 0 && image.size.height > 0 {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
                .clipped()
        } else {
            fallback
        }
        #elseif os(macOS)
        if let image = NSImage(named: NSImage.Name(normalized)),
           image.size.width > 0 && image.size.height > 0 {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
                .clipped()
        } else {
            fallback
        }
        #endif
    }

    var fallback: some View {
        Text(String(company.prefix(2)).uppercased())
            .font(.headline.bold())
            .foregroundStyle(.black)
    }
}

// MARK: - Detail

struct CardDetailView: View {
    let card: TascherlCard

    @StateObject private var nfcManager = NFCManager()
    @State private var walletMessage = ""

    var body: some View {
        let usableStores = StoreRelations.usableStores(for: card.brand)

        ZStack {
            LinearGradient(
                colors: [Color(hex: card.gradientStartHex), Color(hex: card.gradientEndHex)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    HStack {
                        BrandLogoView(brand: card.brand, company: card.company)

                        VStack(alignment: .leading) {
                            Text(card.company)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.70))

                            Text(card.name)
                                .font(.largeTitle.bold())
                                .foregroundStyle(.white)
                        }

                        Spacer()
                    }
                    .padding(.top, 16)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Info")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.70))

                        Text(card.info)
                            .font(.headline)
                            .foregroundStyle(.white)

                        Label(card.locationHint, systemImage: "location.fill")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.80))

                        if !usableStores.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Gültig bei:")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white.opacity(0.70))

                                HStack(spacing: 6) {
                                    ForEach(usableStores, id: \.self) { store in
                                        Text(store)
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(.white.opacity(0.15))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.white.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 24))

                    VStack(spacing: 16) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Kartencode")
                                    .font(.caption)
                                    .foregroundStyle(.black.opacity(0.55))

                                Text(card.code.isEmpty ? "Screenshot-Karte" : card.code)
                                    .font(.system(.footnote, design: .monospaced))
                                    .foregroundStyle(.black)
                            }

                            Spacer()

                            Text(card.renderType.title)
                                .font(.caption.bold())
                                .foregroundStyle(.black)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(.black.opacity(0.06))
                                .clipShape(Capsule())
                        }

                        if card.type == .nfc {
                            NFCDisplayView(card: card, nfcManager: nfcManager)
                        } else {
                            switch card.renderType {
                            case .image:
                                ScreenshotCardDisplay(imageData: card.imageData)

                            case .qr:
                                QRCodeDisplay(value: card.code)

                            case .barcode:
                                BarcodeDisplay(value: card.code)
                            }
                        }

                        Button {
                            if card.type == .nfc {
                                nfcManager.beginScan()
                            } else {
                                copyCode(card.code)
                            }
                        } label: {
                            Label(
                                card.type == .nfc ? "NFC lesen" : "Code kopieren",
                                systemImage: card.type == .nfc ? "wave.3.right.circle.fill" : "doc.on.doc.fill"
                            )
                            .frame(maxWidth: .infinity)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding()
                            .background(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                        }
                        .disabled(card.renderType == .image && card.code.isEmpty)
                        .opacity(card.renderType == .image && card.code.isEmpty ? 0.45 : 1)

                        Button {
                            addToAppleWallet(card: card)
                        } label: {
                            Label("Zu Apple Wallet", systemImage: "wallet.pass.fill")
                                .frame(maxWidth: .infinity)
                                .font(.headline)
                                .foregroundStyle(.black)
                                .padding()
                                .background(Color.black.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                        }

                        if !walletMessage.isEmpty {
                            Text(walletMessage)
                                .font(.caption)
                                .foregroundStyle(.black.opacity(0.55))
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding()
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 32))
                }
                .padding()
            }
        }
    }

    private func copyCode(_ value: String) {
        #if os(iOS)
        UIPasteboard.general.string = value
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #endif

        impact()
    }

    private func addToAppleWallet(card: TascherlCard) {
        guard let string = card.walletPassURL,
              let url = URL(string: string)
        else {
            walletMessage = "Für diese Karte ist noch kein offizieller Apple Wallet Pass hinterlegt."
            return
        }

        #if os(iOS)
        UIApplication.shared.open(url)
        #else
        NSWorkspace.shared.open(url)
        #endif
    }
}

struct ScreenshotCardDisplay: View {
    let imageData: Data?

    var body: some View {
        #if os(iOS)
        if let imageData,
           let uiImage = UIImage(data: imageData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 420)
                .padding()
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 24))
        } else {
            missingScreenshotView
        }
        #elseif os(macOS)
        if let imageData,
           let nsImage = NSImage(data: imageData) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 420)
                .padding()
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 24))
        } else {
            missingScreenshotView
        }
        #endif
    }

    private var missingScreenshotView: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo")
                .font(.largeTitle)

            Text("Kein Screenshot gespeichert")
                .font(.caption)
        }
        .foregroundStyle(.black.opacity(0.65))
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}
// MARK: - QR / Barcode

struct QRCodeDisplay: View {
    let value: String

    var body: some View {
        VStack(spacing: 12) {
            PlatformImageView(image: CodeImageGenerator.generateQRCode(from: value))
                .frame(width: 220, height: 220)
                .padding(12)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 24))

            Text("Zum Scannen bereit")
                .font(.caption)
                .foregroundStyle(.black.opacity(0.55))
        }
    }
}

struct BarcodeDisplay: View {
    let value: String

    var body: some View {
        VStack(spacing: 12) {
            PlatformImageView(image: CodeImageGenerator.generateBarcode(from: value))
                .frame(height: 110)
                .padding()
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 22))

            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.black.opacity(0.55))
        }
    }
}

enum CodeImageGenerator {
    static func generateQRCode(from string: String) -> UIImage {
        let data = Data(string.utf8)

        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")

        let context = CIContext()

        guard let output = filter.outputImage else {
            return UIImage(systemName: "xmark.circle") ?? UIImage()
        }

        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))

        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            return UIImage(systemName: "xmark.circle") ?? UIImage()
        }

        let image = UIImage(cgImage: cgImage)

        if image.size.width < 1 || image.size.height < 1 {
            return UIImage(systemName: "xmark.circle") ?? UIImage()
        }

        return image
    }

    static func generateBarcode(from string: String) -> UIImage {
        guard let filter = CIFilter(name: "CICode128BarcodeGenerator") else {
            return UIImage(systemName: "barcode") ?? UIImage()
        }

        filter.setValue(Data(string.utf8), forKey: "inputMessage")

        let context = CIContext()

        guard let output = filter.outputImage else {
            return UIImage(systemName: "barcode") ?? UIImage()
        }

        let scaled = output.transformed(by: CGAffineTransform(scaleX: 3, y: 3))

        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            return UIImage(systemName: "barcode") ?? UIImage()
        }

        let image = UIImage(cgImage: cgImage)

        if image.size.width < 1 || image.size.height < 1 {
            return UIImage(systemName: "barcode") ?? UIImage()
        }

        return image
    }
}

// MARK: - NFC

#if os(iOS)
final class NFCManager: NSObject, ObservableObject, NFCNDEFReaderSessionDelegate {
    @Published var lastResult: String = ""

    private var session: NFCNDEFReaderSession?

    func beginScan() {
        guard NFCNDEFReaderSession.readingAvailable else {
            DispatchQueue.main.async {
                self.lastResult = "NFC auf diesem Gerät nicht verfügbar."
            }
            return
        }

        session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: true)
        session?.alertMessage = "Halte dein iPhone an das NFC-Tag."
        session?.begin()
    }

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        DispatchQueue.main.async {
            self.lastResult = error.localizedDescription
        }
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        var collected: [String] = []

        for message in messages {
            for record in message.records {
                if let string = String(data: record.payload, encoding: .utf8) {
                    collected.append(string)
                } else {
                    collected.append(record.payload.map { String(format: "%02x", $0) }.joined())
                }
            }
        }

        DispatchQueue.main.async {
            self.lastResult = collected.joined(separator: "\n")
            impact()
        }
    }
}
#else
final class NFCManager: ObservableObject {
    @Published var lastResult: String = ""

    func beginScan() {
        lastResult = "NFC ist auf dieser Plattform nicht verfügbar."
    }
}
#endif

struct NFCDisplayView: View {
    let card: TascherlCard
    @ObservedObject var nfcManager: NFCManager

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(.green.opacity(0.25), lineWidth: 2)
                    .frame(width: 135, height: 135)

                Circle()
                    .stroke(.green.opacity(0.55), lineWidth: 3)
                    .frame(width: 100, height: 100)

                Image(systemName: "wave.3.right.circle.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(.green)
            }
            .padding(.top, 8)

            Text("NFC-Zugang bereit")
                .font(.headline)
                .foregroundStyle(.black)

            Text("iOS kann NFC-Tags lesen. Freie Emulation fremder Gym- oder Zutrittskarten ist nicht allgemein möglich.")
                .font(.caption)
                .foregroundStyle(.black.opacity(0.55))
                .multilineTextAlignment(.center)

            if !nfcManager.lastResult.isEmpty {
                Text("Gelesen: \(nfcManager.lastResult)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.green)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }

            Text("Token: \(card.code)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.black.opacity(0.4))
        }
        .padding()
        .background(Color.black.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 26))
    }
}

// MARK: - Add Card

struct AddCardHostView: View {
    @EnvironmentObject var store: CardStore

    var body: some View {
        NavigationStack {
            AddCardView { card in
                store.addCard(card)
            }
        }
    }
}
#if os(iOS)
struct ScreenshotImagePicker: UIViewControllerRepresentable {
    var onImagePicked: (UIImage) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onImagePicked: (UIImage) -> Void

        init(onImagePicked: @escaping (UIImage) -> Void) {
            self.onImagePicked = onImagePicked
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self)
            else { return }

            provider.loadObject(ofClass: UIImage.self) { image, _ in
                guard let uiImage = image as? UIImage else { return }

                DispatchQueue.main.async {
                    self.onImagePicked(uiImage)
                }
            }
        }
    }
}
#endif

struct AddCardView: View {
    var onAdd: (TascherlCard) -> Void

    @State private var name = ""
    @State private var company = ""
    @State private var code = ""
    @State private var category = "Neue Karte"

    @State private var mode: AddCardMode = .barcode

    @State private var screenshotImageData: Data?
    @State private var showScreenshotPicker = false

    @State private var showScanner = false
    @StateObject private var nfcManager = NFCManager()

    var body: some View {
        ZStack {
            BackgroundView()

            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Neue Karte")
                            .font(.largeTitle.bold())
                            .foregroundStyle(.primary)

                        Text("Manuell eingeben, scannen oder Screenshot hinzufügen.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 14)

                    Picker("Kartentyp", selection: $mode) {
                        ForEach(AddCardMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.icon)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    VStack(spacing: 12) {
                        TextField("Name der Karte", text: $name)
                            .textFieldStyle(TascherlTextFieldStyle())

                        TextField("Unternehmen", text: $company)
                            .textFieldStyle(TascherlTextFieldStyle())

                        TextField("Kategorie", text: $category)
                            .textFieldStyle(TascherlTextFieldStyle())

                        if mode != .screenshot {
                            TextField("Code / Token", text: $code)
                                .textFieldStyle(TascherlTextFieldStyle())
                        }
                    }

                    if mode == .screenshot {
                        VStack(spacing: 12) {
                            #if os(iOS)
                            if let screenshotImageData,
                               let uiImage = UIImage(data: screenshotImageData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 260)
                                    .clipShape(RoundedRectangle(cornerRadius: 22))
                                    .shadow(color: .black.opacity(0.18), radius: 12, y: 8)
                            } else {
                                screenshotPlaceholder
                            }
                            #else
                            screenshotPlaceholder
                            #endif

                            Button {
                                showScreenshotPicker = true
                            } label: {
                                Label(
                                    screenshotImageData == nil ? "Screenshot hinzufügen" : "Screenshot ändern",
                                    systemImage: "photo"
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .tascherlActionButton()
                        }
                    }

                    if mode == .barcode || mode == .qr {
                        Button {
                            showScanner = true
                        } label: {
                            Label("Code scannen", systemImage: "camera.viewfinder")
                                .frame(maxWidth: .infinity)
                        }
                        .tascherlActionButton()
                    }

                    if mode == .nfc {
                        Button {
                            nfcManager.beginScan()
                        } label: {
                            Label("NFC lesen", systemImage: "wave.3.right.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .tascherlActionButton()

                        if !nfcManager.lastResult.isEmpty {
                            Button {
                                code = nfcManager.lastResult
                            } label: {
                                Text("NFC Ergebnis übernehmen")
                                    .frame(maxWidth: .infinity)
                            }
                            .tascherlActionButton()
                        }
                    }

                    Button {
                        addCard()
                    } label: {
                        Text("Karte hinzufügen")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                canAdd
                                ? LinearGradient(
                                    colors: [
                                        TascherlTheme.matteYellow,
                                        Color(red: 0.62, green: 0.48, blue: 0.20)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                : LinearGradient(
                                    colors: [.gray.opacity(0.3)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                    }
                    .disabled(!canAdd)
                }
                .padding()
            }
        }
        .navigationBarHidden(true)
        .onChange(of: mode) {
            if mode != .nfc {
                nfcManager.lastResult = ""
            }

            if mode != .screenshot {
                screenshotImageData = nil
            }

            if mode == .screenshot {
                code = ""
            }
        }
        .sheet(isPresented: $showScanner) {
            CodeScannerView { scannedCode in
                code = scannedCode
                showScanner = false

                if mode == .qr {
                    mode = .qr
                } else {
                    mode = .barcode
                }

                impact()
            }
        }
        #if os(iOS)
        .sheet(isPresented: $showScreenshotPicker) {
            ScreenshotImagePicker { image in
                screenshotImageData = image.jpegData(compressionQuality: 0.88)
                impact()
            }
        }
        #endif
    }

    private var screenshotPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("Für spezielle Karten kannst du einen Screenshot hinzufügen.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    var canAdd: Bool {
        let hasName = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasCompany = !company.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasCode = !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        switch mode {
        case .barcode, .qr, .nfc:
            return hasName && hasCompany && hasCode

        case .screenshot:
            return hasName && hasCompany && screenshotImageData != nil
        }
    }

    private func addCard() {
        let brand = normalizeBrand(company)

        let finalType: TascherlCardType
        let finalRenderType: TascherlCard.CardRenderType

        switch mode {
        case .barcode:
            finalType = .barcode
            finalRenderType = .barcode

        case .qr:
            finalType = .qr
            finalRenderType = .qr

        case .nfc:
            finalType = .nfc
            finalRenderType = .barcode

        case .screenshot:
            finalType = .barcode
            finalRenderType = .image
        }

        let newCard = TascherlCard(
            name: name,
            company: company,
            brand: brand,
            type: finalType,
            category: category.isEmpty ? "Neue Karte" : category,
            info: finalRenderType == .image ? "Screenshot-Karte" : "Neu hinzugefügt",
            code: code,
            locationHint: "Noch keine Standortregel eingerichtet.",
            favorite: false,
            gradientStartHex: finalRenderType == .image
                ? "#C89A2B"
                : finalType == .nfc
                    ? "#F97316"
                    : finalType == .barcode
                        ? "#06B6D4"
                        : "#A855F7",
            gradientEndHex: finalRenderType == .image
                ? "#3A3A3A"
                : finalType == .nfc
                    ? "#B91C1C"
                    : finalType == .barcode
                        ? "#1D4ED8"
                        : "#C026D3",
            walletPassURL: nil,
            renderType: finalRenderType,
            imageData: screenshotImageData
        )

        onAdd(newCard)

        name = ""
        company = ""
        code = ""
        category = "Neue Karte"
        mode = .barcode
        screenshotImageData = nil
        nfcManager.lastResult = ""
    }
}
extension View {
    func tascherlActionButton() -> some View {
        self
            .font(.subheadline.bold())
            .foregroundStyle(.primary)
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

struct TascherlTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .foregroundStyle(.primary)
            .tint(TascherlTheme.matteYellow)
    }
}
// MARK: - Scanner

#if os(iOS)
struct CodeScannerView: UIViewControllerRepresentable {
    var onScan: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.onScan = onScan
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}
}

final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
        setupOverlay()
    }

    private func setupCamera() {
        guard let device = AVCaptureDevice.default(for: .video) else { return }

        do {
            let input = try AVCaptureDeviceInput(device: device)

            if session.canAddInput(input) {
                session.addInput(input)
            }

            let output = AVCaptureMetadataOutput()

            if session.canAddOutput(output) {
                session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: .main)
                output.metadataObjectTypes = [
                    .qr,
                    .ean8,
                    .ean13,
                    .code128,
                    .code39,
                    .upce,
                    .pdf417,
                    .aztec,
                    .dataMatrix
                ]
            }

            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            preview.frame = view.bounds
            view.layer.addSublayer(preview)
            previewLayer = preview

            DispatchQueue.global(qos: .userInitiated).async {
                self.session.startRunning()
            }
        } catch {
            print("Camera setup failed:", error)
        }
    }

    private func setupOverlay() {
        let label = UILabel()
        label.text = "QR oder Barcode scannen"
        label.textColor = .white
        label.font = .boldSystemFont(ofSize: 18)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        let scanArea = UIView()
        scanArea.layer.borderColor = UIColor.systemPink.withAlphaComponent(0.85).cgColor
        scanArea.layer.borderWidth = 2
        scanArea.layer.cornerRadius = 32
        scanArea.backgroundColor = UIColor.clear
        scanArea.translatesAutoresizingMaskIntoConstraints = false

        let scanLine = UIView()
        scanLine.backgroundColor = UIColor.systemPink.withAlphaComponent(0.85)
        scanLine.layer.cornerRadius = 2
        scanLine.translatesAutoresizingMaskIntoConstraints = false

        let hint = UILabel()
        hint.text = "Positioniere QR-Code oder Barcode im Bereich"
        hint.textColor = UIColor.white.withAlphaComponent(0.72)
        hint.font = .systemFont(ofSize: 13, weight: .medium)
        hint.textAlignment = .center
        hint.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(scanArea)
        view.addSubview(scanLine)
        view.addSubview(label)
        view.addSubview(hint)

        NSLayoutConstraint.activate([
            scanArea.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            scanArea.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            scanArea.widthAnchor.constraint(equalToConstant: 300),
            scanArea.heightAnchor.constraint(equalToConstant: 170),

            scanLine.centerXAnchor.constraint(equalTo: scanArea.centerXAnchor),
            scanLine.centerYAnchor.constraint(equalTo: scanArea.centerYAnchor),
            scanLine.widthAnchor.constraint(equalToConstant: 230),
            scanLine.heightAnchor.constraint(equalToConstant: 3),

            label.bottomAnchor.constraint(equalTo: scanArea.topAnchor, constant: -24),
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            hint.topAnchor.constraint(equalTo: scanArea.bottomAnchor, constant: 18),
            hint.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hint.widthAnchor.constraint(equalToConstant: 300)
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue
        else { return }

        session.stopRunning()
        onScan?(value)
    }
}
#else
struct CodeScannerView: View {
    var onScan: (String) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.viewfinder")
                .font(.largeTitle)
            Text("Scanner ist nur auf iPhone/iPad verfügbar.")
        }
        .padding()
    }
}
#endif

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var store: CardStore

    @AppStorage("tascherl_darkMode") private var darkMode = true
    @AppStorage("tascherl_faceIdEnabled") private var faceIdEnabled = true
    @AppStorage("tascherl_locationEnabled") private var locationEnabled = true
    @AppStorage("tascherl_offlineStoreDataEnabled") private var offlineStoreDataEnabled = false
    @AppStorage("tascherl_notifications") private var notifications = true
    @AppStorage("tascherl_secureCloud") private var secureCloud = true

    var body: some View {
        NavigationStack {
            ZStack {
                BackgroundView()

                ScrollView {
                    VStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Einstellungen")
                                .font(.largeTitle.bold())
                                .foregroundStyle(.primary)

                            Text("Tascherl konfigurieren")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 14)

                        SettingsToggleRow(icon: "sparkles", title: "Dark Mode", description: "Schaltet das App-Design um.", value: $darkMode)

                        SettingsToggleRow(icon: "lock.fill", title: "Face ID / App-Sperre", description: "Schützt deine Karten beim App-Start.", value: $faceIdEnabled)

                        SettingsToggleRow(icon: "location.fill", title: "Smart Cards per Standort", description: "Schlägt automatisch passende Karten vor.", value: $locationEnabled)
                        
                        SettingsToggleRow(
                            icon: "arrow.down.circle.fill",
                            title: "Standortdaten offline speichern",
                            description: "Speichert gefundene Filialen lokal, damit Vorschläge auch offline funktionieren.",
                            value: $offlineStoreDataEnabled
                        )

                        SettingsToggleRow(icon: "bell.fill", title: "Benachrichtigungen", description: "Demo-Schalter für Hinweise.", value: $notifications)

                        SettingsToggleRow(icon: "checkmark.shield.fill", title: "Sichere Cloud", description: "Zeigt Datenschutz-Hinweise an.", value: $secureCloud)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("App Status")
                                .font(.headline)
                                .foregroundStyle(.primary)

                            HStack {
                                StatusPill(text: "\(store.cards.count) Karten")
                                StatusPill(text: "QR aktiv")
                            }

                            HStack {
                                StatusPill(text: "Barcode Scan")
                                StatusPill(text: "NFC Demo")
                            }
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 24))

                        Button(role: .destructive) {
                            store.resetDemo()
                        } label: {
                            Label("Alle Karten löschen", systemImage: "trash.fill")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.red.opacity(0.18))
                                .clipShape(RoundedRectangle(cornerRadius: 20))
                        }
                    }
                    .padding()
                }
            }
            .navigationBarHidden(true)
        }
    }
}

struct SettingsToggleRow: View {
    let icon: String
    let title: String
    let description: String
    @Binding var value: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .foregroundStyle(.primary)
                .frame(width: 42, height: 42)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: $value)
                .labelsHidden()
                .tint(.green)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

struct StatusPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color(.tertiarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Location

final class TascherlLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    @Published var lastLocation: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
    }

    func request() {
        #if os(iOS)
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
        #elseif os(macOS)
        manager.requestLocation()
        #endif
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastLocation = locations.first
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location failed:", error.localizedDescription)
    }
}
