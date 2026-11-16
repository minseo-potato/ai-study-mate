# AI 스터디메이트

학술제 참가신청서의 프로젝트 기획을 구현한 로컬 시연용 Flutter + FastAPI 프로젝트입니다. 기존 `모각공` 프로젝트와 별개입니다.

## 실행

Python 3.11 이상과 Flutter SDK가 필요합니다. API 키는 서버 환경변수에만 저장합니다.

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
$env:OPENAI_API_KEY="본인의_API_키"
uvicorn main:app --reload --host 127.0.0.1 --port 8000
```

API 키 없이 화면 흐름을 시연하려면 서버 실행 전에 `$env:DEMO_MODE="1"`을 설정하세요. 이 모드의 계획·질문·요약은 규칙 기반 예시이며 생성형 AI 결과가 아닙니다.

다른 터미널에서:

```powershell
cd flutter_app
flutter create . --platforms web,android
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
```

Android 에뮬레이터에서는 `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000`을 사용합니다. 포함된 Android manifest는 로컬 시연을 위한 인터넷 권한과 HTTP 연결 설정을 담고 있습니다. 배포할 때는 HTTPS 주소를 사용하세요.

Swagger 문서는 서버를 켠 뒤 `http://127.0.0.1:8000/docs`에서 확인할 수 있습니다.

백엔드 통합 시험은 `backend`에서 `pip install -r requirements-dev.txt` 후 `python -m unittest test_flow.py`로 실행합니다. AI 응답은 시험에서 가짜 응답으로 대체하므로 API 키가 필요하지 않습니다.

## 시연 순서

1. 주제·목표·기간·주당 시간·AI 동료 수를 입력하고 **텍스트 추출이 가능한 PDF**를 업로드합니다.
2. 기본 주차별 계획을 검토하고 수정합니다. AI 계획 제안 또는 남은 일정 변경안을 미리 보고 적용할 수 있습니다.
3. 한 주의 학습 정리를 직접 작성해 랩미팅을 시작합니다.
4. AI 동료가 한 명씩 질문합니다. 답변을 제출하고, 답하지 못한 질문은 복습으로 표시합니다.
5. 발표를 다시 정리해 세션을 종료하면 회의록과 다음 주 복습 항목이 저장됩니다.

## 코드 구조

| 파일 | 역할 |
| --- | --- |
| `backend/main.py` | HTTP API, PDF 추출, 기본 주간 분배, 질문 순서, 회의록과 다음 주 복습 반영 |
| `backend/ai.py` | 서버에서만 OpenAI Responses API 호출, JSON 결과 처리 |
| `backend/db.py` | SQLite 테이블과 연결 관리 |
| `flutter_app/lib/main.dart` | 생성·계획 확인/수정·발표·질의응답·회의록 화면 |

## 구현 메모

- PDF는 페이지별 텍스트를 SQLite에 저장합니다. 현재 주차 범위에서 발표문과 겹치는 단어가 많은 페이지 최대 3개를 AI 요청에 포함합니다. 질문에 표시되는 쪽수는 이 페이지들 중 하나일 때만 인정합니다.
- 동료마다 질문 관점과 초기 수준을 다르게 설정하고, 이전 질문/답변과 동료의 누적 이해 상태를 다음 질문에 전달합니다. 질문은 답변 후에만 다음으로 넘어갑니다.
- 최초 발표문, 답변, 재정리한 설명, 회의록을 각각 저장합니다. 사용자가 복습 필요로 표시한 질문과 AI가 제안한 확인 항목은 다음 주로 전달합니다.
- 스캔 이미지 PDF의 OCR, 회원 계정, 여러 기기 동기화, 음성, 실제 사람 초대는 현재 범위에 포함되지 않습니다. 서버는 로컬 단일 사용자 시연용이므로 외부에 공개하려면 인증과 접근 제어가 필요합니다.
- 질문의 정확성과 동료 같은 말투는 AI 출력에 영향을 받습니다. 교안 페이지 표시만으로 답변 내용의 사실성을 보증하지 않으므로 시연에서는 원문과 대조해야 합니다.
