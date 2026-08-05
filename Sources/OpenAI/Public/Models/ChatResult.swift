//
//  ChatResult.swift
//
//
//  Created by Sergii Kryvoblotskyi on 02/04/2023.
//

import Foundation

public struct ChatResult: Codable, Equatable, Sendable {
    /// A unique identifier for the chat completion.
    public let id: String

    /// The Unix timestamp (in seconds) of when the chat completion was created.
    public let created: Int

    /// The model used for the chat completion.
    public let model: String

    /// The object type, which is always `chat.completion`.
    public let object: String

    /// Specifies the latency tier to use for processing the request. This parameter is relevant for customers subscribed to the scale tier service:
    /// - If set to 'auto', and the Project is Scale tier enabled, the system will utilize scale tier credits until they are exhausted.
    /// - If set to 'auto', and the Project is not Scale tier enabled, the request will be processed using the default service tier with a lower uptime SLA and no latency guarentee.
    /// - If set to 'default', the request will be processed using the default service tier with a lower uptime SLA and no latency guarentee.
    /// - If set to 'flex', the request will be processed with the Flex Processing service tier. [Learn more](https://platform.openai.com/docs/guides/flex-processing).
    /// - When not set, the default behavior is 'auto'.
    ///
    /// When this parameter is set, the response body will include the `service_tier` utilized.
    public let serviceTier: ServiceTier?

    /// This fingerprint represents the backend configuration that the model runs with.
    ///
    /// Can be used in conjunction with the `seed` request parameter to understand when backend changes have been made that might impact determinism.
    ///
    /// Note: Even though [API Reference - The chat completion object - system_fingerprint](https://platform.openai.com/docs/api-reference/chat/object#chat/object-system_fingerprint) declares the type as non-optional `string` - the response object may not contain the value, so we have had to make it optional `String?` in the Swift type.
    /// See https://github.com/MacPaw/OpenAI/issues/331 for more details on such a case
    public let systemFingerprint: String?

    /// A list of chat completion choices. Can be more than one if `n` is greater than 1.
    public let choices: [Choice]

    /// Usage statistics for the completion request.
    public let usage: Self.CompletionUsage?
    
    /// Following are fields that are not part of OpenAI API Reference, but are present in responses from other providers
    ///
    /// Perplexity
    /// Citations for the generated answer.
    /// https://docs.perplexity.ai/api-reference/chat-completions#response-citations
    public let citations: [String]?

    public enum CodingKeys: String, CodingKey {
        case id
        case object
        case created
        case model
        case choices
        case serviceTier = "service_tier"
        case systemFingerprint = "system_fingerprint"
        case usage
        case citations
    }
    
    init(id: String, created: Int, model: String, object: String, serviceTier: ServiceTier? = nil, systemFingerprint: String? = nil, choices: [Choice], usage: Self.CompletionUsage? = nil, citations: [String]? = nil) {
        self.id = id
        self.created = created
        self.model = model
        self.object = object
        self.serviceTier = serviceTier
        self.systemFingerprint = systemFingerprint
        self.choices = choices
        self.usage = usage
        self.citations = citations
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let parsingOptions = decoder.userInfo[.parsingOptions] as? ParsingOptions ?? []
        self.id = try container.decodeString(forKey: .id, parsingOptions: parsingOptions)
        self.object = try container.decodeString(forKey: .object, parsingOptions: parsingOptions)
        self.created = try container.decode(Int.self, forKey: .created)
        self.model = try container.decodeString(forKey: .model, parsingOptions: parsingOptions)
        self.choices = try container.decode([ChatResult.Choice].self, forKey: .choices)
        // OpenAI-compatible providers (e.g. MiniMax) send service_tier values outside OpenAI's
        // enum such as "standard"; decoding the enum directly throws dataCorrupted. Decode the
        // raw string and map it, falling back to nil for unknown tiers.
        // wangqi modified 2026-06-11
        if let rawServiceTier = try container.decodeIfPresent(String.self, forKey: .serviceTier) {
            self.serviceTier = ServiceTier(rawValue: rawServiceTier)
        } else {
            self.serviceTier = nil
        }
        self.systemFingerprint = try container.decodeIfPresent(String.self, forKey: .systemFingerprint)
        // It seems to be possible that in some cases `usage` may be neither a full object nor `null`
        // For example, whem model's response is not a content, but `refusal`
        // See: https://github.com/MacPaw/OpenAI/issues/338 for more details
        self.usage = try? container.decodeIfPresent(ChatResult.CompletionUsage.self, forKey: .usage)
        self.citations = try container.decodeIfPresent([String].self, forKey: .citations)
    }
    
