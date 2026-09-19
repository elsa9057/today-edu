param([switch]$CollectOnly,[int]$ServerPid=0)
# TodayEdu v6.3 (Claude edition) - public/static mode for GitHub Actions + Pages; - rare-word weighted issue grouping; - 7-day column window, no-repeat column ranking; - daily archive, new-issue marks, history API; keyless: real article summaries (og:description), factual selection basis,
#   direct outlet RSS, runspace fetch + retry, column/education fixes, bigram clustering, publisher cap
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
# 같은 프로세스 안에서 병렬 요청을 보내므로 호스트당 동시 연결 제한(기본 2)을 늘립니다.
[Net.ServicePointManager]::DefaultConnectionLimit = 32

$BaseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Port = 8767
$AppPath = Join-Path $BaseDir 'app.html'
$CachePath = Join-Path $BaseDir 'cache.json'
$LogPath = Join-Path $BaseDir 'server.log'
$PidPath = Join-Path $BaseDir 'server.pid'
$CollectPidPath = Join-Path $BaseDir 'collector.pid'
$ProgressPath = Join-Path $BaseDir 'progress.json'
$ArchiveDir = Join-Path $BaseDir 'archive'

function Log-Line([string]$text) {
  try {
    $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    [IO.File]::AppendAllText($LogPath, "[$stamp] $text`r`n", (New-Object System.Text.UTF8Encoding($true)))
  } catch {}
}

function To-Utf8Bytes([string]$text) {
  return [System.Text.Encoding]::UTF8.GetBytes($text)
}

$PreferredPublishers = @(
  '조선일보','중앙일보','동아일보','한겨레','경향신문','한국일보','서울신문','국민일보',
  '매일경제','한국경제','연합뉴스','연합뉴스TV','KBS','MBC','SBS','YTN','EBS',
  '한국교육신문','에듀프레스','한국대학신문','대학저널','베리타스알파'
)


# 22개 매체 모두를 매체별 전용 검색으로 확인합니다.
# RSS가 있는 매체도 전용 검색을 함께 사용해 교육 기사 포착률을 보완합니다.
$MediaSearchSources = @(
  @{ publisher='조선일보'; domain='chosun.com'; news='(교육 OR 학교 OR 교사 OR 수능 OR 대입 OR 대학 OR AI교육) when:5d'; column='(교육 칼럼 OR 교육 사설 OR 교육 기고 OR 오피니언 교육) when:7d' },
  @{ publisher='중앙일보'; domain='joongang.co.kr'; news='(교육 OR 학교 OR 교사 OR 수능 OR 대입 OR 대학 OR AI교육) when:5d'; column='(교육 칼럼 OR 교육 사설 OR 교육 기고 OR 오피니언 교육) when:7d' },
  @{ publisher='동아일보'; domain='donga.com'; news='(교육 OR 학교 OR 교사 OR 수능 OR 대입 OR 대학 OR AI교육) when:5d'; column='(교육 칼럼 OR 교육 사설 OR 교육 기고 OR 오피니언 교육) when:7d' },
  @{ publisher='한겨레'; domain='hani.co.kr'; news='(교육 OR 학교 OR 교사 OR 수능 OR 대입 OR 대학 OR AI교육) when:5d'; column='(교육 칼럼 OR 교육 사설 OR 교육 기고 OR 오피니언 교육) when:7d' },
  @{ publisher='경향신문'; domain='khan.co.kr'; news='(교육 OR 학교 OR 교사 OR 수능 OR 대입 OR 대학 OR AI교육) when:5d'; column='(교육 칼럼 OR 교육 사설 OR 교육 기고 OR 오피니언 교육) when:7d' },
  @{ publisher='한국일보'; domain='hankookilbo.com'; news='(교육 OR 학교 OR 교사 OR 수능 OR 대입 OR 대학 OR AI교육) when:5d'; column='(교육 칼럼 OR 교육 사설 OR 교육 기고 OR 오피니언 교육) when:7d' },
  @{ publisher='서울신문'; domain='seoul.co.kr'; news='(교육 OR 학교 OR 교사 OR 수능 OR 대입 OR 대학 OR AI교육) when:5d'; column='(교육 칼럼 OR 교육 사설 OR 교육 기고 OR 오피니언 교육) when:7d' },
  @{ publisher='국민일보'; domain='kmib.co.kr'; news='(교육 OR 학교 OR 교사 OR 수능 OR 대입 OR 대학 OR AI교육) when:5d'; column='(교육 칼럼 OR 교육 사설 OR 교육 기고 OR 오피니언 교육) when:7d' },
  @{ publisher='매일경제'; domain='mk.co.kr'; news='(교육 OR 학교 OR 교사 OR 수능 OR 대입 OR 대학 OR AI교육 OR 에듀테크) when:5d'; column='(교육 칼럼 OR 교육 기고 OR 오피니언 교육 OR 대학 칼럼) when:7d' },
  @{ publisher='한국경제'; domain='hankyung.com'; news='(교육 OR 학교 OR 교사 OR 수능 OR 대입 OR 대학 OR AI교육 OR 에듀테크) when:5d'; column='(교육 칼럼 OR 교육 기고 OR 오피니언 교육 OR 대학 칼럼) when:7d' },
  @{ publisher='연합뉴스'; domain='yna.co.kr'; news='(교육 OR 교육부 OR 교육청 OR 학교 OR 교사 OR 수능 OR 대입 OR 대학 OR AI교육) when:5d'; column='' },
  @{ publisher='연합뉴스TV'; domain='yonhapnewstv.co.kr'; news='(교육 OR 교육부 OR 교육청 OR 학교 OR 교사 OR 수능 OR 대입 OR 대학 OR AI교육) when:5d'; column='' },
  @{ publisher='KBS'; domain='kbs.co.kr'; news='(교육 OR 교육부 OR 교육청 OR 학교 OR 교사 OR 수능 OR 대입 OR 대학 OR AI교육) when:5d'; column='' },
  @{ publisher='MBC'; domain='imnews.imbc.com'; news='(교육 OR 교육부 OR 교육청 OR 학교 OR 교사 OR 수능 OR 대입 OR 대학 OR AI교육) when:5d'; column='' },
  @{ publisher='SBS'; domain='news.sbs.co.kr'; news='(교육 OR 교육부 OR 교육청 OR 학교 OR 교사 OR 수능 OR 대입 OR 대학 OR AI교육) when:5d'; column='' },
  @{ publisher='YTN'; domain='ytn.co.kr'; news='(교육 OR 교육부 OR 교육청 OR 학교 OR 교사 OR 수능 OR 대입 OR 대학 OR AI교육) when:5d'; column='' },
  @{ publisher='EBS'; domain='ebs.co.kr'; news='(교육 OR 교육정책 OR 학교 OR 교사 OR 수능 OR 입시 OR 대학 OR AI교육) when:5d'; column='' },
  @{ publisher='한국교육신문'; domain='hangyo.com'; news='(교육 OR 교육정책 OR 학교 OR 교사 OR 교권 OR 수능 OR 대학 OR AI교육) when:5d'; column='(교육 칼럼 OR 교육 사설 OR 교육 기고 OR 기자수첩) when:7d' },
  @{ publisher='에듀프레스'; domain='edupress.kr'; news='(교육 OR 교육정책 OR 학교 OR 교사 OR 교권 OR 수능 OR 대학 OR AI교육) when:5d'; column='(교육 칼럼 OR 교육 기고 OR 기자수첩 OR 교육 시론) when:7d' },
  @{ publisher='한국대학신문'; domain='news.unn.net'; news='(대학 OR 입시 OR 고등교육 OR 등록금 OR 교수 OR AI OR 에듀테크) when:5d'; column='(대학 칼럼 OR 교육 칼럼 OR 기고 OR 시론) when:7d' },
  @{ publisher='대학저널'; domain='dhnews.co.kr'; news='(대학 OR 입시 OR 고등교육 OR 등록금 OR 교수 OR AI OR 에듀테크) when:5d'; column='(대학 칼럼 OR 교육 칼럼 OR 기고 OR 시론) when:7d' },
  @{ publisher='베리타스알파'; domain='veritas-a.com'; news='(입시 OR 대입 OR 수능 OR 수시 OR 정시 OR 고교 OR 학교 OR 교육) when:5d'; column='(칼럼 OR 기고 OR 시론 OR 기자수첩) when:7d' }
)

