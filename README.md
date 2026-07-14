# QA Bug Automation Install

Jira 버그 티켓을 AI가 자동으로 조사하도록 설정하는 설치 스크립트입니다.

## 설치 방법

QA Bug Automation을 사용할 **프로젝트 루트**로 이동한 후 아래 명령을 복사해서 붙여 넣으세요.

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/cookatrice/qa-bug-automation-install/refs/heads/main/install.sh)"
```

## 지원 AI

1. **Cursor** - IDE+AI 통합 환경
2. **Claude Code** - VSCode, JetBrains 등 모든 IDE 지원
3. **GitHub Copilot** - VSCode / IntelliJ 지원

설치 스크립트 실행 시 사용할 AI를 선택하면 프롬프트 파일과 MCP 설정이 자동으로 구성됩니다.

## 기타문의

- VAS 개발팀
