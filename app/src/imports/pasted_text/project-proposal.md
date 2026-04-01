# EE3070 Project Proposal

## Group No: \_**\___ G\_\_**__

## Project Name: AI-Bot — Voice-Controlled Desktop AI Assistant with Computer Automation

| Member Name | Group Leader | Student ID | Signatu re |
|---- - ------|:---- - -----:|--- - ------|-- -------|
|             |              |            |           |
|             |              |            |           |
|             |              |            |           |
|             |              |            |           |

---

## Section 1: Description of Targeted Scenario and Project Goals

### Background

With the rapid development of artificial intelligence, voice assistants such as Amazon Alexa, Google Home, and Apple Siri have become common household devices. However, these commercial products are limited to cloud-based services and lack the ability to directly control a user's personal computer. Meanwhile, desktop users frequently perform repetitive tasks — opening applications, managing files, adjusting system settings — that could be automated through natural voice commands.

There is a gap in the market for a **compact, privacy-respecting desktop AI assistant** that combines hardware-based voice interaction with direct computer control capabilities. Existing solutions either require cloud processing (raising privacy concerns) or are purely software-based (lacking a dedicated physical interface with display and tactile feedback).

### Identified Problems

1. **Lack of physical AI interface for desktop control**: Current voice assistants cannot directly manage files, launch applications, or control system settings on a personal computer.
2. **Privacy concerns with cloud-only voice assistants**: Commercial voice assistants send all audio to remote servers, posing risks for sensitive work environments.
3. **Inefficient desktop workflows**: Users repeatedly perform manual operations (opening apps, adjusting volume, organizing files) that could be streamlined through voice automation.
4. **No affordable, open-source desktop AI hardware**: Existing smart speakers are closed ecosystems with no customization or local AI processing options.

### Ethical Constraints

1. **Privacy and data security**: The system transmits user audio to cloud-based APIs (Whisper for speech recognition, LLM for dialogue, Edge-TTS for synthesis) for processing. To mitigate privacy risks, audio is transmitted over encrypted HTTPS connections, is not stored persistently on the server side, and is used solely for real-time processing. Users are clearly informed that voice data is uploaded to the cloud, and the device only begins recording after an explicit wake-up trigger, preventing unintended audio capture.
2. **User consent and control**: All computer control operations (file deletion, application management) require explicit user confirmation through voice or physical touch interaction (tap-to-confirm). A dedicated "chat-only mode" disables all computer control for safety.
3. **Transparency**: The system clearly indicates its operational state (recording, processing, executing) through the LCD display and LED indicators, ensuring users always know what the device is doing.
4. **Responsible AI use**: The AI dialogue engine operates within defined boundaries and does not perform destructive or unauthorized system operations. Sensitive operations are sandboxed.

### Impact of the Solution

- **Accessibility**: Provides a hands-free computer control interface that benefits users with mobility impairments or those who prefer voice interaction for multitasking.
- **Productivity**: Automates repetitive desktop tasks, enabling users to manage files, launch applications, and control system settings through simple voice commands, improving workflow efficiency.
- **Educational value**: The project integrates multiple engineering disciplines — embedded systems, PCB design, wireless communication, AI, and software development — serving as a comprehensive learning experience and demonstrating how IoT hardware and cloud AI services can be combined into a practical consumer product.
- **Affordable and customizable alternative**: Compared to commercial smart speakers that are locked into proprietary ecosystems, this project offers a cost-effective, fully customizable desktop AI assistant tailored to individual user needs, with the flexibility to choose different AI models and extend functionality.

### Project Goals

1. Design and fabricate a custom PCB integrating ESP32-S3 microcontroller with audio input/output, display, motion sensing, and power management.
2. Implement real-time voice interaction: user speaks to the device, speech is recognized, AI generates a response, and the response is played back through the speaker.
3. Enable voice-controlled computer automation: file management, application control, and system settings adjustment through natural language commands.
4. Provide a standby desktop widget mode displaying time, weather, and status information on the built-in LCD screen.
5. Implement physical interaction features including tap-to-confirm (capacitive touch) and shake-to-trigger (accelerometer-based) functions.

---

## Section 2: Description of System Functions