$Feeds = @(
  @{ name='조선일보 사회'; publisher='조선일보'; type='news'; url='https://www.chosun.com/arc/outboundfeeds/rss/category/national/?outputType=xml' },
  @{ name='조선일보 오피니언'; publisher='조선일보'; type='column'; url='https://www.chosun.com/arc/outboundfeeds/rss/category/opinion/?outputType=xml' },
  @{ name='동아일보 사회'; publisher='동아일보'; type='news'; url='https://rss.donga.com/national.xml' },
  @{ name='경향신문 사회'; publisher='경향신문'; type='news'; url='https://www.khan.co.kr/rss/rssdata/society_news.xml' },
  @{ name='경향신문 오피니언'; publisher='경향신문'; type='column'; url='https://www.khan.co.kr/rss/rssdata/opinion_news.xml' },
  @{ name='한국경제 사회'; publisher='한국경제'; type='news'; url='https://www.hankyung.com/feed/society' },
  @{ name='한국경제 오피니언'; publisher='한국경제'; type='column'; url='https://www.hankyung.com/feed/opinion' },
  @{ name='국민일보 사회'; publisher='국민일보'; type='news'; url='https://www.kmib.co.kr/rss/data/kmibSocRss.xml' },
  @{ name='연합뉴스TV 사회'; publisher='연합뉴스TV'; type='news'; url='https://www.yonhapnewstv.co.kr/category/news/society/feed/' },
  # v5.0 추가: 매체 직접 RSS. 주소가 바뀌어 실패해도 해당 항목만 '실패'로 표시되고 나머지는 정상 동작합니다.
  @{ name='연합뉴스 사회'; publisher='연합뉴스'; type='news'; url='https://www.yna.co.kr/rss/society.xml' },
  @{ name='한겨레 사회'; publisher='한겨레'; type='news'; url='https://www.hani.co.kr/rss/society/' },
  @{ name='SBS 사회'; publisher='SBS'; type='news'; url='https://news.sbs.co.kr/news/SectionRssFeed.do?sectionId=03' },
  @{ name='에듀프레스 전체'; publisher='에듀프레스'; type='news'; url='https://www.edupress.kr/rss/allArticle.xml' },
  @{ name='한국대학신문 전체'; publisher='한국대학신문'; type='news'; url='https://news.unn.net/rss/allArticle.xml' },
  @{ name='대학저널 전체'; publisher='대학저널'; type='news'; url='https://www.dhnews.co.kr/rss/allArticle.xml' },
  @{ name='베리타스알파 전체'; publisher='베리타스알파'; type='news'; url='https://www.veritas-a.com/rss/allArticle.xml' }
)

$EducationRegex = '(교육부|교육청|교육감|교육정책|교육과정|학교|초등|중등|고등|고교|학생|교사|교원|교직|학부모|수능|입시|대입|대학|전문대|등록금|장학금|학생부|내신|고교학점제|사교육|학원|교권|학교폭력|학폭|유치원|어린이집|늘봄|돌봄|특수교육|직업교육|평생교육|에듀테크|AI.?교육|인공지능.?교육|디지털.?교과서|학습|교과서|교수|캠퍼스|졸업|입학|학사|교육계|교육현장|수시|정시|모집요강|학종|논술전형|의대|의예과|특목고|자사고|영재고|과학고|외고|국제고|재수생|N수)'
$ColumnRegex = '(사설|칼럼|기고|시론|논설|오피니언|에세이|취재수첩|기자수첩|취재일기|취재후기|데스크칼럼|데스크|전문가.?기고|특별기고|세상읽기|아침을.?열며|시평|논단|노트북을.?열며|기자의.?시각|편집국에서|시시각각|여적|만물상|분수대|횡설수설|교단일기)'

# '반면교사'처럼 교육과 무관한데 '교사'가 들어가는 표현은 교육 키워드 판정 전에 지웁니다.
$EduNoiseRegex = '(반면교사|정면교사|살인교사|방화교사|교사범|교사죄|교육부터)'
function Clean-EduNoise([string]$text) {
  if ([string]::IsNullOrWhiteSpace($text)) { return '' }
  return ($text -replace $EduNoiseRegex, ' ')
}
function Test-Education([string]$text) {
  return ((Clean-EduNoise $text) -match $EducationRegex)
}

# 인사·부고·채용공고 등은 크게 감점하고, 보도자료 전재는 조금 감점합니다.
$LowValueRegex = '([\[【]\s*(?:[^\]】]{0,12}\s)?(인사|부고|부음|동정|게시판|포토|알림|공고|모집|신간)\s*[\]】])|채용\s?공고|기간제\s?근로자|인사\s?발령'
$PressReleaseRegex = '[\[【]\s*(보도자료|보도참고자료)\s*[\]】]'

# 한 매체가 후보 목록을 독점하지 않도록 매체별 최대 건수를 둡니다.
$PublisherCaps = @{ '한국대학신문'=8; '대학저널'=8; '베리타스알파'=10 }
$DefaultPublisherCap = 15

# chosun.com 도메인의 자매 매체는 제목 꼬리표를 떼고 매체명을 따로 표시합니다.
$SubBrandRegex = '^(조선비즈|조선에듀|헬스조선)$'
$ColumnNegativeRegex = '^\s*(\[?(속보|단독|종합|영상|포토|현장)\]?|속보\s|단독\s)'

# 실제 칼럼·사설·기고 등으로 확인되는 글만 칼럼 후보로 인정합니다.
# 오피니언 전용 RSS는 섹션 자체를 신뢰하되, 일반/검색 결과는 제목·설명에 칼럼 표지가 있어야 합니다.
function Is-GenuineColumn([string]$title,[string]$summary,[string]$declaredKind,[string]$sourceName) {
  if ([string]::IsNullOrWhiteSpace($title)) { return $false }
  if ($title -match $ColumnNegativeRegex) { return $false }
  if (-not [string]::IsNullOrWhiteSpace($sourceName) -and $sourceName -match '(오피니언|Opinion|사설|칼럼)') { return $true }
  if ($title -match $ColumnRegex) { return $true }
  if ($declaredKind -eq 'column' -and -not [string]::IsNullOrWhiteSpace($summary) -and $summary -match $ColumnRegex) { return $true }
  return $false
}

# 뉴스는 평일 '오늘+어제', 월요일은 주말 누락을 막기 위해 '금요일~오늘'을 봅니다.
# 칼럼은 같은 기간을 우선하고 3건 미만이면 최근 3개 달력 날짜까지 넓힙니다.
function Get-DateWindowInfo {
  $now = [DateTimeOffset]::Now
  $today = $now.Date
  $isMonday = ($today.DayOfWeek -eq [System.DayOfWeek]::Monday)
  if ($isMonday) { $newsStart = $today.AddDays(-3) } else { $newsStart = $today.AddDays(-1) }
  $columnFallbackStart = $today.AddDays(-2)
  if ($newsStart -lt $columnFallbackStart) { $columnFallbackStart = $newsStart }
  $rule = if ($isMonday) { '금요일~오늘' } else { '오늘+어제' }
  return [pscustomobject]@{
    Now=$now
    End=$now.LocalDateTime
    NewsStart=$newsStart
    ColumnFallbackStart=$columnFallbackStart
    Rule=$rule
  }
}

function Is-InDateWindow([string]$published,[datetime]$start,[datetime]$end) {
  try {
    $dto = [DateTimeOffset]::Parse($published)
    $local = $dto.ToLocalTime().DateTime
    return ($local -ge $start -and $local -le $end)
  } catch { return $false }
}


function HtmlDecode([string]$s) {
  if ([string]::IsNullOrWhiteSpace($s)) { return '' }
  $t = [System.Net.WebUtility]::HtmlDecode($s)
  $t = [regex]::Replace($t, '<script[\s\S]*?</script>', ' ', 'IgnoreCase')
  $t = [regex]::Replace($t, '<style[\s\S]*?</style>', ' ', 'IgnoreCase')
  $t = [regex]::Replace($t, '<[^>]+>', ' ')
  $t = [regex]::Replace($t, '\s+', ' ').Trim()
  return $t
}

function Truncate([string]$s, [int]$n) {
  if ([string]::IsNullOrWhiteSpace($s)) { return '' }
  if ($s.Length -le $n) { return $s }
  return $s.Substring(0,$n).Trim() + '…'
}

function Parse-DateSafe([string]$s) {
  $fallback = [DateTimeOffset]::Parse('2000-01-01T00:00:00+00:00')
  if ([string]::IsNullOrWhiteSpace($s)) { return $fallback }
  try { return [DateTimeOffset]::Parse($s) } catch { return $fallback }
}

function Get-XmlText($node, [string]$name) {
  if ($null -eq $node) { return '' }
  try {
    $v = $node.$name
    if ($null -eq $v) { return '' }
    if ($v -is [System.Array]) {
      if ($v.Count -gt 0) {
        $first = $v[0]
        if ($first -is [System.Xml.XmlElement]) { return [string]$first.InnerText }
        return [string]$first
      }
      return ''
    }
    if ($v -is [System.Xml.XmlElement]) { return [string]$v.InnerText }
    return [string]$v
  } catch { return '' }
}

function Get-Link($node) {
  try {
    $v = $node.link
    if ($null -eq $v) { return '' }
    if ($v -is [System.Array]) {
      foreach($x in $v) {
        if ($null -ne $x.href -and -not [string]::IsNullOrWhiteSpace([string]$x.href)) { return [string]$x.href }
        if ($null -ne $x.InnerText -and -not [string]::IsNullOrWhiteSpace([string]$x.InnerText)) { return [string]$x.InnerText }
      }
      return ''
    }
    if ($null -ne $v.href -and -not [string]::IsNullOrWhiteSpace([string]$v.href)) { return [string]$v.href }
    if ($null -ne $v.InnerText -and -not [string]::IsNullOrWhiteSpace([string]$v.InnerText)) { return [string]$v.InnerText }
    return [string]$v
  } catch { return '' }
}

function Normalize-Publisher([string]$p) {
  if ([string]::IsNullOrWhiteSpace($p)) { return '' }
  $p = $p.Trim()
  foreach($known in $PreferredPublishers) {
    if ($p -like "*$known*") { return $known }
  }
  if ($p -like '*베리타스*' -or $p -like '*veritas*') { return '베리타스알파' }
  if ($p -like '*KBS*') { return 'KBS' }
  if ($p -like '*MBC*') { return 'MBC' }
  if ($p -like '*SBS*') { return 'SBS' }
  if ($p -like '*YTN*') { return 'YTN' }
  if ($p -like '*EBS*') { return 'EBS' }
  return $p
}

function Is-PreferredPublisher([string]$p) {
  $n = Normalize-Publisher $p
  return ($PreferredPublishers -contains $n)
}

