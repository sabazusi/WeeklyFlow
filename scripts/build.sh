#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
developer_dir="${DEVELOPER_DIR:-}"

if [[ -z "$developer_dir" ]]; then
    developer_dir="$(xcode-select -p 2>/dev/null || true)"
    if [[ "$developer_dir" == */CommandLineTools && -d /Applications/Xcode.app/Contents/Developer ]]; then
        developer_dir=/Applications/Xcode.app/Contents/Developer
    fi
fi

if [[ -z "$developer_dir" || ! -x "$developer_dir/usr/bin/xcodebuild" ]]; then
    echo "Xcodeが見つかりません。Xcodeをインストールするか、DEVELOPER_DIRを指定してください。" >&2
    exit 1
fi

export DEVELOPER_DIR="$developer_dir"
build_dir="$repo_root/build"
derived_data="$build_dir/DerivedData"
app_source="$derived_data/Build/Products/Release/WeeklyFlow.app"
app_output="$build_dir/WeeklyFlow.app"

mkdir -p "$build_dir"
xcodebuild \
    -project "$repo_root/WeeklyFlow.xcodeproj" \
    -scheme WeeklyFlow \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$derived_data" \
    CODE_SIGNING_ALLOWED=NO \
    build

if [[ ! -d "$app_source" ]]; then
    echo "ビルドは完了しましたが、WeeklyFlow.appが見つかりません。" >&2
    exit 1
fi

rm -rf "$app_output"
ditto "$app_source" "$app_output"
codesign --force --sign - "$app_output"
codesign --verify --strict "$app_output"

echo "ビルド完了: $app_output"
echo "起動するには: open \"$app_output\""
