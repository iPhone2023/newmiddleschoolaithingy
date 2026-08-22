import SwiftUI
import EventKit
import CoreLocation
import WeatherKit
#if canImport(FoundationModels)
import FoundationModels
#endif

@main struct AIApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var wardrobe = WardrobeItem.sampleItems
    @State private var events = AgendaEvent.sampleEvents
    @State private var weather = WeatherContext()
    @State private var recommendation = OutfitRecommendation.default
    @State private var isRefreshingCalendar = false
    @State private var isRefreshingWeather = false
    @State private var locationProvider = LocationProvider()
    @State private var isGeneratingRecommendation = false
    @State private var isPresentingAddItem = false
    @State private var isPresentingGeminiSetup = false
    @State private var calendarMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    recommendationCard
                    weatherCard
                    agendaSection
                    wardrobeSection
                }
                .padding()
                .padding(.bottom, 28)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Daylight")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        isPresentingGeminiSetup = true
                    } label: {
                        Label("AI provider", systemImage: "cpu")
                    }

                    Button {
                        isPresentingAddItem = true
                    } label: {
                        Label("Add clothing", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isPresentingAddItem) {
                AddWardrobeItemView { item in
                    wardrobe.append(item)
                    refreshRecommendation()
                }
            }
            .sheet(isPresented: $isPresentingGeminiSetup) {
                GeminiSetupView()
            }
            .task {
                refreshRecommendation()
            }
            .alert("Calendar", isPresented: Binding(
                get: { calendarMessage != nil },
                set: { if !$0 { calendarMessage = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(calendarMessage ?? "")
            }
        }
        .tint(.indigo)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Dress for the day ahead")
                .font(.largeTitle.bold())
            Text("Your schedule, weather, and wardrobe—considered together.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recommendationCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Today’s outfit", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                if isGeneratingRecommendation {
                    ProgressView()
                        .tint(.white)
                } else {
                    Button("Refresh", action: refreshRecommendation)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }

            HStack(spacing: 8) {
                Label(ModelRouter.providerName, systemImage: "cpu")
                    .font(.caption.weight(.semibold))
                Text("Personalized for today")
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(.white.opacity(0.82))

            HStack(alignment: .top, spacing: 16) {
                Image(systemName: recommendation.symbolName)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.indigo)
                    .frame(width: 64, height: 64)
                    .background(.white, in: RoundedRectangle(cornerRadius: 20))
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 3)

                VStack(alignment: .leading, spacing: 6) {
                    Text(cleanedRecommendationText(recommendation.title))
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                    Text(cleanedRecommendationText(recommendation.items.joined(separator: " · ")))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.82))
                }
                .padding(.top, 3)
            }

            Divider()
                .overlay(.white.opacity(0.28))

            Text(cleanedRecommendationText(recommendation.reason))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.9))

            HStack(spacing: 8) {
                ForEach(recommendation.tags, id: \.self) { tag in
                    Text(cleanedRecommendationText(tag))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.16), in: Capsule())
                }
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [.indigo, .purple, .blue],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 26)
        )
        .shadow(color: .indigo.opacity(0.25), radius: 18, y: 8)
    }

    private func cleanedRecommendationText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "_", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var weatherCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Outside", systemImage: "cloud.sun.fill")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await loadWeather() }
                } label: {
                    if isRefreshingWeather {
                        ProgressView()
                    } else {
                        Text("Refresh")
                    }
                }
                .font(.subheadline.weight(.semibold))
                .disabled(isRefreshingWeather)
            }

            HStack(spacing: 16) {
                Image(systemName: weather.symbolName)
                    .font(.system(size: 34))
                    .symbolRenderingMode(.multicolor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(weather.temperature)°")
                        .font(.title.bold())
                    Text(weather.condition)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Stepper("Temp", value: $weather.temperature, in: 35...100)
                    .labelsHidden()
                    .accessibilityLabel("Temperature")
            }

            Picker("Conditions", selection: $weather.condition) {
                ForEach(WeatherContext.conditions, id: \.self) { condition in
                    Text(condition).tag(condition)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: weather.condition) {
                refreshRecommendation()
            }
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
    }

    private var agendaSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Your day", systemImage: "calendar")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await loadCalendar() }
                } label: {
                    if isRefreshingCalendar {
                        ProgressView()
                    } else {
                        Text("Sync Calendar")
                    }
                }
                .font(.subheadline.weight(.semibold))
                .disabled(isRefreshingCalendar)
            }

            if events.isEmpty {
                ContentUnavailableView(
                    "No events today",
                    systemImage: "calendar.badge.checkmark",
                    description: Text("Sync your calendar to tailor the dress code.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                ForEach(events) { event in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(event.color)
                            .frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title)
                                .font(.subheadline.weight(.semibold))
                            Text(event.timeRange)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(event.dressCode)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(.background, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    private var wardrobeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Available now", systemImage: "tshirt")
                    .font(.headline)
                Spacer()
                Text("\(wardrobe.count) pieces")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(wardrobe) { item in
                    WardrobeItemCard(item: item) {
                        wardrobe.removeAll { $0.id == item.id }
                        refreshRecommendation()
                    }
                }
            }
        }
    }

    private func refreshRecommendation() {
        isGeneratingRecommendation = true
        let context = RecommendationContext(weather: weather, events: events, wardrobe: wardrobe)

        Task {
            let localRecommendation = OutfitRecommender.makeRecommendation(for: context)
            recommendation = localRecommendation

            if let aiRecommendation = await ModelRouter.recommendation(
                for: context,
                fallback: localRecommendation
            ) {
                recommendation = aiRecommendation
            }

            isGeneratingRecommendation = false
        }
    }

    private func loadWeather() async {
        isRefreshingWeather = true
        defer { isRefreshingWeather = false }

        do {
            let location = try await locationProvider.currentLocation()
            let forecast = try await WeatherService.shared.weather(for: location)
            let current = forecast.currentWeather
            weather.temperature = Int(current.temperature.converted(to: .fahrenheit).value.rounded())
            weather.condition = WeatherContext.condition(for: current.symbolName)
            refreshRecommendation()
        } catch {
            calendarMessage = "Weather couldn’t be refreshed. Check your location permission and WeatherKit capability, then try again."
        }
    }

    private func loadCalendar() async {
        isRefreshingCalendar = true
        defer { isRefreshingCalendar = false }

        do {
            let loadedEvents = try await CalendarService.todayEvents()
            events = loadedEvents
            refreshRecommendation()
        } catch {
            calendarMessage = "Calendar access wasn’t available. You can still use the sample schedule and update your outfit recommendation."
        }
    }
}

