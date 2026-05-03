import XCTest
@testable import CCRMenuBar

final class TokenUsageServiceTests: XCTestCase {
    func testProviderDailySpendLimitRoundTripsConfigKey() throws {
        let data = Data("""
        {
          "name": "openrouter",
          "api_base_url": "https://openrouter.ai/api/v1",
          "api_key": "key",
          "models": ["openai/gpt-5"],
          "daily_spend_limit_usd": 1.25
        }
        """.utf8)

        let provider = try JSONDecoder().decode(Provider.self, from: data)
        XCTAssertEqual(provider.daily_spend_limit_usd, 1.25)
        XCTAssertNil(provider.thinking_disabled_models)

        let encoded = try JSONEncoder().encode(provider)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(object["daily_spend_limit_usd"] as? Double, 1.25)
    }

    func testProviderPreservesThinkingDisabledModels() throws {
        let data = Data("""
        {
          "name": "openrouter",
          "api_base_url": "https://openrouter.ai/api/v1",
          "api_key": "sk-test",
          "models": ["openai/gpt-5", "x-ai/grok-4.20"],
          "thinking_disabled_models": ["x-ai/grok-4.20"]
        }
        """.utf8)

        let provider = try JSONDecoder().decode(Provider.self, from: data)
        XCTAssertEqual(provider.thinking_disabled_models, ["x-ai/grok-4.20"])

        let encoded = try JSONEncoder().encode(provider)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(object["thinking_disabled_models"] as? [String], ["x-ai/grok-4.20"])
    }

    func testLiteLLMPricingParsesTokenCosts() throws {
        let data = Data("""
        {
          "gpt-5.5": {
            "litellm_provider": "openai",
            "input_cost_per_token": 0.000005,
            "output_cost_per_token": 0.00003
          }
        }
        """.utf8)

        let prices = try ModelPricingService.parseLiteLLMPrices(from: data)
        let price = try XCTUnwrap(ModelPricingService.bestPrice(for: "OpenAI", model: "gpt-5.5", in: prices))

        XCTAssertEqual(price.cost(for: TokenStats(inputTokens: 1_000_000, outputTokens: 100_000)), 8.0, accuracy: 0.000001)
    }

    func testOpenRouterPricingParsesStringTokenCosts() throws {
        let data = Data("""
        {
          "data": [
            {
              "id": "openai/gpt-5",
              "pricing": {
                "prompt": "0.00000125",
                "completion": "0.00001"
              }
            }
          ]
        }
        """.utf8)

        let prices = try ModelPricingService.parseOpenRouterPrices(from: data)
        let price = try XCTUnwrap(ModelPricingService.bestPrice(for: "OpenRouter", model: "openai/gpt-5", in: prices))

        XCTAssertEqual(price.key, "openrouter/openai/gpt-5")
        XCTAssertEqual(price.cost(for: TokenStats(inputTokens: 1_000_000, outputTokens: 100_000)), 2.25, accuracy: 0.000001)
    }

    func testOpenRouterPricingMatchesCompositeModels() throws {
        let data = Data("""
        {
          "data": [
            {
              "id": "google/gemini-3.1-flash-lite-preview",
              "pricing": {
                "prompt": "0.00000025",
                "completion": "0.0000015"
              }
            }
          ]
        }
        """.utf8)

        let prices = try ModelPricingService.parseOpenRouterPrices(from: data)
        let price = ModelPricingService.bestPrice(for: "openrouter", model: "google/gemini-3.1-flash-lite-preview", in: prices)

        XCTAssertEqual(price?.key, "openrouter/google/gemini-3.1-flash-lite-preview")
    }

    func testOpenRouterPricingDoesNotFallbackToLiteLLMProviderPrices() throws {
        let liteLLMData = Data("""
        {
          "gpt-5.5": {
            "litellm_provider": "openai",
            "input_cost_per_token": 0.000005,
            "output_cost_per_token": 0.00003
          }
        }
        """.utf8)

        let prices = try ModelPricingService.parseLiteLLMPrices(from: liteLLMData)
        let price = ModelPricingService.bestPrice(for: "openrouter", model: "openai/gpt-5.5", in: prices)

        XCTAssertNil(price)
    }

