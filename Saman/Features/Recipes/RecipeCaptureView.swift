import SwiftUI
import SwiftData

struct RecipeCaptureView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appEnv)       private var appEnv
    @Environment(\.dismiss)      private var dismiss
    @Environment(\.openURL)      private var openURL

    /// One-time consent before any recipe text leaves the device (App Review
    /// 5.1.1 / 5.1.2(i): disclose third-party AI processing and get permission).
    @AppStorage(AIProcessingConsent.storageKey) private var hasAIConsent = false
    @State private var showAIConsent = false

    @State private var transcript    = ""
    @State private var recipeLink    = ""
    @State private var recipeTitle   = ""
    @State private var recipeSource  = ""
    @State private var selections:   [IngredientSelection] = []
    @State private var extractedJSON = ""
    @State private var phase:        Phase = .idle
    @State private var showError     = false
    @State private var errorTitle    = "Extraction failed"
    @State private var errorMessage  = ""
    @State private var inlineError: String?
    @State private var extractingFromLink = false
    @State private var capturedSource = ""
    @State private var capturedSourceKind: RecipeSourceKind = .transcript
    @State private var resumeExtractAfterAuth = false
    @StateObject private var transcriber = RecipeAudioTranscriber()
    @State private var showAudioPicker = false
    @State private var transcribingAudio = false
    @State private var resumeFromAudio = false
    @State private var captureTask: Task<Void, Never>?
    @State private var captureIsActive = true
    @State private var captureGeneration = UUID()

    enum Phase { case idle, extracting, reviewing, adding, done }

    struct IngredientSelection: Identifiable {
        let id         = UUID()
        var ingredient: ExtractedIngredient
        var isSelected  = true
    }

    /// Screenshot / UI-test entry: skip the live extract-recipe call and open
    /// the review screen with canned ingredients (including "haldi — andaza se").
    init(demoReview: ExtractedRecipe? = nil) {
        if let demoReview {
            _phase = State(initialValue: .reviewing)
            _recipeTitle = State(initialValue: demoReview.title)
            _recipeSource = State(initialValue: demoReview.attribution ?? "")
            _selections = State(initialValue: demoReview.ingredients.map { IngredientSelection(ingredient: $0) })
            _transcript = State(initialValue: ScreenshotDemoKitchen.karahiTranscript)
            if let data = try? JSONEncoder().encode(demoReview),
               let json = String(data: data, encoding: .utf8) {
                _extractedJSON = State(initialValue: json)
            } else {
                _extractedJSON = State(initialValue: "")
            }
        } else {
            _phase = State(initialValue: .idle)
            _recipeTitle = State(initialValue: "")
            _recipeSource = State(initialValue: "")
            _selections = State(initialValue: [])
            _transcript = State(initialValue: "")
            _extractedJSON = State(initialValue: "")
        }
        _showError = State(initialValue: false)
        _errorTitle = State(initialValue: "Extraction failed")
        _errorMessage = State(initialValue: "")
        _inlineError = State(initialValue: nil)
        _extractingFromLink = State(initialValue: false)
        _capturedSource = State(initialValue: "")
        _capturedSourceKind = State(initialValue: .transcript)
        _recipeLink = State(initialValue: "")
        _resumeExtractAfterAuth = State(initialValue: false)
        _transcriber = StateObject(wrappedValue: RecipeAudioTranscriber())
        _showAudioPicker = State(initialValue: false)
        _transcribingAudio = State(initialValue: false)
        _resumeFromAudio = State(initialValue: false)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.surfaceDoodh.ignoresSafeArea()
                switch phase {
                case .idle:                idleContent
                case .extracting, .adding: loadingContent
                case .reviewing:           reviewContent
                case .done:                doneContent
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(navTitle)
                        .font(.cormorant(size: 20))
                        .foregroundStyle(Color.inkKohl)
                }
                ToolbarItem(placement: .cancellationAction) {
                    if phase != .done {
                        Button("Cancel") {
                            cancelCapture()
                            resumeExtractAfterAuth = false
                            resumeFromAudio = false
                            dismiss()
                        }
                            .foregroundStyle(Color.brandSaag)
                    }
                }
            }
            .alert(errorTitle, isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
            .fullScreenCover(isPresented: Binding(
                get: { appEnv.isAuthPresented },
                set: { appEnv.isAuthPresented = $0 }
            )) {
                AuthView()
            }
            .onChange(of: appEnv.auth.isSignedIn) { _, signedIn in
                if signedIn { resumePendingExtraction() }
            }
            .onChange(of: appEnv.isAuthPresented) { _, presented in
                if !presented && !appEnv.auth.isSignedIn {
                    resumeExtractAfterAuth = false
                    resumeFromAudio = false
                } else if !presented {
                    resumePendingExtraction()
                }
            }
            .onChange(of: recipeLink) { _, _ in inlineError = nil }
            .onChange(of: transcript) { _, _ in inlineError = nil }
            .fileImporter(
                isPresented: $showAudioPicker,
                allowedContentTypes: RecipeAudioFile.acceptedTypes,
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    startCaptureTask { await transcribePickedFile(url) }
                case .failure:
                    presentError(
                        "Couldn't open that recording. Try another audio file, or record it in the app.",
                        title: "Couldn't open the recording"
                    )
                }
            }
            .onAppear {
                captureIsActive = true
                resumePendingExtraction()
            }
            .onDisappear { cancelCapture() }
        }
    }

    private var navTitle: String {
        switch phase {
        case .idle:       return "Capture Recipe"
        case .extracting: return transcribingAudio ? "Transcribing…" : (extractingFromLink ? "Opening…" : "Reading…")
        case .reviewing:  return "Review"
        case .adding:     return "Saving…"
        case .done:       return "Done"
        }
    }

    // MARK: - Idle

    private var canExtract: Bool {
        !recipeLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var idleContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Record it, paste a link, or paste the words.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.inkKohl)
                        Text("YouTube, a recipe page, or Instagram.\nOr say the recipe. Code-switched, andaza and all.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.inkKohlSoft)
                    }
                    .padding(.horizontal, Samaan.Space.md)
                    .padding(.top, Samaan.Space.md)
                    .padding(.bottom, 12)

                    audioCapture
                        .padding(.horizontal, Samaan.Space.md)

                    HStack(spacing: 10) {
                        Rectangle().frame(height: 1).foregroundStyle(Color.borderAkhrotSoft.opacity(0.6))
                        Text("or paste a link")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.inkKohlSoft)
                            .fixedSize()
                        Rectangle().frame(height: 1).foregroundStyle(Color.borderAkhrotSoft.opacity(0.6))
                    }
                    .padding(.horizontal, Samaan.Space.md)
                    .padding(.vertical, 14)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("PASTE A LINK")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.inkKohlSoft)
                            .kerning(0.8)
                        TextField("YouTube, a recipe site, or Instagram", text: $recipeLink)
                            .font(.system(size: 15))
                            .foregroundStyle(Color.inkKohl)
                            .textFieldStyle(.plain)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .accessibilityIdentifier("recipe.link")
                        if !recipeLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            && !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("We'll read the link. Clear it to use the text instead.")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.inkKohlSoft)
                        }
                    }
                    .padding(Samaan.Space.md)
                    .samaanCard()
                    .padding(.horizontal, Samaan.Space.md)

                    HStack(spacing: 10) {
                        Rectangle().frame(height: 1).foregroundStyle(Color.borderAkhrotSoft.opacity(0.6))
                        Text("or paste the words")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.inkKohlSoft)
                            .fixedSize()
                        Rectangle().frame(height: 1).foregroundStyle(Color.borderAkhrotSoft.opacity(0.6))
                    }
                    .padding(.horizontal, Samaan.Space.md)
                    .padding(.vertical, 14)

                    ZStack(alignment: .topLeading) {
                        if transcript.isEmpty {
                            Text("Beta listen, chicken karahi bahut easy hai…")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.inkKohlSoft.opacity(0.55))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $transcript)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.inkKohl)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .accessibilityIdentifier("recipe.transcript")
                    }
                    .frame(minHeight: 180)
                    .background(Color.surfaceMalai, in: RoundedRectangle(cornerRadius: Samaan.Radius.md))
                    .overlay(RoundedRectangle(cornerRadius: Samaan.Radius.md).stroke(Color.borderAkhrotSoft.opacity(0.5), lineWidth: 1))
                    .padding(.horizontal, Samaan.Space.md)

                    if let inlineError {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundStyle(Color.accentMasala)
                            Text(inlineError)
                                .font(.system(size: 13))
                                .foregroundStyle(Color.inkKohl)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.accentMasala.opacity(0.12), in: RoundedRectangle(cornerRadius: Samaan.Radius.md))
                        .padding(.horizontal, Samaan.Space.md)
                        .padding(.top, 12)
                    }
                }
            }

            Button("Extract Recipe") { startCaptureTask { await runExtraction() } }
                .buttonStyle(SamaanPrimaryButtonStyle())
                .disabled(!canExtract || transcriber.isRecording)
                .accessibilityIdentifier("recipe.extract")
                .alert(AIProcessingConsent.title, isPresented: $showAIConsent) {
                    Button("Allow and Extract") {
                        hasAIConsent = true
                        let audio = resumeFromAudio
                        resumeFromAudio = false
                        startCaptureTask { await runExtraction(fromAudio: audio) }
                    }
                    Button("Read Privacy Policy") {
                        if let url = URL(string: Config.privacyPolicyURL) { openURL(url) }
                    }
                    Button("Cancel", role: .cancel) { resumeFromAudio = false }
                } message: {
                    Text(AIProcessingConsent.message)
                }
                .padding(.horizontal, Samaan.Space.md)
                .padding(.bottom, 32)
        }
    }

    // MARK: - Loading

    private var loadingContent: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(Color.brandSaag)
                .scaleEffect(1.3)
            Text(loadingMessage)
                .font(.system(size: 14))
                .foregroundStyle(Color.inkKohlSoft)
        }
    }

    private var loadingMessage: String {
        if phase == .adding { return "Saving to your list…" }
        if transcribingAudio { return "Turning your recording into text…" }
        if extractingFromLink { return "Opening the link…" }
        return "Reading the recipe…"
    }

    // MARK: - Review

    private var reviewContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {

                // Editable title + source
                VStack(alignment: .leading, spacing: 4) {
                    Text("RECIPE TITLE")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.inkKohlSoft)
                        .kerning(0.8)
                    TextField("Recipe title", text: $recipeTitle)
                        .font(.cormorant(size: 26))
                        .foregroundStyle(Color.inkKohl)
                        .textFieldStyle(.plain)

                    Text("FROM")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.inkKohlSoft)
                        .kerning(0.8)
                        .padding(.top, 10)
                    TextField("Who gave you this recipe? e.g. Mom", text: $recipeSource)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.inkKohl)
                        .textFieldStyle(.plain)
                }
                .padding(Samaan.Space.md)
                .samaanCard()
                .padding(.horizontal, Samaan.Space.md)
                .padding(.top, Samaan.Space.md)

                SamaanSectionHeader(
                    title: "\(selections.filter(\.isSelected).count) of \(selections.count) selected",
                    color: .brandSaag
                )

                ForEach($selections) { $sel in
                    IngredientRow(selection: $sel)
                        .padding(.horizontal, Samaan.Space.md)
                        .padding(.bottom, 6)
                }

                Spacer(minLength: 100)
            }
        }
        .accessibilityIdentifier("screenshot.recipeReview")
        .overlay(alignment: .bottom) {
            addButton
        }
    }

    private var addButton: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [Color.surfaceDoodh.opacity(0), Color.surfaceDoodh],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 40)
            .allowsHitTesting(false)

            Button("Add to Shopping List") { Task { await pushToList() } }
                .buttonStyle(SamaanPrimaryButtonStyle())
                .disabled(selections.filter(\.isSelected).isEmpty)
                .padding(.horizontal, Samaan.Space.md)
                .padding(.bottom, 32)
                .background(Color.surfaceDoodh)
        }
    }

    // MARK: - Done

    private var doneContent: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Color.brandSaag.opacity(0.12))
                        .frame(width: 80, height: 80)
                    Image(systemName: "checkmark")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(Color.brandSaag)
                }
                VStack(spacing: 6) {
                    Text("Ingredients saved")
                        .font(.cormorant(size: 26))
                        .foregroundStyle(Color.inkKohl)
                    Text("\"\(recipeTitle)\" added to your shopping list.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.inkKohlSoft)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(SamaanPrimaryButtonStyle())
                .padding(.horizontal, Samaan.Space.md)
                .padding(.bottom, 32)
        }
    }

    // MARK: - Actions

    private var audioCapture: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SAY IT")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.inkKohlSoft)
                .kerning(0.8)
            Button(transcriber.isRecording ? "Stop and read the recipe" : "Record a recipe") {
                startCaptureTask { await toggleRecording() }
            }
            .buttonStyle(SamaanPrimaryButtonStyle())
            .accessibilityIdentifier(transcriber.isRecording ? "recipe.record.stop" : "recipe.record")
            Button("Choose a recording") { showAudioPicker = true }
                .buttonStyle(SamaanSecondaryButtonStyle())
                .disabled(transcriber.isRecording)
                .accessibilityIdentifier("recipe.pickAudio")
            if transcriber.isRecording {
                Text(transcriber.partialTranscript.isEmpty
                     ? "Listening. Tap stop when you're done."
                     : transcriber.partialTranscript)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.inkKohlSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("recipe.recording.partial")
            }
        }
        .padding(Samaan.Space.md)
        .samaanCard()
    }

    /// Starts one capture action at a time; repeated taps leave the active action running.
    private func startCaptureTask(_ action: @escaping @MainActor () async -> Void) {
        guard captureIsActive, captureTask == nil else { return }
        let generation = captureGeneration
        captureTask = Task {
            defer {
                // A cancelled task must not clear a newer capture's task handle.
                if captureGeneration == generation { captureTask = nil }
            }
            await action()
        }
    }

    /// Stops recording and any running capture task, and resets transcription state before dismissal.
    private func cancelCapture() {
        captureIsActive = false
        captureGeneration = UUID()
        captureTask?.cancel()
        captureTask = nil
        transcriber.cancelRecording()
        if transcribingAudio {
            transcribingAudio = false
            phase = .idle
        }
    }

    /// Resumes an extraction that was deferred for sign-in, once auth has finished and the view is active.
    private func resumePendingExtraction() {
        guard captureIsActive, !appEnv.isAuthPresented,
              appEnv.auth.isSignedIn, resumeExtractAfterAuth else { return }
        resumeExtractAfterAuth = false
        let audio = resumeFromAudio
        resumeFromAudio = false
        startCaptureTask { await runExtraction(fromAudio: audio) }
    }

    /// True when the view is still active and `generation` matches the current capture attempt.
    private func acceptsCapture(_ generation: UUID) -> Bool {
        captureIsActive && captureGeneration == generation && !Task.isCancelled
    }

    /// Starts or stops microphone recording, then kicks off extraction once a recording finishes.
    private func toggleRecording() async {
        let generation = captureGeneration
        guard acceptsCapture(generation) else { return }
        if transcriber.isRecording {
            transcribingAudio = true
            phase = .extracting
            let text: String
            do {
                text = try await transcriber.stopRecording()
                guard acceptsCapture(generation) else { return }
            } catch {
                guard acceptsCapture(generation) else { return }
                transcribingAudio = false
                presentError(error.localizedDescription, title: "Didn't catch that")
                return
            }
            transcribingAudio = false
            phase = .idle
            transcript = text
            await runExtraction(fromAudio: true)
            return
        }
        do {
            try await transcriber.startRecording()
        } catch {
            guard acceptsCapture(generation) else { return }
            presentError(error.localizedDescription, title: "Can't record")
        }
    }

    /// Copies and transcribes a picked audio file, then extracts a recipe from the result.
    private func transcribePickedFile(_ url: URL) async {
        let generation = captureGeneration
        guard acceptsCapture(generation) else { return }
        transcribingAudio = true
        phase = .extracting
        let copy: URL
        do {
            copy = try RecipeAudioTranscriber.temporaryCopy(of: url)
        } catch {
            transcribingAudio = false
            presentError(error.localizedDescription, title: "Couldn't open the recording")
            return
        }
        let text: String
        do {
            defer { try? FileManager.default.removeItem(at: copy) }
            text = try await transcriber.transcribeFile(at: copy)
            guard acceptsCapture(generation) else { return }
        } catch {
            guard acceptsCapture(generation) else { return }
            transcribingAudio = false
            presentError(error.localizedDescription, title: "Couldn't transcribe that")
            return
        }
        transcribingAudio = false
        phase = .idle
        transcript = text
        await runExtraction(fromAudio: true)
    }

    /// Validates the link or transcript, ensures consent and sign-in, then calls the extraction service.
    private func runExtraction(fromAudio: Bool = false) async {
        let generation = captureGeneration
        guard acceptsCapture(generation) else { return }
        let audio = fromAudio || resumeFromAudio
        if audio {
            recipeLink = ""
        }
        let link: String?
        let text: String
        switch RecipeCaptureRoute.route(linkRaw: recipeLink, transcriptRaw: transcript, fromAudio: audio) {
        case .empty:
            return
        case .invalidLink:
            presentError(
                "That doesn't look like a link. Paste a full YouTube, recipe, or Instagram URL.",
                title: "Check the link"
            )
            return
        case .url(let value):
            link = value
            text = ""
        case .transcript(let value):
            link = nil
            text = value
        }
        if !hasAIConsent {
            resumeFromAudio = audio
            showAIConsent = true
            return
        }
        if !appEnv.requireAccount() {
            resumeFromAudio = audio
            resumeExtractAfterAuth = true
            return
        }
        resumeFromAudio = false
        extractingFromLink = link != nil
        phase = .extracting
        do {
            let result: ExtractionResult
            if let link {
                result = try await RecipeExtractionService.shared.extract(url: link)
                guard acceptsCapture(generation) else { return }
                capturedSource = link
                capturedSourceKind = .url
            } else {
                result = try await RecipeExtractionService.shared.extract(transcript: text)
                guard acceptsCapture(generation) else { return }
                capturedSource = text
                capturedSourceKind = .transcript
            }
            recipeTitle = result.recipe.title
            if let attribution = result.recipe.attribution?.trimmingCharacters(in: .whitespacesAndNewlines), !attribution.isEmpty {
                recipeSource = attribution
            } else if let link, let host = RecipeLinkInput.hostLabel(link) {
                recipeSource = host
            } else {
                recipeSource = ""
            }
            selections   = result.recipe.ingredients.map { IngredientSelection(ingredient: $0) }
            extractedJSON = result.rawJSON
            Analytics.track(.recipeExtracted)
            phase = .reviewing
        } catch let error as RecipeExtractionService.ExtractionError {
            guard acceptsCapture(generation) else { return }
            switch error {
            case .unauthorized:
                resumeFromAudio = audio
                resumeExtractAfterAuth = true
                appEnv.requireAccount()
                extractingFromLink = false
                phase = .idle
            case .quotaExceeded, .instagramCaptionUnavailable, .urlNotAllowed, .urlFetchFailed, .noRecipeText,
                 .apiError, .serviceError:
                presentError(error.localizedDescription, title: error.captureAlertTitle)
            }
        } catch {
            guard acceptsCapture(generation) else { return }
            presentError(error.localizedDescription)
        }
    }

    private func presentError(_ message: String, title: String = "Extraction failed") {
        errorTitle = title
        errorMessage = message
        inlineError = message
        showError = true
        extractingFromLink = false
        phase = .idle
    }

    private func pushToList() async {
        let chosen = selections.filter(\.isSelected)
        guard !chosen.isEmpty else { return }
        phase = .adding

        let list = ShoppingList(name: recipeTitle)
        context.insert(list)
        PantryProductLink.appendIngredients(chosen.map(\.ingredient), to: list, in: context)

        // Fold the user-entered source back into the stored JSON so the saved
        // recipe and its extracted structure agree on attribution.
        let trimmedSource = recipeSource.trimmingCharacters(in: .whitespacesAndNewlines)
        let attribution = trimmedSource.isEmpty ? nil : trimmedSource
        var finalJSON = extractedJSON
        if var parsed = try? JSONDecoder().decode(ExtractedRecipe.self, from: Data(extractedJSON.utf8)) {
            parsed.attribution = attribution
            if let data = try? JSONEncoder().encode(parsed),
               let json = String(data: data, encoding: .utf8) {
                finalJSON = json
            }
        }

        let sourceText = capturedSource.isEmpty ? transcript : capturedSource
        let recipe = Recipe(
            title: recipeTitle,
            rawTranscript: sourceText,
            extractedJSON: finalJSON,
            attribution: attribution,
            sourceKind: capturedSourceKind
        )
        context.insert(recipe)

        try? context.save()
        Analytics.track(.recipeSaved)
        appEnv.syncNow()
        phase = .done
    }
}