function Classify-Topic([string]$text) {
  $text = Clean-EduNoise $text
  if ($text -match '(AI|인공지능|에듀테크|디지털.?교과서|디지털.?교육|생성형)') { return 'AI교육' }
  if ($text -match '(수능|입시|대입|학생부|내신|정시|수시|논술|전형)') { return '입시' }
  if ($text -match '(대학|전문대|등록금|교수|캠퍼스|총장|학사|대학생)') { return '대학' }
  if ($text -match '(교사|교원|교권|교직|담임|선생님|교원단체)') { return '교사' }
  if ($text -match '(교육부|교육청|교육감|법안|정책|시행|개편|예산|국가교육위원회|교육과정)') { return '정책' }
  if ($text -match '(미국|영국|프랑스|일본|중국|OECD|해외|뉴욕|하버드|옥스퍼드)') { return '해외교육' }
  return '학교'
}

function Importance-Score([string]$title, [string]$summary, $date, [string]$type, [string]$publisher) {
  $text = Clean-EduNoise "$title $summary"
  $score = 0.0
  try { $hours = ([DateTimeOffset]::Now - [DateTimeOffset]$date).TotalHours } catch { $hours = 9999 }
  if ($hours -lt 6) { $score += 4.5 }
  elseif ($hours -lt 12) { $score += 4.0 }
  elseif ($hours -lt 24) { $score += 3.2 }
  elseif ($hours -lt 48) { $score += 2.2 }
  elseif ($hours -lt 168) { $score += 1.0 }
  if ($text -match '(교육부|교육청|교육감|국가교육위원회)') { $score += 3.0 }
  if ($text -match '(발표|시행|개편|확정|도입|폐지|법안|국무회의|예산|전국|전면|의무)') { $score += 2.2 }
  if ($text -match '(수능|대입|입시|고교학점제|교권|학교폭력|등록금|AI|인공지능|사교육|교사)') { $score += 2.0 }
  if ($text -match '(단독|속보|첫|최초|논란|쟁점|갈등|대책)') { $score += 0.8 }
  if ($type -eq 'column') {
    if ($title -match $ColumnRegex) { $score += 2.0 }
    if ($text -match '(왜|어떻게|문제|과제|미래|역할|변화|쟁점|생각)') { $score += 1.2 }
  }
  if (Is-PreferredPublisher $publisher) { $score += 0.5 }
  if ($title -match $LowValueRegex) { $score -= 4.0 }
  elseif ($title -match $PressReleaseRegex) { $score -= 1.5 }
  return [Math]::Round($score,2)
}

function Normalize-Title([string]$title) {
  $t = HtmlDecode $title
  $t = [regex]::Replace($t, '^\[[^\]]+\]\s*', '')
  $t = [regex]::Replace($t, '\s+-\s+[^-]{1,30}$', '')
  $t = [regex]::Replace($t, '[^0-9A-Za-z가-힣 ]', ' ')
  $t = [regex]::Replace($t, '\s+', ' ').Trim().ToLowerInvariant()
  return $t
}

# 한국어 제목은 조사 때문에 단어 단위 비교가 약하므로 글자 2개(bigram) 단위로 비교합니다.
function Get-Bigrams([string]$norm) {
  $set = New-Object 'System.Collections.Generic.HashSet[string]'
  $t = [regex]::Replace([string]$norm, '\s', '')
  for($i=0; $i -lt $t.Length - 1; $i++) { [void]$set.Add($t.Substring($i,2)) }
  return ,$set
}

# 희소어 가중치: 그날 기사 제목 전체에서 드물게 나오는 글자쌍일수록 무게가 큽니다.
$script:Idf = $null
$script:IdfMax = 0.0
$script:IdfThreshold = 18.0
$script:SetWeights = @{}
function Build-Idf($sets) {
  $df = New-Object 'System.Collections.Generic.Dictionary[string,int]'
  $n = 0
  foreach($st in $sets) { $n++; foreach($b in $st) { if ($df.ContainsKey($b)) { $df[$b]++ } else { $df[$b] = 1 } } }
  if ($n -lt 5) { $script:Idf = $null; return }
  $idf = New-Object 'System.Collections.Generic.Dictionary[string,double]'
  foreach($k in $df.Keys) { $idf[$k] = [Math]::Log($n / [double]$df[$k]) }
  $script:Idf = $idf
  $script:IdfMax = [Math]::Log([double]$n)
  # 기사 수가 달라도 기준이 비슷하게 유지되도록 조정합니다(기준 표본 176건).
  $script:IdfThreshold = 18.0 * $script:IdfMax / [Math]::Log(176.0)
  $script:SetWeights = @{}
}
function Get-Idf([string]$b) {
  $v = 0.0
  if ($script:Idf.TryGetValue($b, [ref]$v)) { return $v }
  return $script:IdfMax
}
function Get-SetWeight($set) {
  $key = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($set)
  if ($script:SetWeights.ContainsKey($key)) { return $script:SetWeights[$key] }
  $w = 0.0
  foreach($b in $set) { $w += (Get-Idf $b) }
  $script:SetWeights[$key] = $w
  return $w
}

# 같은 사안이면 0보다 큰 점수, 아니면 0을 돌려줍니다.
function Title-Similarity($setA, $setB) {
  if ($null -eq $setA -or $null -eq $setB) { return 0.0 }
  if ($setA.Count -lt 2 -or $setB.Count -lt 2) { return 0.0 }
  $tmp = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList (,$setA)
  $tmp.IntersectWith($setB)
  $inter = $tmp.Count
  if ($inter -lt 3) { return 0.0 }
  $union = $setA.Count + $setB.Count - $inter
  if ($union -le 0) { return 0.0 }
  $jac = $inter / [double]$union
  $ovl = $inter / [double][Math]::Min($setA.Count, $setB.Count)
  if ($jac -ge 0.30) { return ($jac + $ovl) }
  if ($inter -ge 8 -and $ovl -ge 0.45 -and $jac -ge 0.20) { return ($jac + $ovl) }
  if ($null -ne $script:Idf) {
    $wI = 0.0
    foreach($b in $tmp) { $wI += (Get-Idf $b) }
    if ($wI -ge $script:IdfThreshold) {
      $wMin = [Math]::Min((Get-SetWeight $setA), (Get-SetWeight $setB))
      if ($wMin -gt 0) {
        $w = $wI / $wMin
        if ($w -ge 0.30) { return (0.1 + $w) }
      }
    }
  }
  return 0.0
}

function Clean-SourceSummary([string]$s, [string]$title) {
  if ([string]::IsNullOrWhiteSpace($s)) { return '' }
  $t = HtmlDecode $s
  $t = [regex]::Replace($t, '^\s*\([^\)]{1,80}\)\s*', '')
  $t = [regex]::Replace($t, '^\s*\[[^\]]{1,80}\]\s*', '')
  $t = [regex]::Replace($t, '^\s*[^\s]{1,20}\s+기자\s*[=\-:]\s*', '')
  $t = [regex]::Replace($t, '(무단전재|재배포|저작권자|Copyright|ⓒ).*$','', 'IgnoreCase')
  $t = [regex]::Replace($t, '\s+', ' ').Trim()
  if (-not [string]::IsNullOrWhiteSpace($title)) {
    $plainTitle = [regex]::Replace((HtmlDecode $title), '\s+', ' ').Trim()
    if ($t.StartsWith($plainTitle)) {
      $t = $t.Substring($plainTitle.Length).Trim([char[]]' -–—:')
    }
  }
  return $t
}

function Is-GoogleNewsUrl([string]$u) {
  return ([string]$u -match '^https?://news\.google\.com/')
}

# 언론사가 제공한 요약(RSS 설명 또는 기사 페이지의 og:description)만 씁니다.
# 요약이 없으면 빈 칸으로 두고, 지어낸 문장을 채우지 않습니다.
function Get-RealSummary([string]$raw, [string]$title, [string]$publisher) {
  $clean = Clean-SourceSummary $raw $title
  # 제목 뒤에 붙어 있던 '(서울=연합뉴스) 홍길동 기자 =' 같은 머리말과 끝의 매체명을 한 번 더 지웁니다.
  $clean = [regex]::Replace($clean, '^\s*[\(\[【][^\)\]】]{1,30}[\)\]】]\s*', '')
  $clean = [regex]::Replace($clean, '^\s*[^\s]{1,20}\s+(기자|특파원)\s*[=\-:]\s*', '')
  if (-not [string]::IsNullOrWhiteSpace($publisher) -and $clean.Trim().EndsWith($publisher)) { $clean = $clean.Trim().Substring(0, $clean.Trim().Length - $publisher.Length) }
  $clean = [regex]::Replace($clean, '\s+', ' ').Trim()
  if ($clean.Length -lt 25) { return '' }
  $parts = @([regex]::Split($clean, '(?<=[\.\?\!])\s+'))
  $out = ''
  foreach($p in $parts) {
    $x = ([string]$p).Trim()
    if ($x -match '^(사진|영상|관련기사|기사제보|\[?사진)') { continue }
    if (($out.Length + $x.Length) -gt 230) { break }
    $out = ($out + ' ' + $x).Trim()
  }
  if ($out.Length -lt 25) { $out = Truncate $clean 230 }
  return $out
}

