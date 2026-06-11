namespace MicType.Win.Services;

public static class SkillRouter
{
    public static bool IsReplyTrigger(string text)
    {
        var compact = text.Trim()
            .Replace(" ", "")
            .Replace("，", "")
            .Replace(",", "")
            .ToLowerInvariant();
        string[] triggers =
        [
            "帮我回复", "帮我回一下", "帮我回个", "帮我回他", "帮我回她", "帮我答复",
            "你帮我回复", "回复他", "回复她", "回复这个", "回复一下", "回复对方",
            "helpmereply", "draftareply", "replyto"
        ];
        return triggers.Any(compact.StartsWith);
    }
}
