# FPGA Photo Booth System

## 프로젝트 개요
본 프로젝트는 OV7670 카메라 입력 영상을 FPGA 상에서 실시간으로 처리하여 VGA로 출력하는 포토부스 시스템입니다. Sharpen, Sobel, Gaussian 등 다양한 필터를 RTL 수준에서 구현하였으며, 라인버퍼 기반의 공통 구조를 적용하여 필터 간 재사용성과 확장성을 확보하였습니다.  
추가적으로 Python Flask 서버와 Flutter 기반 GUI를 연동하여 사용자가 실시간으로 필터 및 프레임을 선택할 수 있도록 하였으며, Real-ESRGAN을 활용한 4배 업스케일링 및 Gemini 기반 감정 분석 기능을 실제 촬영 이미지에 적용함으로써 AI 융합형 포토부스로 확장 완료하였습니다.

## 주요 목표
- 카메라 입력 → 필터 처리 → VGA 출력으로 이어지는 실시간 영상처리 파이프라인 구현  
- 라인버퍼 기반 3x3 윈도우 구조를 모든 필터에 공통 적용하여 재사용성 확보  
- Vivado 합성 결과 분석을 기반으로 BRAM 및 DSP 사용량 최적화  
- Python Flask 서버 및 Flutter GUI 연동을 통해 실시간 필터 및 프레임 선택 기능 제공  
- Real-ESRGAN 기반 업스케일링 및 Gemini 기반 감정 분석 결과를 실제 출력 이미지에 반영하여 AI 융합형 포토부스 구현
  
---

## 개발 환경 및 사용 기술

| 구분 | 사용 기술 |
|------|-----------|
| HDL / FPGA | SystemVerilog, Vivado |
| AI 기반 처리 | Gemini (감정 분석), Real-ESRGAN (이미지 업스케일링) |
| 서버 연동 | Python Flask, UART 통신 |
| GUI | Flutter |
| 입출력 장치 | OV7670 (카메라 입력), VGA (영상 출력) |

## 담당 역할
| 영역 | 수행 내용 |
|------|-----------|
| RTL 설계 | Sharpen 및 Sobel 필터 RTL 구현 |
| 구조 설계 | 라인버퍼 기반 3x3 윈도우 구조 정의 및 필터 구조 표준화 |
| 모듈 통합 | 필터 모듈 통합 및 파이프라인 지연(latency) 조정 |
| 동기화 검증 | 주소 카운터 및 클록 기반 타이밍 정렬 |
| 디버깅 | 윈도우 유효 타이밍 불일치로 인한 픽셀 전파 오류 해결 |
| 자원 최적화 | Vivado 합성 분석을 통해 BRAM 및 DSP 사용량 개선 방향 제시 |

---

## 시스템 아키텍처 (System Architecture)

본 시스템은 카메라 입력 데이터가 FPGA 내부의 실시간 영상 처리 파이프라인을 통해 필터 연산을 거친 후 VGA로 출력되는 구조로 설계되었습니다. 또한 서버 및 GUI와의 연동을 통해 사용자 입력에 따라 필터 및 프레임 선택이 가능하도록 구성되어 있습니다.

아래는 전체 시스템 구조를 나타낸 블록 다이어그램입니다.

<img width="3558" height="1238" alt="image" src="https://github.com/user-attachments/assets/d8831dc3-2dd8-4f1a-bf96-6cefdb703d7e" />

### 데이터 흐름 구성 요소

| 구성 요소 | 역할 |
|-----------|------|
| OV7670 카메라 | RGB565 영상 데이터를 실시간 입력 |
| Line Buffer 기반 필터 구조 | 3x3 윈도우를 활용하여 Sharpen, Sobel, Gaussian 등 필터 적용 |
| VGA 출력 블록 | 필터링된 데이터를 VGA 해상도에 맞춰 출력 |
| Python Flask 서버 | 사용자 요청(필터, 프레임 선택)을 FPGA에 전달하는 중계 역할 |
| Flutter GUI | 사용자가 필터 및 테마를 선택할 수 있는 인터페이스 |
| Real-ESRGAN / Gemini | 촬영 완료 후 업스케일링 및 감정 분석 처리 |

---

## 필터별 구현 구조 (Filter Implementation Overview)

본 프로젝트에서 구현된 모든 필터는 동일한 라인버퍼 기반 3x3 윈도우 구조를 사용하도록 설계되어, 구조 확장 및 교체가 용이합니다. 각 필터는 동일한 인터페이스(`clk`, `reset`, `we_in`, `wAddr_in`, `wData_in`, `we_out`, `wAddr_out`, `wData_out`)를 따르며, 출력 레이턴시에 따라 파이프라인 지연값(LAT)을 조정하여 통합 처리에 활용하였습니다.

