using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using MicType.Win.Core;

namespace MicType.Win.Services;

public static class CredentialStore
{
    private const uint CredTypeGeneric = 1;
    private const uint CredPersistSession = 1;
    private const uint CredPersistLocalMachine = 2;

    public static void Save(string targetName, string secret)
    {
        var trimmed = secret.Trim();
        if (trimmed.Length == 0)
        {
            // 空输入绝不删除已存的 Key——清空必须是显式动作，不能是"框是空的"的副作用
            Log.Info($"Credential save skipped (empty input) target={targetName} — existing key untouched");
            return;
        }
        Delete(targetName);

        var bytes = Encoding.Unicode.GetBytes(trimmed);
        var blob = Marshal.AllocCoTaskMem(bytes.Length);
        try
        {
            Marshal.Copy(bytes, 0, blob, bytes.Length);
            var credential = new NativeCredential
            {
                Type = CredTypeGeneric,
                TargetName = targetName,
                CredentialBlobSize = (uint)bytes.Length,
                CredentialBlob = blob,
                Persist = CredPersistLocalMachine,
                UserName = Environment.UserName
            };

            if (CredWrite(ref credential, 0))
            {
                Log.Info($"Credential saved target={targetName} persist=LocalMachine");
            }
            else
            {
                var err = Marshal.GetLastWin32Error();
                Log.Warn($"CredWrite LocalMachine failed lastError={err} target={targetName} — retrying with Session persistence");
                credential.Persist = CredPersistSession;
                if (!CredWrite(ref credential, 0))
                {
                    throw new InvalidOperationException("CredWrite failed: " + Marshal.GetLastWin32Error());
                }
                Log.Warn($"Credential stored with SESSION persistence only target={targetName} — it will not survive logout; this machine restricts persisted credentials");
            }
        }
        finally
        {
            CryptographicOperations.ZeroMemory(bytes);
            Marshal.FreeCoTaskMem(blob);
        }
    }

    public static string? Load(string targetName)
    {
        if (!CredRead(targetName, CredTypeGeneric, 0, out var credentialPtr))
        {
            return null;
        }

        try
        {
            var credential = Marshal.PtrToStructure<NativeCredential>(credentialPtr);
            if (credential.CredentialBlob == IntPtr.Zero || credential.CredentialBlobSize == 0)
            {
                return null;
            }

            var bytes = new byte[credential.CredentialBlobSize];
            Marshal.Copy(credential.CredentialBlob, bytes, 0, bytes.Length);
            var value = Encoding.Unicode.GetString(bytes).TrimEnd('\0');
            return string.IsNullOrWhiteSpace(value) ? null : value;
        }
        finally
        {
            CredFree(credentialPtr);
        }
    }

    public static void Delete(string targetName)
    {
        CredDelete(targetName, CredTypeGeneric, 0);
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct NativeCredential
    {
        public uint Flags;
        public uint Type;
        public string TargetName;
        public string? Comment;
        public long LastWritten;
        public uint CredentialBlobSize;
        public IntPtr CredentialBlob;
        public uint Persist;
        public uint AttributeCount;
        public IntPtr Attributes;
        public string? TargetAlias;
        public string UserName;
    }

    [DllImport("advapi32.dll", EntryPoint = "CredWriteW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredWrite(ref NativeCredential userCredential, uint flags);

    [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredRead(string target, uint type, uint reservedFlag, out IntPtr credentialPtr);

    [DllImport("advapi32.dll", EntryPoint = "CredDeleteW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredDelete(string target, uint type, uint flags);

    [DllImport("advapi32.dll", SetLastError = false)]
    private static extern void CredFree(IntPtr buffer);
}
