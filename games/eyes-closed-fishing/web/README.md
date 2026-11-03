# 《눈 감고 낚시》 웹 버전

`index.html`을 브라우저(모바일 포함)로 열면 바로 플레이할 수 있습니다. 설치나 빌드가 필요 없습니다.

- `game.html` — 원본 소스 (Artifact 페이지 형식)
- `index.html` — `./build.sh`로 생성되는 단독 실행 파일

## 사운드 조달 방식

외부 효과음 파일을 쓰지 않고 **모든 소리를 Web Audio API로 실시간 합성**합니다.
라이선스·크레딧 의무가 없고, 기획서의 "장력에 따라 음높이가 연속 상승하는 마찰음"을 정확히 구현할 수 있습니다.
음성 안내는 브라우저 내장 TTS(Web Speech API, ko-KR)를 사용합니다.

| 기획서 에셋 ID | 구현 |
| --- | --- |
| `amb_water` / `amb_nature` | 갈색 소음 + 저역 필터 + 느린 LFO, 랜덤 새소리 |
| `sfx_cast_swing` / `sfx_cast_splash` | 대역 필터 스윕 휘익 + 줄 풀리는 클릭 + 퐁당 |
| `sfx_bubble` / `sfx_nibble` | 상승 사인 스윕(뽀글) / 짧은 하강 톡 |
| `sfx_decoy_frog` / `sfx_decoy_leaf` | 톱니파 펄스 개구리 / 고역 틱 |
| `sfx_bite` / `sfx_bite_gold` | 노이즈 물튀김 + 저음 쿵 + 배경음 덕킹 / 종소리 배음 추가 |
| `sfx_reel` | 장력에 따라 속도·음색이 변하는 래칫 클릭 + 저음 험 |
| `sfx_line_strain` | 톱니+사각파 → 대역 필터, 장력 50→100에서 300→약 1500Hz 연속 상승, 비브라토 |
| `sfx_fish_run` / 거리 신호 | 스테레오 패닝 물튀김, 가까울수록 커짐 |
| `sfx_line_snap` / `sfx_hook_free` | 고역 크랙 + 삼각파 팅 / 하강 툭 |
| `sfx_catch_splash` / `sfx_catch_jingle` / `sfx_record` | 큰 물튀김 / 도미솔도 아르페지오 / 고음 반짝임 |

어종 파라미터는 기획서 5.2의 초기 튜닝값을 그대로 사용합니다 (`game.html`의 `FISH` 배열).

## 조작

- 짧게 터치: 던지기, 챔질 / 길게 누르기: 릴 감기 / 손 떼기: 장력 해제
- 컴퓨터: 스페이스바, `M` 키로 기록·설정
- 두 손가락 1.5초 길게 누르기 또는 우측 상단 버튼: 기록·설정
