using System.Diagnostics;
using System.Net.Http;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using MicType.Win.Core;

namespace MicType.Win.Services;

public sealed record ChatMessage(string Role, string Content);

public static class LlmClient
{
    private static readonly HttpClient Client = new();

    public static async Task PrewarmAsync(CancellationToken cancellationToken = default)
    {
        var settings = SettingsStore.Instance.Current;
        var key = CredentialStore.Load(settings.CurrentCredentialTarget);
        if (string.IsNullOrWhiteSpace(key)) return;

        var baseUrl = settings.CurrentBaseUrl.TrimEnd('/');
        using var request = new HttpRequestMessage(HttpMethod.Get, baseUrl + "/models");
        request.Headers.Authorization = new("Bearer", key);

        using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        cts.CancelAfter(TimeSpan.FromSeconds(5));
        try
        {
            using var _ = await Client.SendAsync(request, cts.Token);
        }
        catch
        {
            // Deliberately ignored: this is a latency prewarm only.
        }
    }

    public static async Task<(bool Ok, string Message)> TestModelAsync(string model, CancellationToken cancellationToken = default)
    {
        var start = Stopwatch.StartNew();
        var result = await ChatAsync(
            [new ChatMessage("user", "请只回复一个字：好")],
            temperature: null,
            timeout: TimeSpan.FromSeconds(30),
            model,
            cancellationToken);

        var elapsed = start.Elapsed.TotalSeconds.ToString("0.0");
        return result.Text is not null
            ? (true, $"✓ {elapsed}s · {L10n.Tr("返回：", "Response: ")}{result.Text[..Math.Min(20, result.Text.Length)]}")
            : (false, "✗ " + (result.Error ?? L10n.Tr("未知原因", "unknown")));
    }

    public static async Task<(string? Text, string? Error)> ChatAsync(
        IReadOnlyList<ChatMessage> messages,
        double? temperature,
        TimeSpan timeout,
        string model,
        CancellationToken cancellationToken = default)
    {
        var first = await PerformAsync(messages, temperature, timeout, model, cancellationToken);
        if (first.Text is null && temperature is not null &&
            first.Error?.Contains("temperature", StringComparison.OrdinalIgnoreCase) == true)
        {
            return await PerformAsync(messages, null, timeout, model, cancellationToken);
        }

        return first;
    }

    private static async Task<(string? Text, string? Error)> PerformAsync(
        IReadOnlyList<ChatMessage> messages,
        double? temperature,
        TimeSpan timeout,
        string model,
        CancellationToken cancellationToken)
    {
        var settings = SettingsStore.Instance.Current;
        var key = CredentialStore.Load(settings.CurrentCredentialTarget);
        if (string.IsNullOrWhiteSpace(key))
        {
            return (null, L10n.Tr("未配置 API Key", "No API key configured"));
        }

        var baseUrl = settings.CurrentBaseUrl.Trim().TrimEnd('/');
        if (!Uri.TryCreate(baseUrl + "/chat/completions", UriKind.Absolute, out var uri))
        {
            return (null, L10n.Tr("Base URL 格式不对", "Invalid base URL"));
        }

        for (var attempt = 0; attempt < 2; attempt++)
        {
            using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            cts.CancelAfter(timeout);
            try
            {
                using var request = CreateChatRequest(uri, key, model, messages, temperature);
                using var response = await Client.SendAsync(request, cts.Token);
                var raw = await response.Content.ReadAsStringAsync(cts.Token);
                if (!response.IsSuccessStatusCode)
                {
                    return (null, DescribeHttpError((int)response.StatusCode, raw));
                }

                var parsed = JsonSerializer.Deserialize<ChatResponse>(raw, JsonOptions);
                var content = parsed?.Choices?.FirstOrDefault()?.Message?.Content?.Trim();
                return string.IsNullOrWhiteSpace(content)
                    ? (null, L10n.Tr("模型返回了空内容", "Model returned empty content"))
                    : (content, null);
            }
            catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
            {
                if (attempt == 0) continue;
                return (null, L10n.Tr("请求超时（已重试，网络到 API 太慢）", "Request timed out (retried — network to the API is slow)"));
            }
            catch (HttpRequestException ex)
            {
                if (attempt == 0) continue;
                return (null, ex.Message + L10n.Tr("（已重试）", " (retried)"));
            }
        }

        return (null, L10n.Tr("未知网络错误", "Unknown network error"));
    }

    private static HttpRequestMessage CreateChatRequest(
        Uri uri,
        string key,
        string model,
        IReadOnlyList<ChatMessage> messages,
        double? temperature)
    {
        var body = new ChatRequest(
            model,
            messages.Select(m => new WireMessage(m.Role, m.Content)).ToList(),
            temperature);
        var request = new HttpRequestMessage(HttpMethod.Post, uri);
        request.Headers.Authorization = new("Bearer", key);
        request.Content = JsonContent.Create(body, options: JsonOptions);
        return request;
    }

    private static string DescribeHttpError(int statusCode, string raw)
    {
        var detail = "";
        try
        {
            var json = JsonSerializer.Deserialize<ApiErrorResponse>(raw, JsonOptions);
            if (!string.IsNullOrWhiteSpace(json?.Error?.Message))
            {
                detail = "：" + json.Error.Message[..Math.Min(60, json.Error.Message.Length)];
            }
        }
        catch
        {
            // ignore malformed error bodies
        }

        return statusCode switch
        {
            401 => L10n.Tr("API Key 无效 (401)", "Invalid API key (401)") + detail,
            404 => L10n.Tr("模型名不存在 (404)", "Model not found (404)") + detail,
            429 => L10n.Tr("限流或余额不足 (429)", "Rate limited or out of credit (429)") + detail,
            _ => L10n.Tr("接口返回 ", "API returned ") + statusCode + detail
        };
    }

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower
    };

    private sealed record ChatRequest(string Model, List<WireMessage> Messages, double? Temperature);
    private sealed record WireMessage(string Role, string Content);
    private sealed record ChatResponse(List<Choice>? Choices);
    private sealed record Choice(WireMessage? Message);
    private sealed record ApiErrorResponse(ApiError? Error);
    private sealed record ApiError(string? Message);
}
