# Phân công giai đoạn tiếp theo & So sánh 2 phương án ETL

> Tài liệu để thống nhất trong nhóm: chọn **Phương án A** (giữ P1–P4 + tầng `stg_clean`, nhánh `main`)
> hay **Phương án B** (Stage → DW trực tiếp, nhánh `etl-theo-doi-tuong`).

Thành viên:

| Người | Tên | Phần dữ liệu đang phụ trách |
|---|---|---|
| 1 | Triệu Phúc Hiếu | players, clubs (kiêm tích hợp Master) |
| 2 | Bùi Quốc Hậu | competitions, games |
| 3 | Nguyễn Trần Quốc Thi | club_games, appearances |
| 4 | XuanHuyenDang | player_valuations, transfers |

---

## 1. Phương án A – Giữ P1–P4 + tầng `stg_clean` (nhánh `main`)

### 1.1. Hiện trạng

```
Container 01 - Load Staging Raw        : CSV -> stg_raw (TRUNCATE + 10 DFT)        ✅ chạy được
Container 02 - Transform Staging Clean : P1, P2, P3, P4 -> stg_clean (8 bảng)      ✅ chạy được, 02_check PASS
sql/03_create_dw.sql                   : 8 Dim + 4 Fact + 2 Aggregate              ✅ có bảng, chưa có dữ liệu
```

### 1.2. Việc còn thiếu

Thêm vào `Main_ETL_Master.dtsx`:

- **Container 03 - Load Dimensions**: `stg_clean` → các bảng Dim
- **Container 04 - Load Facts**: `stg_clean` + Lookup Dim → các bảng Fact
- **Container 05 - Aggregate**: tính 2 bảng tổng hợp

Mỗi Dim/Fact là **một Data Flow** theo mẫu nhóm 08:

```
SRC - stg_clean.xxx -> DC - chuẩn hoá -> LKP - Dim... (lấy surrogate key) -> LKP - Fact (đã có chưa) -> DST - Fact/Dim
```

### 1.3. Phân công

| Người | Package mới | Nội dung | Nguồn (`stg_clean`) | Đích (DW) |
|---|---|---|---|---|
| **1** – Hiếu | `P5_Load_Dim_Club_Player.dtsx` | DF Load DimClub (**SCD1 + SCD2 + SCD3**), DF Load DimPlayer (**SCD1 + SCD2**), bổ sung CLB/cầu thủ chỉ xuất hiện ở fact (`Other`). **Tích hợp Container 03/04/05 vào Master** | `clubs`, `players` (+ `transfers`, `games` để lấy CLB Other) | `dim_club`, `dim_player` |
| **2** – Hậu | `P6_Load_Dim_Competition_Match_Manager.dtsx` | DF Load DimCompetition, DimMatch, DimManager (SCD1); kiểm tra 3 dim tĩnh (Date, Season, TransferType) do script sinh | `competitions`, `games`, `club_games` | `dim_competition`, `dim_match`, `dim_manager` |
| **3** – Thi | `P7_Load_Fact_TeamMatch_Appearance.dtsx` | DF Load FactTeamMatch (7 Lookup), DF Load FactPlayerAppearance (5 Lookup); **Container 05 Aggregate**; **script DQ check trên DW** | `club_games`, `appearances`, `games` | `fact_team_match`, `fact_player_appearance`, 2 bảng aggregate |
| **4** – Huyền | `P8_Load_Fact_Valuation_Transfer.dtsx` | DF Load FactPlayerValuation, DF Load FactTransfer (Lookup DimTransferType theo `fee_status`, `fee_band`) | `player_valuations`, `transfers` | `fact_player_valuation`, `fact_transfer` |

**Thứ tự phụ thuộc:**

```
P5 (Dim Club/Player) ─┐
                      ├──> P7 (Fact TeamMatch/Appearance) ─┐
P6 (Dim Comp/Match/   │                                    ├──> Container 05 Aggregate
    Manager)         ─┴──> P8 (Fact Valuation/Transfer)  ──┘
```

Trong lúc chờ P5/P6 hoàn thiện, người làm Fact có thể chạy tạm P5/P6 để có dữ liệu thử Lookup.

### 1.4. Quy tắc chung cho mọi Data Flow (để đạt góp ý của GV)

