#!/usr/bin/env bash
# QA Bug Automation - AI 워크플로우 설치 스크립트
# Version: 1.0.0-beta.1
#
# 사용할 AI를 먼저 선택하면 프롬프트 파일과 MCP 설정이 진행됩니다.
# - Cursor: IDE+AI 통합 환경 (별도 선택)
# - Claude Code: IDE 무관 (VSCode, JetBrains 등 모두 동일)
# - GitHub Copilot: MCP 설정 시 IDE 선택 필요 (VSCode / IntelliJ)
#
# 사용법:
#   1. 프로젝트 루트로 이동: cd ~/my-project
#   2. 설치 실행: /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/cookatrice/qa-bug-automation-install/refs/heads/main/install.sh)"
#   3. AI 선택 후 설정 파일이 현재 디렉토리에 생성됩니다

set -euo pipefail

# ============================================================================
# 설정 변수
# ============================================================================

SCRIPT_VERSION="1.0.0-beta.1"
BACKUP_DIR="$HOME/.qa-bug-automation-backup/$(date +%Y%m%d_%H%M%S)"
MCP_LOCAL_URL="http://localhost:8080/sse"
MCP_REMOTE_URL="http://10.202.201.25:8080/sse"

# Repository 설정 (GitHub)
REPO_BASE_URL="https://raw.githubusercontent.com/cookatrice/qa-bug-automation-install/refs/heads/main"
BUG_INVESTIGATION_URL="${REPO_BASE_URL}/bug-investigation.mdc"
CLAUDE_MD_URL="${REPO_BASE_URL}/CLAUDE.md"

# 색상
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# 설정 파일은 원격 repository에서 다운로드됩니다
# - bug-investigation.mdc: Cursor/Claude/Copilot 워크플로우
# - CLAUDE.md: Claude Code 프롬프트 파일
# ============================================================================

# ============================================================================
# 유틸리티 함수
# ============================================================================

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

backup_file() {
    local file=$1
    if [ -f "$file" ]; then
        mkdir -p "$BACKUP_DIR"
        cp "$file" "$BACKUP_DIR/"
        log_info "백업: $file"
    fi
}

prompt_yes_no() {
    local message=$1
    while true; do
        read -p "$message (y/n): " yn
        case $yn in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "y 또는 n을 입력하세요.";;
        esac
    done
}

download_template_file() {
    local url=$1
    local output_file=$2
    local description=$3

    log_info "$description 다운로드 중..."

    if curl -fsSL "$url" -o "$output_file"; then
        log_success "✓ $description 다운로드 완료: $output_file"
        return 0
    else
        log_error "✗ $description 다운로드 실패"
        log_error "  URL: $url"
        log_error "  대상 파일: $output_file"
        return 1
    fi
}

# ============================================================================
# MCP 환경 선택
# ============================================================================

select_mcp_environment() {
    echo ""
    echo "MCP 서버 환경을 선택하세요:"
    echo "1) 로컬 (localhost:8080) - 개발용"
    echo "2) 원격 (10.202.201.25:8080) - 운영용"
    echo "3) 둘 다 추가"
    echo ""

    read -p "선택 (1-3): " choice

    case $choice in
        1)
            SELECTED_MCP_URL="$MCP_LOCAL_URL"
            SELECTED_MCP_NAME="bug-investigator-local"
            SELECTED_MCP_BOTH=false
            ;;
        2)
            SELECTED_MCP_URL="$MCP_REMOTE_URL"
            SELECTED_MCP_NAME="bug-investigator"
            SELECTED_MCP_BOTH=false
            ;;
        3)
            SELECTED_MCP_BOTH=true
            ;;
        *)
            log_warning "잘못된 선택. 로컬 환경을 사용합니다."
            SELECTED_MCP_URL="$MCP_LOCAL_URL"
            SELECTED_MCP_NAME="bug-investigator-local"
            SELECTED_MCP_BOTH=false
            ;;
    esac
}

# ============================================================================
# [Cursor / Copilot 용] MCP 설정 병합 함수
# ============================================================================