### System Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    Hardware Device                       │
│  ESP32-S3 + INMP441 Mic + MAX98357A Amp + ST7789 LCD   │
│  + MPU6050 IMU + Capacitive Touch + WS2812B LEDs       │
│  + TP4056 Charger + AMS1117 LDO + Li-ion Battery       │
└───────────────────────┬─────────────────────────────────┘
                        │ WiFi (WebSocket)
                        ▼
┌─────────────────────────────────────────────────────────┐
│                   PC Server (Python)                     │
│  FastAPI Backend                                        │
│  ├── Whisper (Speech-to-Text)                           │
│  ├── Edge-TTS (Text-to-Speech)                          │
│  ├── LLM Engine (GPT-4 / Claude API)                    │
│  └── NanoBot (Lightweight Computer Control Agent)        │
└─────────────────────────────────────────────────────────┘
```

### Function 1: Voice Interaction (MVP)

**Modules used**: INMP441 (I2S digital microphone), MAX98357A (I2S Class-D amplifier), 3W spe
aker, ESP32-S3 (WiFi), PC server (Whisper + Edge-TTS + LLM)

**How it works**:
1. User speaks to the device; INMP441 captures audio via I2S interface.
2. ESP32-S3 streams audio data to the PC server over WiFi (WebSocket).
3. Server runs Whisper speech recognition to convert audio to text.
4. Text is sent to the LLM (GPT-4/Claude) for intent understanding and response generation.
5. Response text is converted to audio using Edge-TTS.
6. Audio is streamed back to ESP32-S3, which plays it through MAX98357A and speaker.

**User interaction**: User simply speaks to the device naturally. The device shows recording/processing/playback status on the LCD screen.

### Function 2: Computer Control via Voice (MVP)

**Modules used**: PC s
erver (NanoBot lightweight computer control agent), LLM intent recognition

**How it works**:
1. After speech recognition, the LLM identifies the user's intent (e.g., "open VS Code", "create a folder on Desktop").
2. If the intent is a computer control command, the server routes it to NanoBot.
3. NanoBot is a lightweight, easily customizable agent that executes computer control tasks including file operations, application management, and system commands.
4. Execution result is returned to the user via voice feedback.

**Why NanoBot over OpenClaw**: NanoBot was chosen for its lightweight architecture and ease of modification. OpenClaw's large codebase (700+ skills) proved difficult to customize for our specific project needs, while NanoBot provides a compact, developer-friendly framework that is straightforward to extend and adapt.

**Supported operations**:

- File management: create, delete, move, rename, search files/folders
- Application control: open, close, switch applications
- System operations: adjust volume, brightness, take screenshots, lock screen

**Safety**: Destructive operations require user confirmation via tap (capacitive touch) or voice ("confirm" / "cancel").

### Function 3: Desktop Widget Mode (MVP)


**Modules used**: ST7789 1.69" IPS LCD (SPI interface), ESP32-S3 (NTP time sync, weather API)

**How it works**:
1. In standby mode, the LCD displays current time (synced via NTP), weather information (from weather API), and upcoming reminders.
2. The display updates periodically with minimal power consumption.
3. UI is rendered using the LVGL embedded GUI framework.

**User interaction**: The device serves as a desktop clock/weather station when not actively in conversation.

### Function 4: Physical Interaction

**Mod
ules used**: ESP32-S3 built-in capacitive touch sensor (IO7), MPU6050 6-axis IMU (I2C), WS2812B RGB LEDs

**How it works**:
- **Tap interaction**: Capacitive touch pad on the top sub-board detects single tap (confirm), double tap (reject), and triple tap (interrupt). Replaces mechanical buttons for a cleaner design.
- **Shake to trigger**: MPU6050 accelerometer detects shaking motion, triggering fun features (daily fortune, random quotes, decision maker).
- **LED feedback**: 6 WS2812B RGB LEDs provide ambient lighting and status indication (breathing effect during standby, color changes during recording/processing).

### Function 5: Power Management

**Modules used**: TP4056 (Li-io
n charge controller), AMS1117-3.3 (LDO voltage regulator), USB Type-C (16-pin), 3.7V Li-ion battery (1000–2000mAh)

**How it works**:
1. USB Type-C provides 5V input for charging via TP4056 (1A charge current, set by 1.2KΩ PROG resistor).
2. TP4056 manages battery charging with LED status indicators (red = charging, green = full).
3. AMS1117-3.3 regulates battery voltage to stable 3.3V for all digital components.
4. The device operates cordlessly on battery power for portable use.

### Hardware Block Diagram

```
                        USB Type-C 5V
                            │
                        ┌───┴───┐
                        │TP4056 │──── Charge LEDs (Red/Green)
                        └───┬───┘
                            │
                      3.7V Li-ion Battery
                            │
                      ┌─────┴─────┐
                      │ AMS1117   │
                      │  3.3V LDO │
                      └─────┬─────┘
                            │ 3.3V
            ┌───────┬───────┼───────┬──────────┬──────────┐
            │       │       │       │          │          │
       ┌────┴───┐ ┌─┴──┐ ┌─┴───┐ ┌┴────┐ ┌───┴───┐ ┌───┴───┐
       │INMP441 │ │MAX │ │ST   │ │MPU  │ │Touch  │ │WS2812B│
       │  Mic   │ │9835│ │7789 │ │6050 │ │Pad    │ │ LEDs  │
       │ (I2S)  │ │7A  │ │(SPI)│ │(I2C)│ │(Touch)│ │(GPIO) │
       └────┬───┘ └─┬──┘ └──┬──┘ └──┬──┘ └───┬───┘ └───┬───┘
            │       │       │       │        │         │
            └───────┴───────┴───┬───┴────────┴─────────┘
                                │
                     ┌──────────┴──────────┐
                     │   ESP32-S3-WROOM-1  │
                     │   N16R8 (Main MCU)  │
                     │  16MB Flash + 8MB   │
                     │      PSRAM          │
                     │                     │
                     │   WiFi / Bluetooth  │
                     └──────────┬──────────┘
                                │ WiFi
                                ▼
                     ┌─────────────────────┐
                     │   PC Server         │
                     │ (Whisper+TTS+LLM+   │
                     │  NanoBot)             │
                     └─────────────────────┘
