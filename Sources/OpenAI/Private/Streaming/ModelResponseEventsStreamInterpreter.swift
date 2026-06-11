//
//  ModelResponseEventsStreamInterpreter.swift
//  OpenAI
//
//  Created by Oleksii Nezhyborets on 04.04.2025.
//

import Foundation

/// This class is NOT thread safe. It's a callers responsibility to make all the calls in serialized manner.
final class ModelResponseEventsStreamInterpreter: @unchecked Sendable, StreamInterpreter {
    private let parser = ServerSentEventsStreamParser()
    private var onEventDispatched: ((ResponseStreamEvent) -> Void)?
    private var onError: ((Error) -> Void)?
    private let decoder = JSONDecoder()
    
    init () {
        parser.setCallbackClosures { [weak self] event in
            guard let self else {
                return
            }
            
            do {
                try self.processEvent(event)
            } catch {
                self.processError(error)
            }
        } onError: { [weak self] error in
            self?.processError(error)
        }
    }
    
    /// Sets closures an instance of type. Not thread safe.
    ///
    /// - Parameters:
    ///     - onEventDispatched: Can be called multiple times per `processData`
    ///     - onError: Will only be called once per `processData`
    func setCallbackClosures(onEventDispatched: @escaping @Sendable (ResponseStreamEvent) -> Void, onError: @escaping @Sendable (Error) -> Void) {
        self.onEventDispatched = onEventDispatched
        self.onError = onError
    }
    
    func processData(_ data: Data) {
        let decoder = JSONDecoder()
        if let decoded = JSONResponseErrorDecoder(decoder: decoder).decodeErrorResponse(data: data) {
            onError?(decoded)
            return
        }
        
        parser.processData(data: data)
    }
    
    private func processEvent(_ event: ServerSentEventsStreamParser.Event) throws {
        // wangqi: normalize the known incorrect annotation event name before mapping.
        let finalEvent = event.fixMappingError()
        var eventType = finalEvent.eventType

        /// If the SSE `event` property is not specified by the provider service, our parser defaults it to "message" which is not a valid model response type.
        /// In this case we check the `data.type` property for a valid model response type.
        if eventType == "message" || eventType.isEmpty,
           let payloadEventType = finalEvent.getPayloadType() {
            eventType = payloadEventType
        }

        // wangqi [2026-03-10]: Handle LM Studio's non-standard reasoning_text events.
        // LM Studio uses "response.reasoning_text.delta/done" with "content_index" instead
        // of the standard "response.reasoning_summary_text.delta/done" with "summary_index".
        if eventType == "response.reasoning_text.delta" {
            let mapped = try decodeLMStudioReasoningTextDelta(data: finalEvent.data)
            onEventDispatched?(.reasoningSummaryText(.delta(mapped)))
            return
        } else if eventType == "response.reasoning_text.done" {
            let mapped = try decodeLMStudioReasoningTextDone(data: finalEvent.data)
            onEventDispatched?(.reasoningSummaryText(.done(mapped)))
            return
        }

        guard let modelResponseEventType = ModelResponseStreamEventType(rawValue: eventType) else {
            // wangqi [2026-03-10]: Silently skip unknown event types from non-standard servers
            return
        }

        let responseStreamEvent = try responseStreamEvent(modelResponseEventType: modelResponseEventType, data: finalEvent.data)
        onEventDispatched?(responseStreamEvent)
    }

    // MARK: - LM Studio compatibility decoders

    // Lenient payloads for LM Studio's non-standard reasoning_text events.
    // All fields use decodeIfPresent with safe defaults so missing fields never crash.
    private struct LMStudioReasoningTextDeltaPayload: Decodable {
        let itemId: String
        let outputIndex: Int
        let contentIndex: Int
        let delta: String
        let sequenceNumber: Int
        enum CodingKeys: String, CodingKey {
            case itemId = "item_id"
            case outputIndex = "output_index"
            case contentIndex = "content_index"
            case delta
            case sequenceNumber = "sequence_number"
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            itemId         = (try? c.decodeIfPresent(String.self, forKey: .itemId)) ?? ""
            outputIndex    = (try? c.decodeIfPresent(Int.self,    forKey: .outputIndex)) ?? 0
            contentIndex   = (try? c.decodeIfPresent(Int.self,    forKey: .contentIndex)) ?? 0
            delta          = (try? c.decodeIfPresent(String.self, forKey: .delta)) ?? ""
            sequenceNumber = (try? c.decodeIfPresent(Int.self,    forKey: .sequenceNumber)) ?? 0
        }
    }