# Cursor의 .cursor/mcp.json 형식 병합
merge_mcp_json() {
    local config_file=$1
    local server_name=$2
    local mcp_url=$3

    backup_file "$config_file"

    if [ ! -f "$config_file" ]; then
        mkdir -p "$(dirname "$config_file")"
        cat > "$config_file" <<MEOF
{
  "mcpServers": {
    "$server_name": {
      "url": "$mcp_url",
      "transport": "sse"
    }
  }
}
MEOF
        log_success "MCP 설정 생성: $config_file"
        return 0
    fi

    if command -v python3 &>/dev/null; then
        python3 << PYEOF
import json

with open("$config_file", 'r') as f:
    config = json.load(f)

config.setdefault('mcpServers', {})['$server_name'] = {
    'url': '$mcp_url',
    'transport': 'sse'
}

with open("$config_file", 'w') as f:
    json.dump(config, f, indent=2, ensure_ascii=False)
print("✓ MCP 설정 병합 완료: $config_file")
PYEOF
    elif command -v jq &>/dev/null; then
        local tmp_file=$(mktemp)
        jq ".mcpServers[\"$server_name\"] = {\"url\": \"$mcp_url\", \"transport\": \"sse\"}" \
           "$config_file" > "$tmp_file" && mv "$tmp_file" "$config_file"
        log_success "MCP 설정 병합 완료: $config_file"
    else
        log_warning "Python3 또는 jq가 필요합니다. 수동으로 추가해주세요:"
        echo "  파일: $config_file"
        echo "  키:   mcpServers.$server_name = { url: $mcp_url, transport: sse }"
        return 1
    fi
}

# VSCode Copilot의 .vscode/mcp.json 형식 병합
#
# ✅ 올바른 설정:
#   - 파일 위치: .vscode/mcp.json       (settings.json 아님)
#   - 루트 키:   "servers"              (mcpServers 아님)
#   - transport: "type": "http"         ("transport": "sse" 아님)
#
# ❌ 흔한 실수:
#   - settings.json의 github.copilot.chat.mcp.servers 키 → 구버전/미작동
#   - mcpServers 키 → Cursor/Claude Code 형식, Copilot에서 무시됨
merge_vscode_mcp() {
    local mcp_file=$1
    local server_name=$2
    local mcp_url=$3

    backup_file "$mcp_file"

    if [ ! -f "$mcp_file" ]; then
        mkdir -p "$(dirname "$mcp_file")"
        cat > "$mcp_file" <<MEOF
{
  "servers": {
    "$server_name": {
      "type": "http",
      "url": "$mcp_url"
    }
  }
}
MEOF
        log_success "VSCode mcp.json 생성: $mcp_file"
        return 0
    fi

    if command -v python3 &>/dev/null; then
        python3 << PYEOF
import json

with open("$mcp_file", 'r') as f:
    config = json.load(f)

config.setdefault('servers', {})['$server_name'] = {
    'type': 'http',
    'url': '$mcp_url'
}

with open("$mcp_file", 'w') as f:
    json.dump(config, f, indent=2, ensure_ascii=False)
print("✓ VSCode mcp.json 병합 완료: $mcp_file")
PYEOF
    elif command -v jq &>/dev/null; then
        local tmp_file=$(mktemp)
        jq ".servers[\"$server_name\"] = {\"type\": \"http\", \"url\": \"$mcp_url\"}" \
           "$mcp_file" > "$tmp_file" && mv "$tmp_file" "$mcp_file"
        log_success "VSCode mcp.json 병합 완료: $mcp_file"
    else
        log_warning "Python3 또는 jq가 필요합니다. 수동으로 추가해주세요:"
        echo "  파일: $mcp_file"
        echo "  키:   servers.$server_name = { type: http, url: $mcp_url }"
        return 1
    fi
}