```        

### Bill of Materia   ls (BOM)
                 
The following c                                                    omp o-- | nent-------------   list is der----------- i --ved from the actual s- c --- | ------hematic d-----sign -------v2.0):

------------------ **Main  Board — Acti       ve Components (ICs & Modules)**

                  | Re  f | Component | Part Number / Value | Package | Qty | Function |
|--- --|-----------|--  -------------------|----  -----|---                  --|  ----------|
| U1 | MCU Modul                                   e | ES P32-S3-WROOM-1-N16R  8 | Module | 1 |         Main cont                  rol  ler (dual-core, WiFi/BT, 16MB Flash + 8MB                        PSRAM ) |
| U2 | MEMS Microphone |                 INMP441                    (EV  _INMP441) | Module | 1 | I2S digital audi                       o captu re |
| U3 | Audio Amplifier | MAX           98357AETE+                 T |   QFN-16 | 1 | I2S Class-D amplifier, driv                       es spe aker |
| U4 |        Charge Contr           oller | TP4056 | SOP-8 | 1 | Li-  ion battery charge management (1A) |
| U5 | Vol               tage Regulator | AMS1117-3.3 | SOT-223 | 1 | 3.3V         LDO (battery →                       3.3V for all ICs                                           ) | --- | -------
| U----- 7  | 6-Axis I---------U | ZY-MPU-60 t --- | -----------------------amp-hole (------------------ 2×4, 2 .54mm) | 1 | Accelerometer + gyroscope for shake detection |  

**Main Board — Connectors                          **

|  Ref | Compon       ent | Part Number | Qty | F         unc  tion |
|-----|-----------|------                     -------| -----|-------      ---|
| J1 | Battery Connector |      B2  B-PH-K-S(LF)(SN) (JST PH 2-pin) | 1                     | Li- ion battery connection |
| J2 | USB Type-C |             KH  -TYPE-C-16P-N (16-pin) | 1 |                            5V ch arging and USB data /debug |
| J3 | Displ               ay   FPC | AFC01-S12FCA-00 (12-pin FPC) | 1 |                ST778 9 1.69" IPS LCD conn ection |
| P1 | Spea               ker   Connector | PZ254V-11-02P (2-pin) | 1 | 3             W 4Ω s peaker connection | 
| H1 | Expansion Hea               der   | 2.54mm 1×5P Female | 1 | Breakout: IO1, IO2, TXD0, RXD0, IO39 |
| H2 | Expansion Header | 2.54mm          1×5P Female | 1 | Br           eakout: I  O13, IO45, IO48, I                                         O47 ----, IO2--- 1 --------- | ----- |
| H4 |  E --xpansio n --- | --- Header |--------------------2.54m 1×5P Fema-- le | 1 | Br      eakout: IO3, 3V3, 3            V3, GND      (t  ouch sub-board link) |

**M                        ain Boa          rd — Passive Compone           nts**
     
|   Ref | Component | Value | Pa                        ckage |           Qty | Function |
           |-----|-     ---  -------|-------|---------|                           -----|          ----------|
| C1, C2 | Capac   itor |      10µ  F | 0805 | 2 | ESP32-S3 power                         decoup          ling |
| C3 | Capac           itor |      100n  F | 0603 | 1 | ESP32-S3 power decoupli              ng |
| C5 | Capacitor | 100nF | 0603 |          1 | INMP441 VD  D decoupling |
| C7 | Capacitor | 100nF (0.1        µF) | 0         603 | 1 | MAX98357A V           BAT dec     oup  ling |
| C8 | Capacitor |                            100nF | 06      03 | 1 | S T7789 bac           klight      / p  ower decoupling |
| C9, C10, C11 | Capacitor | Various | 0603/0      805 | 3 |  TP4056 and AMS1117 input/ou     tpu  t filtering |
| C13 | Capacitor | 100               nF | 06          03 | 1 | MP U6050 V            CC deco     upl  ing |
| R1, R2 | Resistor | 5.1kΩ | 0603             | 2 | U         SB Type-C  CC1/CC2            pull-dow     n (  UFP identification) |
| R3, R4 | Resist             or | Curren      t-limiting  | 0603 |            2 | Ch     arge   status LED current limiting |
| R6 | Re           sistor           | 4.7Ω       | 060             3 | 1 |      ST  7789 backlight LED current limiting                  |
| R1          2 | Re      sistor |            100kΩ      | 0  603 | 1 | INMP441 L/R channel select pull            -down |
| R_PROG | Resistor | 1.2kΩ | 0603 | 1    | TP4056 charg   e current program                          min -g  | (1A--------- ) --- |
| D1 |  L --- | ---ED | Red | 06-------| TP4056 c- harging indicator (CHRG) |
| D2 | L    ED   | Green | 0603 | 1 | TP4056 standby/full ind  icator (STDBY) |

**Main Board —   Switches**

| Ref | Component | Par t Number | Qty | Function |
|-----|---                         --------|--------                                           --- ---------|-----|------------------ - --- | ----------|
| SW1 -------------------------------- | Slide Switch | S                     K12  D07VG4 | 1 | Mai                                       n power on/off (battery to LDO) |
| —  | R  eset Button | Tactile switch | 1 |                    ESP32-S3 EN reset (with RC delay) |

**Ma  in Board — Other**

|                               Component | Qty | Func                 tio  n |
|-----------|-----|----------|
| 3W 4Ω Speaker | 1 | Audio output |
| 1.69" IP    S TFT LCD (S  T7789 driver) |    1 | Display (con                                      nec ts vi-- a  FPC to J3)   -|
| 3.7V Li-- i --- | -----on Ba--------------tery (1000------------ –2000mA     h) | 1 | Po   rtable p          owe  r source |
| WS2812B LED Strip | 1 | Ambie       nt lighting / status indicatio              n (  data on IO38) |

**Touch Sub-Board**

| Ref | Component | Value / Part | Qty               |   Function |
|-----|-----------|-                  -----      -------|-----| ----------|
| R5 | R  esistor | 4.7kΩ | 1 | ESD protection for c        apacitive touch pad |
| TP1–TP4 | Test Points | — | 4 | Signal breakout: TOUCH_                                                                                                                                                                                                                                            MAI ---- | ------------------N, GND------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- 3V3, LED_DIN |
| TP5------ –TP6 | Test Points | — | 2 | Touch copper pad connections |
| — | Copper Pad | PCB copper pour | 1 | Capacitive touch                                                                                                                                                       sensing area (8–12mm) |

---

## Section 3: Project Planning Schedule

| Week | Tasks to be completed |
|------|----------------------|
| 6    | Submit project proposal. Receive PCB b                                                                              oards and components. Begin soldering main board and touch sub-board. |
| 7    | Complete PCB soldering. Power-on test (verify 3.3V supply). Test ESP32-S3 basic functionality (WiFi, serial debug). Begin individual module testing (microphone, s                         peaker, display). |
| 8    | Complete hardware module testing: INMP441 audio capture, MAX98357A audio playback, ST7789 display output. Test MPU6050 motion detection and capacitive touch sensing. Begin firmware development (WiFi communication, I2S audio driver). |
| 9    | Integrate all hardware modules for full system test. Set up PC server environment: install Python, FastAPI, Whisper, Edge-TTS. Implement WebSocket communication between ESP32-S3 and PC server. Begin end-to-end voice pipeline (record → tran                        smit → recognize). |
| 10   | Complete voice interaction pipeline: speech recognition (Whisper) + AI response (LLM) + text-to-speech (Edge-TTS) + playback. Integrate NanoBot for computer control. Implement basic                                                         computer control commands (open app, manage files). |
| 11   | Implement standby widget mode (time/weather display). Implement physical interaction (tap-to-confirm, shake-to-trigger). Implement L                                                                         ED ambient lighting effects. System stability tes                                                                                                                                                                                                                            ting and bug fixing. |
| 12   | Complete_3D-printed enclosure assembly. Full system in_egration te              sting. Prepare demo                                                                                                                                                                                                            nst ration: ------------ v --------------------------------------------------------------------------oice dialogue, co--------------------------------------------------------------------------------------------------------------------------------- mputer control, widget mode, physical interaction. Write final report. |
| 13   | Final presentation and demonstration. |

---

## Section 4: Division of Labor

*(Please fill in member                                                          names and Student IDs)*

| Member | Responsibilities |
|--------|-----------------|
| Member 1 (Name, SID) | **Hardware design & PCB**: Schematic design in LCEDA (all 7 modules), PCB layout and routing, soldering,                               hardware debugging. 3D enclosure design (Autodesk Fusion). |
| Member 2 (Name, SID) | **Firmware development**: ESP32-S3 firmware (Arduino/MicroPython) — WiFi communication, I2S audio driver, SPI display driver, touch/IMU sensor integration, LED control, device state machine. |
| Member 3 (Name, SID) | **PC server backend**: Python + FastAPI server, WebSocket communication handler, Whisper speech recognition integration, Edge-TTS voice synthesis, LLM API integration (GPT-4/Cl            aude), NanoBot computer control integration. |
| Member 4 (Name, SID) | **System integration & testing**: End-to-end testing of voice pipeline, computer control validation, standby display features, physical interaction testing, demo preparation, documentation and report writing. |

---

## Section 5: Gantt Chart

```
Task / Member               | Wk6 | Wk7 | Wk8 | Wk9 | Wk10| Wk11| Wk12| Wk13|
─────────────────────────────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤
PCB Soldering & Power Test   | ███ | ██  |     |     |     |     |     |     |
  (Member 1)                 |     |     |     |     |     |     |     |     |