    private struct LMStudioReasoningTextDonePayload: Decodable {
        let itemId: String
        let outputIndex: Int
        let contentIndex: Int
        let text: String
        let sequenceNumber: Int
        enum CodingKeys: String, CodingKey {
            case itemId = "item_id"
            case outputIndex = "output_index"
            case contentIndex = "content_index"
            case text
            case sequenceNumber = "sequence_number"
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            itemId         = (try? c.decodeIfPresent(String.self, forKey: .itemId)) ?? ""
            outputIndex    = (try? c.decodeIfPresent(Int.self,    forKey: .outputIndex)) ?? 0
            contentIndex   = (try? c.decodeIfPresent(Int.self,    forKey: .contentIndex)) ?? 0
            text           = (try? c.decodeIfPresent(String.self, forKey: .text)) ?? ""
            sequenceNumber = (try? c.decodeIfPresent(Int.self,    forKey: .sequenceNumber)) ?? 0
        }
    }

    private func decodeLMStudioReasoningTextDelta(data: Data) throws -> Schemas.ResponseReasoningSummaryTextDeltaEvent {
        let p = try decoder.decode(LMStudioReasoningTextDeltaPayload.self, from: data)
        return Schemas.ResponseReasoningSummaryTextDeltaEvent(
            _type: .response_reasoningSummaryText_delta,
            itemId: p.itemId,
            outputIndex: p.outputIndex,
            summaryIndex: p.contentIndex,
            delta: p.delta,
            sequenceNumber: p.sequenceNumber
        )
    }

    private func decodeLMStudioReasoningTextDone(data: Data) throws -> Schemas.ResponseReasoningSummaryTextDoneEvent {
        let p = try decoder.decode(LMStudioReasoningTextDonePayload.self, from: data)
        return Schemas.ResponseReasoningSummaryTextDoneEvent(
            _type: .response_reasoningSummaryText_done,
            itemId: p.itemId,
            outputIndex: p.outputIndex,
            summaryIndex: p.contentIndex,
            text: p.text,
            sequenceNumber: p.sequenceNumber
        )
    }

    private func processError(_ error: Error) {
        onError?(error)
    }
    
    private typealias Schemas = Components.Schemas
    