# ============================================================================
# IntelliJ GitHub Copilot MCP 설정
# ============================================================================
#
# ✅ IntelliJ GitHub Copilot (전역만)
#    - 파일 위치: ~/.config/github-copilot/intellij/mcp.json  (macOS/Linux)
#                 %APPDATA%\github-copilot\intellij\mcp.json   (Windows)
#    - 루트 키:    "servers"
#    - 형식:       { "url": "..." }  ← type 필드 불필요
#    - ❌ 프로젝트별 설정 불가 (전역만 지원)
#
# ============================================================================
# IntelliJ GitHub Copilot 전역 mcp.json 병합
#
# ✅ 형식:
#   - 파일 위치: ~/.config/github-copilot/intellij/mcp.json  (전역)
#   - 루트 키:    "servers"
#   - 형식:       { "url": "..." }  ← type 필드 불필요
#   - ❌ 프로젝트별 설정 불가 (전역만 지원)
merge_intellij_copilot_mcp() {
    local server_name=$1
    local mcp_url=$2

    # OS별 전역 설정 파일 경로 결정
    local mcp_file
    case "$(uname)" in
        Darwin|Linux)
            mcp_file="$HOME/.config/github-copilot/intellij/mcp.json"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            mcp_file="${APPDATA}/github-copilot/intellij/mcp.json"
            ;;
        *)
            log_warning "지원되지 않는 OS입니다. 수동으로 설정해주세요."
            echo "  macOS/Linux: ~/.config/github-copilot/intellij/mcp.json"
            echo "  Windows:     %APPDATA%\\github-copilot\\intellij\\mcp.json"
            return 1
            ;;
    esac

    backup_file "$mcp_file"
    mkdir -p "$(dirname "$mcp_file")"

    if [ ! -f "$mcp_file" ]; then
        cat > "$mcp_file" <<MEOF
{
  "servers": {
    "$server_name": {
      "url": "$mcp_url"
    }
  }
}
MEOF
        log_success "IntelliJ Copilot mcp.json 생성: $mcp_file"
        return 0
    fi

    if command -v python3 &>/dev/null; then
        MCP_FILE="$mcp_file" SERVER_NAME="$server_name" MCP_URL="$mcp_url" python3 << 'PYEOF'
import json
import sys
import os

mcp_file    = os.environ['MCP_FILE']
server_name = os.environ['SERVER_NAME']
mcp_url     = os.environ['MCP_URL']

def strip_jsonc_comments(text):
    """// 스타일 주석 제거 (JSONC → JSON 변환)"""
    result = []
    i = 0
    in_string = False
    while i < len(text):
        ch = text[i]
        if in_string:
            if ch == '\\':          # 이스케이프 문자
                result.append(ch)
                i += 1
                if i < len(text):
                    result.append(text[i])
            elif ch == '"':
                in_string = False
                result.append(ch)
            else:
                result.append(ch)
        else:
            if ch == '"':
                in_string = True
                result.append(ch)
            elif ch == '/' and i + 1 < len(text) and text[i+1] == '/':
                # // 주석 — 줄 끝까지 건너뜀
                while i < len(text) and text[i] != '\n':
                    i += 1
                continue
            else:
                result.append(ch)
        i += 1
    return ''.join(result)

try:
    with open(mcp_file, 'r') as f:
        raw = f.read()
    cleaned = strip_jsonc_comments(raw)
    config = json.loads(cleaned)
except json.JSONDecodeError as e:
    print(f"[ERROR] mcp.json 파싱 실패: {e}", file=sys.stderr)
    print(f"[ERROR] 주석 제거 후에도 파싱 실패. 파일을 덮어써야 합니다.", file=sys.stderr)
    sys.exit(1)

config.setdefault('servers', {})[server_name] = {
    'url': mcp_url
}

with open(mcp_file, 'w') as f:
    json.dump(config, f, indent=2, ensure_ascii=False)
