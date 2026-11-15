# AI 생성 목표 예시 씬 — Meadow (하늘·잔디 전환)

> **이 폴더의 모든 파일은 AI(Claude)가 작성했습니다.**
> 과제 제출물이 아니며, 평가 대상인 "직접 작성한 셰이더"에 포함되지 않습니다.

## 이 폴더가 무엇인가

- 과제용 셰이더 3개(`Assets/02. MyShaders/`)를 만들기 전에, "이런 연출을 목표로 한다"는 것을 보여 주려고 AI에게 만들게 한 **고퀄리티 목표 예시**입니다.
- 과제 제출물은 이 예시를 보고 핵심만 추려 **직접 간단하게 다시 작성한** 버전입니다.
- 작업지시서(`ASSIGNMENT.md`)의 폴더·이름 규칙과 구분하려고 별도 폴더(`03. AIReference_Meadow`)와 별도 셰이더 경로(`AIReference/...`)를 씁니다.

## 예시와 제출물의 대응

| AI 예시 (이 폴더) | 직접 작성한 간단 버전 (제출물) | 간단 버전에서 남긴 것 |
| --- | --- | --- |
| `AIReference/MeadowSky` — 낮/밤 전환, 구름, 별, 은하수, 달 | `MyShaders/GradientSky` | 방향으로 그라데이션 계산, 태양 원반 |
| `AIReference/MeadowGrass`, `MeadowGround` — 인스턴싱 잔디, 돌풍, 조명 | `MyShaders/WindGrass` | 풀잎 모양 자르기, 높이에 따른 바람 흔들림 |
| `AIReference/PetalTransition`, `DriftPetal` — 꽃잎이 화면을 덮었다가 흩어지는 전환 | `MyShaders/PetalWipe` | 칸마다 꽃잎이 자라 화면을 덮는 전환 |
| `AIReference/Meteor` — 유성 | (없음) | |

## 연출 내용

맑은 낮 하늘과 넓은 잔디 들판 → 빛나는 흰 꽃잎이 화면을 덮는 전환 → 별이 빛나고 가끔 유성이 떨어지는 밤, 바람에 잔잔히 흔들리는 잔디.

## 씬 만드는 방법

씬과 머티리얼은 저장소에 들어 있지 않고, 에디터 메뉴로 생성합니다.

1. 유니티 메뉴 `Tools > AI Reference Meadow > Build Demo Scene`을 실행합니다.
2. `Scenes/AIReference_Meadow.unity`와 머티리얼, 포스트 프로세싱 프로파일이 이 폴더 안에 만들어집니다.
3. Play를 누르면 낮 → 꽃잎 전환 → 밤 연출이 재생됩니다.

`Tools > AI Reference Meadow > Check Shader Errors`로 셰이더 6개의 컴파일 오류 여부를 확인할 수 있습니다.

## 폴더 구성

| 경로 | 내용 |
| --- | --- |
| `Common/MeadowCommon.hlsl` | 공용 함수(해시, 노이즈 등) |
| `MeadowSky/`, `MeadowGrass/`, `PetalTransition/`, `Meteor/`, `DriftPetal/` | 셰이더 6개 |
| `Scripts/` | 연출 진행, 잔디 그리기, 유성 생성 스크립트 |
| `Scripts/Editor/MeadowSceneBuilder.cs` | 씬 생성 메뉴 |