struct WardrobeItemCard: View {
    let item: WardrobeItem
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: item.symbolName)
                    .font(.title2)
                    .foregroundStyle(item.color)
                Spacer()
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .accessibilityLabel("Remove \(item.name)")
            }
            Text(item.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(item.category)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .leading)
        .background(item.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
    }
}

struct AddWardrobeItemView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var category = "Top"
    let onAdd: (WardrobeItem) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("Item name", text: $name)
                Picker("Category", selection: $category) {
                    ForEach(WardrobeItem.categories, id: \.self) { category in
                        Text(category)
                    }
                }
            }
            .navigationTitle("Add to wardrobe")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(WardrobeItem(name: name, category: category))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct WardrobeItem: Identifiable {
    let id = UUID()
    let name: String
    let category: String

    static let categories = ["Top", "Bottom", "Layer", "Dress", "Shoes", "Accessory"]

    var symbolName: String {
        switch category {
        case "Top": "tshirt.fill"
        case "Bottom": "figure.walk"
        case "Layer": "jacket.fill"
        case "Dress": "figure.dress.line.vertical.figure"
        case "Shoes": "shoe.2.fill"
        default: "bag.fill"
        }
    }

    var color: Color {
        switch name.lowercased() {
        case let name where name.contains("navy"): .indigo
        case let name where name.contains("white"): .gray
        case let name where name.contains("denim"): .blue
        case let name where name.contains("black"): .black
        default: .orange
        }
    }

    static let sampleItems = [
        WardrobeItem(name: "Navy overshirt", category: "Layer"),
        WardrobeItem(name: "White tee", category: "Top"),
        WardrobeItem(name: "Dark denim", category: "Bottom"),
        WardrobeItem(name: "White sneakers", category: "Shoes")
    ]
}

struct AgendaEvent: Identifiable {
    let id = UUID()
    let title: String
    let startDate: Date
    let endDate: Date
    let dressCode: String
    let color: Color

    var timeRange: String {
        startDate.formatted(date: .omitted, time: .shortened) + "–" + endDate.formatted(date: .omitted, time: .shortened)
    }

    static let sampleEvents = [
        AgendaEvent(title: "Design review", startDate: .now.addingTimeInterval(60 * 60), endDate: .now.addingTimeInterval(2 * 60 * 60), dressCode: "Smart casual", color: .indigo),
        AgendaEvent(title: "Dinner with friends", startDate: .now.addingTimeInterval(7 * 60 * 60), endDate: .now.addingTimeInterval(9 * 60 * 60), dressCode: "Relaxed", color: .orange)
    ]
}

struct WeatherContext {
    var temperature = 68
    var condition = "Partly cloudy"

    static let conditions = ["Sunny", "Partly cloudy", "Rainy", "Windy", "Snowy"]

    static func condition(for symbolName: String) -> String {
        if symbolName.contains("rain") || symbolName.contains("drizzle") || symbolName.contains("thunder") {
            return "Rainy"
        }
        if symbolName.contains("snow") || symbolName.contains("sleet") {
            return "Snowy"
        }
        if symbolName.contains("wind") {
            return "Windy"
        }
        if symbolName.contains("sun") && !symbolName.contains("cloud") {
            return "Sunny"
        }
        return "Partly cloudy"
    }