print(f"✓ IntelliJ Copilot mcp.json 병합 완료: {mcp_file}")
PYEOF

        # python3 종료 코드 확인 — 파싱 실패 시 덮어쓸지 물어봄
        if [ $? -ne 0 ]; then
            echo ""
            log_warning "기존 mcp.json 파싱에 실패했습니다."
            log_warning "덮어쓰면 기존 서버 설정이 모두 사라집니다."
            echo ""
            if prompt_yes_no "새 내용으로 덮어쓰시겠습니까?"; then
                cat > "$mcp_file" <<MEOF
{
  "servers": {
    "$server_name": {
      "url": "$mcp_url"
    }
  }
}
MEOF
                log_success "✓ mcp.json 새로 작성 완료: $mcp_file"
            else
                log_warning "건너뜀. 수동으로 아래 내용을 추가해주세요:"
                echo "  파일: $mcp_file"
                printf '  추가할 내용:\n  {\n    "servers": {\n      "%s": { "url": "%s" }\n    }\n  }\n' "$server_name" "$mcp_url"
            fi
        fi
    elif command -v jq &>/dev/null; then
        local tmp_file=$(mktemp)
        jq ".servers[\"$server_name\"] = {\"url\": \"$mcp_url\"}" \
           "$mcp_file" > "$tmp_file" && mv "$tmp_file" "$mcp_file"
        log_success "IntelliJ Copilot mcp.json 병합 완료: $mcp_file"
    else
        log_warning "Python3 또는 jq가 필요합니다. 수동으로 추가해주세요:"
        echo "  파일: $mcp_file"
        echo "  키:   servers.$server_name = { url: $mcp_url }"
        return 1
    fi
}

# GitHub Copilot MCP 설정 진입점 — IDE 선택 후 분기
setup_copilot_mcp() {
    local project_dir=$1

    echo ""
    echo "MCP를 설정할 IDE를 선택하세요:"
    echo ""
    echo "1) VSCode Copilot     → .vscode/mcp.json (프로젝트별)"
    echo "2) IntelliJ Copilot   → ~/.config/github-copilot/intellij/mcp.json (전역)"
    echo "3) 둘 다 (1 + 2)"
    echo ""
    read -p "선택 (1-3): " ide_choice

    case $ide_choice in
        1)
            _setup_vscode_copilot "$project_dir"
            ;;
        2)
            _setup_intellij_copilot
            ;;
        3)
            _setup_vscode_copilot "$project_dir"
            _setup_intellij_copilot
            ;;
        *)
            log_warning "잘못된 선택. VSCode Copilot으로 진행합니다."
            _setup_vscode_copilot "$project_dir"
            ;;
    esac
}

_setup_vscode_copilot() {
    local project_dir=$1
    local mcp_file="$project_dir/.vscode/mcp.json"

    if [ "$SELECTED_MCP_BOTH" = true ]; then
        merge_vscode_mcp "$mcp_file" "bug-investigator-local" "$MCP_LOCAL_URL"
        merge_vscode_mcp "$mcp_file" "bug-investigator" "$MCP_REMOTE_URL"
    else
        merge_vscode_mcp "$mcp_file" "$SELECTED_MCP_NAME" "$SELECTED_MCP_URL"
    fi

    log_success "✓ VSCode Copilot MCP 설정 완료: .vscode/mcp.json"
    echo ""
    log_warning "⚠️  VSCode 사용 시:"
    echo "     1. mcp.json 파일 상단 [Start] 버튼 클릭"
    echo "     2. Copilot Chat → [Agent] 모드 선택"
    echo "     3. 툴 아이콘 → bug-investigator 확인"
}

_setup_intellij_copilot() {
    if [ "$SELECTED_MCP_BOTH" = true ]; then
        merge_intellij_copilot_mcp "bug-investigator-local" "$MCP_LOCAL_URL"
        merge_intellij_copilot_mcp "bug-investigator" "$MCP_REMOTE_URL"
    else
        merge_intellij_copilot_mcp "$SELECTED_MCP_NAME" "$SELECTED_MCP_URL"
    fi

    log_success "✓ IntelliJ Copilot MCP 설정 완료 (전역): ~/.config/github-copilot/intellij/mcp.json"
    echo ""
    log_warning "⚠️  IntelliJ Copilot 사용 시:"
    echo "     1. IntelliJ 재시작 (mcp.json 변경 시 재시작 필요)"
    echo "     2. Copilot Chat → [Agent] 모드 선택"
    echo "     3. Configure tools 아이콘 → bug-investigator check 확인 & start"
    echo "     4. MCP Sampling(Optional) → Allows Models 확인"
    echo ""
    log_info "📌 IntelliJ Copilot은 프로젝트별 설정을 지원하지 않습니다 (전역만 가능)"
}
#
# Claude Code가 읽는 MCP 설정 위치:
#   - 프로젝트 스코프: <프로젝트 루트>/.mcp.json
#   - 전역 스코프:     ~/.claude/settings.json
#
# ❌ 사용하지 않는 위치:
#   - ~/Library/Application Support/Claude/claude_desktop_config.json (Claude Desktop 전용)
#   - .claude/mcp.json (Claude Code가 읽지 않음)
#   - .vscode/settings.json의 github.copilot.chat.mcp.servers (Copilot 전용)
# ============================================================================