    public struct Choice: Codable, Equatable, Sendable {
        /// The index of the choice in the list of choices.
        public let index: Int
        /// Log probability information for the choice.
        public let logprobs: Self.ChoiceLogprobs?
        /// A chat completion message generated by the model.
        public let message: Self.Message
        /// The reason the model stopped generating tokens. This will be stop if the model hit a natural `stop` point or a provided stop sequence, `length` if the maximum number of tokens specified in the request was reached, `content_filter` if content was omitted due to a flag from our content filters, `tool_calls` if the model called a tool, or `function_call` (deprecated) if the model called a function.
        public let finishReason: String
        
        public struct Message: Codable, Equatable, Sendable {
            /// The contents of the message.
            public let content: String?
            /// The refusal message generated by the model.
            public let refusal: String?
            /// The role of the author of this message.
            public let role: String
            /// Annotations for the message, when applicable, as when using the web search tool.
            /// Web search tool: https://platform.openai.com/docs/guides/tools-web-search?api-mode=chat
            ///
            /// This field is declared non-optional in OpenAI API reference, but to not make breaking changes for our users that use this SDK for other providers like DeepSeek, made it optional for now
            /// See https://github.com/MacPaw/OpenAI/issues/293
            public let annotations: [Annotation]?
            /// If the audio output modality is requested, this object contains data about the audio response from the model.
            /// [Learn more](https://platform.openai.com/docs/guides/audio)
            public let audio: Audio?
            /// The tool calls generated by the model, such as function calls.
            ///
            /// This field is declared not-optional in OpenAI API reference. But it seems that under some conditions it may not be present in a response.
            /// See https://github.com/MacPaw/OpenAI/issues/293
            public let toolCalls: [ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam]?
            
            /// Following are fields that are not part of OpenAI but are present in responses from other providers
            
            /// Value for `reasoning` field in response.
            ///
            /// Provided by:
            /// - Gemini (in OpenAI compatibility mode)
            ///   https://github.com/MacPaw/OpenAI/issues/283#issuecomment-2711396735
            /// - OpenRouter
            internal let _reasoning: String?

            /// Value for `reasoning_content` field.
            ///
            /// Provided by:
            /// - Deepseek
            ///   https://api-docs.deepseek.com/api/create-chat-completion#responses
            internal let _reasoningContent: String?

            /// Reasoning content.
            ///
            /// Supported response fields:
            /// - `reasoning` (Gemini, OpenRouter)
            /// - `reasoning_content` (Deepseek)
            public var reasoning: String? {
                _reasoning ?? _reasoningContent
            }
            
            /// Media content from extended provider fields (images, etc.)
            public let images: [MediaContent]?

            public enum CodingKeys: String, CodingKey {
                case content, refusal, role, annotations, audio, toolCalls = "tool_calls"
                case _reasoning = "reasoning"
                case _reasoningContent = "reasoning_content"
                case images
            }
            
            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                
                // Decode standard fields
                content = try container.decodeIfPresent(String.self, forKey: .content)
                refusal = try container.decodeIfPresent(String.self, forKey: .refusal)
                role = try container.decode(String.self, forKey: .role)
                annotations = try container.decodeIfPresent([Annotation].self, forKey: .annotations)
                audio = try container.decodeIfPresent(Audio.self, forKey: .audio)
                toolCalls = try container.decodeIfPresent([ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam].self, forKey: .toolCalls)
                _reasoning = try container.decodeIfPresent(String.self, forKey: ._reasoning)
                _reasoningContent = try container.decodeIfPresent(String.self, forKey: ._reasoningContent)
                
                // Decode images using MediaContentFactory
                images = MediaContentFactory.decodeMediaContent(from: container, forKey: .images)
            }
            
            public struct Audio: Codable, Equatable, Sendable {
                /// Base64 encoded audio bytes generated by the model, in the format specified in the request.
                public let data: String
                /// The Unix timestamp (in seconds) for when this audio response will no longer be accessible on the server for use in multi-turn conversations.
                public let expiresAt: Int
                /// Unique identifier for this audio response.
                public let id: String
                /// Transcript of the audio generated by the model.
                public let transcript: String
                
