using MicType.Win.Core;
using System.Media;

namespace MicType.Win.Services;

public static class Sounds
{
    public static void PlayStart()
    {
        if (SettingsStore.Instance.Current.PlaySounds) SystemSounds.Question.Play();
    }

    public static void PlaySuccess()
    {
        if (SettingsStore.Instance.Current.PlaySounds) SystemSounds.Asterisk.Play();
    }

    public static void PlayError()
    {
        if (SettingsStore.Instance.Current.PlaySounds) SystemSounds.Hand.Play();
    }

    public static void PlayCancel()
    {
        if (SettingsStore.Instance.Current.PlaySounds) SystemSounds.Exclamation.Play();
    }
}