# Claude Code MCP 설정 진입점 — CLI 유무에 따라 방법 선택
setup_claude_code_mcp() {
    local project_dir=$1

    if command -v claude &>/dev/null; then
        log_info "claude CLI 감지됨 → claude mcp add 명령으로 등록합니다."
        setup_claude_code_mcp_via_cli "$project_dir"
    else
        log_warning "claude CLI가 PATH에 없습니다 → 파일 직접 생성 방식으로 대체합니다."
        log_warning "(나중에 claude CLI 설치 후 'claude mcp list'로 등록 여부를 확인하세요)"
        setup_claude_code_mcp_via_file "$project_dir"
    fi
}

# 방법 A: claude mcp add CLI 사용 (권장)
setup_claude_code_mcp_via_cli() {
    local project_dir=$1

    echo ""
    echo "MCP 등록 범위를 선택하세요:"
    echo "1) 이 프로젝트만 (.mcp.json) — 팀원과 공유 가능"
    echo "2) 전체 사용자 (~/.claude/settings.json) — 내 모든 프로젝트에서 사용"
    read -p "선택 (1-2): " scope_choice

    local scope_flag
    case $scope_choice in
        1) scope_flag="-s project" ;;
        2) scope_flag="-s user" ;;
        *) scope_flag="-s project" ;;
    esac

    # project scope는 현재 디렉토리 기준으로 .mcp.json을 생성하므로
    # 반드시 프로젝트 루트에서 실행해야 함
    pushd "$project_dir" > /dev/null

    if [ "$SELECTED_MCP_BOTH" = true ]; then
        if claude mcp add $scope_flag --transport sse bug-investigator-local "$MCP_LOCAL_URL" 2>/dev/null; then
            log_success "✓ 로컬 MCP 등록 완료: bug-investigator-local ($MCP_LOCAL_URL)"
        else
            log_warning "bug-investigator-local 등록 실패 (이미 존재하거나 오류). 파일 직접 수정을 권장합니다."
        fi

        if claude mcp add $scope_flag --transport sse bug-investigator "$MCP_REMOTE_URL" 2>/dev/null; then
            log_success "✓ 원격 MCP 등록 완료: bug-investigator ($MCP_REMOTE_URL)"
        else
            log_warning "bug-investigator 등록 실패 (이미 존재하거나 오류). 파일 직접 수정을 권장합니다."
        fi
    else
        if claude mcp add $scope_flag --transport sse "$SELECTED_MCP_NAME" "$SELECTED_MCP_URL" 2>/dev/null; then
            log_success "✓ MCP 등록 완료: $SELECTED_MCP_NAME ($SELECTED_MCP_URL)"
        else
            log_warning "$SELECTED_MCP_NAME 등록 실패 (이미 존재하거나 오류). 파일 직접 수정을 권장합니다."
        fi
    fi

    popd > /dev/null

    # 등록 결과 확인
    echo ""
    log_info "현재 등록된 MCP 서버 목록:"
    claude mcp list 2>/dev/null || log_warning "claude mcp list 실행 실패"
}

