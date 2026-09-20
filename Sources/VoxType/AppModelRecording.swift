import AppKit
import Foundation

extension AppModel {
    func startRecording() async {
        guard !phase.isBusy else { return }

        phase = .preparing
        transcript = ""
        stableTranscript = ""
        draftTail = ""
        elapsedSeconds = 0
        statusMessage =
            isModelReady
            ? settings.text(.hudPreparing)
            : settings.text(.statusPreparingEngine)
        lastSavedSession = nil
        lastFinalizationSeconds = nil
        lastPrepareSeconds = nil
        let prepareStartedAt = Date()
        captureTargetApplication()

        // Give immediate visual acknowledgement while permissions and the retained model settle.
        if settings.showFloatingHUD {
            showHUD(target: targetInput)
        }

        let canRecord = await permissions.requestRecordingPermissions()
        guard canRecord else {
            fail(
                presentRecordingPermissionBlocker()
                    ?? settings.text(.permissionRecordingRequired))
            return
        }

        do {
            let draft = try await sessionStore.begin(
                in: settings.saveFolderURL,
                localeIdentifier: settings.resolvedLocale.identifier,
                targetApplication: targetApplicationName
            )
            currentDraft = draft

            async let startedLocale = speechEngine.start(
                locale: settings.resolvedLocale,
                onUpdate: { [weak self] live in
                    Task { @MainActor in
                        self?.receiveTranscriptUpdate(live)
                    }
                },
                onError: { [weak self] error in
                    Task { @MainActor in
                        guard let self else { return }
                        self.statusMessage = self.settings.localizedError(error)
                    }
                }
            )
            let activeSpeechEngine = speechEngine
            _ = try audioCapture.start(
                writingTo: draft.audioURL,
                onBuffer: { [weak activeSpeechEngine] buffer, time in
                    activeSpeechEngine?.consume(buffer, at: time)
                }
            )
            resolvedLocaleIdentifier = try await startedLocale

            isModelReady = true
            lastPrepareSeconds = Date().timeIntervalSince(prepareStartedAt)
            recordingStartedAt = Date()
            phase = .recording
            statusMessage = recordingStatusMessage

        } catch {
            _ = audioCapture.stop()
            await speechEngine.cancel()
            speechEngine.scheduleReserve(locale: settings.resolvedLocale)
            if let draft = currentDraft {
                await sessionStore.markFailed(
                    draft,
                    durationSeconds: 0,
                    error: error.localizedDescription,
                    targetApplication: targetApplicationName
                )
            }
            currentDraft = nil
            fail(settings.localizedError(error))
        }
    }

    func stopRecording() async {
        guard phase == .recording else { return }

        phase = .finalizing
        statusMessage = settings.text(.statusFinalizingWords)
        if let started = recordingStartedAt {
            elapsedSeconds = Date().timeIntervalSince(started)
        }
        let captureResult = audioCapture.stop()
        let duration = captureResult.durationSeconds
        let audioWriteWarning = captureResult.writeErrorDescription
        let liveFallback = transcript
        let finalizationStartedAt = Date()
        let refineTask = makeRefinementTask()

        do {
            let finalText = try await speechEngine.stop()
            lastFinalizationSeconds = Date().timeIntervalSince(finalizationStartedAt)
            let appleText =
                finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? liveFallback
                : finalText
            var bestText = appleText
            var refinementStatus: String?
            if let refineTask {
                statusMessage = settings.text(.statusRefining)
                let result = TranscriptRefinement.select(
                    apple: appleText,
                    refined: await refineTask.value,
                    durationSeconds: duration,
                    language: settings.dictationLanguage,
                    backend: refinement.backend
                )
                bestText = result.text
                refinementStatus = result.status
            }
            transcript = bestText
            stableTranscript = bestText
            draftTail = ""
            speechEngine.scheduleReserve(locale: settings.resolvedLocale)

            phase = .delivering
            statusMessage = settings.text(.statusInserting)

            let draft = currentDraft
            let capturedTargetApplicationName = self.targetApplicationName
            let saveTask = Task<SavedSession?, Error> {
                guard let draft else { return nil }
                return try await sessionStore.finish(
                    draft,
                    transcript: bestText,
                    durationSeconds: duration,
                    targetApplication: capturedTargetApplicationName,
                    status: audioWriteWarning == nil ? refinementStatus : "audio-write-warning"
                )
            }

            var deliveryError: Error?
            do {
                try await outputDispatcher.deliver(
                    bestText,
                    mode: settings.deliveryMode,
                    target: targetInput,
                    preserveClipboard: settings.preserveClipboard,
                    pasteDelayMilliseconds: settings.pasteDelayMilliseconds
                )
            } catch {
                deliveryError = error
            }

            var saved: SavedSession?
            var saveError: Error?
            do {
                saved = try await saveTask.value
                lastSavedSession = saved
            } catch {
                saveError = error
            }

            if let deliveryError {
                statusMessage = settings.localizedError(deliveryError)
            } else if let saveError {
                statusMessage = settings.text(
                    .statusTextDeliveredArchiveFailed, settings.localizedError(saveError))
            } else if let audioWriteWarning {
                statusMessage = settings.text(
                    .statusTextDeliveredAudioIncomplete, audioWriteWarning)
            } else {
                statusMessage = deliverySuccessMessage(for: settings.deliveryMode, saved: saved)
            }

            phase = .idle
            currentDraft = nil
            recordingStartedAt = nil
            hudController?.hide()
            refreshRecentSessions()
        } catch {
            await recoverFromFinalizationError(
                error,
                duration: duration,
                fallbackText: liveFallback,
                audioWriteWarning: audioWriteWarning
            )
        }
    }

