#!/usr/bin/env bash
#
# 一键发布到 GitHub：建库（已存在则跳过）→ 推送源码 → 打 tag → 建 Release → 上传 APK
#
# 用法：
#   GITHUB_TOKEN=ghp_xxx bash tools/publish.sh
#
# 可选环境变量：
#   GITHUB_OWNER  账号，默认 suiyuanmingjing
#   REPO_NAME     仓库名，默认 cctv-native
#   VISIBLE       public | private，默认 public
#   TAG           标签，默认 v1.0
#   RELEASE_NAME  发布标题，默认 "CCTV-直播 v1.0（带/不带内核）"
set -euo pipefail

OWNER="${GITHUB_OWNER:-suiyuanmingjing}"
REPO="${REPO_NAME:-cctv-native}"
VISIBLE="${VISIBLE:-public}"
TAG="${TAG:-v1.0}"
RELEASE_NAME="${RELEASE_NAME:-CCTV-直播 v1.0（带/不带内核）}"

if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "缺少 GITHUB_TOKEN。" >&2
  echo "  GITHUB_TOKEN=xxx bash tools/publish.sh" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# --- token 只落临时文件，并通过 GIT_ASKPASS 交给 git，不写进命令行或 .git/config ---
TOKEN_FILE=$(mktemp)
ASKPASS=$(mktemp)
trap 'rm -f "$TOKEN_FILE" "$ASKPASS"' EXIT
printf '%s' "${GITHUB_TOKEN}" > "$TOKEN_FILE"
chmod 600 "$TOKEN_FILE"
printf '#!/bin/sh\ncat %s\n' "$TOKEN_FILE" > "$ASKPASS"
chmod 700 "$ASKPASS"
export GIT_ASKPASS="$ASKPASS"
export GIT_TERMINAL_PROMPT=0

API="https://api.github.com"
auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}" -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28")

echo "==> 1/4 创建仓库 ${OWNER}/${REPO}"
code=$(curl -sS -o /tmp/gh_create.json -w '%{http_code}' -X POST "${API}/user/repos" "${auth[@]}" \
  -d "{\"name\":\"${REPO}\",\"private\":$([ "${VISIBLE}" = "private" ] && echo true || echo false),\"description\":\"CCTV 直播 Android 版：打开即全屏播放官网直播\"}")
case "$code" in
  201) echo "    已创建" ;;
  422) echo "    仓库已存在，继续" ;;
  *)   echo "    创建失败 HTTP ${code}"; cat /tmp/gh_create.json; exit 1 ;;
esac

echo "==> 2/4 推送源码"
git branch -M main
git remote remove origin 2>/dev/null || true
git remote add origin "https://github.com/${OWNER}/${REPO}.git"
if ! git push -u origin main 2>/tmp/gh_push.err; then
  echo "    普通推送失败，改用强制推送（仓库里可能已有自动生成的 README 提交）"
  git push -u --force origin main || { cat /tmp/gh_push.err; exit 1; }
fi

echo "==> 3/4 打标签 ${TAG}"
git tag -f "${TAG}"
git push -f origin "${TAG}"

echo "==> 4/4 创建 Release 并上传 APK"
BODY=$(cat <<'RELEASE_BODY'
### 两个版本，任选其一

| 文件 | 区别 |
| --- | --- |
| `cctv-1.0-guard.apk` | 启动时检查系统浏览器内核版本，太低会提示更新 |
| `cctv-1.0-plain.apk` | 不做任何检测，行为同以前 |

两个包名不同（`com.cctv.fullscreen.guard` 与 `com.cctv.fullscreen`），**可以同时安装对比**。

### 说明

- 系统要求：Android 5.0 及以上
- 「不带内核」版用系统自带浏览器内核；「带内核」版内置 GeckoView（安装包大很多）
- 只加载 CCTV 官网公开直播页面，不解析、不代理、不保存任何视频内容
- 这两个包是 **debug 签名**，仅供侧载测试

### 用法

| 操作 | 效果 |
| --- | --- |
| 主页点频道 | 开始播放 |
| 播放时上下滑 | 换台 |
| 播放时从左往右滑 | 打开频道列表 |
| 返回键 | 回主页 |
RELEASE_BODY
)

payload=$(python3 -c 'import json,sys; print(json.dumps({"tag_name":sys.argv[1],"name":sys.argv[2],"body":sys.argv[3]}))' "${TAG}" "${RELEASE_NAME}" "${BODY}")
code=$(curl -sS -o /tmp/gh_release.json -w '%{http_code}' -X POST \
  "${API}/repos/${OWNER}/${REPO}/releases" "${auth[@]}" -d "${payload}")
if [ "$code" = "422" ]; then
  echo "    Release 已存在，复用已有的"
  curl -sS -o /tmp/gh_release.json "${auth[@]}" "${API}/repos/${OWNER}/${REPO}/releases/tags/${TAG}"
elif [ "$code" != "201" ]; then
  echo "    创建 Release 失败 HTTP ${code}"; cat /tmp/gh_release.json; exit 1
fi

UPLOAD=$(python3 -c 'import json;print(json.load(open("/tmp/gh_release.json"))["upload_url"].split("{")[0])')
ASSETS=$(python3 -c 'import json;print(" ".join(a["name"] for a in json.load(open("/tmp/gh_release.json")).get("assets",[])))')

for apk in dist/cctv-1.0-gecko.apk dist/cctv-1.0-webview.apk; do
  if [ ! -f "$apk" ]; then echo "    缺少 $apk，跳过"; continue; fi
  name=$(basename "$apk")
  case " $ASSETS " in
    *" $name "*) echo "    $name 已上传，跳过"; continue ;;
  esac
  echo -n "    上传 $name ... "
  curl -sS -o /dev/null -w "HTTP %{http_code}\n" -X POST "${UPLOAD}?name=${name}" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Content-Type: application/vnd.android.package-archive" \
    --data-binary "@${apk}"
done

echo
echo "完成 → https://github.com/${OWNER}/${REPO}/releases/tag/${TAG}"