# '선정 근거'는 확인 가능한 사실만 적습니다: 보도 매체 수, 발표 주체, 보도 시각, 칼럼 필자.
function Reason-For($item, $relatedItems) {
  $text = Clean-EduNoise "$($item.title) $($item.raw_summary)"
  $parts = @()
  if ($item.type -eq 'column') {
    $m = [regex]::Match([string]$item.title, '\[(기고|시론|칼럼|사설|기자수첩|취재일기|논단|특별기고)\s*/\s*([^\]]{2,15})\]')
    if ($m.Success) { $parts += ("{0} {1} · 필자 {2}" -f $item.publisher, $m.Groups[1].Value, $m.Groups[2].Value.Trim()) }
    else {
      $k = [regex]::Match([string]$item.title, $ColumnRegex)
      if ($k.Success) { $parts += ("{0} {1}" -f $item.publisher, $k.Value) } else { $parts += ("{0} 오피니언" -f $item.publisher) }
    }
    return ($parts -join ' · ')
  }
  $pubs = @($relatedItems | ForEach-Object { $_.publisher } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
  if ($pubs.Count -ge 2) {
    $names = @($pubs | Select-Object -First 4) -join '·'
    if ($pubs.Count -gt 4) { $names += (" 외 {0}곳" -f ($pubs.Count - 4)) }
    $parts += ("{0}개 매체 보도({1})" -f $pubs.Count, $names)
  }
  if ($text -match '(교육부|교육청|교육감|국가교육위원회|국교위)') { $parts += '교육당국 발표·조치 관련' }
  if ($text -match '(국회|법안|개정안|시행령|국무회의)') { $parts += '법·제도 변경 관련' }
  if ($text -match '(수능|대입|수시|정시|원서 접수)') { $parts += '입시 일정 관련' }
  try { $hours = ([DateTimeOffset]::Now - [DateTimeOffset]::Parse([string]$item.published)).TotalHours } catch { $hours = 999 }
  if ($hours -ge 0 -and $hours -lt 6) { $parts += ("{0}시간 전 보도" -f [Math]::Max(1,[int][Math]::Floor($hours))) }
  return ($parts -join ' · ')
}

function Convert-FeedItem($node, $feed) {
  $title = HtmlDecode (Get-XmlText $node 'title')
  if ([string]::IsNullOrWhiteSpace($title)) { return $null }
  $link = Get-Link $node
  $desc = Get-XmlText $node 'description'
  if ([string]::IsNullOrWhiteSpace($desc)) { $desc = Get-XmlText $node 'summary' }
  if ([string]::IsNullOrWhiteSpace($desc)) { $desc = Get-XmlText $node 'content' }
  $summary = Truncate (HtmlDecode $desc) 650
  $dateText = Get-XmlText $node 'pubDate'
  if ([string]::IsNullOrWhiteSpace($dateText)) { $dateText = Get-XmlText $node 'updated' }
  if ([string]::IsNullOrWhiteSpace($dateText)) { $dateText = Get-XmlText $node 'published' }
  $date = Parse-DateSafe $dateText
  $text = "$title $summary"
  if (-not (Test-Education $text)) { return $null }
  $declaredType = [string]$feed.type
  $type = 'news'
  if ($declaredType -eq 'column') {
    if (-not (Is-GenuineColumn $title $summary 'column' ([string]$feed.name))) { return $null }
    $type = 'column'
  } elseif (Is-GenuineColumn $title $summary 'news' ([string]$feed.name)) {
    $type = 'column'
  }
  $pub = Normalize-Publisher ([string]$feed.publisher)
  return [pscustomobject]@{
    title=$title
    publisher=$pub
    url=$link
    raw_summary=$summary
    summary=$summary
    topic=(Classify-Topic $text)
    type=$type
    published=$date.ToString('o')
    score=(Importance-Score $title $summary $date $type $pub)
    source=[string]$feed.name
    coverage_count=1
    publishers=@($pub)
  }
}

function Parse-RssContent([string]$content, $feed) {
  $out = @()
  if ([string]::IsNullOrWhiteSpace($content)) { return $out }
  [xml]$xml = $content
  $nodes = @()
  if ($null -ne $xml.rss -and $null -ne $xml.rss.channel -and $null -ne $xml.rss.channel.item) { $nodes = @($xml.rss.channel.item) }
  elseif ($null -ne $xml.feed -and $null -ne $xml.feed.entry) { $nodes = @($xml.feed.entry) }
  foreach($n in $nodes) {
    $obj = Convert-FeedItem $n $feed
    if ($null -ne $obj) { $out += $obj }
  }
  return $out
}

function Parse-GoogleNewsContent([string]$content,[string]$kind,[string]$expectedPublisher='') {
  $items = @()
  if ([string]::IsNullOrWhiteSpace($content)) { return $items }
  [xml]$xml = $content
  $nodes = @()
  if ($null -ne $xml.rss -and $null -ne $xml.rss.channel -and $null -ne $xml.rss.channel.item) { $nodes = @($xml.rss.channel.item) }
  foreach($n in $nodes) {
    $titleRaw = HtmlDecode (Get-XmlText $n 'title')
    if ([string]::IsNullOrWhiteSpace($titleRaw)) { continue }
    $source = ''
    try {
      if ($null -ne $n.source) {
        if ($null -ne $n.source.InnerText) { $source = [string]$n.source.InnerText }
        else { $source = [string]$n.source }
      }
    } catch {}
    $pub = Normalize-Publisher $source
    if (-not [string]::IsNullOrWhiteSpace($expectedPublisher)) {
      $expected = Normalize-Publisher $expectedPublisher
      if ([string]::IsNullOrWhiteSpace($pub) -or -not (Is-PreferredPublisher $pub)) { $pub = $expected }
      elseif ($pub -ne $expected -and $source -notlike "*$expectedPublisher*") { continue }
    }
    if (-not (Is-PreferredPublisher $pub)) { continue }
    $title = $titleRaw
    if ($titleRaw -match '^(.*)\s+-\s+([^\-]+)$') { $title = $matches[1].Trim() }
    if ($title -match '^(.*\S)\s+-\s+([^\-]{1,15})$' -and $matches[2].Trim() -match $SubBrandRegex) {
      $pub = ($title -replace '^.*\S\s+-\s+([^\-]{1,15})$','$1').Trim()
      $title = ($title -replace '\s+-\s+[^\-]{1,15}$','').Trim()
    }
    $desc = Truncate (HtmlDecode (Get-XmlText $n 'description')) 650
    $date = Parse-DateSafe (Get-XmlText $n 'pubDate')
    $text = "$title $desc"
    if (-not (Test-Education $text)) { continue }
    $type = 'news'
    if ($kind -eq 'column') {
      if (-not (Is-GenuineColumn $title $desc 'column' 'Google News 검색')) { continue }
      $type = 'column'
    } elseif (Is-GenuineColumn $title $desc 'news' 'Google News 검색') {
      $type = 'column'
    }
    $items += [pscustomobject]@{
      title=$title; publisher=$pub; url=(Get-Link $n); raw_summary=''; summary=''
      topic=(Classify-Topic $text); type=$type; published=$date.ToString('o')
      score=(Importance-Score $title $desc $date $type $pub); source='Google News 검색'
      coverage_count=1; publishers=@($pub)
    }
  }
  return $items
}

function Write-Progress([int]$done,[int]$total,[string]$message) {
  try {
    $o=[pscustomobject]@{ done=$done; total=$total; message=$message; updated_at=[DateTimeOffset]::Now.ToString('o') }
    [IO.File]::WriteAllText($ProgressPath, ($o | ConvertTo-Json -Compress), (New-Object System.Text.UTF8Encoding($false)))
  } catch {}
}

$FetchScript = {
  param([string]$url, [int]$timeout)
  $ProgressPreference = 'SilentlyContinue'
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $r = Invoke-WebRequest -UseBasicParsing -Uri $url -TimeoutSec $timeout -Headers @{ 'User-Agent'='Mozilla/5.0 (Windows NT 10.0; Win64; x64) TodayEdu/6.0'; 'Accept-Language'='ko-KR,ko;q=0.9' }
    [pscustomobject]@{ ok=$true; content=[string]$r.Content; error='' }
  } catch {
    [pscustomobject]@{ ok=$false; content=''; error=[string]$_.Exception.Message }
  }
}