# 방법 B: 파일 직접 생성 (claude CLI가 없을 때 fallback)
setup_claude_code_mcp_via_file() {
    local project_dir=$1

    echo ""
    echo "MCP 등록 범위를 선택하세요:"
    echo "1) 이 프로젝트만 (.mcp.json) — 팀원과 공유 가능"
    echo "2) 전체 사용자 (~/.claude/settings.json) — 내 모든 프로젝트에서 사용"
    read -p "선택 (1-2): " scope_choice

    case $scope_choice in
        1)
            # 프로젝트 루트의 .mcp.json (Claude Code project scope)
            local mcp_file="$project_dir/.mcp.json"
            if [ "$SELECTED_MCP_BOTH" = true ]; then
                merge_claude_code_mcp_json "$mcp_file" "bug-investigator-local" "$MCP_LOCAL_URL"
                merge_claude_code_mcp_json "$mcp_file" "bug-investigator" "$MCP_REMOTE_URL"
            else
                merge_claude_code_mcp_json "$mcp_file" "$SELECTED_MCP_NAME" "$SELECTED_MCP_URL"
            fi
            log_success "✓ 프로젝트 MCP 설정 완료: .mcp.json"
            ;;
        2)
            # ~/.claude/settings.json (Claude Code user scope)
            local settings_file="$HOME/.claude/settings.json"
            if [ "$SELECTED_MCP_BOTH" = true ]; then
                merge_claude_code_settings_json "$settings_file" "bug-investigator-local" "$MCP_LOCAL_URL"
                merge_claude_code_settings_json "$settings_file" "bug-investigator" "$MCP_REMOTE_URL"
            else
                merge_claude_code_settings_json "$settings_file" "$SELECTED_MCP_NAME" "$SELECTED_MCP_URL"
            fi
            log_success "✓ 전역 MCP 설정 완료: ~/.claude/settings.json"
            ;;
        *)
            log_warning "잘못된 선택. 프로젝트 스코프로 설정합니다."
            setup_claude_code_mcp_via_file "$project_dir"
            ;;
    esac
}

# 프로젝트 루트 .mcp.json 병합 (Claude Code project scope)
merge_claude_code_mcp_json() {
    local config_file=$1
    local server_name=$2
    local mcp_url=$3

    backup_file "$config_file"

    if [ ! -f "$config_file" ]; then
        cat > "$config_file" <<MEOF
{
  "mcpServers": {
    "$server_name": {
      "url": "$mcp_url",
      "transport": "sse"
    }
  }
}
MEOF
        log_success "생성: $config_file"
        return 0
    fi

    if command -v python3 &>/dev/null; then
        python3 << PYEOF
import json

with open("$config_file", 'r') as f:
    config = json.load(f)

config.setdefault('mcpServers', {})['$server_name'] = {
    'url': '$mcp_url',
    'transport': 'sse'
}

with open("$config_file", 'w') as f:
    json.dump(config, f, indent=2, ensure_ascii=False)
print("✓ 병합 완료: $config_file")
PYEOF
    elif command -v jq &>/dev/null; then
        local tmp_file=$(mktemp)
        jq ".mcpServers[\"$server_name\"] = {\"url\": \"$mcp_url\", \"transport\": \"sse\"}" \
           "$config_file" > "$tmp_file" && mv "$tmp_file" "$config_file"
        log_success "병합 완료: $config_file"
    else
        log_warning "Python3 또는 jq가 필요합니다. 수동으로 추가해주세요:"
        echo "  파일: $config_file"
        echo "  키:   mcpServers.$server_name = { url: $mcp_url, transport: sse }"
        return 1
    fi
}

# ~/.claude/settings.json 병합 (Claude Code user scope)
merge_claude_code_settings_json() {
    local settings_file=$1
    local server_name=$2
    local mcp_url=$3

    backup_file "$settings_file"
    mkdir -p "$(dirname "$settings_file")"

    if [ ! -f "$settings_file" ]; then
        cat > "$settings_file" <<MEOF
{
  "mcpServers": {
    "$server_name": {
      "url": "$mcp_url",
      "transport": "sse"
    }
  }
}
MEOF
        log_success "생성: $settings_file"
        return 0
    fi

    if command -v python3 &>/dev/null; then
        python3 << PYEOF
import json

with open("$settings_file", 'r') as f:
    settings = json.load(f)

settings.setdefault('mcpServers', {})['$server_name'] = {
    'url': '$mcp_url',
    'transport': 'sse'
}

with open("$settings_file", 'w') as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
print("✓ 병합 완료: $settings_file")
PYEOF
    elif command -v jq &>/dev/null; then
        local tmp_file=$(mktemp)
        jq ".mcpServers[\"$server_name\"] = {\"url\": \"$mcp_url\", \"transport\": \"sse\"}" \
           "$settings_file" > "$tmp_file" && mv "$tmp_file" "$settings_file"
        log_success "병합 완료: $settings_file"
    else
        log_warning "Python3 또는 jq가 필요합니다. 수동으로 추가해주세요:"
        echo "  파일: $settings_file"
        echo "  키:   mcpServers.$server_name = { url: $mcp_url, transport: sse }"
        return 1
    fi
}

