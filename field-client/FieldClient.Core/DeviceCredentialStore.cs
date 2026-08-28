using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;

namespace Xiangshang.FieldClient;

public static class DeviceCredentialSource
{
    public static DeviceCredentials Resolve(string? environmentDeviceId, string? environmentDeviceKey, Func<DeviceCredentials?> credentialReader)
    {
        var hasEnvironmentValue = !string.IsNullOrWhiteSpace(environmentDeviceId) || !string.IsNullOrWhiteSpace(environmentDeviceKey);
        if (hasEnvironmentValue)
        {
            if (string.IsNullOrWhiteSpace(environmentDeviceId) || string.IsNullOrWhiteSpace(environmentDeviceKey))
            {
                throw new InvalidOperationException("FIELD_DEVICE_ID 与 FIELD_DEVICE_KEY 必须同时提供。");
            }
            return new DeviceCredentials(environmentDeviceId!.Trim(), environmentDeviceKey!.Trim());
        }

        var stored = credentialReader();
        if (stored is not null && !string.IsNullOrWhiteSpace(stored.DeviceId) && !string.IsNullOrWhiteSpace(stored.DeviceKey))
        {
            return new DeviceCredentials(stored.DeviceId.Trim(), stored.DeviceKey.Trim());
        }
        throw new InvalidOperationException("未找到设备凭证。请由部署工具写入 Windows Credential Manager（XiangshangField:DeviceCredentials），或仅在首次部署时同时提供 FIELD_DEVICE_ID 与 FIELD_DEVICE_KEY。");
    }
}

public static class WindowsCredentialStore
{
    public const string DeviceCredentialTarget = "XiangshangField:DeviceCredentials";
    private const uint CredTypeGeneric = 1;
    private const uint CredPersistLocalMachine = 2;

    public static DeviceCredentials? TryReadDeviceCredentials(string target = DeviceCredentialTarget)
    {
        if (!OperatingSystem.IsWindows() || !CredRead(target, CredTypeGeneric, 0, out var pointer)) return null;
        try
        {
            var credential = Marshal.PtrToStructure<NativeCredential>(pointer);
            if (credential.CredentialBlob == IntPtr.Zero || credential.CredentialBlobSize == 0) return null;
            var deviceId = Marshal.PtrToStringUni(credential.UserName);
            var deviceKey = Marshal.PtrToStringUni(credential.CredentialBlob, checked((int)credential.CredentialBlobSize) / sizeof(char));
            return string.IsNullOrWhiteSpace(deviceId) || string.IsNullOrWhiteSpace(deviceKey) ? null : new DeviceCredentials(deviceId, deviceKey);
        }
        finally
        {
            CredFree(pointer);
        }
    }

    public static void SaveDeviceCredentials(DeviceCredentials credentials, string target = DeviceCredentialTarget)
    {
        ArgumentNullException.ThrowIfNull(credentials);
        ArgumentException.ThrowIfNullOrWhiteSpace(credentials.DeviceId);
        ArgumentException.ThrowIfNullOrWhiteSpace(credentials.DeviceKey);
        ArgumentException.ThrowIfNullOrWhiteSpace(target);
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException("Windows Credential Manager 仅可在 Windows 场地端使用。");

        var deviceId = credentials.DeviceId.Trim();
        var keyBytes = Encoding.Unicode.GetBytes(credentials.DeviceKey.Trim());
        if (deviceId.Length > 512 || keyBytes.Length > 2560) throw new ArgumentException("设备凭证长度超过 Windows Credential Manager 限制。", nameof(credentials));
        var blob = Marshal.AllocCoTaskMem(keyBytes.Length);
        try
        {
            Marshal.Copy(keyBytes, 0, blob, keyBytes.Length);
            var credential = new WritableNativeCredential
            {
                Type = CredTypeGeneric,
                TargetName = target,
                CredentialBlobSize = checked((uint)keyBytes.Length),
                CredentialBlob = blob,
                Persist = CredPersistLocalMachine,
                UserName = deviceId
            };
            if (!CredWrite(ref credential, 0)) throw new Win32Exception(Marshal.GetLastWin32Error(), "无法将设备凭证写入 Windows Credential Manager。");
        }
        finally
        {
            CryptographicOperations.ZeroMemory(keyBytes);
            if (blob != IntPtr.Zero)
            {
                Marshal.Copy(new byte[keyBytes.Length], 0, blob, keyBytes.Length);
                Marshal.FreeCoTaskMem(blob);
            }
        }
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct NativeCredential
    {
        public uint Flags;
        public uint Type;
        public IntPtr TargetName;
        public IntPtr Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public uint CredentialBlobSize;
        public IntPtr CredentialBlob;
        public uint Persist;
        public uint AttributeCount;
        public IntPtr Attributes;
        public IntPtr TargetAlias;
        public IntPtr UserName;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WritableNativeCredential
    {
        public uint Flags;
        public uint Type;
        [MarshalAs(UnmanagedType.LPWStr)] public string TargetName;
        public IntPtr Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public uint CredentialBlobSize;
        public IntPtr CredentialBlob;
        public uint Persist;
        public uint AttributeCount;
        public IntPtr Attributes;
        public IntPtr TargetAlias;
        [MarshalAs(UnmanagedType.LPWStr)] public string UserName;
    }

    [DllImport("Advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CredRead(string target, uint type, uint flags, out IntPtr credential);

    [DllImport("Advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CredWrite(ref WritableNativeCredential credential, uint flags);

    [DllImport("Advapi32.dll", SetLastError = true)]
    private static extern void CredFree(IntPtr buffer);
}