# 상위 기사의 원문 페이지를 열어 언론사가 직접 쓴 요약(og:description)을 가져옵니다.
# Google News 링크면 먼저 실제 기사 주소로 바꿉니다. 어느 단계든 실패하면 조용히 건너뜁니다.
$EnrichScript = {
  param([string]$url, [int]$timeout)
  $ProgressPreference = 'SilentlyContinue'
  $hdr = @{ 'User-Agent'='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36'; 'Accept-Language'='ko-KR,ko;q=0.9' }
  try { [System.Text.Encoding]::RegisterProvider([System.Text.CodePagesEncodingProvider]::Instance) } catch {}
  function Read-Html($resp) {
    $bytes = $resp.RawContentStream.ToArray()
    $cs = ''
    try { $ct = [string]$resp.Headers['Content-Type']; $m = [regex]::Match($ct, 'charset=([\w\-]+)'); if ($m.Success) { $cs = $m.Groups[1].Value } } catch {}
    if (-not $cs) {
      $head = [System.Text.Encoding]::ASCII.GetString($bytes, 0, [Math]::Min(4096, $bytes.Length))
      $m = [regex]::Match($head, 'charset\s*=\s*["'']?([\w\-]+)', 'IgnoreCase')
      if ($m.Success) { $cs = $m.Groups[1].Value }
    }
    $enc = [System.Text.Encoding]::UTF8
    if ($cs) { try { $enc = [System.Text.Encoding]::GetEncoding($cs) } catch {} }
    return $enc.GetString($bytes)
  }
  function Get-Meta([string]$html, [string]$key) {
    foreach($pat in @(
      ('<meta[^>]+(?:property|name)\s*=\s*["'']' + $key + '["''][^>]*?content\s*=\s*"([^"]*)"'),
      ('<meta[^>]+(?:property|name)\s*=\s*["'']' + $key + '["''][^>]*?content\s*=\s*''([^'']*)'''),
      ('<meta[^>]+content\s*=\s*"([^"]*)"[^>]*?(?:property|name)\s*=\s*["'']' + $key + '["'']'))) {
      $m = [regex]::Match($html, $pat, 'IgnoreCase')
      if ($m.Success -and $m.Groups[1].Value.Trim().Length -gt 0) { return [System.Net.WebUtility]::HtmlDecode($m.Groups[1].Value).Trim() }
    }
    return ''
  }
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $target = $url
    if ($target -match '^https?://news\.google\.com/.*/articles/([^?/]+)') {
      $id = $matches[1]
      $page = Invoke-WebRequest -UseBasicParsing -Uri ("https://news.google.com/rss/articles/" + $id) -TimeoutSec $timeout -Headers $hdr
      $sg = [regex]::Match([string]$page.Content, 'data-n-a-sg="([^"]+)"').Groups[1].Value
      $ts = [regex]::Match([string]$page.Content, 'data-n-a-ts="([^"]+)"').Groups[1].Value
      if (-not $sg -or -not $ts) { return [pscustomobject]@{ ok=$false; content=''; final_url=''; error='google-sig' } }
      $inner = '["garturlreq",[["X","X",["X","X"],null,null,1,1,"US:en",null,1,null,null,null,null,null,0,1],"X","X",1,[1,1,1],1,1,null,0,0,null,0],"' + $id + '",' + $ts + ',"' + $sg + '"]'
      $freq = '[[["Fbv4je","' + $inner.Replace('"','\"') + '",null,"generic"]]]'
      $body = 'f.req=' + [Uri]::EscapeDataString($freq)
      $r = Invoke-WebRequest -UseBasicParsing -Method Post -Uri 'https://news.google.com/_/DotsSplashUi/data/batchexecute' -Body $body -ContentType 'application/x-www-form-urlencoded;charset=UTF-8' -TimeoutSec $timeout -Headers $hdr
      $raw = [string]$r.Content
      $resolved = ''
      try {
        $line = ($raw -split "`n" | Where-Object { $_ -like '*garturlres*' } | Select-Object -First 1)
        $outer = ConvertFrom-Json $line
        $innerJson = [string]$outer[0][2]
        $arr = ConvertFrom-Json $innerJson
        $resolved = [string]$arr[1]
      } catch {
        $m = [regex]::Match($raw, 'garturlres\\",\\"(https?://.+?)\\"')
        if ($m.Success) { $resolved = [regex]::Unescape([regex]::Unescape($m.Groups[1].Value)) }
      }
      if ($resolved -notmatch '^https?://') { return [pscustomobject]@{ ok=$false; content=''; final_url=''; error='google-decode' } }
      $target = $resolved
    }
    $resp = Invoke-WebRequest -UseBasicParsing -Uri $target -TimeoutSec $timeout -Headers $hdr -MaximumRedirection 5
    $html = Read-Html $resp
    $desc = Get-Meta $html 'og:description'
    if (-not $desc) { $desc = Get-Meta $html 'description' }
    if (-not $desc) { $desc = Get-Meta $html 'twitter:description' }
    return [pscustomobject]@{ ok=[bool]$desc; content=$desc; final_url=$target; error=$(if ($desc) { '' } else { 'no-meta' }) }
  } catch {
    return [pscustomobject]@{ ok=$false; content=''; final_url=''; error=[string]$_.Exception.Message }
  }
}

# 상위 뉴스와 칼럼에 실제 요약과 원문 주소를 채웁니다.
function Enrich-TopItems($items) {
  $targets = @($items | Where-Object { $null -ne $_ -and -not [string]::IsNullOrWhiteSpace([string]$_.url) -and ([string]$_.summary_source -ne 'rss' -or (Is-GoogleNewsUrl ([string]$_.url))) })
  if ($targets.Count -eq 0) { return }
  $reqs = @()
  for($i=0; $i -lt $targets.Count; $i++) { $reqs += [pscustomobject]@{ name=("enrich{0}" -f $i); url=[string]$targets[$i].url; idx=$i } }
  $res = @(Invoke-FetchPool $reqs 4 8 '상위 기사 원문 요약을 가져오는 중입니다.' $EnrichScript)
  $okDesc = 0; $okUrl = 0
  foreach($r in $res) {
    $it = $targets[[int]$r.request.idx]
    if (-not [string]::IsNullOrWhiteSpace($r.final_url) -and -not (Is-GoogleNewsUrl $r.final_url) -and (Is-GoogleNewsUrl ([string]$it.url))) {
      $it.url = $r.final_url; $okUrl++
    }
    if ($r.ok -and [string]$it.summary_source -ne 'rss') {
      $sum = Get-RealSummary ([string]$r.content) ([string]$it.title) ([string]$it.publisher)
      if ($sum) { $it.summary = $sum; $it.summary_source = 'article'; $okDesc++ }
    }
  }
  $errs = @($res | Where-Object { -not $_.ok } | Group-Object -Property error | ForEach-Object { "{0}x{1}" -f $_.Count, $_.Name })
  Log-Line ("Enrich: targets={0}, summaries={1}, resolvedUrls={2}, errors=[{3}]" -f $targets.Count, $okDesc, $okUrl, ($errs -join '; '))
}

# ---------- 날짜별 기록: 어제와 비교해 '새 이슈'를 표시하고, 최근 흐름을 보여주기 위해 저장합니다.
function Save-Archive($news, $columns) {
  try {
    if (-not (Test-Path $ArchiveDir)) { New-Item -ItemType Directory -Path $ArchiveDir -Force | Out-Null }
    $day = (Get-Date).ToString('yyyy-MM-dd')
    $items = @()
    foreach($it in @($news | Select-Object -First 60) + @($columns | Select-Object -First 10)) {
      $items += [pscustomobject]@{ title=[string]$it.title; publisher=[string]$it.publisher; topic=[string]$it.topic; type=[string]$it.type; coverage=[int]$it.coverage_count; url=[string]$it.url }
    }
    $o = [pscustomobject]@{ date=$day; generated_at=[DateTimeOffset]::Now.ToString('o'); total=@($news).Count; items=$items }
    [IO.File]::WriteAllText((Join-Path $ArchiveDir ($day + '.json')), ($o | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($false)))
    # 60일보다 오래된 기록은 지웁니다.
    Get-ChildItem $ArchiveDir -Filter '*.json' | Where-Object { $_.BaseName -lt (Get-Date).AddDays(-60).ToString('yyyy-MM-dd') } | Remove-Item -Force -ErrorAction SilentlyContinue
  } catch { Log-Line ("Archive save fail: {0}" -f $_.Exception.Message) }
}

function Load-Archives([int]$days) {
  $out = @()
  if (-not (Test-Path $ArchiveDir)) { return $out }
  $from = (Get-Date).AddDays(-$days).ToString('yyyy-MM-dd')
  foreach($f in @(Get-ChildItem $ArchiveDir -Filter '*.json' | Where-Object { $_.BaseName -ge $from } | Sort-Object BaseName -Descending)) {
    try { $out += (Get-Content -Raw -Encoding UTF8 $f.FullName | ConvertFrom-Json) } catch {}
  }
  return $out
}

# 상위 기사마다 최근 7일 중 며칠 보도됐는지 세고, 처음 나온 이슈에는 new 표시를 합니다.
function Mark-Continuity($items) {
  $today = (Get-Date).ToString('yyyy-MM-dd')
  $archives = @(Load-Archives 7 | Where-Object { [string]$_.date -ne $today })
  $has = ($archives.Count -gt 0)
  $prev = @()
  foreach($a in $archives) {
    $sets = New-Object 'System.Collections.Generic.List[object]'
    foreach($t in @($a.items)) { $sets.Add((Get-Bigrams (Normalize-Title ([string]$t.title)))) }
    $prev += [pscustomobject]@{ date=[string]$a.date; sets=$sets }
  }
  foreach($it in @($items)) {
    $mine = New-Object 'System.Collections.Generic.List[object]'
    $mine.Add((Get-Bigrams (Normalize-Title ([string]$it.title))))
    foreach($r in @($it.related_articles | Select-Object -First 3)) { if ([string]$r.title -ne [string]$it.title) { $mine.Add((Get-Bigrams (Normalize-Title ([string]$r.title)))) } }
    $seen = @()
    foreach($p in $prev) {
      $found = $false
      foreach($ms in $mine) { foreach($ps in $p.sets) { if ((Title-Similarity $ms $ps) -gt 0) { $found = $true; break } }; if ($found) { break } }
      if ($found) { $seen += $p.date }
    }
    $it | Add-Member -NotePropertyName days_seen -NotePropertyValue $seen.Count -Force
    $it | Add-Member -NotePropertyName seen_dates -NotePropertyValue @($seen) -Force
    $it | Add-Member -NotePropertyName is_new -NotePropertyValue ($has -and $seen.Count -eq 0) -Force
  }
  return $has
}