# ============================================================================
# LLM별 설치 함수
#
# 분류 기준:
#   Cursor      — IDE와 AI가 하나로 묶인 특수 케이스 (IDE 기준으로 분류)
#   Claude Code — 어떤 IDE(VSCode, JetBrains 등)든 설정 파일·MCP 경로 동일
#   Copilot     — 어떤 IDE(VSCode, JetBrains 등)든 설정 파일·MCP 형식 동일
# ============================================================================

# ----------------------------------------------------------
# Cursor (특수 케이스 — IDE + AI 번들)
# 프롬프트: .cursor/rules/bug-investigation.mdc
# MCP:      .cursor/mcp.json  (mcpServers 키, transport: sse)
# ----------------------------------------------------------
install_cursor() {
    log_info "Cursor 설정 설치 중..."

    local project_dir=$(pwd)

    # .cursor/rules/bug-investigation.mdc 다운로드
    mkdir -p "$project_dir/.cursor/rules"
    if ! download_template_file "$BUG_INVESTIGATION_URL" \
         "$project_dir/.cursor/rules/bug-investigation.mdc" \
         "Cursor Rules"; then
        log_error "Cursor Rules 다운로드 실패. 설치를 중단합니다."
        return 1
    fi

    echo ""
    if prompt_yes_no "MCP 설정을 추가하시겠습니까?"; then
        select_mcp_environment

        local mcp_file="$project_dir/.cursor/mcp.json"

        if [ "$SELECTED_MCP_BOTH" = true ]; then
            merge_mcp_json "$mcp_file" "bug-investigator-local" "$MCP_LOCAL_URL"
            merge_mcp_json "$mcp_file" "bug-investigator" "$MCP_REMOTE_URL"
        else
            merge_mcp_json "$mcp_file" "$SELECTED_MCP_NAME" "$SELECTED_MCP_URL"
        fi

        log_success "✓ MCP 설정 완료: .cursor/mcp.json"
        echo ""
        log_warning "⚠️  Cursor 재시작 → Settings → MCP → bug-investigator 활성화"
    fi

    echo ""
}

# ----------------------------------------------------------
# Claude Code (LLM 기준 — IDE 무관)
# 프롬프트: CLAUDE.md + .claude/bug-investigation.md
# MCP:      claude mcp add CLI (권장)
#           또는 .mcp.json / ~/.claude/settings.json (fallback)
# 적용 IDE: VSCode, JetBrains, 터미널 등 모두 동일
# ----------------------------------------------------------
install_claude_code() {
    log_info "Claude Code 설정 설치 중..."
    log_info "(VSCode, JetBrains 등 어떤 IDE든 동일한 설정이 적용됩니다)"

    local project_dir=$(pwd)

    # 1. CLAUDE.md 다운로드 (루트 진입점)
    backup_file "$project_dir/CLAUDE.md"
    if ! download_template_file "$CLAUDE_MD_URL" "$project_dir/CLAUDE.md" "CLAUDE.md"; then
        log_error "CLAUDE.md 다운로드 실패. 설치를 중단합니다."
        return 1
    fi

    # 2. .claude/bug-investigation.md 다운로드 (전체 워크플로우)
    mkdir -p "$project_dir/.claude"
    if ! download_template_file "$BUG_INVESTIGATION_URL" \
         "$project_dir/.claude/bug-investigation.md" \
         "워크플로우 파일"; then
        log_error "워크플로우 파일 다운로드 실패. 설치를 중단합니다."
        return 1
    fi

    # 3. MCP 설정
    echo ""
    if prompt_yes_no "MCP 설정을 추가하시겠습니까?"; then
        select_mcp_environment
        setup_claude_code_mcp "$project_dir"
    fi

    echo ""
    echo "  IDE 재시작 후 Claude Code 채팅 패널에서 /mcp 를 입력하면"
    echo "  등록된 bug-investigator 서버를 확인할 수 있습니다."
    echo ""
}

