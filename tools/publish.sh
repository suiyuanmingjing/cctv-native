#!/usr/bin/env bash
#
# 一键发布到 GitHub：建库 → 推送源码 → 打 tag → 建 Release → 上传两个 APK
#
# 用法：
#   GITHUB_TOKEN=ghp_xxx bash tools/publish.sh
#
# 可选环境变量：
#   REPO_NAME     仓库名，默认 cctv-native
#   VISIBLE       public | private，默认 public
#   TAG           标签，默认 v1.0
#   RELEASE_NAME  发布标题，默认 "CCTV-直播 v1.0（带/不带内核）"
#
# token 需要 repo 权限（建库 + 推送 + 建 Release）。
set -euo pipefail

OWNER="${GITHUB_OWNER:-suiyuanmingjing}"
REPO="${REPO_NAME:-cctv-native}"
VISIBLE="${VISIBLE:-public}"
TAG="${TAG:-v1.0}"
RELEASE_NAME="${RELEASE_NAME:-CCTV-直播 v1.0（带/不带内核）}"

if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "缺少 GITHUB_TOKEN。" >&2
  echo "到 GitHub → Settings → Developer settings → Personal access tokens" >&2
  echo "生成一个带 repo 权限的 token，然后：" >&2
  echo "  GITHUB_TOKEN=xxx bash tools/publish.sh" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

API="https://api.github.com"
auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}" -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28")
gitauth=(-c "http.extraheader=AUTHORIZATION: bearer ${GITHUB_TOKEN}")

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
git "${gitauth[@]}" push -u origin main

echo "==> 3/4 打标签 ${TAG}"
git tag -f "${TAG}"
git "${gitauth[@]}" push -f origin "${TAG}"

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
- 应用不内置浏览器内核，用的是系统自带 WebView
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
if [ "$code" != "201" ]; then
  echo "    创建 Release 失败 HTTP ${code}"; cat /tmp/gh_release.json; exit 1
fi

UPLOAD=$(python3 -c 'import json;print(json.load(open("/tmp/gh_release.json"))["upload_url"].split("{")[0])')

for apk in dist/cctv-1.0-guard.apk dist/cctv-1.0-plain.apk; do
  if [ ! -f "$apk" ]; then echo "    缺少 $apk，跳过"; continue; fi
  name=$(basename "$apk")
  echo -n "    上传 $name ... "
  curl -sS -o /dev/null -w "HTTP %{http_code}\n" -X POST "${UPLOAD}?name=${name}" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Content-Type: application/vnd.android.package-archive" \
    --data-binary "@${apk}"
done

echo
echo "完成 → https://github.com/${OWNER}/${REPO}/releases/tag/${TAG}"