    private func makeRefinementTask() -> Task<String?, Never>? {
        guard refinement.state == .ready,
            let audioURL = currentDraft?.audioURL
        else {
            return nil
        }
        return Task {
            try? await refinement.refine(
                audioURL: audioURL,
                timeoutSeconds: RefinementPolicy.timeoutSeconds
            )
        }
    }

    private func receiveTranscriptUpdate(_ live: LiveTranscript) {
        transcript = live.text
        let parts = LiveTranscriptDisplay.parts(
            from: live,
            finalPass: refinement.state == .ready
        )
        stableTranscript = parts.stable
        draftTail = parts.draft
        guard let draft = currentDraft else { return }

        let now = Date()
        if now.timeIntervalSince(lastPartialWriteAt) >= 0.65 {
            lastPartialWriteAt = now
            Task {
                await sessionStore.writePartial(live.text, for: draft)
            }
        }
    }

    private func recoverFromFinalizationError(
        _ error: Error,
        duration: TimeInterval,
        fallbackText: String,
        audioWriteWarning: String?
    ) async {
        if let draft = currentDraft {
            let cleanFallback = fallbackText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanFallback.isEmpty {
                do {
                    lastSavedSession = try await sessionStore.finish(
                        draft,
                        transcript: cleanFallback,
                        durationSeconds: duration,
                        targetApplication: targetApplicationName,
                        status: "partial-after-error"
                    )
                    transcript = cleanFallback
                    stableTranscript = cleanFallback
                    draftTail = ""
                    outputDispatcher.copy(cleanFallback)
                } catch {
                    await sessionStore.markFailed(
                        draft,
                        durationSeconds: duration,
                        error: error.localizedDescription,
                        targetApplication: targetApplicationName
                    )
                }
            } else {
                await sessionStore.markFailed(
                    draft,
                    durationSeconds: duration,
                    error: error.localizedDescription,
                    targetApplication: targetApplicationName
                )
            }
        }

        currentDraft = nil
        recordingStartedAt = nil
        speechEngine.scheduleReserve(locale: settings.resolvedLocale)
        hudController?.hide(after: 1.3)
        refreshRecentSessions()
        if let audioWriteWarning {
            fail(
                settings.text(
                    .statusTranscriptionAudioIncomplete,
                    audioWriteWarning,
                    settings.localizedError(error)
                )
            )
        } else {
            fail(settings.text(.statusFinalTranscriptionFailed, settings.localizedError(error)))
        }
    }

    private func captureTargetApplication() {
        let ownBundleIdentifier = Bundle.main.bundleIdentifier
        let frontmost = NSWorkspace.shared.frontmostApplication

        if let frontmost, frontmost.bundleIdentifier != ownBundleIdentifier {
            targetApplication = frontmost
            lastExternalApplication = frontmost
        } else {
            targetApplication = lastExternalApplication
        }
        targetApplicationName = targetApplication?.localizedName
        targetInput = outputDispatcher.captureInputTarget(in: targetApplication)
    }

    private var recordingStatusMessage: String {
        switch settings.deliveryMode {
        case .insertOnly, .insertAndClipboard:
            guard targetInput != nil, let targetApplicationName else {
                return settings.text(.statusListeningClipboardFallback)
            }
            return settings.text(.statusListeningReturnToApp, targetApplicationName)
        case .clipboardOnly:
            return settings.text(.statusListeningCopy)
        case .saveOnly:
            return settings.text(.statusListeningSave)
        }
    }

    func showHUD(target: OutputDispatcher.InputTarget? = nil) {
        if hudController == nil {
            hudController = HUDController(model: self)
        }
        hudController?.show(
            targetProcessIdentifier: target?.application.processIdentifier,
            targetWindow: target?.focusedWindow
        )
    }

    private func deliverySuccessMessage(for mode: DeliveryMode, saved: SavedSession?) -> String {
        switch mode {
        case .insertOnly:
            settings.text(.statusInsertedSaved)
        case .clipboardOnly:
            settings.text(.statusCopiedSaved)
        case .insertAndClipboard:
            settings.text(.statusInsertedCopiedSaved)
        case .saveOnly:
            saved == nil ? settings.text(.statusFinished) : settings.text(.statusAudioTextSaved)
        }
    }

    func fail(_ message: String) {
        if let started = recordingStartedAt {
            elapsedSeconds = Date().timeIntervalSince(started)
        }
        recordingStartedAt = nil
        phase = .failed(message)
        statusMessage = message
        hudController?.hide(after: 1.3)
    }
}