# ----------------------------------------------------------
# GitHub Copilot
# 프롬프트: .github/copilot-instructions.md  → IDE 무관
# MCP:      IDE별 경로 상이 → IDE 선택 필요
#
#   1) VSCode Copilot (프로젝트별)
#      - 파일: .vscode/mcp.json
#      - 키:   "servers"
#      - 형식: { "type": "http", "url": "..." }
#
#   2) IntelliJ Copilot (전역만)
#      - 파일: ~/.config/github-copilot/intellij/mcp.json
#      - 키:   "servers"
#      - 형식: { "url": "..." }  ← type 필드 불필요
#      - ❌ 프로젝트별 설정 불가
# ----------------------------------------------------------
install_copilot() {
    log_info "GitHub Copilot 설정 설치 중..."

    local project_dir=$(pwd)

    # .github/copilot-instructions.md 다운로드 (전체 워크플로우 — IDE 무관)
    mkdir -p "$project_dir/.github"
    backup_file "$project_dir/.github/copilot-instructions.md"
    if ! download_template_file "$BUG_INVESTIGATION_URL" \
         "$project_dir/.github/copilot-instructions.md" \
         "Copilot 프롬프트"; then
        log_error "Copilot 프롬프트 다운로드 실패. 설치를 중단합니다."
        return 1
    fi
    log_info "  (프롬프트 파일은 VSCode, IntelliJ 모두 동일하게 적용됩니다)"

    # MCP 설정 — IDE별 파일 경로가 다르므로 IDE 선택 필요
    echo ""
    if prompt_yes_no "MCP 설정을 추가하시겠습니까?"; then
        select_mcp_environment
        setup_copilot_mcp "$project_dir"
    fi

    echo ""
}

install_all() {
    log_info "전체 설치를 시작합니다 (Cursor + Claude Code + GitHub Copilot)..."
    echo ""

    install_cursor
    install_claude_code
    install_copilot

    log_success "전체 설치 완료!"
}

# ============================================================================
# 대화형 메뉴
# ============================================================================

show_main_menu() {
    clear
    echo "================================================"
    echo "  QA Bug Automation - AI 워크플로우 설치"
    echo "  Version: $SCRIPT_VERSION"
    echo "================================================"
    echo ""
    echo "  사용할 AI를 선택하세요."
    echo "  IDE는 선택하지 않아도 됩니다 — AI가 기준입니다."
    echo ""
    echo "  (예외) Cursor는 IDE+AI 번들이므로 별도 항목입니다."
    echo ""
    echo "1) Cursor                        (IDE+AI 번들)"
    echo "2) Claude Code                   (VSCode / JetBrains / 기타 IDE)"
    echo "3) GitHub Copilot                (VSCode Copilot / IntelliJ Copilot)"
    echo "4) 전체 설치                     (1 + 2 + 3)"
    echo "0) 종료"
    echo ""
    read -p "선택 (0-4): " choice

    case $choice in
        1) install_cursor ;;
        2) install_claude_code ;;
        3) install_copilot ;;
        4) install_all ;;
        0) exit 0 ;;
        *)
            log_error "잘못된 선택입니다."
            sleep 2
            show_main_menu
            return
            ;;
    esac

    # 완료 메시지
    echo ""
    echo "================================================"
    echo "  설치가 완료되었습니다! 🎉"
    echo "================================================"
    echo ""
    echo "다음 단계:"
    echo "1. IDE를 재시작하세요"
    echo "2. 버그 티켓으로 테스트하세요:"
    echo "   예) \"VRBT-123 조사해줘\""
    echo ""
    if [ -d "$BACKUP_DIR" ] && [ "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        echo "백업 위치: $BACKUP_DIR"
    fi
    echo "================================================"

    exit 0
}

# ============================================================================
# 메인 실행
# ============================================================================

main() {
    # Git 저장소 확인 (권장)
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_warning "현재 디렉토리가 Git 저장소가 아닙니다."
        if ! prompt_yes_no "계속하시겠습니까?"; then
            exit 0
        fi
        echo ""
    fi

    show_main_menu
}

main "$@"