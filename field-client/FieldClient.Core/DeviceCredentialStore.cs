using System.Runtime.InteropServices;

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

    [DllImport("Advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CredRead(string target, uint type, uint flags, out IntPtr credential);

    [DllImport("Advapi32.dll", SetLastError = true)]
    private static extern void CredFree(IntPtr buffer);
}