# 칼럼 순위: (1) 지난 브리핑에서 이미 추천한 글은 뒤로 (2) 하루 지날 때마다 조금씩 감점 (3) 점수·최신순
function Rank-Columns($cols) {
  $today = (Get-Date).ToString('yyyy-MM-dd')
  $shownSets = New-Object 'System.Collections.Generic.List[object]'
  $shownDates = New-Object 'System.Collections.Generic.List[string]'
  foreach($a in @(Load-Archives 7 | Where-Object { [string]$_.date -ne $today })) {
    foreach($t in @(@($a.items) | Where-Object { [string]$_.type -eq 'column' } | Select-Object -First 3)) {
      $shownSets.Add((Get-Bigrams (Normalize-Title ([string]$t.title))))
      $shownDates.Add([string]$a.date)
    }
  }
  $todayDate = ([DateTimeOffset]::Now).Date
  foreach($c in @($cols)) {
    $days = 0
    try { $days = [int][Math]::Max(0, ($todayDate - [DateTimeOffset]::Parse([string]$c.published).ToLocalTime().Date).TotalDays) } catch {}
    $mine = Get-Bigrams (Normalize-Title ([string]$c.title))
    $shownOn = @()
    for($i=0; $i -lt $shownSets.Count; $i++) { if ((Title-Similarity $mine $shownSets[$i]) -gt 0) { $shownOn += $shownDates[$i] } }
    $shownOn = @($shownOn | Select-Object -Unique)
    $c | Add-Member -NotePropertyName age_days -NotePropertyValue $days -Force
    $c | Add-Member -NotePropertyName shown_before -NotePropertyValue ($shownOn.Count -gt 0) -Force
    $c | Add-Member -NotePropertyName shown_dates -NotePropertyValue @($shownOn) -Force
    $c | Add-Member -NotePropertyName rank_score -NotePropertyValue ([Math]::Round(([double]$c.score - 0.4 * $days), 2)) -Force
  }
  return @($cols | Sort-Object -Property @{Expression={ if ($_.shown_before) {1} else {0} }}, @{Expression='rank_score';Descending=$true}, @{Expression='published';Descending=$true})
}

function Get-History {
  $list = @()
  foreach($a in @(Load-Archives 14)) {
    $topics = @{}
    foreach($t in @($a.items)) { $k=[string]$t.topic; if (-not $topics.ContainsKey($k)) { $topics[$k]=0 }; $topics[$k]++ }
    $list += [pscustomobject]@{ date=[string]$a.date; total=[int]$a.total; topics=$topics; items=@($a.items | ForEach-Object { [pscustomobject]@{ title=$_.title; publisher=$_.publisher; topic=$_.topic; coverage=$_.coverage; type=$_.type } }) }
  }
  return [pscustomobject]@{ days=$list }
}

# 서버(오늘교육_종료.exe로 종료)가 꺼지면 수집기도 스스로 멈춥니다.
function Test-ServerAlive {
  if ($ServerPid -le 0) { return $true }
  return ($null -ne (Get-Process -Id $ServerPid -ErrorAction SilentlyContinue))
}

function Stop-IfServerGone {
  if (-not (Test-ServerAlive)) {
    Log-Line ("Server PID={0} stopped - collector exits" -f $ServerPid)
    try { Remove-Item $CollectPidPath -Force -ErrorAction SilentlyContinue } catch {}
    [Environment]::Exit(0)
  }
}

# Start-Job(요청마다 PowerShell 프로세스 생성) 대신 한 프로세스 안의 runspace로 병렬 요청합니다.
function Invoke-FetchPool($requests, [int]$throttle, [int]$timeoutSec, [string]$label, $scriptBlock = $FetchScript) {
  $list = @($requests)
  $out = @()
  if ($list.Count -eq 0) { return $out }
  $pool = [runspacefactory]::CreateRunspacePool(1, $throttle)
  $pool.Open()
  $tasks = @()
  foreach($req in $list) {
    $ps = [powershell]::Create()
    $ps.RunspacePool = $pool
    [void]$ps.AddScript($scriptBlock.ToString()).AddArgument([string]$req.url).AddArgument($timeoutSec)
    $tasks += [pscustomobject]@{ req=$req; ps=$ps; handle=$ps.BeginInvoke(); result=$null; finished=$false }
  }
  $waves = [Math]::Ceiling($list.Count / [double]$throttle)
  $deadline = (Get-Date).AddSeconds($waves * ($timeoutSec + 2) + 5)
  if ($scriptBlock -ne $FetchScript) { $deadline = (Get-Date).AddSeconds($waves * ($timeoutSec * 3 + 2) + 5) }
  $done = 0
  Write-Progress 0 $list.Count ("{0} 0/{1}" -f $label, $list.Count)
  while ($done -lt $tasks.Count) {
    foreach($t in $tasks) {
      if ($t.finished -or -not $t.handle.IsCompleted) { continue }
      $r = $null
      try {
        $res = $t.ps.EndInvoke($t.handle)
        if ($null -ne $res -and $res.Count -gt 0) { $r = $res[$res.Count - 1] }
      } catch {}
      if ($null -eq $r) { $r = [pscustomobject]@{ ok=$false; content=''; error='응답을 받지 못함' } }
      $t.result = $r
      $t.finished = $true
      $done++
      try { $t.ps.Dispose() } catch {}
      Write-Progress $done $list.Count ("{0} {1}/{2}" -f $label, $done, $list.Count)
    }
    if ($done -ge $tasks.Count) { break }
    if ((Get-Date) -gt $deadline) { break }
    Stop-IfServerGone
    Start-Sleep -Milliseconds 150
  }
  $stuck = $false
  foreach($t in $tasks) {
    if (-not $t.finished) {
      $stuck = $true
      try { [void]$t.ps.BeginStop($null, $null) } catch {}
      $t.result = [pscustomobject]@{ ok=$false; content=''; error=('{0}초 안에 응답하지 않아 건너뜀' -f $timeoutSec) }
    }
    $out += [pscustomobject]@{ request=$t.req; ok=[bool]$t.result.ok; content=[string]$t.result.content; error=[string]$t.result.error; final_url=[string]$t.result.final_url; retried=$false }
  }
  if (-not $stuck) { try { $pool.Close(); $pool.Dispose() } catch {} }
  return $out
}

# 1차: 6개씩 동시에, 10초 제한 / 2차: 실패한 것만 3개씩, 15초 제한으로 한 번 더 시도
function Fetch-RequestsParallel($requests) {
  $all = @($requests)
  $first = @(Invoke-FetchPool $all 6 10 '22개 매체를 확인 중입니다.')
  $failed = @($first | Where-Object { -not $_.ok })
  if ($failed.Count -eq 0) { return $first }
  Log-Line ("Retry: {0} failed sources" -f $failed.Count)
  Stop-IfServerGone
  Start-Sleep -Milliseconds 1500
  $retryReqs = @($failed | ForEach-Object { $_.request })
  $second = @(Invoke-FetchPool $retryReqs 3 15 ('응답이 늦은 {0}개 요청을 다시 확인 중입니다.' -f $retryReqs.Count))
  $byName = @{}
  foreach($x in $second) { $byName[[string]$x.request.name] = $x }
  $merged = @()
  foreach($r in $first) {
    $key = [string]$r.request.name
    if (-not $r.ok -and $byName.ContainsKey($key)) {
      $x = $byName[$key]
      if ($x.ok) {
        $merged += [pscustomobject]@{ request=$r.request; ok=$true; content=[string]$x.content; error=''; retried=$true }
      } else {
        $merged += [pscustomobject]@{ request=$r.request; ok=$false; content=''; error=('재시도 실패: ' + [string]$x.error); retried=$true }
      }
    } else {
      $merged += $r
    }
  }
  return $merged
}

