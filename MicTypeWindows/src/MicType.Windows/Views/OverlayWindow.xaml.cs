using System.Windows;
using System.Windows.Media;
using System.Windows.Threading;
using Forms = System.Windows.Forms;

namespace MicType.Win.Views;

public partial class OverlayWindow : Window
{
    private int _generation;

    public OverlayWindow()
    {
        InitializeComponent();
    }

    public void ShowRecording(string label)
    {
        _generation++;
        Spinner.Visibility = Visibility.Collapsed;
        Dot.Visibility = Visibility.Visible;
        Dot.Fill = new SolidColorBrush(Color.FromRgb(248, 113, 113));
        MessageText.Text = label;
        Position();
        Show();
    }

    public void ShowProcessing(string label)
    {
        _generation++;
        Dot.Visibility = Visibility.Collapsed;
        Spinner.Visibility = Visibility.Visible;
        MessageText.Text = label;
        Position();
        Show();
    }

    public void FlashSuccess(string label)
    {
        Flash(label, Color.FromRgb(34, 197, 94), TimeSpan.FromSeconds(1));
    }

    public void FlashError(string label)
    {
        Flash(label, Color.FromRgb(250, 204, 21), TimeSpan.FromSeconds(2.5));
    }

    private void Flash(string label, Color color, TimeSpan duration)
    {
        _generation++;
        var generation = _generation;
        Spinner.Visibility = Visibility.Collapsed;
        Dot.Visibility = Visibility.Visible;
        Dot.Fill = new SolidColorBrush(color);
        MessageText.Text = label;
        Position();
        Show();
        var timer = new DispatcherTimer { Interval = duration };
        timer.Tick += (_, _) =>
        {
            timer.Stop();
            if (_generation == generation) Hide();
        };
        timer.Start();
    }

    private void Position()
    {
        var area = Forms.Screen.FromPoint(Forms.Cursor.Position).WorkingArea;
        Left = area.Left + (area.Width - Width) / 2;
        Top = area.Bottom - Height - 28;
    }
}