                public enum CodingKeys: String, CodingKey {
                    case data
                    case expiresAt = "expires_at"
                    case id, transcript
                }
            }
        }

        public struct ChoiceLogprobs: Codable, Equatable, Sendable {
            /// A list of message content tokens with log probability information.
            public let content: [Self.ChatCompletionTokenLogprob]?
            /// A list of message refusal tokens with log probability information.
            public let refusal: [Self.ChatCompletionTokenLogprob]?

            public struct ChatCompletionTokenLogprob: Codable, Equatable, Sendable {

                /// The token.
                public let token: String
                /// A list of integers representing the UTF-8 bytes representation of the token.
                /// Useful in instances where characters are represented by multiple tokens and
                /// their byte representations must be combined to generate the correct text
                /// representation. Can be `null` if there is no bytes representation for the token.
                public let bytes: [Int]?
                /// The log probability of this token.
                public let logprob: Double
                /// List of the most likely tokens and their log probability, at this token position.
                /// In rare cases, there may be fewer than the number of requested `top_logprobs` returned.
                public let topLogprobs: [TopLogprob]

                public struct TopLogprob: Codable, Equatable, Sendable {

                    /// The token.
                    public let token: String
                    /// A list of integers representing the UTF-8 bytes representation of the token.
                    /// Useful in instances where characters are represented by multiple tokens and their byte representations must be combined to generate the correct text representation. Can be `null` if there is no bytes representation for the token.
                    public let bytes: [Int]?
                    /// The log probability of this token.
                    public let logprob: Double
                }

                public enum CodingKeys: String, CodingKey {
                    case token
                    case bytes
                    case logprob
                    case topLogprobs = "top_logprobs"
                }
            }
        }

        public enum CodingKeys: String, CodingKey {
            case index
            case logprobs
            case message
            case finishReason = "finish_reason"
        }

