# GW1 (ChassisuC) 핀맵 — RC40 Pin Assignment

> `RC40_Pinmap.xlsx` 시트 `GW1`(= ChassisuC) 전사. **Pin Assignment(MASAR) 가 채워진 핀**만 수록
> (= 실제 사용 핀, Use=ON). 디버깅 참조용. MASAR 매핑은 학습된 RC40 규칙으로 도출.
>
> 핀 명명: 입력 `DevInp_<pin>_D`, 출력 `DevOutp_<pin>[HS|LS]_D`. 엑셀 Type→MASAR 클래스 매핑 적용.

---

## 1. 입력 (IN) — `DevInp_<pin>_D`

| 핀 | Type | Pin Assignment | Connect to | MASAR 매핑 |
| --- | --- | --- | --- | --- |
| K21 | DigitalSignal | `ENG_INHBIT_1` | — | Dig_as (HwInpDig) — ※ Inhibit 핀 |
| K22 | DigitalSignal | `ENG_INHBIT_2` | — | Dig_as (HwInpDig) — ※ Inhibit 핀 |
| K31 | AnalogSignal | `MODE_MN` | — | AnU_as (HwInpAnU) |
| K34 | AnalogSignal | `MODE_RM` | — | AnU_as (HwInpAnU) |
| K38 | DigitalSignal | `APP_SIG1` | — | Dig_as (HwInpDig) |
| K39 | DigitalSignal | `APP_SIG2` | — | Dig_as (HwInpDig) |
| K24 | KeyOn | `KEYON` | CHSS-KEY-M-#1 | (특수) KeyOn 입력 |

> Inhibit 핀(K21/K22)은 MASAR 관례상 특수명 `DevInp_Inhb1_D`/`Inhb2` 사용 가능.

---

## 2. 출력 (OUT) — `DevOutp_<pin>[HS|LS]_D`

| 핀 | Type | HS/LS | Pin Assignment | MASAR 매핑 |
| --- | --- | --- | --- | --- |
| A03 | PWMSignal | LS | `PWR_LED_FAULT` | PropSig_as (HwOutpPropSig) |
| A05 | PWMSignal | LS | `PWR_LED_MN` | PropPwr_as (HwOutpPropPwr) |
| A19 | PWMSignal | LS | `PWR_LED_RM` | PropPwr_as (HwOutpPropPwr) |
| A20 | PWMSignal | LS | `PWR_LED_CONN` | PropPwr_as (HwOutpPropPwr) |
| A31 | PWMSignal | HS | `PWR_LED` | PropPwr_as (HwOutpPropPwr) |
| A33 | PWMSignal | HS | `IGN_COM` | PropPwr_as (HwOutpPropPwr) |
| A48 | PWMSignal | HS | `PWR_GRLY_HS` | PropPwr_as (HwOutpPropPwr) |
| K07 | PWMSignal | — | `OUT_PWR_PDU1` | PropPwr_as (HwOutpPropPwr) |
| K12 | PWMSignal | — | `IGN_GA` | PropSig_as (HwOutpPropSig) |
| K14 | PWMSignal | — | `IGN_CRR` | PropPwr_as (HwOutpPropPwr) |
| K15 | PWMSignal | — | `IGN_RT` | PropPwr_as (HwOutpPropPwr) |
| K16 | PWMSignal | — | `IGN_BRK` | PropPwr_as (HwOutpPropPwr) |
| K17 | PWMSignal | — | `WU_SU` | PropSig_as (HwOutpPropSig) — 조향 Wakeup |
| K80 | PWMSignal | LS | `APP_DA2_PWM` | PropSig_as (HwOutpPropSig) |
| K81 | PWMSignal | LS | `APP_DA1_PWM` | PropSig_as (HwOutpPropSig) |
| K84 | DigitalSignal | LS | `GL_SHFT_SEL` | DigSig_as (HwOutpDigSig) — 기어 실렉터 |
| K85 | DigitalSignal | LS | `GL_SHFT_DN` | DigSig_as (HwOutpDigSig) — 기어 Down |
| K86 | DigitalSignal | LS | `GL_SHFT_UP` | DigSig_as (HwOutpDigSig) — 기어 Up |
| K87 | DigitalSignal | LS | `GL_SHFT_PK` | DigSig_as (HwOutpDigSig) — 기어 Park |

---

## 3. 전원 / 그라운드 / 센서 공급

| 핀 | Type | Pin Assignment |
| --- | --- | --- |
| K01 | Power Supply | `PWR_CHSS2` |
| K03 | Power Supply | `PWR_CHSS1` |
| K05 | Power Supply | `PWR_GS` (기어 실렉터 전원) |
| K02 | Ground | `GND_CHSS2` |
| K04 | Ground | `GND_CHSS1` |
| K06 | Ground | `GND_GS` |
| K71 | SensorSupply | `PWR_AP_VCC2` (가속페달 센서 전원) |
| K72 | SensorSupply | `PWR_AP_VCC1` |
| K18 | SensorGND | `GND_AP_GND2` |
| K19 | SensorGND | `GND_AP_GND1` |

---

## 4. CAN 버스

| 핀 | 버스 | Pin Assignment |
| --- | --- | --- |
| K89 | CAN2 | `DCAN_H` |
| K67 | CAN2 | `DCAN_L` |
| K91 | CAN4 | `CCAN_H` |
| K69 | CAN4 | `CCAN_L` |

---

## 5. 기능 그룹 요약 (디버깅용)

| 그룹 | 핀 | 신호 |
| --- | --- | --- |
| **LED (상태표시)** | A03,A05,A19,A20,A31 | FAULT/MN/RM/CONN/LED |
| **IGN (시동/점화)** | A33,K12,K14,K15,K16 | COM/GA/CRR/RT/BRK |
| **기어 실렉터(GL)** | K84~K87 | SEL/DN/UP/PK |
| **가속(APP)** | K38,K39(in), K80,K81(out) | SIG1/2, DA1/DA2 PWM |
| **모드 입력** | K31,K34 | MODE_MN / MODE_RM |
| **엔진 Inhibit** | K21,K22 | ENG_INHBIT_1/2 |
| **조향 Wakeup** | K17 | WU_SU |
| **전원 릴레이** | A48,K07 | PWR_GRLY_HS, OUT_PWR_PDU1 |
| **키온** | K24 | KEYON |
| **CAN** | K89/K67(DCAN), K91/K69(CCAN) | |

> 통계: Pin Assignment 채워진 핀 — 입력 7, 출력 19(신호) + 전원/GND/센서 10 + CAN 4.
> 전체 핀 정의 163행 중 미사용(Use=OFF, Pin Assignment 공란)은 생략.