    private func responseStreamEvent(
        modelResponseEventType: ModelResponseStreamEventType,
        data: Data
    ) throws -> ResponseStreamEvent {
        switch modelResponseEventType {
        case .responseCreated:
                .created(try decode(data: data))
        case .responseInProgress:
                .inProgress(try decode(data: data))
        case .responseCompleted:
                .completed(try decode(data: data))
        case .responseFailed:
                .failed(try decode(data: data))
        case .responseIncomplete:
                .incomplete(try decode(data: data))
        case .responseOutputItemAdded:
                .outputItem(.added(try decode(data: data)))
        case .responseOutputItemDone:
                .outputItem(.done(try decode(data: data)))
        case .responseContentPartAdded:
                .contentPart(.added(try decode(data: data)))
        case .responseContentPartDone:
                .contentPart(.done(try decode(data: data)))
        case .responseOutputTextDelta:
                .outputText(.delta(try decode(data: data)))
        case .responseOutputTextDone:
                .outputText(.done(try decode(data: data)))
        case .responseRefusalDelta:
                .refusal(.delta(try decode(data: data)))
        case .responseRefusalDone:
                .refusal(.done(try decode(data: data)))
        case .responseFunctionCallArgumentsDelta:
                .functionCallArguments(.delta(try decode(data: data)))
        case .responseFunctionCallArgumentsDone:
                .functionCallArguments(.done(try decode(data: data)))
        case .responseFileSearchCallInProgress:
                .fileSearchCall(.inProgress(try decode(data: data)))
        case .responseFileSearchCallSearching:
                .fileSearchCall(.searching(try decode(data: data)))
        case .responseFileSearchCallCompleted:
                .fileSearchCall(.completed(try decode(data: data)))
        case .responseWebSearchCallInProgress:
                .webSearchCall(.inProgress(try decode(data: data)))
        case .responseWebSearchCallSearching:
                .webSearchCall(.searching(try decode(data: data)))
        case .responseWebSearchCallCompleted:
                .webSearchCall(.completed(try decode(data: data)))
        case .responseReasoningSummaryPartAdded:
                .reasoningSummaryPart(.added(try decode(data: data)))
        case .responseReasoningSummaryPartDone:
                .reasoningSummaryPart(.done(try decode(data: data)))
        case .responseReasoningSummaryTextDelta:
                .reasoningSummaryText(.delta(try decode(data: data)))
        case .responseReasoningSummaryTextDone:
                .reasoningSummaryText(.done(try decode(data: data)))
        case .responseImageGenerationCallCompleted:
                .imageGenerationCall(.completed(try decode(data: data)))
        case .responseImageGenerationCallGenerating:
                .imageGenerationCall(.generating(try decode(data: data)))
        case .responseImageGenerationCallInProgress:
                .imageGenerationCall(.inProgress(try decode(data: data)))
        case .responseImageGenerationCallPartialImage:
                .imageGenerationCall(.partialImage(try decode(data: data)))
        case .responseMcpCallArgumentsDelta:
                .mcpCallArguments(.delta(try decode(data: data)))
        case .responseMcpCallArgumentsDone:
                .mcpCallArguments(.done(try decode(data: data)))
        case .responseMcpCallCompleted:
                .mcpCall(.completed(try decode(data: data)))
        case .responseMcpCallFailed:
                .mcpCall(.failed(try decode(data: data)))
        case .responseMcpCallInProgress:
                .mcpCall(.inProgress(try decode(data: data)))
        case .responseMcpListToolsCompleted:
                .mcpListTools(.completed(try decode(data: data)))
        case .responseMcpListToolsFailed:
                .mcpListTools(.failed(try decode(data: data)))
        case .responseMcpListToolsInProgress:
                .mcpListTools(.inProgress(try decode(data: data)))
        case .responseQueued:
                .queued(try decode(data: data))
        case .responseReasoningDelta:
                .reasoning(.delta(try decode(data: data)))
        case .responseReasoningDone:
                .reasoning(.done(try decode(data: data)))
        case .responseOutputTextAnnotationAdded:
                .outputTextAnnotation(.added(try decode(data: data)))
        case .responseAudioDelta:
            // Audio, AudioTranscript and CodeInterpreter events are not part of API Reference at the moment
            // But they are present in code generated from OpenAPI spec, so we also include it
                .audio(.delta(try decode(data: data)))
        case .responseAudioDone:
                .audio(.done(try decode(data: data)))
        case .responseAudioTranscriptDelta:
                .audioTranscript(.delta(try decode(data: data)))
        case .responseAudioTranscriptDone:
                .audioTranscript(.done(try decode(data: data)))
        case .responseCodeInterpreterCallCodeDelta:
                .codeInterpreterCall(
                    .code(
                        .delta(
                            try decode(data: data)
                        )
                    )
                )
        case .responseCodeInterpreterCallCodeDone:
                .codeInterpreterCall(
                    .code(
                        .done(try decode(data: data))
                    )
                )
        case .responseCodeInterpreterCallInProgress:
                .codeInterpreterCall(.inProgress(try decode(data: data)))
        case .responseCodeInterpreterCallInterpreting:
                .codeInterpreterCall(.interpreting(try decode(data: data)))
        case .responseCodeInterpreterCallCompleted:
                .codeInterpreterCall(.completed(try decode(data: data)))
        case .error:
                .error(try decode(data: data))
        }
    }
    
    private func decode<T: Codable>(data: Data) throws -> T {
        try decoder.decode(T.self, from: data)
    }
}

private extension ServerSentEventsStreamParser.Event {
    struct TypeEnvelope: Decodable { let type: String }

    func getPayloadType() -> String? {
        try? JSONDecoder().decode(TypeEnvelope.self, from: self.data).type
    }

    // wangqi: fork helper restored after the upstream merge dropped it (the merged top kept calling it).
    // Remove when OpenAI unifies the event name. The API streams the annotation event as the incorrect
    // "response.output_text.annotation.added"; the generated type expects "response.output_text_annotation.added".
    func fixMappingError() -> Self {
        let incorrectEventType = "response.output_text.annotation.added"
        let correctEventType = "response.output_text_annotation.added"

        guard self.eventType == incorrectEventType || self.getPayloadType() == incorrectEventType else {
            return self
        }

        let fixedDataString = self.decodedData.replacingOccurrences(of: incorrectEventType, with: correctEventType)
        return .init(
            id: self.id,
            data: fixedDataString.data(using: .utf8) ?? self.data,
            decodedData: fixedDataString,
            eventType: correctEventType,
            retry: self.retry
        )
    }
}