// MARK: - AI processing consent

enum AIProcessingConsent {
    static let storageKey = "samaan.consent.anthropicExtraction.v1"
    static let title = "Send this recipe to Anthropic?"
    static let message = "To pull out the ingredients and steps, Samaan sends the recipe text or link you give it to our server. That includes words you paste, words from a recording made in the app, and words from an audio file you choose. The recording is transcribed on your iPhone and is not uploaded. If it isn't already a structured recipe, that text goes to Anthropic, our AI provider. Nothing else from your pantry or account goes with it. We only ask once. See our Privacy Policy for details."
}

// MARK: - Ingredient row

private struct IngredientRow: View {
    @Binding var selection: RecipeCaptureView.IngredientSelection

    var body: some View {
        let ing = selection.ingredient
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selection.isSelected.toggle()
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selection.isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(selection.isSelected ? Color.brandSaag : Color.inkKohlSoft.opacity(0.4))
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(ing.ingredient)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.inkKohl)
                        Spacer()
                        Text(ing.amountLabel)
                            .font(.samaanMono(13))
                            .foregroundStyle(ing.vague ? Color.inkKohlSoft : Color.brandSaag)
                    }
                    Text(ing.originalPhrase)
                        .font(.system(size: 12))
                        .italic()
                        .foregroundStyle(Color.inkKohlSoft)
                }
            }
            .padding(12)
            .samaanCard()
            .opacity(selection.isSelected ? 1 : 0.45)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    RecipeCaptureView()
        .environment(\.appEnv, AppEnvironment(modelContainer: .preview))
        .modelContainer(.preview)
}
