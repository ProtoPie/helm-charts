# CLAUDE.md

이 파일은 Claude Code (claude.ai/code)가 이 레포지토리에서 작업할 때 참고하는 가이드입니다.

## 릴리스 프로세스

IMPORTANT: main에 머지하기 전에 반드시 `Chart.yaml`의 `version`을 올려야 한다. GitHub Actions의 `chart-releaser-action`은 기존 릴리스와 버전이 다를 때만 새 릴리스를 생성한다. 버전을 안 올리면 변경사항이 `https://protopie.github.io/helm-charts`에 배포되지 않고 조용히 무시된다.

## 패스워드 자동 생성 함정

IMPORTANT: `db.env.DB_WRITE_PASSWORD`나 `db.env.DB_READ_PASSWORD`가 비어있으면(기본값), `_helpers.tpl`이 매 템플릿 렌더링마다 `randAlphaNum`으로 랜덤 패스워드를 생성한다. `{{ include }}` 호출마다 서로 다른 값이 나오기 때문에 `db-secret.yaml`과 `db-configmap.yaml` init 스크립트의 패스워드가 **같은 릴리스 안에서도 불일치**한다. `helm upgrade` 시에는 이전 릴리스와도 달라진다.

첫 설치 전에 반드시 values 파일이나 `--set`으로 지정할 것:
- `db.env.DB_WRITE_PASSWORD`, `db.env.DB_READ_PASSWORD`
- `analytics.web.env.AE_API_USER_PASS`, `analytics.api.env.DJANGO_SECRET_KEY` (analytics 사용 시)

## 차트 구성

- `charts/cloud/` — ProtoPie Cloud 온프레미스 배포 차트
  - 이미지: `protopie/enterprise-onpremises:{api,web}-<version>`, `nginx:1.26.3-alpine`, `bitnami/postgresql:14`
  - `config.yml`과 `license.pem`은 `--set-file` 플래그로 주입, `api-configmap.yaml`에 ConfigMap으로 저장
  - 선택 컴포넌트: Analytics (비공개 베타, ECR 이미지), User Testing
- `charts/aws-ecr-credential/` — AWS ECR 이미지 풀 시크릿 자동 갱신 (CronJob, 8시간 주기)

## 찾기 어려운 파일 위치

- **Nginx 라우팅**: `templates/nginx-deployment.yaml` 하나에 nginx.conf와 virtualhost.conf가 인라인으로 들어있다 (ConfigMap 2개 + Deployment 1개, 총 3개 YAML 문서). 라우팅 변경은 여기서 한다.
- **DB 초기화 스크립트**: `templates/db-configmap.yaml`에 사용자/데이터베이스 생성 SQL이 있다 (`db-secret.yaml`과 동일한 패스워드 헬퍼를 렌더링)
- **패스워드 생성 로직**: `templates/_helpers.tpl` 76-115라인 (독립적인 `randAlphaNum` 생성기 4개)

## Feature 토글

`values.yaml`의 6개 토글이 여러 템플릿 파일의 렌더링을 제어한다. `helm template --set <토글>=true`로 영향 범위를 확인할 수 있다:
- `analytics.enabled` — Analytics API/Web deployment, secret, nginx upstream/location 블록
- `userTesting.enabled` — User Testing deployment, nginx 블록
- `cloud.share.enabled` — nginx share 서버 블록
- `cloud.wellKnown.enabled` — apple-app-site-association, assetlinks.json 볼륨 마운트
- `postgresql.enabled` — DB 레이어 전체 전환: 내장 StatefulSet+Service vs Bitnami 서브차트. credential 소스(`db.env.*` vs `postgresql.auth.*`)와 호스트 해석도 함께 변경됨
- `ingress.enabled` — ALB Ingress 리소스

## Probe 기본값

차트가 probe timeout을 명시하지 않아서 Kubernetes 기본값(`timeoutSeconds: 1`, `failureThreshold: 3`)에 의존한다. DB 마이그레이션이나 부하 상황에서 파드가 반복 kill될 수 있다. 소비 환경에서 반드시 오버라이드할 것: startupProbe에 `timeoutSeconds: 5`, `failureThreshold: 12` 권장.

## 하류 소비자 (Downstream Consumers)

- **staging-eks**: ArgoCD가 `internal` 브랜치를 직접 참조하여 배포 (dev-ee, qa-ee 등). 환경별 값은 `cloud.values.yaml`에 정의
- **enterprise-eks**: `main` 브랜치 기반의 GitHub Pages 차트를 사용하여 멀티 리전 클러스터(Seoul, Oregon, Mumbai, Frankfurt)에 배포
- 소비자의 `cloud.values.yaml`에서 YAML 중복 키 주의 — `image:` 키가 두 번 선언되면 마지막 값만 적용되며, ArgoCD Image Updater의 parameter override가 이를 마스킹하여 발견이 어렵다. 새 환경 추가 시 정상 환경(dev-ee)과 diff 비교 필수.