    var symbolName: String {
        switch condition {
        case "Sunny": "sun.max.fill"
        case "Rainy": "cloud.rain.fill"
        case "Windy": "wind"
        case "Snowy": "snowflake"
        default: "cloud.sun.fill"
        }
    }
}

struct OutfitRecommendation {
    let title: String
    let items: [String]
    let reason: String
    let tags: [String]
    let symbolName: String

    static let `default` = OutfitRecommendation(
        title: "Navy overshirt + dark denim",
        items: ["White tee", "White sneakers"],
        reason: "A versatile smart-casual layer for a mild day and your design review.",
        tags: ["Calendar-aware", "Mild weather"],
        symbolName: "sparkles"
    )
}

struct RecommendationContext {
    let weather: WeatherContext
    let events: [AgendaEvent]
    let wardrobe: [WardrobeItem]

    var summary: String {
        let clothing = wardrobe.map { "\($0.name) (\($0.category))" }.joined(separator: ", ")
        let agenda = events.map { "\($0.title), \($0.dressCode)" }.joined(separator: "; ")
        return "Weather: \(weather.condition), \(weather.temperature)°F. Events: \(agenda). Available wardrobe: \(clothing)."
    }
}

enum OutfitRecommender {
    static func makeRecommendation(for context: RecommendationContext) -> OutfitRecommendation {
        let hasProfessionalEvent = context.events.contains {
            $0.dressCode.localizedCaseInsensitiveContains("smart") || $0.title.localizedCaseInsensitiveContains("review")
        }
        let isCold = context.weather.temperature < 60 || context.weather.condition == "Windy"
        let isWet = context.weather.condition == "Rainy" || context.weather.condition == "Snowy"

        let layer = context.wardrobe.first { $0.category == "Layer" }
        let top = context.wardrobe.first { $0.category == "Top" }
        let bottom = context.wardrobe.first { $0.category == "Bottom" }
        let shoes = context.wardrobe.first { $0.category == "Shoes" }
        let selected = [layer, top, bottom, shoes].compactMap { $0?.name }

        let title = selected.prefix(2).joined(separator: " + ")
        var tags = [hasProfessionalEvent ? "Smart casual" : "Everyday"]
        tags.append(isWet ? "Rain-ready" : isCold ? "Layered" : "Mild weather")

        return OutfitRecommendation(
            title: title.isEmpty ? "Build a look from your wardrobe" : title,
            items: Array(selected.dropFirst(2)),
            reason: isWet
                ? "Keep the outfit practical for wet conditions and polished enough for your schedule."
                : hasProfessionalEvent
                    ? "This balances your smart-casual event with a comfortable, weather-ready base."
                    : "A comfortable option selected from the pieces marked available today.",
            tags: tags,
            symbolName: isWet ? "umbrella.fill" : hasProfessionalEvent ? "briefcase.fill" : "sun.max.fill"
        )
    }
}

@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
    }

    func currentLocation() async throws -> CLLocation {
        guard CLLocationManager.locationServicesEnabled() else {
            throw LocationError.unavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                manager.requestLocation()
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .denied, .restricted:
                self.continuation = nil
                continuation.resume(throwing: LocationError.permissionDenied)
            @unknown default:
                self.continuation = nil
                continuation.resume(throwing: LocationError.unavailable)
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse else {
            return
        }
        manager.requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(throwing: error)
    }

    private enum LocationError: Error {
        case unavailable
        case permissionDenied
    }
}

enum CalendarService {
    static func todayEvents() async throws -> [AgendaEvent] {
        let store = EKEventStore()
        guard try await store.requestFullAccessToEvents() else {
            return []
        }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? .now
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)

        return store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .map {
                AgendaEvent(
                    title: $0.title ?? "Untitled event",
                    startDate: $0.startDate,
                    endDate: $0.endDate,
                    dressCode: inferredDressCode(for: $0.title ?? ""),
                    color: .indigo
                )
            }
    }

    private static func inferredDressCode(for title: String) -> String {
        let formalKeywords = ["interview", "client", "presentation", "review", "meeting"]
        return formalKeywords.contains { title.localizedCaseInsensitiveContains($0) } ? "Smart casual" : "Flexible"
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
enum AIStylist {
    static func recommendation(
        for context: RecommendationContext,
        fallback: OutfitRecommendation
    ) async -> OutfitRecommendation? {
        guard SystemLanguageModel.default.isAvailable else {
            return nil
        }

        let prompt = """
        You are a concise personal stylist. Recommend one outfit using only the available wardrobe.
        Consider the weather and calendar events. Respond in exactly three short paragraphs:
        outfit title, comma-separated items, and a one-sentence reason.
        \(context.summary)
        """

        do {
            let response = try await LanguageModelSession().respond(to: prompt)
            let lines = response.content
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            guard lines.count >= 3 else { return nil }
            return OutfitRecommendation(
                title: lines[0],
                items: lines[1].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) },
                reason: lines[2],
                tags: fallback.tags + ["On-device AI"],
                symbolName: fallback.symbolName
            )
        } catch {
            return nil
        }
    }
}
#endif

#Preview {
    ContentView()
}

    