    func testOpenRouterPricingWinsForOpenRouterModels() throws {
        let openRouterData = Data("""
        {
          "data": [
            {
              "id": "openai/gpt-5.5",
              "pricing": {
                "prompt": "0.000006",
                "completion": "0.00004"
              }
            }
          ]
        }
        """.utf8)
        let liteLLMData = Data("""
        {
          "gpt-5.5": {
            "litellm_provider": "openai",
            "input_cost_per_token": 0.000005,
            "output_cost_per_token": 0.00003
          }
        }
        """.utf8)

        let prices = try ModelPricingService.parseOpenRouterPrices(from: openRouterData) +
            ModelPricingService.parseLiteLLMPrices(from: liteLLMData)
        let price = ModelPricingService.bestPrice(for: "openrouter", model: "openai/gpt-5.5", in: prices)

        XCTAssertEqual(price?.key, "openrouter/openai/gpt-5.5")
        XCTAssertEqual(price?.source, .openRouter)
    }

    func testLiteLLMPricingMatchesBaseModelWhenModelKeyIsVersioned() throws {
        let data = Data("""
        {
          "claude-opus-4-7-20260416": {
            "litellm_provider": "anthropic",
            "base_model": "claude-opus-4-7",
            "input_cost_per_token": 0.000005,
            "output_cost_per_token": 0.000025
          }
        }
        """.utf8)

        let prices = try ModelPricingService.parseLiteLLMPrices(from: data)
        let price = ModelPricingService.bestPrice(for: "Anthropic", model: "claude-opus-4-7", in: prices)

        XCTAssertEqual(price?.key, "claude-opus-4-7-20260416")
    }

    func testLiteLLMPricingSkipsRowsWithoutTokenPricing() throws {
        let data = Data("""
        {
          "github_copilot/gpt-5": {
            "litellm_provider": "github_copilot",
            "base_model": "gpt-5"
          }
        }
        """.utf8)

        let prices = try ModelPricingService.parseLiteLLMPrices(from: data)

        XCTAssertTrue(prices.isEmpty)
    }

    func testLiteLLMPricingSkipsOpenRouterRows() throws {
        let data = Data("""
        {
          "openrouter/openai/gpt-5.5": {
            "litellm_provider": "openrouter",
            "input_cost_per_token": 0.000005,
            "output_cost_per_token": 0.00003
          }
        }
        """.utf8)

        let prices = try ModelPricingService.parseLiteLLMPrices(from: data)

        XCTAssertTrue(prices.isEmpty)
    }

    func testPricingDoesNotFallbackAcrossDifferentProviders() throws {
        let data = Data("""
        {
          "gpt-5": {
            "litellm_provider": "openai",
            "input_cost_per_token": 0.00000125,
            "output_cost_per_token": 0.00001
          }
        }
        """.utf8)

        let prices = try ModelPricingService.parseLiteLLMPrices(from: data)
        let price = ModelPricingService.bestPrice(for: "Local", model: "gpt-5", in: prices)

        XCTAssertNil(price)
    }

    func testDetectModeUsesThinkingWhenEnabled() {
        let body: [String: Any] = [
            "model": "claude-sonnet-4-6",
            "thinking": ["type": "enabled"],
            "messages": [["role": "user", "content": "hi"]],
        ]

        XCTAssertEqual(TokenUsageService.detectMode(in: body, inputTokens: 1, longContextThreshold: nil), "think")
    }

    func testDetectModeUsesBackgroundForTitleGeneration() {
        let body: [String: Any] = [
            "model": "claude-haiku",
            "messages": [[
                "role": "system",
                "content": [[
                    "type": "text",
                    "text": "Generate a concise, sentence-case title (3-7 words) that captures the main topic or goal of this coding session.",
                ]],
            ]],
        ]

        XCTAssertEqual(TokenUsageService.detectMode(in: body, inputTokens: 10, longContextThreshold: nil), "background")
    }

