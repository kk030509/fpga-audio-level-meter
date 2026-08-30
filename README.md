# FPGA Audio Level Meter

Basys3 FPGA에서 8 kHz PCM 음원을 재생하면서 Low / Mid / High 3개 주파수 대역의 오디오 레벨을 분석하고,  
3개의 MAX7219 8×8 Dot Matrix에 실시간으로 시각화하는 프로젝트입니다.

PCM5102A DAC를 이용한 I2S 오디오 출력과 FPGA 내부 DSP 처리를 함께 구현했습니다.

---

## Tech Stack

- **Board:** Digilent Basys3
- **FPGA:** Xilinx Artix-7 (XC7A35T)
- **Tool:** Vivado
- **Language:** Verilog HDL
- **System Clock:** 100 MHz
- **Audio Source:** 8 kHz / Signed 8-bit PCM
- **Audio Output:** PCM5102A DAC
- **Display:** MAX7219 8×8 Dot Matrix × 3
- **Interface:** I2S / SPI-like MAX7219 Serial Interface
- **Memory:** FPGA Block RAM

---

## Key Features

- BRAM 기반 8-bit PCM 음원 저장 및 반복 재생
- Q15 1차 IIR Filter 기반 Low / Mid / High 3-Band 주파수 분리
- 512-Sample Absolute Average 기반 대역별 Energy 계산
- 대역별 Fixed Threshold 기반 0~8 단계 Level Mapping
- MAX7219 3-Chain 기반 실시간 Audio Level 시각화
- PCM5102A DAC를 이용한 Standard I2S Audio 출력
- Valid 신호 기반 DSP / Display 데이터 흐름 제어

---

## System Architecture

```text
audio_8k_s8.mem
        │
        ▼
┌──────────────────────┐
│ Audio Sample Reader  │
│      + Audio ROM     │
└──────────┬───────────┘
           │ 8-bit PCM
           │
           ├───────────────────────────┐
           │                           │
           ▼                           ▼
  16-bit Sign Extension        16-bit PCM Scale
           │                           │
           ▼                           ▼
┌──────────────────────┐      ┌──────────────────┐
│ Audio Band Splitter  │      │ I2S Transmitter  │
│   Q15 IIR Filters    │      │ Standard I2S     │
└──────────┬───────────┘      └────────┬─────────┘
           │                           │
     Low / Mid / High                  ▼
           │                     PCM5102A DAC
           ▼
┌──────────────────────┐
│  Band Energy Meter   │
│  512-Sample Average  │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│  Band Level Mapper   │
│   Fixed Threshold    │
│      Level 0~8       │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ Matrix Level History │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ MAX7219 Display Ctrl │
│  + Display Engine    │
│  + Chain Driver      │
└──────────┬───────────┘
           │
           ▼
   8×8 Dot Matrix × 3
```

---

## Module Description

### `audio_rom.v`

- `.mem` 파일에 저장된 8-bit PCM 데이터를 FPGA 내부 ROM으로 구성
- `$readmemh()`를 이용해 BRAM 초기화
- Address 기반 synchronous read 수행

### `audio_sample_reader.v`

- I2S Transmitter의 `sample_req` 신호에 맞춰 PCM 주소 증가
- 마지막 샘플 이후 주소를 0으로 복귀시켜 반복 재생
- ROM read latency를 고려해 `sample_valid` 생성

### `i2s_transmitter.v`

- 16-bit Mono PCM을 Left / Right 채널에 동일하게 출력
- BCK / LRCK / DATA 생성
- 다음 PCM 데이터를 미리 요청하기 위한 `sample_req` 생성
- Standard I2S 규격에 맞게 **LRCK 전환 후 1 BCK 뒤에 다음 채널 MSB가 출력되도록 구현**

### `iir_lpf_q15.v`

- Q15 Fixed-Point 형식의 1차 IIR Low-Pass Filter
- 곱셈 및 누산 경로를 Pipeline 구조로 구성
- FPGA에서 부동소수점 연산 없이 필터 연산 수행

### `audio_band_splitter.v`

두 개의 Low-Pass Filter 출력을 이용해 세 대역을 생성합니다.

```text
LOW  = LPF_LOW
MID  = LPF_HIGH - LPF_LOW
HIGH = PCM - LPF_HIGH
```

### `band_energy_meter.v`

- 각 대역 신호의 절댓값 계산
- 512개의 Sample을 누적
- 대역별 평균 Energy 계산
- Window 완료 시 `avg_valid` 출력

### `band_level_mapper.v`

- Low / Mid / High 대역별 Fixed Threshold 적용
- Energy 크기를 0~8 단계 Level로 변환
- 대역별 특성을 고려해 서로 다른 Threshold 사용

### `matrix_level_history.v`

- 새 Level이 생성될 때마다 이전 Level History 이동
- 8×8 Dot Matrix 표시용 Frame 데이터 생성

