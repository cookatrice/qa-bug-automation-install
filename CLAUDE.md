# 프로젝트 가이드

## Bug Investigation Workflow

이 프로젝트는 버그 자동 조사 워크플로우를 사용합니다.

### 사용 방법

Jira 티켓 번호를 언급하면 자동으로 버그 조사가 시작됩니다:

```
"VRBT-2342 조사해줘"
"PROJ-1234 버그 확인해줘"
```

### 트리거 조건

- **패턴**: `VRBT-XXX`, `PROJ-XXX` 형태의 티켓 번호
- **동작**: MCP 서버를 통해 Jira/로그/OpenSearch 자동 조사

### 상세 워크플로우

전체 워크플로우는 **`.claude/bug-investigation.md`** 파일을 참조하세요.

MCP 서버가 자동으로 상세 단계를 따라 버그를 조사하고 수정합니다.