─────────────────────────────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤
Module Hardware Testing      |     | ██  | ███ |     |     |     |     |     |
  (Member 1 & 2)             |     |     |     |     |     |     |     |     |
─────────────────────────────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤
Firmware Dev (WiFi, I2S,     |     |     | ██  | ███ | ██  |     |     |     |
  SPI, Touch, LED)           |     |     |     |     |     |     |     |     |
  (Member 2)                 |     |     |     |     |     |     |     |     |
─────────────────────────────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤
PC Server Setup (FastAPI,    |     |     |     | ███ | ███ |     |     |     |
  Whisper, TTS, LLM)         |     |     |     |     |     |     |     |     |
  (Member 3)                 |     |     |     |     |     |     |     |     |
─────────────────────────────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤
NanoBot Integration          |     |     |     |     | ███ | ██  |     |     |
  (Member 3)                 |     |     |     |     |     |     |     |     |
─────────────────────────────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤
Widget Mode & Physical       |     |     |     |     |     | ███ | ██  |     |
  Interaction                |     |     |     |     |     |     |     |     |
  (Member 2 & 4)             |     |     |     |     |     |     |     |     |
─────────────────────────────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤
3D Enclosure Design &        |     |     |     |     | ██  | ██  | ██  |     |
  Assembly                   |     |     |     |     |     |     |     |     |
  (Member 1)                 |     |     |     |     |     |     |     |     |