        public enum FinishReason: String, Codable, Equatable, Sendable {
            case stop
            case length
            case toolCalls = "tool_calls"
            case contentFilter = "content_filter"
            case functionCall = "function_call"
            case error
        }
    }

    public struct CompletionUsage: Codable, Equatable, Sendable {
        /// Number of tokens in the generated completion.
        public let completionTokens: Int
        /// Number of tokens in the prompt.
        public let promptTokens: Int
        /// Total number of tokens used in the request (prompt + completion).
        public let totalTokens: Int
        /// Breakdown of tokens used in the prompt.
        public let promptTokensDetails: PromptTokensDetails?
        /// Breakdown of tokens used in the completion.
        /// wangqi 2026-02-05: Added to support reasoning_tokens and other completion details
        public let completionTokensDetails: CompletionTokensDetails?
        // Surface cache-write counts so token tracking can show what a turn paid to populate the
        // provider's prompt cache. Vercel's gateway reports it top level as
        // `cache_creation_input_tokens` rather than inside `prompt_tokens_details`.
        // Optional so the synthesized decoder stays lenient for the servers that omit it.
        // wangqi modified 2026-08-04
        /// Tokens written into the provider's prompt cache by this request (gateway-shaped field).
        public let cacheCreationInputTokens: Int?

        public init(
            completionTokens: Int,
            promptTokens: Int,
            totalTokens: Int,
            promptTokensDetails: PromptTokensDetails? = nil,
            completionTokensDetails: CompletionTokensDetails? = nil,
            // wangqi modified 2026-08-04
            cacheCreationInputTokens: Int? = nil
        ) {
            self.completionTokens = completionTokens
            self.promptTokens = promptTokens
            self.totalTokens = totalTokens
            self.promptTokensDetails = promptTokensDetails
            self.completionTokensDetails = completionTokensDetails
            self.cacheCreationInputTokens = cacheCreationInputTokens
        }


        public struct PromptTokensDetails: Codable, Equatable, Sendable {
            /// Audio input tokens present in the prompt.
            public let audioTokens: Int
            /// Cached tokens present in the prompt.
            public let cachedTokens: Int
            // Cache *writes* are reported by OpenRouter as `cache_write_tokens` in this same
            // breakdown. Display-only: OpenAI-shaped providers already count writes inside
            // `prompt_tokens`, so this must never be added to any input total.
            // wangqi modified 2026-08-04
            /// Tokens written into the provider's prompt cache by this request.
            public let cacheWriteTokens: Int

            enum CodingKeys: String, CodingKey {
                case audioTokens = "audio_tokens"
                case cachedTokens = "cached_tokens"
                // wangqi modified 2026-08-04
                case cacheWriteTokens = "cache_write_tokens"
            }

            // wangqi 2026-02-05: Custom decoder to gracefully handle missing or unknown fields
            // This ensures that missing fields don't break parsing of other normal fields
            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)

                // Decode each field individually, providing default value (0) if missing
                self.audioTokens = try container.decodeIfPresent(Int.self, forKey: .audioTokens) ?? 0
                self.cachedTokens = try container.decodeIfPresent(Int.self, forKey: .cachedTokens) ?? 0
                // wangqi modified 2026-08-04
                self.cacheWriteTokens = try container.decodeIfPresent(Int.self, forKey: .cacheWriteTokens) ?? 0
            }
        }

        public struct CompletionTokensDetails: Codable, Equatable, Sendable {
            /// Reasoning tokens used in the completion (e.g., for models like DeepSeek, o1).
            public let reasoningTokens: Int
            /// Audio output tokens in the completion.
            public let audioTokens: Int
            /// Accepted prediction tokens (for speculative decoding).
            public let acceptedPredictionTokens: Int
            /// Rejected prediction tokens (for speculative decoding).
            public let rejectedPredictionTokens: Int

            enum CodingKeys: String, CodingKey {
                case reasoningTokens = "reasoning_tokens"
                case audioTokens = "audio_tokens"
                case acceptedPredictionTokens = "accepted_prediction_tokens"
                case rejectedPredictionTokens = "rejected_prediction_tokens"
            }

            // wangqi 2026-02-05: Custom decoder to gracefully handle missing or unknown fields
            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)

                // Decode each field individually, providing default value (0) if missing
                self.reasoningTokens = try container.decodeIfPresent(Int.self, forKey: .reasoningTokens) ?? 0
                self.audioTokens = try container.decodeIfPresent(Int.self, forKey: .audioTokens) ?? 0
                self.acceptedPredictionTokens = try container.decodeIfPresent(Int.self, forKey: .acceptedPredictionTokens) ?? 0
                self.rejectedPredictionTokens = try container.decodeIfPresent(Int.self, forKey: .rejectedPredictionTokens) ?? 0
            }
        }

        enum CodingKeys: String, CodingKey {
            case completionTokens = "completion_tokens"
            case promptTokens = "prompt_tokens"
            case totalTokens = "total_tokens"
            case promptTokensDetails = "prompt_tokens_details"
            case completionTokensDetails = "completion_tokens_details"
            // wangqi modified 2026-08-04
            case cacheCreationInputTokens = "cache_creation_input_tokens"
        }
    }
}

extension ChatQuery.ChatCompletionMessageParam {

    public init(from decoder: Decoder) throws {
        let messageContainer = try decoder.container(keyedBy: Self.ChatCompletionMessageParam.CodingKeys.self)
        switch try messageContainer.decode(Role.self, forKey: .role) {
        case .system:
            self = try .system(.init(from: decoder))
        case .developer:
            self = try .developer(.init(from: decoder))
        case .user:
            self = try .user(.init(from: decoder))
        case .assistant:
            self = try .assistant(.init(from: decoder))
        case .tool:
            self = try .tool(.init(from: decoder))
        }
    }
}

extension ChatQuery.ChatCompletionMessageParam.UserMessageParam.Content {
    enum ContentDecodingError: Error {
        case unableToDecodeNeitherOfPossibleTypes(Decoder, [Error])
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        var errors: [Error] = []
        do {
            let string = try container.decode(String.self)
            self = .string(string)
            return
        } catch {
            errors.append(error)
        }
        
        do {
            let contentParts = try container.decode([ChatQuery.ChatCompletionMessageParam.UserMessageParam.Content.ContentPart].self)
            self = .contentParts(contentParts)
            return
        } catch {
            errors.append(error)
        }
        
        throw ContentDecodingError.unableToDecodeNeitherOfPossibleTypes(decoder, errors)
    }
}