function Merge-Clusters($clusters) {
  $list = New-Object 'System.Collections.Generic.List[object]'
  foreach($c in $clusters) { $list.Add($c) }
  $changed = $true
  $guard = 0
  while ($changed -and $guard -lt 50) {
    $changed = $false; $guard++
    for($i=0; $i -lt $list.Count -and -not $changed; $i++) {
      $a = $list[$i]
      if (@($a.items).Count -lt 2) { continue }
      for($j=0; $j -lt $list.Count; $j++) {
        if ($j -eq $i) { continue }
        $b = $list[$j]
        if ($a.rep.type -ne $b.rep.type) { continue }
        $hits = 0
        foreach($sa in $a.sets) { foreach($sb in $b.sets) { if ((Title-Similarity $sa $sb) -gt 0) { $hits++; if ($hits -ge 2) { break } } }; if ($hits -ge 2) { break } }
        if ($hits -lt 2) { continue }
        $keep = $a; $drop = $b
        if ([double]$b.rep.score -gt [double]$a.rep.score) { $keep = $b; $drop = $a }
        $oldPubs = [Math]::Max(@($keep.rep.publishers).Count, @($drop.rep.publishers).Count)
        foreach($st in $drop.sets) { $keep.sets.Add($st) }
        $keep.items = @($keep.items) + @($drop.items)
        $pubs = @($keep.items | ForEach-Object { $_.publisher } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
        $keep.rep.coverage_count = $pubs.Count
        $keep.rep.publishers = $pubs
        $extra = [Math]::Max(0, $pubs.Count - $oldPubs)
        $keep.rep.score = [Math]::Round(([double]$keep.rep.score + [Math]::Min(2.0, 0.85 * $extra)), 2)
        [void]$list.Remove($drop)
        $changed = $true
        break
      }
    }
  }
  return $list.ToArray()
}

function Cluster-Items($inputItems) {
  $sorted = @($inputItems | Sort-Object -Property @{Expression='score';Descending=$true}, @{Expression='published';Descending=$true})
  $allSets = New-Object 'System.Collections.Generic.List[object]'
  foreach($it in $sorted) { $allSets.Add((Get-Bigrams (Normalize-Title ([string]$it.title)))) }
  Build-Idf $allSets
  $clusters = @()
  for($k=0; $k -lt $sorted.Count; $k++) {
    $it = $sorted[$k]
    $norm = Normalize-Title ([string]$it.title)
    $set = $allSets[$k]
    $bestIndex = -1
    $bestSim = 0.0
    for($i=0; $i -lt $clusters.Count; $i++) {
      $c = $clusters[$i]
      if ($c.rep.type -ne $it.type) { continue }
      foreach($cs in $c.sets) {
        $sim = Title-Similarity $set $cs
        if ($sim -gt $bestSim) { $bestSim=$sim; $bestIndex=$i }
      }
    }
    if ($bestIndex -ge 0 -and $bestSim -gt 0) {
      $c = $clusters[$bestIndex]
      $c.sets.Add($set)
      $newItems = @($c.items) + @($it)
      $c.items = $newItems
      $pubs = @($newItems | ForEach-Object { $_.publisher } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
      $c.rep.coverage_count = $pubs.Count
      $c.rep.publishers = $pubs
      $bonus = [Math]::Min(3.2, [double](($pubs.Count - 1) * 0.85))
      $c.rep.score = [Math]::Round(([double]$c.rep.score + $bonus),2)
      $clusters[$bestIndex] = $c
    } else {
      $sets = New-Object 'System.Collections.Generic.List[object]'
      $sets.Add($set)
      $clusters += [pscustomobject]@{ norm=$norm; rep=$it; items=@($it); sets=$sets }
    }
  }
  $clusters = @(Merge-Clusters $clusters)
  $out = @()
  foreach($c in $clusters) {
    $rep = $c.rep
    $related = @($c.items | Sort-Object -Property published -Descending)
    $seen = @{}
    $relatedArticles = @()
    foreach($r in $related) {
      $pubKey = [string]$r.publisher
      if ([string]::IsNullOrWhiteSpace($pubKey)) { $pubKey = [string]$r.url }
      if ($seen.ContainsKey($pubKey)) { continue }
      $seen[$pubKey] = $true
      $relatedArticles += [pscustomobject]@{
        publisher=[string]$r.publisher
        title=[string]$r.title
        url=[string]$r.url
        published=[string]$r.published
        emphasis=''
      }
      if ($relatedArticles.Count -ge 6) { break }
    }
    $rep | Add-Member -NotePropertyName related_articles -NotePropertyValue $relatedArticles -Force
    # 같은 사안 묶음 안에서 언론사 요약이 있는 기사를 찾아 대표 요약으로 씁니다.
    $sum = Get-RealSummary ([string]$rep.raw_summary) ([string]$rep.title) ([string]$rep.publisher)
    if ([string]::IsNullOrWhiteSpace($sum)) {
      foreach($r in $related) {
        $sum = Get-RealSummary ([string]$r.raw_summary) ([string]$r.title) ([string]$r.publisher)
        if (-not [string]::IsNullOrWhiteSpace($sum)) { break }
      }
    }
    $rep | Add-Member -NotePropertyName summary -NotePropertyValue $sum -Force
    $rep | Add-Member -NotePropertyName summary_source -NotePropertyValue $(if ($sum) { 'rss' } else { '' }) -Force
    $rep | Add-Member -NotePropertyName reason -NotePropertyValue (Reason-For $rep $related) -Force
    $rep | Add-Member -NotePropertyName comparison_note -NotePropertyValue '' -Force
    $out += $rep
  }
  return $out
}

function Build-Briefing {
  Log-Line 'Build-Briefing start (v6.3)'
  $all = @()
  $status = @()
  $requests = @()

  foreach($f in $Feeds) {
    $requests += [pscustomobject]@{ mode='rss'; name=[string]$f.name; url=[string]$f.url; feed=$f; kind=[string]$f.type; publisher=[string]$f.publisher }
  }

  $queries = @(
    @{ q='교육 OR 교육부 OR 학교 OR 교사 OR 수능 OR 대입 OR 대학 when:5d'; kind='news'; name='전체 교육뉴스 보조 검색'; publisher='' },
    @{ q='교육 칼럼 OR 교육 사설 OR 교육 기고 OR 교육 시론 OR 기자수첩 when:7d'; kind='column'; name='전체 교육칼럼 보조 검색'; publisher='' }
  )
  foreach($m in $MediaSearchSources) {
    $domain=[string]$m.domain; $publisher=[string]$m.publisher; $newsTerms=[string]$m.news
    if (-not [string]::IsNullOrWhiteSpace($domain) -and -not [string]::IsNullOrWhiteSpace($newsTerms)) {
      $queries += @{ q=("site:{0} {1}" -f $domain,$newsTerms); kind='news'; name=("{0} 전용 교육뉴스" -f $publisher); publisher=$publisher }
    }
    $columnTerms=[string]$m.column
    if (-not [string]::IsNullOrWhiteSpace($domain) -and -not [string]::IsNullOrWhiteSpace($columnTerms)) {
      $queries += @{ q=("site:{0} {1}" -f $domain,$columnTerms); kind='column'; name=("{0} 전용 교육칼럼" -f $publisher); publisher=$publisher }
    }
  }
  foreach($q in $queries) {
    $enc=[Uri]::EscapeDataString([string]$q.q)
    $url="https://news.google.com/rss/search?q=$enc&hl=ko&gl=KR&ceid=KR:ko"
    $requests += [pscustomobject]@{ mode='google'; name=[string]$q.name; url=$url; feed=$null; kind=[string]$q.kind; publisher=[string]$q.publisher }
  }

  Write-Progress 0 $requests.Count '수집을 시작합니다.'
  $raw = @(Fetch-RequestsParallel $requests)
  foreach($rr in $raw) {
    $req=$rr.request
    if (-not $rr.ok) {
      $status += [pscustomobject]@{ name=[string]$req.name; ok=$false; count=0; error=[string]$rr.error }
      Log-Line ("Source FAIL: {0} / {1}" -f [string]$req.name,[string]$rr.error)
      continue
    }
    try {
      if ($req.mode -eq 'rss') { $got=@(Parse-RssContent ([string]$rr.content) $req.feed) }
      else { $got=@(Parse-GoogleNewsContent ([string]$rr.content) ([string]$req.kind) ([string]$req.publisher)) }
      if ($got.Count -gt 0) { $all += $got }
      $status += [pscustomobject]@{ name=[string]$req.name; ok=$true; count=$got.Count; error=''; retried=[bool]$rr.retried }
      $okLabel = if ($rr.retried) { 'Source OK (재시도)' } else { 'Source OK' }
      Log-Line ("{0}: {1} / {2}" -f $okLabel,[string]$req.name,$got.Count)
    } catch {
      $status += [pscustomobject]@{ name=[string]$req.name; ok=$false; count=0; error=$_.Exception.Message }
      Log-Line ("Parse FAIL: {0} / {1}" -f [string]$req.name,$_.Exception.Message)
    }
  }

  Write-Progress $requests.Count $requests.Count '기사 후보를 정리하고 있습니다.'

  # 달력 날짜 기준으로 정확히 필터링합니다.
  $window = Get-DateWindowInfo
  $newsPool = @($all | Where-Object { $_.type -eq 'news' -and (Is-InDateWindow ([string]$_.published) $window.NewsStart $window.End) })
  # 칼럼은 뉴스보다 수명이 길어 최근 7일(오늘 포함)을 모두 후보로 봅니다.
  $columnStart = ([DateTimeOffset]::Now).Date.AddDays(-6)
  $columnPool = @($all | Where-Object { $_.type -eq 'column' -and (Is-InDateWindow ([string]$_.published) $columnStart $window.End) })
  $columnExpanded = $false
  $windowed = @($newsPool) + @($columnPool)

  $dedup = @()
  if ($windowed.Count -gt 0) {
    $groups = $windowed | Group-Object -Property @{ Expression = { (Normalize-Title ([string]$_.title)) + '|' + ([string]$_.publisher) } }
    foreach($g in $groups) {
      $best = $g.Group | Sort-Object -Property @{Expression={ if (Is-GoogleNewsUrl ([string]$_.url)) {0} else {1} };Descending=$true}, @{Expression='score';Descending=$true} | Select-Object -First 1
      if ($null -ne $best) { $dedup += $best }
    }
  }
  $clustered=@(); if($dedup.Count -gt 0){$clustered=@(Cluster-Items $dedup)}
  $newsSorted=@($clustered | Where-Object {$_.type -eq 'news'} | Sort-Object -Property @{Expression='score';Descending=$true}, @{Expression='published';Descending=$true})
  $pubCount=@{}
  $news=@()
  foreach($it in $newsSorted) {
    $p=[string]$it.publisher
    $cap = if ($PublisherCaps.ContainsKey($p)) { [int]$PublisherCaps[$p] } else { $DefaultPublisherCap }
    if (-not $pubCount.ContainsKey($p)) { $pubCount[$p]=0 }
    if ($pubCount[$p] -lt $cap) { $news += $it; $pubCount[$p]++ }
  }
  $columnsRaw=@($clustered | Where-Object {$_.type -eq 'column'})
  $columns=@()
  try { $columns = @(Rank-Columns $columnsRaw) } catch {
    Log-Line ("Rank-Columns FAIL: {0}" -f $_.Exception.Message)
    $columns=@($columnsRaw | Sort-Object -Property @{Expression='score';Descending=$true}, @{Expression='published';Descending=$true})
  }
  try { Enrich-TopItems (@($news | Select-Object -First 12) + @($columns | Select-Object -First 5)) } catch { Log-Line ("Enrich FAIL: {0}" -f $_.Exception.Message) }
  $hasHistory = $false
  try { $hasHistory = Mark-Continuity (@($news | Select-Object -First 40) + @($columns)) } catch { Log-Line ("Continuity FAIL: {0}" -f $_.Exception.Message) }
  if (@($news).Count -gt 0) { Save-Archive $news $columns } else { Log-Line 'Archive skipped: no news collected' }
  $columnStartUsed = $columnStart
  $brief=[pscustomobject]@{
    generated_at=[DateTimeOffset]::Now.ToString('o'); news=$news; columns=$columns; status=$status
    source_count=@($status | Where-Object {$_.ok}).Count; candidate_count=$dedup.Count
    added_sources=$PreferredPublishers; publisher_search_count=$MediaSearchSources.Count; app_version='6.3'
    news_window_rule=[string]$window.Rule
    news_window_start=$window.NewsStart.ToString('yyyy-MM-dd 00:00')
    news_window_end=$window.End.ToString('yyyy-MM-dd HH:mm')
    column_window_start=$columnStartUsed.ToString('yyyy-MM-dd 00:00')
    column_expanded=$false
    column_days=7
    has_history=[bool]$hasHistory
    preferred_publishers=$PreferredPublishers
  }
  Stop-IfServerGone
  # 공개 페이지용(TODAYEDU_PUBLIC=1)에서는 언론사 요약문을 싣지 않고 제목·링크만 남깁니다.
  $isPublic = ([string]$env:TODAYEDU_PUBLIC -eq '1')
  if ($isPublic) {
    foreach($it in @($news) + @($columns)) {
      if ($null -eq $it) { continue }
      $it.summary = ''; $it.raw_summary = ''
      if ($it.PSObject.Properties['summary_source']) { $it.summary_source = '' }
    }
  }
  $brief | Add-Member -NotePropertyName public -NotePropertyValue $isPublic -Force
  $json=$brief | ConvertTo-Json -Depth 10
  [IO.File]::WriteAllText($CachePath,$json,(New-Object System.Text.UTF8Encoding($false)))
  Write-Progress $requests.Count $requests.Count '업데이트가 완료되었습니다.'
  Log-Line ("Build-Briefing done: candidates={0}, news={1} (before cap {2}), genuineColumns={3}" -f $dedup.Count,$news.Count,$newsSorted.Count,$columns.Count)
  return $brief
}

function Is-CollectorRunning {
  try {
    if (-not (Test-Path $CollectPidPath)) { return $false }
    $cpid=[int](Get-Content -Raw $CollectPidPath)
    $p=Get-Process -Id $cpid -ErrorAction SilentlyContinue
    if ($null -eq $p) { Remove-Item $CollectPidPath -Force -ErrorAction SilentlyContinue; return $false }
    return $true
  } catch { return $false }
}

function Start-Collector {
  if (Is-CollectorRunning) { return }
  try {
    $self=$MyInvocation.ScriptName
    if ([string]::IsNullOrWhiteSpace($self)) { $self=$PSCommandPath }
    $argLine="-NoProfile -ExecutionPolicy Bypass -File `"$self`" -CollectOnly -ServerPid $PID"
    $p=Start-Process -FilePath 'powershell.exe' -ArgumentList $argLine -WindowStyle Hidden -PassThru
    [IO.File]::WriteAllText($CollectPidPath,[string]$p.Id,[System.Text.Encoding]::ASCII)
    Log-Line ("Collector started PID={0}" -f $p.Id)
  } catch { Log-Line ("Collector start failed: {0}" -f $_.Exception.Message) }
}

function Read-ProgressObj {
  try {
    if (Test-Path $ProgressPath) { return (Get-Content -Raw -Encoding UTF8 $ProgressPath | ConvertFrom-Json) }
  } catch {}
  return [pscustomobject]@{done=0;total=0;message='수집 준비 중';updated_at=[DateTimeOffset]::Now.ToString('o')}
}

function Get-Briefing([bool]$force) {
  if ($force) { Start-Collector }
  $refreshing=Is-CollectorRunning
  if (Test-Path $CachePath) {
    try {
      $obj=Get-Content -Raw -Encoding UTF8 $CachePath | ConvertFrom-Json
      $fi=Get-Item $CachePath
      if (-not $force -and ((Get-Date)-$fi.LastWriteTime).TotalMinutes -ge 15 -and -not $refreshing) { Start-Collector; $refreshing=$true }
      $obj | Add-Member -NotePropertyName refreshing -NotePropertyValue $refreshing -Force
      $obj | Add-Member -NotePropertyName loading -NotePropertyValue $false -Force
      $obj | Add-Member -NotePropertyName progress -NotePropertyValue (Read-ProgressObj) -Force
      return $obj
    } catch { Log-Line ("Cache read fail: {0}" -f $_.Exception.Message) }
  }
  if (-not $refreshing) { Start-Collector; $refreshing=$true }
  return [pscustomobject]@{
    generated_at=[DateTimeOffset]::Now.ToString('o'); news=@(); columns=@(); status=@(); source_count=0; candidate_count=0
    added_sources=$PreferredPublishers; publisher_search_count=$MediaSearchSources.Count; app_version='6.3'
    loading=$true; refreshing=$refreshing; progress=(Read-ProgressObj)
  }
}

function Send-Response($stream, [int]$code, [string]$contentType, [byte[]]$body) {
  $statusText = 'OK'
  if ($code -eq 404) { $statusText = 'Not Found' }
  elseif ($code -ge 400) { $statusText = 'Error' }
  $header = "HTTP/1.1 $code $statusText`r`nContent-Type: $contentType`r`nContent-Length: $($body.Length)`r`nCache-Control: no-store`r`nConnection: close`r`n`r`n"
  $hb = [System.Text.Encoding]::ASCII.GetBytes($header)
  $stream.Write($hb,0,$hb.Length)
  $stream.Write($body,0,$body.Length)
  $stream.Flush()
}

if ($CollectOnly) {
  try {
    [IO.File]::WriteAllText($CollectPidPath,[string]$PID,[System.Text.Encoding]::ASCII)
    Log-Line ("Collector mode PID={0}" -f $PID)
    $b = Build-Briefing
    if ($env:GITHUB_ACTIONS -eq 'true' -and @($b.news).Count -eq 0) { Write-Host 'No news collected - keep previous page.'; exit 1 }
    # 정적 페이지(GitHub Pages)에서 쓰도록 최근 기록도 파일로 남깁니다.
    [IO.File]::WriteAllText((Join-Path $BaseDir 'history.json'), ((Get-History) | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
  } catch {
    Log-Line ("COLLECTOR ERROR: {0}" -f ($_ | Out-String))
    if ($env:GITHUB_ACTIONS -eq 'true') { Write-Host ($_ | Out-String); exit 1 }
  }
  finally { try { Remove-Item $CollectPidPath -Force -ErrorAction SilentlyContinue } catch {} }
  exit
}

if (-not (Test-Path $AppPath)) {
  Log-Line 'app.html not found.'
  exit 1
}

try { Remove-Item $LogPath -Force -ErrorAction SilentlyContinue } catch {}
Log-Line 'Server start (background mode)'
try { [IO.File]::WriteAllText($PidPath, [string]$PID, [System.Text.Encoding]::ASCII) } catch {}

$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback,$Port)
try {
  $listener.Start()
  Log-Line ("Listening on http://127.0.0.1:{0} PID={1}" -f $Port,$PID)
} catch {
  Log-Line ("Cannot open port {0}: {1}" -f $Port,$_.Exception.Message)
  try { Remove-Item $PidPath -Force -ErrorAction SilentlyContinue } catch {}
  exit 1
}

Start-Collector

while ($true) {
  $client = $listener.AcceptTcpClient()
  try {
    $stream = $client.GetStream()
    $reader = New-Object System.IO.StreamReader($stream,[System.Text.Encoding]::ASCII,$false,1024,$true)
    $requestLine = $reader.ReadLine()
    while (($line=$reader.ReadLine()) -ne $null -and $line -ne '') {}
    if ([string]::IsNullOrWhiteSpace($requestLine)) { $client.Close(); continue }
    $parts = $requestLine.Split(' ')
    if ($parts.Count -lt 2) { throw 'Invalid HTTP request line' }
    $rawTarget = [string]$parts[1]
    $route = ($rawTarget -split '\?',2)[0]
    Log-Line ("Request: {0}" -f $route)

    if ($route -eq '/api/history') {
      try {
        $json = (Get-History) | ConvertTo-Json -Depth 6
        Send-Response $stream 200 'application/json; charset=utf-8' (To-Utf8Bytes $json)
      } catch {
        Send-Response $stream 500 'application/json; charset=utf-8' (To-Utf8Bytes '{"days":[]}')
      }
    } elseif ($route -eq '/api/brief' -or $route -eq '/api/refresh') {
      try {
        $force = ($route -eq '/api/refresh')
        $obj = Get-Briefing $force
        $json = $obj | ConvertTo-Json -Depth 10
        Send-Response $stream 200 'application/json; charset=utf-8' (To-Utf8Bytes $json)
      } catch {
        $detail = $_ | Out-String
        Log-Line ("API ERROR: {0}" -f $detail)
        $payload = [pscustomobject]@{
          error=$_.Exception.Message
          generated_at=[DateTimeOffset]::Now.ToString('o')
          hint='server.log 파일을 확인해 주세요.'
        } | ConvertTo-Json -Depth 4
        Send-Response $stream 500 'application/json; charset=utf-8' (To-Utf8Bytes $payload)
      }
    } elseif ($route -eq '/' -or $route -eq '/app.html') {
      $bytes = [IO.File]::ReadAllBytes($AppPath)
      Send-Response $stream 200 'text/html; charset=utf-8' $bytes
    } else {
      Send-Response $stream 404 'text/plain; charset=utf-8' (To-Utf8Bytes 'Not found')
    }
  } catch {
    Log-Line ("REQUEST ERROR: {0}" -f ($_ | Out-String))
  } finally {
    try { $client.Close() } catch {}
  }
}