## 명령어

```bash
helm lint charts/cloud                              # 차트 린트
helm template my-release charts/cloud               # 로컬 템플릿 렌더링
helm dependency update charts/cloud                 # 서브차트 의존성 업데이트
helm test <release> -n <namespace>                  # 클러스터 내 연결 테스트
```

설치 (Enterprise 플랜 필요):
```bash
helm repo add protopie https://protopie.github.io/helm-charts && helm repo update
helm install my-release protopie/cloud -n <namespace> \
    --set-file cloud.config.yml=config.yml \
    --set-file cloud.license.pem=license.pem
```

## 듀얼 브랜치 모델

이 레포지토리는 두 개의 영구 브랜치를 병행 운영한다:
- **`main`** — 프로덕션 차트. `chart-releaser-action`으로 GitHub Pages에 배포되며, enterprise-eks 고객 환경에서 사용
- **`internal`** — 개발/스테이징 서버 운영 차트. staging-eks의 ArgoCD가 이 브랜치를 직접 참조하여 실제 서비스 운영 (dev-ee, qa-ee 등)

main의 변경사항은 internal로 흡수되지만, internal → main 머지는 하지 않는다. 두 브랜치는 각각의 서버 환경을 담당하는 독립적인 운영 차트다.

### `internal` 브랜치 상세

기존 Kotlin/KTOR 기반 레거시 UT 대신 NestJS 기반 마이크로서비스 아키텍처가 스테이징 환경에서 운영되고 있다.

### 추가된 컴포넌트
- **user-testing-server** — NestJS REST API + Socket.IO WebSocket 서버 (포트 3030). Prisma 마이그레이션, JWT 인증, 메트릭 엔드포인트(9090) 포함
- **user-testing-db** — 전용 PostgreSQL 16.6 StatefulSet. 대용량 JSONB 페이로드 지원을 위한 튜닝 설정 (WAL, shared_buffers, work_mem 등)
- **user-testing-redis** — Socket.IO broadcast/presence용 Redis 캐시 (포트 6379). emptyDir 사용으로 파드 재시작 시 데이터 유실됨
- **cilium-network-policy** — mTLS 기반 네트워크 정책 최대 9개 (조건부). 토글 조합에 따라 활성화되는 정책이 달라짐 (API, Web, DB는 항상 포함 / UT 레거시 vs UT 서버+DB+Redis는 `useLegacy`에 따라 분기 / Analytics 2개는 `analytics.enabled`에 따라)

### 마이그레이션 토글 (이중 플래그)
```yaml
userTesting:
  enabled: false   # 전체 UT 컴포넌트 마스터 스위치
  useLegacy: true  # true=레거시 Kotlin, false=신규 NestJS
```
- `enabled: true, useLegacy: true` → 레거시 UT만 배포
- `enabled: true, useLegacy: false` → 신규 NestJS UT 스택 배포 (DB + Redis 포함)

### main과의 주요 차이점
- **외부 시크릿 지원**: `db.existingSecret`, `userTesting.existingAppSecret`, `userTesting.db.existingSecret`으로 Vault/AWS Secrets Manager 연동 가능
- **API probe 설정 가능**: main에서는 하드코딩이지만 internal에서는 values로 오버라이드 가능
- **API feature flag**: `cloud.api.featureFlag`로 nginx에 `X-feature-flag` 헤더 추가 (values.yaml에 미선언, 템플릿에서만 참조)
- **하드코딩된 관리자 계정**: `user-testing-server-deployment.yaml`에 `ADMIN_USERNAME: admin`, `ADMIN_PASSWORD: admin123`이 하드코딩됨. 실제 스테이징 서버에서 운영 중이므로, values로 분리하여 환경별로 관리하는 것이 바람직함
- **Nginx 라우팅 확장**: 레거시(`/user-research`) + 신규(`/api/ut/`, `/api/ut/socket.io/`) 엔드포인트 분기
- **Cilium 네트워크 정책**: `ciliumNetworkPolicy.enabled`로 서비스 간 mTLS 강제 가능
- main 변경 시 internal로의 전파를 고려할 것. 특히 `nginx-deployment.yaml`과 `values.yaml`은 internal에서 크게 변경되었으므로, main 수정 후 internal에서 충돌 없이 흡수 가능한지 확인 필요.