### `max7219_display_controller.v`

- MAX7219 초기화 및 Display Update 순서 제어
- 전송 중 새로운 Frame 요청을 관리

### `max7219_display_engine.v`

- MAX7219 Register Address와 Dot Matrix Row 데이터를 조합
- Low / Mid / High Frame을 3개의 MAX7219 전송 데이터로 변환

### `max7219_chain_driver.v`

- 3개의 MAX7219 Daisy Chain 제어
- DIN / CLK / CS 신호 생성
- 48-bit Serial Data 전송

---

## Audio Processing Flow

오디오 입력은 Signed 8-bit PCM 형태로 BRAM에 저장됩니다.

```text
8-bit PCM
    │
    ▼
16-bit Sign Extension
    │
    ▼
Q15 IIR Band Split
    │
    ├── LOW
    ├── MID
    └── HIGH
    │
    ▼
Absolute Value
    │
    ▼
512-Sample Average
    │
    ▼
Fixed Threshold Comparison
    │
    ▼
Level 0 ~ 8
```

512 Sample Window를 사용하므로 8 kHz Sample Rate 기준 약 64 ms마다 새로운 Level이 계산됩니다.

```text
512 / 8000 ≈ 64 ms
```

---

## I2S Timing Improvement

초기 I2S Transmitter에서는 LRCK가 전환되는 시점과 다음 채널의 MSB 출력이 동시에 발생했습니다.

```text
Before

LRCK Change
     │
     └── MSB Output
         (same timing)
```

PCM5102A 출력에서 음질 문제가 발생하여 I2S Timing을 다시 확인했고,  
Standard I2S에서는 LRCK가 변경된 후 **1 BCK 뒤에 다음 채널의 MSB가 출력되어야 한다는 점을 반영했습니다.**

```text
After

LRCK Change
     │
     └── 1 BCK
           │
           └── Next Channel MSB
```

이를 위해 Left / Right 채널의 마지막 Bit를 출력하는 시점에 LRCK를 미리 전환하도록 수정했습니다.

---

## Refactoring

초기 구조에서는 Python으로 음원을 분석하여 대역별 Threshold를 생성하고, RTL에서는 계산된 값을 단순 비교하는 방식을 사용했습니다.

리팩토링 후에는 Python의 역할을 **BRAM 초기화용 PCM 데이터 변환**으로 제한하고, FPGA 내부에서 다음 처리를 수행하도록 변경했습니다.

```text
Band Split
→ Energy Average
→ Fixed Threshold Mapping
→ Matrix History
→ Display Control
```

또한 DSP 연산 경로의 Timing Margin 확보를 위해 Q15 IIR Filter의 곱셈 및 누산 연산을 Pipeline 구조로 분리했습니다.

---

## Fixed Threshold Mapping

대역별 Energy 특성이 서로 다르기 때문에 Low / Mid / High에 각각 다른 Threshold를 사용합니다.

Threshold 값은 실제 FPGA 출력 또는 Simulation / ILA 결과를 확인하면서 조정할 수 있습니다.

```text
Energy < T1       → Level 0
T1 ≤ Energy < T2  → Level 1
...
Energy ≥ T8       → Level 8
```

---

## Project Structure

```text
fpga-audio-level-meter/
│
├── src/
│   ├── audio_level_meter_top.v
│   ├── audio_rom.v
│   ├── audio_sample_reader.v
│   ├── i2s_transmitter.v
│   ├── iir_lpf_q15.v
│   ├── audio_band_splitter.v
│   ├── band_energy_meter.v
│   ├── band_level_mapper.v
│   ├── matrix_level_history.v
│   ├── max7219_display_controller.v
│   ├── max7219_display_engine.v
│   └── max7219_chain_driver.v
│
├── mem/
│   └── audio_8k_s8.mem
│
├── constraints/
│   └── audio_level_meter.xdc
│
├── sim/
│   ├── tb_audio_sample_reader.v
│   └── tb_i2s_transmitter.v
│
└── README.md
```

---

## Hardware Connection

### PCM5102A

| Signal | FPGA Signal |
|---|---|
| BCK | `i2s_bck` |
| LCK / LRCK | `i2s_lrck` |
| DIN | `i2s_dout` |

### MAX7219

| Signal | FPGA Signal |
|---|---|
| DIN | `JA2` |
| CS | `JA3` |
| CLK | `JA4` |

---

## Notes

- PCM 데이터는 8 kHz / Signed 8-bit 형식으로 사용합니다.
- I2S 출력에서는 8-bit PCM을 16-bit 데이터 범위로 확장하여 PCM5102A에 전달합니다.
- DSP 처리에서는 원래 Signed PCM 크기를 유지하기 위해 Sign Extension 후 사용합니다.
- Fixed Threshold 값은 입력 음원 및 Filter 특성에 따라 조정할 수 있습니다.