### 1) 라인버퍼 기반 3x3 윈도우 구조 (공통 구조)
| 구성 요소 | 역할 |
|-----------|------|
| 라인버퍼 2개 | 현재 입력 픽셀과 이전 2라인 픽셀을 저장 |
| 쉬프트 레지스터 | 1라인 내 픽셀을 순차 이동하여 열 단위 정렬 |
| 3x3 윈도우 생성 | 총 9개의 픽셀을 필터 연산에 사용 |
| win_valid 신호 | 3x3 윈도우가 유효하게 채워졌음을 표시 |

<img width="600" alt="image" src="https://github.com/user-attachments/assets/a66a381b-4d34-4f63-9662-d1c151bb570c" />
<img width="600" alt="image" src="https://github.com/user-attachments/assets/1eb91212-1c75-4bbb-8f63-124d3027c18e" />  

### 2) Sharpen Filter
- 중심 픽셀에 높은 가중치(예: +5)를 부여하고, 주변 4개 픽셀을 감산하여 엣지 강조
- RGB565 기반 3채널 분리 후 각각 커널 연산 수행
- 예시 연산: `conv = 5*P(1,1) - (P(0,1)+P(2,1)+P(1,0)+P(1,2))`
- 필터 특성: 선명도 향상 및 경계 강조
- 시뮬레이션 결과
  - 새로운 픽셀 r22에 저장, 클럭마다 우상단 방향으로 이동하며 3x3 윈도우 형성 
  - 라인버퍼가 2줄 이상 채워지면 전체 윈도우 완성, 이를 Sharpen 연산에 사용
     (G, B Channel도 동일)
    <img width="2769" height="762" alt="image" src="https://github.com/user-attachments/assets/1608e14e-7aa3-4da5-8976-f465bd3336ec" />
  - conv_r,g,b: 각 채널에 대한 샤프닝 연산 수행 결과
  - wData_out: 세 채널 결과를 RGB565형식으로 합친 최종 값
  <img width="2670" height="318" alt="image" src="https://github.com/user-attachments/assets/468c52aa-ea9f-4ae4-a47e-c60cd4541252" />

### 3) Sobel Filter
- Gray 변환 후 수평(Gx), 수직(Gy) 기울기 계산
- Gx = `[-1 0 1; -2 0 2; -1 0 1]`, Gy = `[1 2 1; 0 0 0; -1 -2 -1]`
- Edge 값 = `|Gx| + |Gy|`
- Threshold 비교 후 이진화(0 또는 255) 처리
- 필터 특성: 명확한 엣지 검출용 하드웨어 엣지 디텍터
- 시뮬레이션 결과
  - GrayScale 변환 후 라인버퍼에 저장하기 때문에 Sharpen에 비해 2클럭 늦게 윈도우가 채워짐
  <img width="2869" height="594" alt="image" src="https://github.com/user-attachments/assets/df218d83-65e8-4860-928d-b3f22b39cc22" />

  - gx=0x005, gy=0x005 → |5|+|5|=10 → mag=0x000a로 계산, Sobel 연산 정상 동작
  - sobel_val : 에지 강도(0~255) 계산 결과, 
  - edge_bin : 임계값(THRESHOLD) 비교 후 0/255로 이진화
  - wData_out : 최종 출력 (RGB565, 흑백 에지 맵)
  <img width="2880" height="366" alt="image" src="https://github.com/user-attachments/assets/6df15320-d403-44d4-abc1-81575a17d169" />

### 4) Gaussian Filter
- 3x3 Gaussian 마스크 기반 저주파 통과 필터
- 예: `[1 2 1; 2 4 2; 1 1 1] / 16`
- 노이즈 제거 및 영상 스무딩 효과
- RGB 채널별 누적 연산 후 평균화 방식 적용
- 시뮬레이션 결과
  - 입력 픽셀이 들어오면 라인버퍼에 저장되어 순차적으로 누적
    <img width="599" height="81" alt="image" src="https://github.com/user-attachments/assets/8417c874-c1fb-4579-b8ba-9949622e3157" />

  - 라인버퍼가 채워지면 3x3 윈도우가 형성되고 win_valid 신호로 유효성 확인
    <img width="496" height="196" alt="image" src="https://github.com/user-attachments/assets/de6eb76b-93f7-4f07-aff1-f375cd6e8a6b" />

  - 윈도우 내 픽셀 값들을 이용해 RGB 합산을 수행하여 가우시안 블러 연산 진행
    <img width="569" height="71" alt="image" src="https://github.com/user-attachments/assets/ac24bb06-be3b-4419-9437-600e4c60316a" />

  - 연산된 결과 RGB565 형태로 변환해 최종 출력
    <img width="594" height="29" alt="image" src="https://github.com/user-attachments/assets/a46fb20a-eba4-4593-b107-a11f81bd0a37" />