─────────────────────────────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤
System Integration &         |     |     |     |     |     | ██  | ███ |     |
  End-to-End Testing         |     |     |     |     |     |     |     |     |
  (Member 4)                 |     |     |     |     |     |     |     |     |
─────────────────────────────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤
Report Writing &             |     |     |     |     |     |     | ███ |     |
  Demo Preparation           |     |     |     |     |     |     |     |     |
  (All Members)              |     |     |     |     |     |     |     |     |
─────────────────────────────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤
Final Presentation           |     |     |     |     |     |     |     | ███ |
  (All Members)              |     |     |     |     |     |     |     |     |
```

---

## Section 6: Summarize the Current Progress

### Overa
ll Status

The project is currently in the **hardware fabrication stage**. Schematic design and PCB layout have been completed and verified. PCB boards have been ordered for fabrication and all components have been purchased. 3D enclosure design is in progress.

### Completed Work

**1. Project Planning and Research (Week 1–2)**
- Established project goals and defined core functions (voice interaction, computer control, desktop widget, physical interaction).
- Researched and selected key software frameworks: NanoBot (lightweight computer control agent), Whisper (speech recognition), Edge-TTS (speech synthesis).
- Compar
ed NeoAI, OpenClaw, and NanoBot for computer control. Selected NanoBot for its lightweight architecture and ease of customization, as OpenClaw's large codebase proved difficult to modify for our project needs.
- Created detailed function implementation documents covering all 9 planned system functions.

**2. Component Selection (Week 2)**
- Selected ESP32-S3-WROOM-1-N16R8 as the main MCU (dual-core, WiFi/Bluetooth, 16MB Flash + 8MB PSRAM).
- Selected INMP441 (I2S digital microphone) and MAX98357A (I2S Class-D amplifier) for audio.
- Selected 1.69" IP
S TFT with ST7789 driver (SPI interface) for display.
- Selected MPU6050 6-axis IMU for motion detection.
- Selected TP4056 + AMS1117-3.3 for power management.
- Designed capacitive touch interaction using ESP32-S3's built-in touch sensor (replacing external TTP223 chip, reducing BOM by 5–7 components).

**3. Pin Assignment Planni
ng (Week 2)**
- Completed full GPIO pin assignment for ESP32-S3, accounting for N16R8 module restrictions (GPIO22–37 occupied by internal Octal SPI Flash/PSRAM).
- Documented all pin assignments: I2S audio (IO14–18, IO8), SPI display (IO9–12, IO46), I2C IMU (IO5–6), touch (IO7), LED (IO38), USB (IO19–20).

**4. Schematic Design in LCEDA (Week 2–5)**
- Completed schematics for all 7 hardware modules:
  - ESP32-S3 minimum system (power decoupling, EN reset, IO0 boot, USB Type-C)
  - INMP441 microphone (I2S interface)
  - MAX98357A amplifier (I2S int
erface, gain configuration)
  - ST7789 display (SPI interface, backlight driver)
  - Power management (TP4056 charge IC + AMS1117-3.3 LDO)
  - MPU6050 gyroscope (I2C interface, stamp-hole module)
  - Capacitive touch system (ESP32-S3 built-in, with ESD protection resistors)
- Passed ERC (Electrical Rules Check) with no errors.

**5. PCB Design (Week 5–6)**
- Completed PCB layout and routing for the main board.
- Designed a separate touch sub-board (t
op panel) with capacitive touch pad and ESD protection.
- Originally included 6× WS2812B RGB LEDs on the sub-board; later changed to LED strip on the ma
in board for enclosure flexibility.
- Sub-board simplified to a pure touch sensing board (copper pad + ESD resistor).
- Passed DRC (Design Rules Check) for both main board and sub-board.

**6. Procurement (Week 6)**
- Ordered PCB fabrication through JLCPCB (main board + touch sub-board).
- Purchased all electronic components.

**7. 3D Enclosure Design (In Progress)**
- Started designing a 3D-printed enclosure using Autodesk Fusion.

### Documentation Produced

- `README.md` — Project overview and feature descriptions
- `CLAUDE.md` — Project guidelines and pin assignments
- `CHANGELOG.md` — Detailed daily work log (9 days of progress)
- `功能讨论区/功能实现讨论.md` — Detailed implementation plan for all 9 functions
- `功能讨论区/task.md` — MVP task checklist with 8 development phases
- `功能讨论区/openClaw.md` — Computer control framework research (OpenClaw, NeoAI, NanoBot comparison)
- `原理图设计/01–07, 09` — Step-by-step schematic design tutorials for each module
- Component datasheets collected in `元件资料区/` and `元件TXT/`