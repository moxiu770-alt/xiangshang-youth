#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
repo_root="$(CDPATH= cd -- "$script_dir/.." && pwd)"
project="$script_dir/FieldClient.Windows/FieldClient.Windows.csproj"
release_dir="${FIELD_CLIENT_RELEASE_DIR:-$repo_root/backend/storage/releases}"
version="${FIELD_CLIENT_VERSION:-0.4.27}"
archive_name="xiangshang-field-client-windows-x64.zip"
manifest_name="field-client-release.json"

if [[ -n "${DOTNET_ROOT:-}" && -x "$DOTNET_ROOT/dotnet" ]]; then
  dotnet_cmd="$DOTNET_ROOT/dotnet"
elif command -v dotnet >/dev/null 2>&1; then
  dotnet_cmd="$(command -v dotnet)"
else
  echo "未找到 .NET 8 SDK。请在发布机安装 SDK，现场 Windows 客户端不需要安装。" >&2
  exit 1
fi

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/xiangshang-field-release.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
publish_dir="$work_dir/向上少年场地端"
mkdir -p "$publish_dir" "$release_dir"

"$dotnet_cmd" restore "$project" --locked-mode
"$dotnet_cmd" publish "$project" \
  --configuration Release \
  --runtime win-x64 \
  --self-contained true \
  --no-restore \
  --output "$publish_dir" \
  -p:Version="$version" \
  -p:PublishSingleFile=true \
  -p:IncludeNativeLibrariesForSelfExtract=true \
  -p:DebugType=None \
  -p:DebugSymbols=false

cp "$script_dir/README-WINDOWS.txt" "$publish_dir/开始使用.txt"
mkdir -p "$publish_dir/采集适配器"
cp "$script_dir/ADAPTER-README.txt" "$publish_dir/采集适配器/放置厂商适配器.txt"
archive_tmp="$work_dir/$archive_name"
(
  cd "$work_dir"
  zip -q -r -X "$archive_tmp" "向上少年场地端"
)

archive_path="$release_dir/$archive_name"
mv "$archive_tmp" "$archive_path"
checksum="$(shasum -a 256 "$archive_path" | awk '{print $1}')"
size_bytes="$(wc -c < "$archive_path" | tr -d ' ')"
generated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

node -e 'const fs=require("fs"); const [target,version,fileName,sizeBytes,sha256,generatedAt]=process.argv.slice(1); fs.writeFileSync(target, JSON.stringify({version,platform:"Windows 10/11 x64",runtime:"win-x64 self-contained",fileName,sizeBytes:Number(sizeBytes),sha256,generatedAt,unsigned:true},null,2)+"\n")' \
  "$release_dir/$manifest_name" "$version" "$archive_name" "$size_bytes" "$checksum" "$generated_at"

echo "Windows 场地端发布完成"
echo "压缩包：$archive_path"
echo "大小：$size_bytes bytes"
echo "SHA-256：$checksum"
