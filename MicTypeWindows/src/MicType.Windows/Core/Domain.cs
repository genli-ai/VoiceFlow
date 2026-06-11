namespace MicType.Win.Core;

public enum Phase
{
    Idle,
    Recording,
    Processing
}

public enum AppLanguage
{
    Zh,
    En
}

public enum HotkeyChoice
{
    RightControl,
    RightShift,
    CapsLock
}

public enum PolishLevel
{
    Off,
    Smart
}

public enum LlmProvider
{
    OpenAi,
    DeepSeek
}

public enum SelectionAction
{
    Modify,
    Reply,
    New
}

public sealed record HistoryItem(DateTimeOffset Date, string Raw, string Polished);

public sealed class MTException(string message) : Exception(message)
{
    public string UserMessage => Message;
}
