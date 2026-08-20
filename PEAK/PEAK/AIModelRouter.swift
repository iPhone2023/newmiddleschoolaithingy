import Foundation
import Security
import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

enum ModelRouter {
    static var providerName: String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable {
            return "Apple Intelligence"
        }
        #endif
        return GeminiKeychain.apiKey == nil ? "Set up Gemini" : "Gemini"
    }

    static func recommendation(
        for context: RecommendationContext,
        fallback: OutfitRecommendation
    ) async -> OutfitRecommendation? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *),
           SystemLanguageModel.default.isAvailable,
           let recommendation = await AIStylist.recommendation(for: context, fallback: fallback) {
            return recommendation
        }
        #endif

        guard let apiKey = GeminiKeychain.apiKey else {
            return nil
        }

        return await GeminiStylist.recommendation(
            for: context,
            fallback: fallback,
            apiKey: apiKey
        )
    }
}

enum GeminiKeychain {
    private static let service = "com.peak.ai"
    private static let account = "gemini-api-key"

    static var apiKey: String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else {
            return nil
        }
        return key
    }

    static func save(_ apiKey: String) {
        let data = Data(apiKey.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes = [kSecValueData as String: data]

        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) != errSecSuccess {
            var item = query
            item[kSecValueData as String] = data
            SecItemAdd(item as CFDictionary, nil)
        }
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum GeminiStylist {
    private static let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/interactions")!

    static func recommendation(
        for context: RecommendationContext,
        fallback: OutfitRecommendation,
        apiKey: String
    ) async -> OutfitRecommendation? {
        let prompt = """
        You are a concise personal stylist. Recommend one outfit using only the available wardrobe.
        Consider the weather and calendar events. Respond in exactly three short paragraphs:
        outfit title, comma-separated items, and a one-sentence reason.
        (context.summary)
        """

        let requestBody = GeminiRequest(
            model: "gemini-3.7-flash",
            input: prompt,
            systemInstruction: "Only recommend clothing explicitly present in the available wardrobe."
        )

        do {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
            request.httpBody = try JSONEncoder().encode(requestBody)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  200..<300 ~= httpResponse.statusCode else {
                return nil
            }

            let text = try JSONDecoder().decode(GeminiResponse.self, from: data).outputText
            let lines = text
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            guard lines.count >= 3 else { return nil }

            return OutfitRecommendation(
                title: lines[0],
                items: lines[1].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) },
                reason: lines[2],
                tags: fallback.tags + ["Gemini"],
                symbolName: fallback.symbolName
            )
        } catch {
            return nil
        }
    }
}

private struct GeminiRequest: Encodable {
    let model: String
    let input: String
    let systemInstruction: String

    enum CodingKeys: String, CodingKey {
        case model
        case input
        case systemInstruction = "system_instruction"
    }
}

private struct GeminiResponse: Decodable {
    let steps: [Step]

    var outputText: String {
        steps
            .reversed()
            .first(where: { $0.type == "model_output" })?
            .content
            .compactMap(\.text)
            .joined(separator: "\n") ?? ""
    }

    struct Step: Decodable {
        let type: String
        let content: [Content]
    }

    struct Content: Decodable {
        let type: String
        let text: String?
    }
}

struct GeminiSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Gemini API key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Your key is stored only in this device’s Keychain. Gemini receives your calendar, weather, and available-wardrobe context when Apple Intelligence is unavailable.")
                }

                if GeminiKeychain.apiKey != nil {
                    Section {
                        Button("Remove Gemini key", role: .destructive) {
                            GeminiKeychain.delete()
                            apiKey = ""
                        }
                    }
                }
            }
            .navigationTitle("Gemini fallback")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        GeminiKeychain.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                apiKey = GeminiKeychain.apiKey ?? ""
            }
        }
    }
}
