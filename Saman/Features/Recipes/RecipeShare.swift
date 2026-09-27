import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// On-device share for a recipe that is already saved. The text is the share
/// that every destination can take. When rendering succeeds, a PNG card is a
/// second representation for destinations that want an image.
///
/// A later public page (`samanpantry.com/r/<id>`) can be added by appending
/// that URL inside `RecipeShareText.format`. This version does not add a
/// universal link or an iOS Share Extension.
enum RecipeShareText {
    static let appStoreURL = "https://apps.apple.com/us/app/id6761982454"
    static let footerTitle = "Saved with Samaan Pantry"

    static func format(
        title: String,
        attribution: String?,
        ingredients: [ExtractedIngredient],
        steps: [String],
        notes: String?,
        transcript: String?
    ) -> String {
        var lines: [String] = []
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append(trimmedTitle.isEmpty ? "Recipe" : trimmedTitle)

        if let attribution = attribution?.trimmingCharacters(in: .whitespacesAndNewlines), !attribution.isEmpty {
            lines.append("from \(attribution)")
        }
        lines.append("")

        if !ingredients.isEmpty {
            lines.append("Ingredients")
            for ingredient in ingredients {
                lines.append("• \(ingredientLine(ingredient))")
            }
            lines.append("")
        }

        if !steps.isEmpty {
            lines.append("How to make it")
            for (index, step) in steps.enumerated() {
                lines.append("\(index + 1). \(step)")
            }
            lines.append("")
        }

        if let notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            lines.append("Notes")
            lines.append(notes)
            lines.append("")
        }

        if ingredients.isEmpty && steps.isEmpty {
            let fallback = transcript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !fallback.isEmpty {
                lines.append(fallback)
                lines.append("")
            }
        }

        lines.append(footerTitle)
        lines.append(appStoreURL)
        return lines.joined(separator: "\n")
    }

    static func ingredientLine(_ ingredient: ExtractedIngredient) -> String {
        let name = ingredient.ingredient.trimmingCharacters(in: .whitespacesAndNewlines)
        let phrase = ingredient.originalPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        var line = name.isEmpty ? phrase : name
        if ingredient.amountLabel != "—" {
            line += " — \(ingredient.amountLabel)"
        }
        if !phrase.isEmpty && phrase.caseInsensitiveCompare(name) != .orderedSame {
            if !name.isEmpty {
                line += " (\(phrase))"
            }
        }
        return line
    }
}

struct RecipeSharePayload: Transferable, Sendable {
    let text: String
    let pngData: Data

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.text)
        DataRepresentation(exportedContentType: .png) { payload in
            payload.pngData
        }
    }
}

struct RecipeShareOffer {
    let text: String
    let imagePayload: RecipeSharePayload?
    let preview: Image

    @MainActor
    static func make(
        title: String,
        attribution: String?,
        ingredients: [ExtractedIngredient],
        steps: [String],
        notes: String?,
        transcript: String?
    ) -> RecipeShareOffer {
        let text = RecipeShareText.format(
            title: title,
            attribution: attribution,
            ingredients: ingredients,
            steps: steps,
            notes: notes,
            transcript: transcript
        )
        guard let rendered = RecipeShareImage.render(
            title: title,
            attribution: attribution,
            ingredients: ingredients,
            steps: steps,
            transcript: transcript
        ) else {
            return RecipeShareOffer(text: text, imagePayload: nil, preview: Image(systemName: "fork.knife"))
        }
        return RecipeShareOffer(
            text: text,
            imagePayload: RecipeSharePayload(text: text, pngData: rendered.data),
            preview: Image(uiImage: rendered.image)
        )
    }
}

private enum RecipeShareImage {
    struct Rendered {
        let image: UIImage
        let data: Data
    }

    @MainActor
    static func render(
        title: String,
        attribution: String?,
        ingredients: [ExtractedIngredient],
        steps: [String],
        transcript: String?
    ) -> Rendered? {
        let card = RecipeShareCard(
            title: title,
            attribution: attribution,
            ingredients: ingredients,
            steps: steps,
            transcript: transcript
        )
        .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        renderer.isOpaque = true
        guard let image = renderer.uiImage, let data = image.pngData() else { return nil }
        return Rendered(image: image, data: data)
    }
}

private struct RecipeShareCard: View {
    let title: String
    let attribution: String?
    let ingredients: [ExtractedIngredient]
    let steps: [String]
    let transcript: String?

    private var shownIngredients: [ExtractedIngredient] { Array(ingredients.prefix(8)) }
    private var shownSteps: [String] { Array(steps.prefix(6)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Recipe" : title)
                .font(.custom("CormorantGaramond-Bold", size: 28))
                .foregroundStyle(Color.inkKohl)
                .fixedSize(horizontal: false, vertical: true)

            if let attribution = attribution?.trimmingCharacters(in: .whitespacesAndNewlines), !attribution.isEmpty {
                Text("from \(attribution)")
                    .font(.system(size: 13).italic())
                    .foregroundStyle(Color.brandSaag)
            }

            if !shownIngredients.isEmpty {
                Text("INGREDIENTS")
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(0.6)
                    .foregroundStyle(Color.inkKohlSoft)
                ForEach(Array(shownIngredients.enumerated()), id: \.offset) { _, ingredient in
                    Text(RecipeShareText.ingredientLine(ingredient))
                        .font(.system(size: 14))
                        .foregroundStyle(Color.inkKohl)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if ingredients.count > shownIngredients.count {
                    Text("+\(ingredients.count - shownIngredients.count) more")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.inkKohlSoft)
                }
            }

            if !shownSteps.isEmpty {
                Text("HOW TO MAKE IT")
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(0.6)
                    .foregroundStyle(Color.inkKohlSoft)
                    .padding(.top, 4)
                ForEach(Array(shownSteps.enumerated()), id: \.offset) { index, step in
                    Text("\(index + 1). \(step)")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.inkKohl)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if steps.count > shownSteps.count {
                    Text("+\(steps.count - shownSteps.count) more steps")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.inkKohlSoft)
                }
            }

            if shownIngredients.isEmpty && shownSteps.isEmpty,
               let transcript = transcript?.trimmingCharacters(in: .whitespacesAndNewlines),
               !transcript.isEmpty {
                Text(transcript)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.inkKohl)
                    .lineLimit(8)
            }

            Rectangle()
                .fill(Color.brandSaag.opacity(0.35))
                .frame(height: 1)
                .padding(.top, 6)

            Text(RecipeShareText.footerTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.brandSaag)
            Text(RecipeShareText.appStoreURL)
                .font(.system(size: 11))
                .foregroundStyle(Color.inkKohlSoft)
                .lineLimit(2)
        }
        .padding(22)
        .frame(width: 360, alignment: .topLeading)
        .background(Color.surfaceDoodh)
    }
}