### 5) System Verification (Cartoon Filter)
- Block Diagram
<img width="503" alt="image" src="https://github.com/user-attachments/assets/83efcbe8-501a-4e95-8061-608e187aee1d" />

- Simulation
  - Gaussian Blur → Poletarization → Sobel Edge 순서의 파이프라인 진행 
  - 각 단계의 값이 순차적으로 전파되는 것을 확인
  - gx, gy, mag 계산 결과 정상 출력, 최종 out_pixel 값이 출력 파이프라인과 맞게 정렬
    <img width="2259" height="1010" alt="image" src="https://github.com/user-attachments/assets/6ec5fdc7-36c0-4091-8f0d-13e3fcda78d6" />


- Result
<img width="340" alt="image" src="https://github.com/user-attachments/assets/27920976-2457-4215-a2a4-5bc8fd6f57b5" />


---

## 문제 해결 사례 (Troubleshooting)

프로젝트 수행 과정에서 하드웨어 초기화 및 입력 처리 과정에서 여러 문제가 발생하였으며, 아래는 PDF에 명시된 해결 사례입니다.

### 1) SCCB(Camera Init) 레지스터 설정 불일치 문제
| 항목 | 내용 |
|------|------|
| 증상 | OV7670 카메라 초기화가 정상적으로 이루어지지 않아 영상 출력이 불안정하게 나타남 |
| 원인 | SCCB 레지스터 전송 로그를 확인할 때, `$display`를 사용할 경우 출력 시점이 실제 전송 완료 시점과 불일치하여 검증이 정확하지 않음 |
| 해결 방식 | 실제 전송 완료 타이밍과 동기화하기 위해 `$display`를 `$strobe`로 교체하여 최종 전송 레지스터 값을 정확하게 확인 |
| 결과 | SCCB 레지스터가 정상적으로 설정되었음을 확인하고 안정적인 영상 입력 확보 성공 |

<img width="700" alt="image" src="https://github.com/user-attachments/assets/fe0b88c5-10dd-475b-acce-94c8a169b08e" />
<img width="700" alt="image" src="https://github.com/user-attachments/assets/fe19e173-f79d-4e93-8c0a-20d11e31908d" />



### 2) UART 기반 사용자 입력 처리 시 입력 이벤트 중복 문제
| 항목 | 내용 |
|------|------|
| 증상 | 버튼 입력을 UART 신호로 대체하였을 때, 신호가 단발성으로 입력되지 않거나 연속 인식되어 여러 번 전송되는 문제 발생 |
| 원인 | 버튼이 High 상태로 유지될 경우 이벤트가 반복적으로 발생하거나 반대로 짧은 이벤트는 인식되지 않음 |
| 해결 방식 | 입력 신호 유지 시간을 관리하기 위해 일정 주기(예: 8클럭) 동안 상태를 유지하는 hold 카운터를 추가하고, 타임아웃 이후에만 idle 상태로 복귀하도록 FSM 수정 |
| 결과 | 입력 신호가 단일 이벤트로 안정적으로 처리되며, 사용자 조작에 따라 필터 변경 및 프레임 전환이 정상적으로 수행됨 |

<p align="center">
  <img src="https://github.com/user-attachments/assets/bfa3333d-53fd-432c-b6a8-2d4b1b24976d" height="250px" />
  <img src="https://github.com/user-attachments/assets/3deda94b-606b-4543-9d41-ee7694728de5" height="250px" />
</p>

---

## 배운 점 (What I Learned)

본 프로젝트를 통해 단순한 필터 설계를 넘어, 시스템 관점에서의 구조 설계와 최적화 경험을 쌓을 수 있었습니다.  
특히 다음과 같은 설계 역량을 강화할 수 있었습니다.

- 라인버퍼 및 파이프라인 구조를 최적화하며, 제한된 BRAM 및 DSP 자원 내에서 효율적인 구조 설계의 중요성을 이해하였습니다.  
- 필터 모듈 간 지연(latency) 정렬과 주소 동기화를 수행하며, 시스템 단위 통합 설계 감각을 향상시켰습니다.  
- SystemVerilog 기반 검증 환경을 활용하여 타이밍, 경계 조건 및 신호 유효성 검증의 중요성을 체감하였습니다.  
- 스티커, 인생네컷, AI 기능을 결합하며 하드웨어 설계가 실제 사용자 경험과 연결될 수 있다는 점을 확인하였습니다.  
- 모듈 간 역할 분리와 통합 단계에서의 인터페이스 정렬 경험을 통해 협업 기반 설계의 필요성을 느꼈습니다.