1. **Lookup Dim** để lấy surrogate key; không tìm thấy → gán **-1** (dòng Unknown).
2. **Không TRUNCATE Fact**; thêm **Lookup chính bảng Fact** để chỉ insert dòng chưa có (*góp ý 5: load tăng trưởng*).
3. Dùng biến **`LoadFrom` / `LoadTo`** (lọc ở câu nguồn hoặc Conditional Split) để demo nạp từng đợt.
4. **Dim**: Lookup theo khoá tự nhiên → *mới* thì OLE DB Destination; *thay đổi* thì Conditional Split → OLE DB Command (SCD1/SCD3) hoặc stored procedure (SCD2).
5. Đặt tên component theo kiểu `SRC - ...`, `DC - ...`, `LKP - ...`, `DST - ...` như nhóm 08.
6. **Mỗi người chỉ sửa package của mình**; không commit `.dtproj`, Master có đường dẫn máy cá nhân, hay file CSV.

### 1.5. Lịch tích hợp

1. Người 1 tạo sẵn 4 package rỗng P5–P8, commit trước để mọi người pull về.
2. Mỗi người làm package của mình → chạy thử → chụp màn hình Data Flow + số dòng.
3. Người 1 thêm Container 03/04/05 (Execute Package Task gọi P5–P8 + Execute SQL Aggregate) vào Master, chạy toàn bộ, commit.
4. Người 3 chạy script DQ check trên DW và chụp kết quả cho báo cáo.

---

## 2. So sánh Phương án A và Phương án B

| Tiêu chí | **A. P1–P4 + `stg_clean`** (`main`) | **B. Stage → DW trực tiếp** (`etl-theo-doi-tuong`) |
|---|---|---|
| Kiến trúc | CSV → `stg_raw` → **`stg_clean`** → DW (3 lớp, 2 chặng biến đổi) | CSV → `stg_raw` → DW (biến đổi trong **1 Data Flow** cho mỗi Dim/Fact) |
| **Góp ý 4** – staging → đích trong 1 data flow, không cắt khúc bỏ vào staging riêng | ⚠️ **Rủi ro**: `stg_clean` chính là "staging riêng" mà GV góp ý | ✅ Đáp ứng; giống cách nhóm 08 được GV đánh giá đúng |
| **Góp ý 5** – load tăng trưởng, Lookup | ⏳ Chưa có, phải làm trong P5–P8 | ✅ Đã có: cửa sổ `LoadFrom`/`LoadTo`, Lookup Dim, Lookup Fact |
| Khối lượng còn lại | **Nhiều**: 4 package mới (P5–P8) + Aggregate + tích hợp | **Ít**: chạy thử, sửa lỗi nếu có, chụp minh chứng, viết báo cáo |
| Phân công | Rõ ràng, mỗi người 1 package | Code đã có; phân công theo **kiểm thử – giải thích – báo cáo** |
| Công sức P1–P4 đã làm | Giữ nguyên package của từng người | Logic P1–P4 được chuyển vào các DF Load Dim/Fact; package P1–P4 bị bỏ |
| Độ dễ trình bày | Phải giải thích vì sao có 2 lớp staging | Dễ: mỗi Dim/Fact một flow thẳng hàng |
| Đã chạy thật chưa | Container 01–02 ✅; phần Dim/Fact chưa có | Validate thành công, **chưa chạy thật trong Visual Studio** (rủi ro: Sort 1,9 triệu dòng appearances) |
| Tài liệu | Mục 8 doc thiết kế vẫn bản cũ | Đã cập nhật mục 8, 9 + `Huong_dan_chay_ETL_SSIS.md` |

### 2.1. Nếu chọn Phương án B – phân công

| Người | Phần phụ trách (chạy, kiểm tra, giải thích, viết báo cáo) |
|---|---|
| 1 – Hiếu | DF DimClub, DimClub Other, DimPlayer (SCD1/2/3) + chạy toàn bộ Master |
| 2 – Hậu | DF DimCompetition, DimMatch, DimManager + 3 Dim tĩnh |
| 3 – Thi | DF FactTeamMatch, FactPlayerAppearance + Container 04 Aggregate + DQ check |
| 4 – Huyền | DF FactPlayerValuation, FactTransfer |

Mỗi người demo **nạp tăng trưởng** (đổi `LoadFrom`/`LoadTo`, chạy lại, số dòng chỉ tăng phần mới) cho phần của mình và chụp minh chứng.

---

## 3. Đề xuất

**Nên chọn Phương án B.**

- GV đã góp ý trực tiếp về việc "cắt khúc bỏ vào staging riêng"; cách làm của nhóm 08 (stage → đích trong 1 data flow) đã được xác nhận là đúng.
- Phương án A vẫn giữ đúng điểm bị góp ý và còn nhiều việc phải làm.
- Phương án B gần như xong phần code, chỉ cần chạy thử và chuẩn bị trình bày.

Nếu nhóm vẫn muốn giữ A (để mọi người giữ package P1–P4 của mình), nên **hỏi lại GV** xem tầng `stg_clean` có được chấp nhận không **trước khi** bắt tay làm P5–P8.
