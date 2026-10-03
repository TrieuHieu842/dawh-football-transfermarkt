# Hướng dẫn chạy ETL SSIS – Football Transfermarkt DWH

Tài liệu mô tả cách chạy thực tế toàn bộ quy trình ETL và cấu trúc chi tiết của package `Main_ETL_Master.dtsx`: các Control Flow, Data Flow và component bên trong.

- Package: `etl-ssis-transfermarkt/Football_DAWH_ETL_SSIS/Football_DAWH_ETL_SSIS/Main_ETL_Master.dtsx`
- Script SQL: `sql/00_create_staging_raw.sql`, `sql/01_create_dw.sql`
- Câu SQL tham khảo dùng trong package: `sql/etl_source_queries.sql` (không cần chạy)

---

## Mục lục

1. [Kiến trúc tổng quan](#1-kiến-trúc-tổng-quan)
2. [Cách chạy thực tế](#2-cách-chạy-thực-tế)
3. [Control Flow của Main_ETL_Master](#3-control-flow-của-main_etl_master)
4. [Data Flow và component](#4-data-flow-và-component)
5. [Kiểm tra kết quả](#5-kiểm-tra-kết-quả)
6. [Xử lý sự cố thường gặp](#6-xử-lý-sự-cố-thường-gặp)

---

## 1. Kiến trúc tổng quan

```
10 file CSV ──► stg_raw (football_dwh_staging) ──► Dim / Fact (football_dwh_dw) ──► Bảng tổng hợp
            Container 01                      Container 02 (Dim), 03 (Fact)     Container 04
```

| Lớp | Nội dung | Nguyên tắc |
|---|---|---|
| **Stage** (`stg_raw_*`) | Bản sao nguyên trạng 10 file CSV, mọi cột kiểu chuỗi | Không biến đổi; TRUNCATE rồi nạp lại mỗi lần chạy |
| **DW** (`dim_*`, `fact_*`) | Kho dữ liệu theo thiết kế Kimball | Chỉ chứa các thuộc tính, measure đã chọn lọc trong tài liệu thiết kế |
| **Tổng hợp** | `fact_club_season_summary`, `fact_player_season_summary` | Tính lại cho các mùa có dữ liệu trong cửa sổ nạp |

Nguyên tắc của phần ETL (Stage → DW):

- **Mỗi dim, mỗi fact là một Data Flow**, đi thẳng từ stage tới đích, không qua bảng trung gian.
- **OLE DB Source chỉ `SELECT CAST(cột AS NVARCHAR(n))`** đúng các cột đã chọn. Phép CAST là bắt buộc, vì SSIS đọc kiểu `NVARCHAR(MAX)` thành `DT_NTEXT` và không dùng được hàm chuỗi trên kiểu này.
- **Mọi xử lý đều là component SSIS:** làm sạch, ép kiểu, khử trùng, chuẩn hóa, kiểm tra, lọc cửa sổ nạp, Lookup, SCD.
- **Ngoại lệ duy nhất dùng SQL:** `value_change_eur` của FactPlayerValuation tính bằng `LAG`, vì SSIS không có hàm tương đương.
- **Nạp gia tăng:** fact không bị xóa. Mỗi lần chạy chỉ lấy sự kiện trong cửa sổ `LoadFrom`–`LoadTo`, và `LKP - Fact... (đã có chưa)` chặn các dòng đã nạp trước đó.

---

## 2. Cách chạy thực tế

### Bước 0. Chuẩn bị (một lần trên mỗi máy)

| Việc | Cách làm |
|---|---|
| Bật SQL Server 2022 | PowerShell (Run as Administrator): `net start MSSQLSERVER` |
| Dữ liệu nguồn | Tải bộ Kaggle *davidcariboo/player-scores*, chép đủ **10 file CSV** vào `data/raw/` |
| Công cụ | Visual Studio 2022 + extension *SQL Server Integration Services Projects 2022*; SQL Server Management Studio (SSMS) |

10 file CSV cần có: `appearances`, `club_games`, `clubs`, `competitions`, `countries`, `games`, `national_teams`, `player_valuations`, `players`, `transfers`.

### Bước 1. Tạo database staging (SSMS)

Kết nối Server name `localhost` (Windows Authentication), mở và chạy (F5) file **`sql/00_create_staging_raw.sql`**. Script này:

- Tạo 2 database `football_dwh_staging` và `football_dwh_dw` nếu chưa có.
- Tạo 10 bảng `dbo.stg_raw_*`; mọi cột là `NVARCHAR(MAX)`, kèm `batch_id`, `loaded_at`, `source_file`.
- Tạo bảng `dbo.etl_reject` để ghi các dòng lỗi.

### Bước 2. Tạo kho dữ liệu (SSMS)

Chạy **`sql/01_create_dw.sql`**. Script này:

- Tạo 8 dim, 4 fact, 2 bảng tổng hợp, `etl_load_window` (cửa sổ nạp), `etl_batch`.
- Sinh sẵn 3 dim tĩnh: **Dim_Date** (1990–2030), **Dim_Season** (41 mùa), **Dim_Transfer_Type** (6 loại phí).
- Thêm dòng **Unknown (key = -1)** cho mọi dim.
- Tạo 2 stored procedure cho SCD Type 2: `usp_DimClub_NewVersion`, `usp_DimPlayer_NewVersion`.

> ⚠️ Script `00` và `01` **xóa và tạo lại** bảng. Chỉ chạy lại khi muốn làm lại từ đầu. Các lần nạp sau (kể cả demo nạp gia tăng) **không** chạy lại 2 script này.

### Bước 3. Mở project trong Visual Studio

1. **File → Open → Project/Solution** → chọn `etl-ssis-transfermarkt\Football_DAWH_ETL_SSIS\Football_DAWH_ETL_SSIS.slnx`.
2. Double-click `Main_ETL_Master.dtsx` trong Solution Explorer.
3. Kiểm tra khung **Connection Managers** ở cuối màn hình thiết kế:
   - 2 kết nối OLE DB (`...football_dwh_staging`, `...football_dwh_dw`): Server name = `localhost`, bấm **Test Connection**.
   - 10 kết nối `FFCM ...`: double-click và kiểm tra **File name** trỏ đúng tới `data\raw\<tên>.csv` trên máy.
4. Package được sinh bằng code nên các khối chưa có vị trí sắp sẵn. Vào **Format → Auto Layout → Diagram** ở tab Control Flow, rồi làm tương tự trong từng Data Flow cho dễ nhìn.

### Bước 4. Đặt cửa sổ nạp

Mở **SSIS → Variables** (hoặc chuột phải vùng trống → *Variables*) và sửa cột **Value**:

| Biến | Ý nghĩa | Mặc định |
|---|---|---|
| `LoadFrom` | Chỉ nạp sự kiện (trận, lần ra sân, định giá, chuyển nhượng) từ ngày này | 1/1/1900 |
| `LoadTo` | Chỉ nạp sự kiện đến ngày này | 12/31/9999 (nạp hết) |

Dim luôn được nạp đầy đủ. Dòng mới được thêm, dòng thay đổi được cập nhật theo SCD.

### Bước 5. Chạy package

| Muốn chạy | Cách làm |
|---|---|
| **Toàn bộ** (01 → 02 → 03 → 04) | Nhấn **F5** (Start Debugging) khi đang mở `Main_ETL_Master.dtsx` |
| Một container | Chuột phải container → **Execute Container** |
| Một Data Flow hoặc task | Chuột phải khối → **Execute Task** |

Trong lúc chạy:

- Khối **vàng** là đang chạy, **✅ xanh** là xong, **❌ đỏ** là lỗi.
- Double-click một Data Flow để xem **số dòng trên từng mũi tên**. Nên chụp màn hình phần này cho báo cáo.
- Nhật ký nằm ở tab **Progress**; tên tab đổi thành *Execution Results* sau khi dừng.
- Chạy xong, nhấn **Shift+F5** để thoát chế độ debug.

Container 01 và Container 03 chạy lâu nhất, vì có bảng appearances 1,9 triệu dòng.

### Bước 6. Demo nạp gia tăng

| Lần chạy | `LoadTo` | Kết quả mong đợi |
|---|---|---|
| 1 | 12/31/2018 | Dim nạp đầy đủ; fact chỉ có sự kiện đến hết 2018 |
| 2 | 12/31/2021 | Fact **chỉ thêm** dữ liệu 2019–2021; dòng của lần 1 bị Lookup fact chặn |
| 3 | 12/31/9999 | Nạp phần còn lại (từ 2022) |
| 4 | 12/31/9999 (chạy lại) | Fact **không tăng dòng nào**; dim chỉ cập nhật nếu nguồn thay đổi |

Sau mỗi lần chạy, chạy câu truy vấn ở [mục 5](#5-kiểm-tra-kết-quả) để thấy số dòng tăng dần.

### Chạy ngoài Visual Studio (tùy chọn)

`dtexec` và SQL Agent chỉ chạy được khi SQL Server đã cài thành phần **Integration Services**. Cách làm:

1. Chạy lại SQL Server Setup → *Add features* → chọn **Integration Services**.
2. Trong SSMS: tạo **Integration Services Catalog (SSISDB)**.
3. Trong Visual Studio: chuột phải project → **Deploy** lên SSISDB.
4. Chạy package từ SSMS (*Integration Services Catalogs → Execute*) hoặc lên lịch bằng SQL Server Agent.

Với đồ án, chạy trong Visual Studio là đủ.

---

## 3. Control Flow của Main_ETL_Master

```
Container 01 - Load Source to Stage
        │
        ▼
Container 02 - Load Dimensions
        │
        ▼
Container 03 - Load Facts
        │
        ▼
Container 04 - Aggregate
```

Dim phải nạp xong trước, vì fact cần Lookup sang dim để lấy surrogate key.

| Container | Task bên trong (theo thứ tự chạy) | Kết nối |
|---|---|---|
| **01 - Load Source to Stage** | `SQL_Truncate_Staging_Raw` → 10 Data Flow `DFT_Load_stg_raw_*` (chạy song song) | Flat File → Staging |
| **02 - Load Dimensions** | `DF - Load DimCompetition` → `DF - Load DimClub` → `DF - Load DimClub (CLB chỉ có trong fact)` → `DF - Load DimPlayer` → `DF - Load DimMatch` → `DF - Load DimManager` | Staging → DW |
| **03 - Load Facts** | `SQL - Set Load Window` → `DF - Load FactTeamMatch` → `DF - Load FactPlayerAppearance` → `DF - Load FactPlayerValuation` → `DF - Load FactTransfer` | Staging → DW |
| **04 - Aggregate** | `SQL - Rebuild Season Summary` | DW |

### Các Execute SQL Task

| Task | Việc làm |
|---|---|
| `SQL_Truncate_Staging_Raw` | TRUNCATE 10 bảng `stg_raw_*`, để nạp lại không bị nhân đôi |
| `SQL - Set Load Window` | Ghi `LoadFrom`/`LoadTo` vào `etl_load_window`; xóa reject cũ của các bảng fact; cập nhật `is_future_date` trong Dim_Date |
| `SQL - Rebuild Season Summary` | Xóa và tính lại `fact_club_season_summary` (thắng/hòa/thua, điểm = 3 × thắng + hòa) và `fact_player_season_summary`, chỉ cho các mùa có sự kiện trong cửa sổ vừa nạp |

---

## 4. Data Flow và component

### Ký hiệu

| Viết tắt | Component SSIS |
|---|---|
| **SRC** | OLE DB Source |
| **DC** | Derived Column |
| **CONV** | Data Conversion |
| **SORT** | Sort (bật *Remove rows with duplicate sort values*) |
| **UA** | Union All |
| **LKP** | Lookup |
| **CSPL** | Conditional Split |
| **CMD** | OLE DB Command |
| **DST** | OLE DB Destination |

### 4.1. Container 01 – Load Source to Stage

10 Data Flow cùng một mẫu, tên `DFT_Load_stg_raw_<bảng>`:

```
Flat File Source ──► Derived Column ──► OLE DB Destination
 (đọc CSV, UTF-8)    (thêm batch_id,     (stg_raw_<bảng>)
                      loaded_at, source_file)
```

### 4.2. Container 02 – Load Dimensions

Mẫu chung: **SRC (stage) → làm sạch, ép kiểu, khử trùng → chuẩn hóa → LKP Dim**. Dòng chưa có thì **DST** (insert); dòng đã có mà thay đổi thì **CSPL** xác định loại thay đổi rồi **CMD** cập nhật theo SCD.

#### DF - Load DimCompetition (9 khối – SCD1)

```
SRC - stg Competitions → DC - Clean Text → SORT - Remove Duplicates → LKP - stg Countries
→ DC - Standardize → LKP - DimCompetition
     ├─(No Match)→ DST - DimCompetition
     └─(Match)───→ CSPL - Changed ─(Changed)→ CMD - Update DimCompetition (SCD1)
```

| Component | Việc làm |
|---|---|
| SRC - stg Competitions | 7/11 cột: `competition_id`, `name`, `type`, `sub_type`, `country_id`, `country_name`, `confederation` |
| DC - Clean Text | TRIM, bỏ ký tự `\x00A0`, chuỗi rỗng → NULL |
| SORT - Remove Duplicates | Khử trùng theo `competition_id` |
| LKP - stg Countries | Lấy tên quốc gia từ `stg_raw_countries` khi giải thiếu tên quốc gia |
| DC - Standardize | Giá trị mặc định "Không xác định"; giải quốc tế ghi "International"; chuẩn hóa liên đoàn `europa → UEFA`, `asien → AFC`, `afrika → CAF`, `amerika → Americas` |
| LKP - DimCompetition | Tra `competition_id`, trả về `competition_key` và các giá trị đang lưu (`old_*`) |
| DST - DimCompetition | Giải mới thì insert |
| CSPL - Changed + CMD | So giá trị mới với giá trị cũ; khác thì `UPDATE` ghi đè (SCD1) |

#### DF - Load DimClub (18 khối – SCD1 + SCD2 + SCD3)

```
SRC - stg Clubs ─────────► DC - Type Club ──────────┐
SRC - stg National Teams ─► DC - Type National Team ─┴─► UA - Clubs and National Teams
→ DC - Clean Text → CONV - Data Types ─(lỗi)→ DC - Reject Info → DST - etl_reject
→ SORT - Remove Duplicates → LKP - DimCompetition (League) → DC - Standardize → LKP - DimClub
     ├─(No Match)→ DST - DimClub
     └─(Match)───→ CSPL - Change Type ─(SCD2 Stadium)→ CMD - SCD2 New Version
                                      ─(SCD3 League)─→ CMD - SCD3 Update League
                                      ─(SCD1)────────→ CMD - SCD1 Update
```

| Component | Việc làm |
|---|---|
| SRC - stg Clubs | 5/17 cột của clubs: `club_id`, `name`, `domestic_competition_id`, `stadium_name`, `stadium_seats` |
| SRC - stg National Teams | 4/17 cột của national_teams: `national_team_id`, `name`, `country_name`, `confederation` |
| DC - Type Club / Type National Team | Gán `club_type` = `Club` / `National Team` |
| UA - Clubs and National Teams | Gộp 2 nguồn thành 1 luồng |
| CONV - Data Types | `club_id`, `stadium_seats` → INT; dòng lỗi vào `etl_reject` |
| LKP - DimCompetition (League) | Lấy tên giải VĐQG, quốc gia, liên đoàn của CLB từ Dim_Competition |
| DC - Standardize | `stadium_capacity_band` (`< 20.000`, `20.000-39.999`, `40.000-59.999`, `>= 60.000`, Không xác định); quốc gia/liên đoàn (CLB lấy theo giải, đội tuyển lấy của chính đội; `CONCACAF`, `CONMEBOL → Americas`) |
| LKP - DimClub | Tra phiên bản **hiện tại** (`is_current = 1`) theo `club_id` |
| CMD - SCD2 New Version | Đổi sân hoặc sức chứa: gọi `usp_DimClub_NewVersion` để đóng phiên bản cũ và thêm phiên bản mới |
| CMD - SCD3 Update League | Đổi giải: chuyển giải hiện tại sang `previous_league_name`, ghi giải mới |
| CMD - SCD1 Update | Đổi tên, loại, quốc gia, liên đoàn: ghi đè |

#### DF - Load DimClub (CLB chỉ có trong fact) (15 khối)

Thêm vào Dim_Club các CLB chỉ xuất hiện trong dữ liệu sự kiện (đội hạng dưới, CLB nước ngoài) với `club_type = Other`, để fact không bị rơi về khóa -1.

```
SRC - stg Transfers (CLB đi) ──┐
SRC - stg Transfers (CLB đến) ─┤
SRC - stg Games (Đội nhà) ─────┼─► UA - Clubs In Facts → DC - Clean Text
SRC - stg Games (Đội khách) ───┤   → CONV - Data Types ─(lỗi)→ DC - Reject Info → DST - etl_reject
SRC - stg Valuations (CLB) ────┘   → CSPL - Has Club Id → SORT - Remove Duplicates → LKP - DimClub
                                   ─(No Match)→ DC - Other Club Attributes → DST - DimClub (Other)
```

#### DF - Load DimPlayer (12 khối – SCD1 + SCD2)

```
SRC - stg Players → DC - Clean Text → CONV - Data Types ─(lỗi)→ DC - Reject Info → DST - etl_reject
→ SORT - Remove Duplicates → DC - Standardize and Bands → LKP - DimPlayer
     ├─(No Match)→ DST - DimPlayer
     └─(Match)───→ CSPL - Change Type ─(SCD2 Position Agent)→ CMD - SCD2 New Version
                                      ─(SCD1)───────────────→ CMD - SCD1 Update
```

| Component | Việc làm |
|---|---|
| SRC - stg Players | 12/26 cột: `player_id`, `name`, `date_of_birth`, `country_of_birth`, `country_of_citizenship`, `position`, `sub_position`, `foot`, `height_in_cm`, `agent_name`, `contract_expiration_date`, `international_caps` |
| DC - Clean Text | Làm sạch; ngày `1989-02-06 00:00:00` → `1989-02-06` |
| CONV - Data Types | ID → INT, ngày → DATE, chiều cao → SMALLINT, số trận đội tuyển → INT |
| DC - Standardize and Bands | `height_band` (ngoài 150–220 cm → Không xác định); `international_caps_band` (trống → Không xác định, 0 → Chưa khoác áo); `contract_expiry_year`; giá trị mặc định |
| CSPL - Change Type | **SCD2** khi đổi vị trí, vị trí chi tiết hoặc người đại diện; **SCD1** khi đổi các thuộc tính còn lại |
| CMD - SCD2 New Version / SCD1 Update | Gọi `usp_DimPlayer_NewVersion` / `UPDATE` ghi đè |

#### DF - Load DimMatch (11 khối – SCD1)

```
SRC - stg Games → DC - Clean Text → CONV - Data Types ─(lỗi)→ DC - Reject Info → DST - etl_reject
→ SORT - Remove Duplicates → DC - Standardize and Bands → LKP - DimMatch
     ├─(No Match)→ DST - DimMatch
     └─(Match)───→ CSPL - Changed → CMD - Update DimMatch (SCD1)
```

- SRC lấy 7/23 cột của games: `game_id`, `round`, `stadium`, `referee`, 2 sơ đồ chiến thuật, `attendance`.
- DC - Standardize and Bands:
  - `round_type`: chứa "Matchday" → Matchday; chứa "Group" → Group stage; đúng bằng "Final" → Final; còn lại → Knockout.
  - `attendance_band`: 5 nhóm số khán giả.

#### DF - Load DimManager (8 khối)

```
SRC - stg Club Games (HLV đội) ─────┐
SRC - stg Club Games (HLV đối thủ) ─┴─► UA - Managers → DC - Clean Text → CSPL - Has Name
→ SORT - Remove Duplicates → LKP - DimManager ─(No Match)→ DST - DimManager
```

### 4.3. Container 03 – Load Facts

Mẫu chung của 4 Data Flow:

```
SRC (stage) → [LKP stage] → DC - Clean Text → CONV - Data Types ─(lỗi)→ reject
→ CSPL - Validate and Window ─(Reject)→ reject ; (Out Of Window) bỏ qua
→ SORT - Remove Duplicates → DC tính measure, DateKey
→ chuỗi LKP Dim → DC - Unknown Keys → LKP Fact (đã có chưa) ─(No Match)→ DST Fact
```

- **CSPL - Validate and Window**: loại dòng sai quy tắc và bỏ qua dòng có ngày nằm ngoài `[LoadFrom, LoadTo]`.
- **DC - Unknown Keys**: khóa nào Lookup không tìm thấy thì gán -1, trỏ về dòng Unknown của dim.
- **LKP Fact (đã có chưa)**: chỉ cho đi tiếp các dòng chưa có trong fact. Đây là bước đảm bảo nạp gia tăng không bị trùng.
- Mỗi fact có 2 nhánh lỗi: **Conversion** (sai kiểu dữ liệu) và **Rule** (vi phạm quy tắc), đều qua `DC - Reject Info` rồi vào `DST - etl_reject`.

#### DF - Load FactTeamMatch (21 khối)

| # | Component | Việc làm |
|---|---|---|
| 1 | SRC - stg Club Games | 9/11 cột của club_games |
| 2 | LKP - stg Games (ngày, mùa, giải) | Lấy ngày, mùa, giải của trận từ `stg_raw_games` |
| 3 | DC - Clean Text | Làm sạch; vị trí xếp hạng `-1` hoặc trống → NULL |
| 4 | CONV - Data Types | ID → INT; bàn thắng, vị trí, mùa → SMALLINT; ngày → DATE |
| 5 | CSPL - Validate and Window | Thiếu khóa, tỉ số hoặc không tìm thấy trận → reject; ngoài cửa sổ → bỏ qua |
| 6 | SORT - Remove Duplicates | Theo `(game_id, club_id)` |
| 7 | DC - Calculate Measures and DateKey | `date_key` (YYYYMMDD), `is_home`, `is_win`, `is_draw`, `is_loss`, `is_clean_sheet` (**tính lại từ tỉ số**) |
| 8–14 | LKP - DimSeason, DimCompetition, DimMatch, DimClub, DimClub Opponent, DimManager, DimManager Opponent | Lấy 7 surrogate key |
| 15 | DC - Unknown Keys | Khóa không tìm thấy → -1 |
| 16 | LKP - FactTeamMatch (đã có chưa) | Tra theo `(match_key, club_key)` |
| 17 | DST - FactTeamMatch | Ghi `goals_for`, `goals_against`, các cờ, `league_position` |
| + | DC - Reject Info / DST - etl_reject (Conversion, Rule) | 2 nhánh lỗi |

#### DF - Load FactPlayerAppearance (19 khối)

```
SRC - stg Appearances → LKP - stg Games (mùa) → DC - Clean Text → CONV - Data Types
→ CSPL - Validate and Window → SORT - Remove Duplicates → DC - DateKey and Count
→ LKP - DimSeason → LKP - DimCompetition → LKP - DimMatch → LKP - DimPlayer → LKP - DimClub
→ DC - Unknown Keys → LKP - FactPlayerAppearance (đã có chưa) → DST - FactPlayerAppearance
```

- SRC lấy 11/13 cột. Bỏ `player_name` (đã có ở Dim_Player) và `player_current_club_id` (CLB hiện tại, không phải CLB lúc thi đấu).
- CSPL - Validate and Window: thiếu khóa, `minutes_played` ngoài 0–130, số bàn/kiến tạo/thẻ âm → reject. Dữ liệu hiện tại có 3 dòng 135, 135 và 148 phút.
- DC - DateKey and Count: `date_key`, `appearance_count = 1`.
- Ghi chú: SORT trên 1,9 triệu dòng tốn RAM và thời gian. Khi nạp theo đợt, số dòng qua Sort ít hơn.

#### DF - Load FactPlayerValuation (16 khối)

```
SRC - stg Player Valuations → DC - Clean Text → CONV - Data Types → CSPL - Validate and Window
→ SORT - Remove Duplicates → DC - DateKey and Count → LKP - DimPlayer (kèm ngày sinh)
→ LKP - DimClub → LKP - DimCompetition → DC - Age and Unknown Keys
→ LKP - FactPlayerValuation (đã có chưa) → DST - FactPlayerValuation
```

- SRC lấy 5/6 cột (bỏ `current_club_name`). Riêng `value_change_eur` = giá trị lần này − lần trước, tính bằng `LAG` trong câu nguồn.
- DC - Age and Unknown Keys: `age_at_valuation` tính từ ngày sinh lấy qua `LKP - DimPlayer`.

#### DF - Load FactTransfer (18 khối)

```
SRC - stg Transfers → DC - Clean Text → CONV - Data Types → CSPL - Validate and Window
→ SORT - Remove Duplicates → DC - Fee Attributes and DateKey
→ LKP - DimSeason → LKP - DimPlayer → LKP - DimClub From → LKP - DimClub To → LKP - DimTransferType
→ DC - Age and Unknown Keys → LKP - FactTransfer (đã có chưa) → DST - FactTransfer
```

| Component | Việc làm |
|---|---|
| SRC - stg Transfers | 7/10 cột; bỏ 3 cột tên (cầu thủ, CLB đi, CLB đến) |
| CONV - Data Types | Phí, giá trị thị trường dạng `'700000.000'` → DECIMAL(19,3) |
| DC - Fee Attributes and DateKey | `transfer_fee_eur`, `market_value_eur` (BIGINT); `fee_status` (Có phí / Miễn phí hoặc cho mượn / **Không công bố** khi phí trống); `fee_band`; `fee_premium_eur` = phí − giá trị thị trường; `date_key` |
| LKP - DimSeason | Tra theo mùa dạng `24/25` (`season_short`) |
| LKP - DimTransferType | Tra theo `(fee_status, fee_band)` |
| DC - Age and Unknown Keys | `age_at_transfer`; khóa không tìm thấy → -1 |

---

## 5. Kiểm tra kết quả

Chạy trong SSMS sau mỗi lần chạy package:

```sql
USE football_dwh_dw;

-- Số dòng các bảng
SELECT 'dim_competition' AS bang, COUNT(*) AS so_dong FROM dbo.dim_competition
UNION ALL SELECT 'dim_club', COUNT(*) FROM dbo.dim_club
UNION ALL SELECT 'dim_player', COUNT(*) FROM dbo.dim_player
UNION ALL SELECT 'dim_match', COUNT(*) FROM dbo.dim_match
UNION ALL SELECT 'dim_manager', COUNT(*) FROM dbo.dim_manager
UNION ALL SELECT 'fact_team_match', COUNT(*) FROM dbo.fact_team_match
UNION ALL SELECT 'fact_player_appearance', COUNT(*) FROM dbo.fact_player_appearance
UNION ALL SELECT 'fact_player_valuation', COUNT(*) FROM dbo.fact_player_valuation
UNION ALL SELECT 'fact_transfer', COUNT(*) FROM dbo.fact_transfer
UNION ALL SELECT 'fact_club_season_summary', COUNT(*) FROM dbo.fact_club_season_summary
UNION ALL SELECT 'fact_player_season_summary', COUNT(*) FROM dbo.fact_player_season_summary;

-- Cửa sổ vừa nạp
SELECT * FROM dbo.etl_load_window;

-- Dòng lỗi
SELECT source_table, reason, COUNT(*) AS so_dong
FROM football_dwh_staging.dbo.etl_reject
GROUP BY source_table, reason;

-- Mỗi trận có đúng 2 dòng trong FactTeamMatch
SELECT COUNT(*) AS so_tran_loi
FROM (SELECT match_key FROM dbo.fact_team_match GROUP BY match_key HAVING COUNT(*) <> 2) x;
```

Kết quả dự kiến khi nạp đủ (`LoadTo = 12/31/9999`):

| Bảng | Số dòng (không tính dòng Unknown) |
|---|---:|
| dim_competition | 65 |
| dim_club | khoảng 18.676 (796 CLB + 124 đội tuyển + 17.756 CLB `Other`) |
| dim_player | 50.149 |
| dim_match | 88.958 |
| dim_manager | 7.028 |
| fact_team_match | 177.916 |
| fact_player_appearance | 1.894.347 (+ 3 dòng trong `etl_reject`) |
| fact_player_valuation | 656.301 |
| fact_transfer | 175.165 (61.526 phí NULL – không công bố) |

---

## 6. Xử lý sự cố thường gặp

| Hiện tượng | Nguyên nhân | Cách xử lý |
|---|---|---|
| Không kết nối được `localhost` | Dịch vụ SQL Server 2022 đang tắt | `net start MSSQLSERVER` (quyền Administrator) |
| Task của Container 01 lỗi đọc CSV | Đường dẫn `FFCM ...` sai hoặc file bị đổi ký tự xuống dòng (CRLF) | Sửa File name trong Connection Manager; dùng file CSV gốc tải từ Kaggle |
| Số dòng stage gấp đôi | Chạy Container 01 không qua `SQL_Truncate_Staging_Raw` | Chạy cả container, không chạy lẻ từng `DFT_Load_stg_raw_*` |
| Lookup báo không tìm thấy bảng | Chưa chạy `sql/01_create_dw.sql` | Chạy script tạo DW (Bước 2) |
| Fact không tăng dòng khi chạy lại | **Đúng thiết kế**: Lookup fact chặn dòng đã có | Muốn nạp lại từ đầu thì chạy lại `sql/01_create_dw.sql` |
| `DF - Load FactPlayerAppearance` chạy rất lâu, tốn RAM | SORT trên 1,9 triệu dòng | Nạp theo đợt nhỏ (đặt `LoadTo`) hoặc tăng RAM cho máy |
| Khối báo ❌ | Lỗi lúc thực thi | Mở tab **Progress**, đọc dòng lỗi màu đỏ đầu tiên |
