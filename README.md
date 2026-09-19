# 오늘교육 (모바일)

오전 6시부터 밤 12시까지 30분마다 GitHub가 교육뉴스를 자동으로 모아
웹페이지를 새로 게시합니다. 폰에서 주소를 열고 홈 화면에 추가해 쓰면 됩니다.

## 처음 설정 (한 번만)

1. github.com 에서 계정을 만듭니다.
2. 오른쪽 위 `+` → **New repository**
   - Repository name: `today-edu`
   - **Public** 선택 → **Create repository**
3. 만들어진 화면에서 **uploading an existing file** 을 누르고,
   압축을 푼 폴더 안의 내용(`.github`, `collector`, `docs`, `.gitignore`, `README.md`)을
   전부 끌어다 놓은 뒤 **Commit changes** 를 누릅니다.
4. 저장소 위쪽 **Settings** → 왼쪽 **Pages**
   - Source: **GitHub Actions** 를 고릅니다. (저장은 자동)
5. 저장소 위쪽 **Actions** 탭 → 왼쪽 **collect** → 오른쪽 **Run workflow** → **Run workflow**
   - 3~5분 뒤 초록 체크가 뜨면 첫 수집과 게시가 끝난 것입니다.
6. 폰에서 `https://(내 아이디).github.io/today-edu/` 를 엽니다.
   - 아이폰(사파리): 공유 버튼 → **홈 화면에 추가**
   - 안드로이드(크롬): 오른쪽 위 ⋮ → **홈 화면에 추가** 또는 **앱 설치**

## 업데이트 방식

- 30분마다(매시 7분, 37분) 자동으로 새 기사를 모읍니다. GitHub 사정에 따라 몇 분~수십 분 늦어질 수 있습니다.
- 페이지의 **다시 불러오기** 는 가장 최근 수집 결과를 불러옵니다.
- 바로 새로 모으고 싶으면 **Actions → collect → Run workflow** 를 누르고 5분쯤 뒤 새로고침하세요.
- 수집 결과 파일은 저장소에 쌓지 않고 페이지로 바로 게시합니다.
  '새 이슈' 판단에 쓰는 날짜별 기록만 매일 밤 23시대에 한 번 저장소에 백업합니다.

## 문제가 생기면

- **Actions 탭에 collect가 없을 때**: `.github` 폴더가 업로드되지 않은 것입니다.
  **Add file → Create new file** 에서 파일 이름에 `.github/workflows/collect.yml` 을 적고,
  압축 파일 안의 같은 파일 내용을 붙여 넣은 뒤 저장하세요.
- **페이지 게시 단계에서 실패할 때**: Settings → Pages 의 Source 가 **GitHub Actions** 인지 확인하세요.
- **빨간 X가 뜰 때**: 해당 실행을 눌러 로그를 보면 이유가 나옵니다.
  기사를 하나도 못 모은 때는 일부러 실패로 처리해 이전 페이지를 그대로 둡니다.
- **수집 간격을 바꾸려면**: `.github/workflows/collect.yml` 의 `cron` 줄을 고칩니다.
  시각은 UTC 기준이라 한국 시각에서 9시간을 빼서 적습니다.

## 참고

- 공개 페이지이므로 언론사 요약문은 싣지 않고 제목·링크만 보여줍니다.
  검색엔진에는 노출되지 않도록 설정해 두었지만, 주소를 아는 사람은 볼 수 있습니다.
- 저장한 기사, 내 키워드, 읽음 표시는 각 기기의 브라우저에만 보관됩니다.