    func testDetectModeUsesImageWhenImageContentExists() {
        let body: [String: Any] = [
            "model": "claude-sonnet",
            "messages": [[
                "role": "user",
                "content": [["type": "image", "source": ["media_type": "image/png"]]],
            ]],
        ]

        XCTAssertEqual(TokenUsageService.detectMode(in: body, inputTokens: 10, longContextThreshold: nil), "image")
    }

    func testDetectModeUsesLongContextThreshold() {
        let body: [String: Any] = [
            "model": "claude-sonnet",
            "messages": [["role": "user", "content": "large context"]],
        ]

        XCTAssertEqual(TokenUsageService.detectMode(in: body, inputTokens: 60_000, longContextThreshold: 60_000), "longContext")
    }

    func testDetectModeDoesNotTreatPassiveWebSearchTextAsWebSearch() {
        let body: [String: Any] = [
            "model": "claude-sonnet",
            "messages": [[
                "role": "user",
                "content": "Available tool metadata mentions web_search, but this request did not use it.",
            ]],
            "tools": [["name": "WebSearch"]],
        ]

        XCTAssertEqual(TokenUsageService.detectMode(in: body, inputTokens: 10, longContextThreshold: nil), "default")
    }

    func testDetectModeUsesWebSearchForActiveToolUse() {
        let body: [String: Any] = [
            "model": "claude-sonnet",
            "messages": [[
                "role": "assistant",
                "content": [["type": "tool_use", "name": "WebSearch"]],
            ]],
        ]

        XCTAssertEqual(TokenUsageService.detectMode(in: body, inputTokens: 10, longContextThreshold: nil), "webSearch")
    }

    func testLiveTokenMeterEstimatesTokensFromSSETextDelta() {
        let chunk = """
        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"abcdefghijkl"}}

        """.data(using: .utf8)!

        XCTAssertEqual(LiveTokenGenerationMeter.estimatedOutputTokens(from: chunk), 3)
    }

    func testLiveTokenMeterIgnoresSSEWithoutGeneratedText() {
        let chunk = """
        event: message_start
        data: {"type":"message_start","message":{"usage":{"input_tokens":10,"output_tokens":0}}}

        """.data(using: .utf8)!

        XCTAssertEqual(LiveTokenGenerationMeter.estimatedOutputTokens(from: chunk), 0)
    }

    func testLiveTokenMeterRestoresActiveStatusSnapshot() throws {
        let updatedAt = ISO8601DateFormatter().string(from: Date())
        let data = Data("""
        {
          "isActive": true,
          "updatedAt": "\(updatedAt)",
          "outputTokens": 120,
          "tokensPerSecond": 42.5,
          "models": [
            {
              "provider": "openrouter",
              "model": "x-ai/grok-4.20",
              "outputTokens": 120,
              "tokensPerSecond": 42.5,
              "requestCount": 1
            }
          ]
        }
        """.utf8)

        let snapshot = try XCTUnwrap(LiveTokenGenerationMeter.snapshot(fromStatusData: data))
        XCTAssertTrue(snapshot.isVisible)
        XCTAssertEqual(snapshot.models.first?.model, "x-ai/grok-4.20")
        XCTAssertEqual(snapshot.tokensPerSecond, 42.5, accuracy: 0.001)
    }

    func testLiveTokenMeterIgnoresInactiveStatusSnapshot() {
        let updatedAt = ISO8601DateFormatter().string(from: Date())
        let data = Data("""
        {
          "isActive": false,
          "updatedAt": "\(updatedAt)",
          "outputTokens": 120,
          "tokensPerSecond": 42.5,
          "models": [
            {
              "provider": "openrouter",
              "model": "x-ai/grok-4.20",
              "outputTokens": 120,
              "tokensPerSecond": 42.5,
              "requestCount": 1
            }
          ]
        }
        """.utf8)

        XCTAssertNil(LiveTokenGenerationMeter.snapshot(fromStatusData: data))
    }
}
