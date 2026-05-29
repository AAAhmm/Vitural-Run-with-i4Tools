using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Security.Principal;
using System.Text;
using System.Threading;

class VirtualRunLauncher
{
    [STAThread]
    static int Main(string[] args)
    {
        // ---- Self-elevate if not admin ----
        if (!IsAdministrator())
        {
            var psi = new ProcessStartInfo
            {
                FileName = Process.GetCurrentProcess().MainModule.FileName,
                UseShellExecute = true,
                Verb = "runas"
            };
            // Pass through all original arguments
            if (args.Length > 0)
                psi.Arguments = string.Join(" ", Array.ConvertAll(args, EscapeArg));

            try { Process.Start(psi); }
            catch (System.ComponentModel.Win32Exception)
            {
                // User declined UAC
                return 1;
            }
            return 0;
        }

        // ---- Extract embedded PowerShell script ----
        string exeDir = Path.GetDirectoryName(Process.GetCurrentProcess().MainModule.FileName);
        string scriptPath = Path.Combine(exeDir, "VirtualRun.ps1");

        // Write the embedded script to disk (so calibration data persists alongside EXE)
        using (var stream = Assembly.GetExecutingAssembly()
            .GetManifestResourceStream("VirtualRun.VirtualRun.ps1"))
        {
            if (stream == null)
            {
                Console.WriteLine("ERROR: Embedded script not found in EXE resources.");
                Console.WriteLine("Press Enter...");
                Console.ReadLine();
                return 1;
            }

            string currentScript;
            using (var reader = new StreamReader(stream, Encoding.UTF8))
            {
                currentScript = reader.ReadToEnd();
            }

            // Only overwrite if different (preserves user's script if they want to customize)
            string existingScript = null;
            if (File.Exists(scriptPath))
            {
                existingScript = File.ReadAllText(scriptPath, Encoding.UTF8);
            }

            if (existingScript != currentScript)
            {
                File.WriteAllText(scriptPath, currentScript, new UTF8Encoding(true)); // BOM
            }
        }

        // ---- Launch PowerShell ----
        string psArgs = string.Join(" ", Array.ConvertAll(args, EscapeArg));
        string fullArgs = "-ExecutionPolicy Bypass -NoProfile -File \"" + scriptPath + "\"";
        if (!string.IsNullOrEmpty(psArgs))
            fullArgs += " " + psArgs;

        var process = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                Arguments = fullArgs,
                UseShellExecute = false,
                RedirectStandardOutput = false,
                RedirectStandardError = false,
                CreateNoWindow = false,
                WorkingDirectory = exeDir
            }
        };

        process.Start();
        process.WaitForExit();
        return process.ExitCode;
    }

    static bool IsAdministrator()
    {
        try
        {
            using (var identity = WindowsIdentity.GetCurrent())
            {
                var principal = new WindowsPrincipal(identity);
                return principal.IsInRole(WindowsBuiltInRole.Administrator);
            }
        }
        catch { return false; }
    }

    /// <summary>Escape a command-line argument for safe passing through Process.Start</summary>
    static string EscapeArg(string arg)
    {
        if (string.IsNullOrEmpty(arg)) return "\"\"";
        if (arg.Contains(" ") || arg.Contains("\""))
            return "\"" + arg.Replace("\"", "\\\"") + "\"";
        return arg;
    }
}
