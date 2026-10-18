# Diễn giải chi tiết package SSIS `Main_ETL_Master.dtsx`

> Tài liệu được sinh tự động từ file `Main_ETL_Master.dtsx`: toàn bộ câu SQL, biểu thức, cấu hình Lookup, Conditional Split, Sort, Aggregate và ánh xạ cột đều lấy trực tiếp từ package nên khớp với bản đang chạy. Tên container, Data Flow và component được đặt **theo chức năng** (việc component đó làm). Phần *vai trò / ý nghĩa* là diễn giải của nhóm.

## Mục lục

1. Tổng quan package
2. 01 - Trích xuất file CSV vào Staging
3. 02 - Làm sạch và nạp Dimension
4. 03 - Làm sạch tính toán và nạp Fact
5. Tính toán ở đâu: ETL, kho hay tầng phân tích
6. Các quy ước xử lý dùng chung

---

## 1. Tổng quan package

Package gồm **3 Sequence Container chạy nối tiếp**, đi đúng thứ tự **Extract → Transform → Load**. Mọi phép tính **ở mức từng dòng** (cờ, điểm, hiệu số, tuổi, phí chênh, biến động giá trị, band) đều nằm **trong ETL, trước khi ghi vào kho**. Kho chỉ lưu fact ở grain chi tiết nhất, không chạy SQL tính toán sau khi nạp. Phép **tổng hợp** (theo mùa, CLB, HLV…) do tầng phân tích SSAS / Power BI thực hiện.

```
10 file CSV ──01──► stg_raw_* ──02──► 8 Dimension ──03──► 4 Fact chi tiết ──► SSAS / Power BI (tổng hợp)
      (Extract)  (football_dwh_staging)   (Transform + Load vào football_dwh_dw)
```

### 1.1. Control Flow cấp package

| Thứ tự | Container | Nội dung | Giai đoạn ETL |
|---|---|---|---|
| 1 | **01 - Trích xuất file CSV vào Staging** | 1 Execute SQL + 10 Data Flow | Extract: CSV → Staging |
| 2 | **02 - Làm sạch và nạp Dimension** | 6 Data Flow | Transform + Load: Staging → Dimension |
| 3 | **03 - Làm sạch tính toán và nạp Fact** | 3 Execute SQL + 4 Data Flow | Transform + Load: Staging → Fact, ghi nhật ký lần chạy |

Ràng buộc thứ tự (Precedence Constraint, *Success*): `01 - Trích xuất file CSV vào Staging` → `02 - Làm sạch và nạp Dimension`; `02 - Làm sạch và nạp Dimension` → `03 - Làm sạch tính toán và nạp Fact`. Dimension phải nạp trước fact vì fact cần tra surrogate key từ dimension.

### 1.2. Biến (Variables)

| Biến | Kiểu | Giá trị hiện tại | Dùng ở đâu |
|---|---|---|---|
| `BatchID` | String | BATCH_20261018_224515 | Mã lần chạy `BATCH_yyyyMMdd_HHmmss`, tính từ `System::StartTime` nên cố định suốt một lần chạy và khác nhau giữa các lần chạy; ghi vào cột `batch_id` của Staging, dimension, fact và `etl_batch` |
| `LoadedAt` | DateTime | 10/18/2026 10:45:19 PM | Thời điểm nạp, ghi vào cột `loaded_at` của Staging |
| `LoadFrom` | DateTime | 1/1/1900 | Ngày bắt đầu cửa sổ nạp: *Kiểm tra hợp lệ và cửa sổ nạp* của 4 Data Flow fact chi tiết; *Ghi cửa sổ nạp gia tăng* |
| `LoadTo` | DateTime | 12/31/9999 | Ngày kết thúc cửa sổ nạp |

**Cách đổi:** Control Flow → click vùng trống → icon **Variables** (góc phải trên) → sửa cột *Value*.

### 1.3. Connection Managers

| Tên | Loại | Trỏ tới |
|---|---|---|
| `FFCM appearances` | Flat File | file `appearances.csv` |
| `FFCM clubs` | Flat File | file `clubs.csv` |
| `FFCM club_games` | Flat File | file `club_games.csv` |
| `FFCM competitions` | Flat File | file `competitions.csv` |
| `FFCM countries` | Flat File | file `countries.csv` |
| `FFCM games` | Flat File | file `games.csv` |
| `FFCM national_teams` | Flat File | file `national_teams.csv` |
| `FFCM players` | Flat File | file `players.csv` |
| `FFCM player_valuations` | Flat File | file `player_valuations.csv` |
| `FFCM tranfers` | Flat File | file `transfers.csv` |
| `localhost.football_dwh_dw` | OLE DB | database `football_dwh_dw` |
| `localhost.football_dwh_staging` | OLE DB | database `football_dwh_staging` |

Flat File Connection đọc mã UTF-8 (code page 65001), dấu nháy kép làm text qualifier, dòng đầu là tên cột, mọi cột đọc dạng chuỗi.

---

## 2. 01 - Trích xuất file CSV vào Staging

**Mục đích (Extract):** chép nguyên trạng 10 file CSV vào 10 bảng `stg_raw_*` của `football_dwh_staging`. Không biến đổi giá trị; mỗi lần chạy xóa sạch rồi nạp lại.

### 2.1. Control Flow

```
Xóa dữ liệu cũ trong Staging
   ├──► Chép file appearances vào Staging
   ├──► Chép file club_games vào Staging
   ├──► Chép file clubs vào Staging
   ├──► Chép file competitions vào Staging
   ├──► Chép file countries vào Staging
   ├──► Chép file games vào Staging
   ├──► Chép file national_teams vào Staging
   ├──► Chép file player_valuations vào Staging
   ├──► Chép file players vào Staging
   └──► Chép file transfers vào Staging
```
(10 Data Flow chạy song song sau khi xóa dữ liệu cũ)

**Xóa dữ liệu cũ trong Staging** · *Execute SQL Task* — kết nối `localhost.football_dwh_staging`. Xóa dữ liệu cũ để chạy lại không bị nhân đôi:

```sql
TRUNCATE TABLE dbo.stg_raw_appearances;
TRUNCATE TABLE dbo.stg_raw_club_games;
TRUNCATE TABLE dbo.stg_raw_clubs;
TRUNCATE TABLE dbo.stg_raw_competitions;
TRUNCATE TABLE dbo.stg_raw_countries;
TRUNCATE TABLE dbo.stg_raw_games;
TRUNCATE TABLE dbo.stg_raw_national_teams;
TRUNCATE TABLE dbo.stg_raw_player_valuations;
TRUNCATE TABLE dbo.stg_raw_players;
TRUNCATE TABLE dbo.stg_raw_transfers;
```

### 2.2. Data Flow `Chép file <tên> vào Staging` (10 Data Flow cùng một mẫu)

```
Đọc file CSV ──► Thêm cột truy vết ──► Ghi vào bảng Staging
(Flat File Source) (Derived Column)    (OLE DB Destination)
```

**Thêm cột truy vết** (ví dụ của `Chép file appearances vào Staging`; `source_file` đổi theo từng file):

- `batch_id` (DT_WSTR(30)) = `@[User::BatchID]`
- `loaded_at` (DT_DATE) = `@[User::LoadedAt]`
- `source_file` (DT_WSTR(15)) = `"appearances.csv"`

| Data Flow | File nguồn (Connection) | Bảng Staging | Số cột nạp |
|---|---|---|---|
| `Chép file appearances vào Staging` | `FFCM appearances` | `[dbo].[stg_raw_appearances]` | 16 |
| `Chép file club_games vào Staging` | `FFCM club_games` | `[dbo].[stg_raw_club_games]` | 14 |
| `Chép file clubs vào Staging` | `FFCM clubs` | `[dbo].[stg_raw_clubs]` | 20 |
| `Chép file competitions vào Staging` | `FFCM competitions` | `[dbo].[stg_raw_competitions]` | 14 |
| `Chép file countries vào Staging` | `FFCM countries` | `[dbo].[stg_raw_countries]` | 11 |
| `Chép file games vào Staging` | `FFCM games` | `[dbo].[stg_raw_games]` | 26 |
| `Chép file national_teams vào Staging` | `FFCM national_teams` | `[dbo].[stg_raw_national_teams]` | 20 |
| `Chép file player_valuations vào Staging` | `FFCM player_valuations` | `[dbo].[stg_raw_player_valuations]` | 9 |
| `Chép file players vào Staging` | `FFCM players` | `[dbo].[stg_raw_players]` | 29 |
| `Chép file transfers vào Staging` | `FFCM tranfers` | `[dbo].[stg_raw_transfers]` | 13 |

*Ghi vào bảng Staging* dùng chế độ *Table or view – fast load* (TABLOCK, CHECK_CONSTRAINTS, ROWS_PER_BATCH = 10000).

---

## 3. 02 - Làm sạch và nạp Dimension

**Mục đích (Transform + Load):** làm sạch, chuẩn hóa và nạp 6 dimension lấy từ nguồn (3 dimension tĩnh Date, Season, Transfer Type đã được script `01_create_dw.sql` sinh sẵn). Bản ghi mới thì thêm, bản ghi đổi thì xử lý theo SCD.

### 3.1. Control Flow

```
Nạp Dim_Competition (SCD1)
   ──► Nạp Dim_Club (SCD1 SCD2 SCD3)
   ──► Bổ sung CLB chỉ có trong Fact vào Dim_Club
   ──► Nạp Dim_Player (SCD1 SCD2)
   ──► Nạp Dim_Match (SCD1)
   ──► Nạp Dim_Manager
```

Thứ tự: Dim_Competition có trước để Dim_Club tra tên giải VĐQG; Dim_Club (từ clubs.csv) có trước để bước bổ sung CLB *Other* biết CLB nào đã tồn tại.

### 3.2. Các Data Flow

#### 3.2.1. Nạp Dim_Competition (SCD1)

| Đích | Cách nạp | Số component |
|---|---|---|
| `Dim_Competition` | SCD Type 1 | 9 |

Nạp danh sách giải đấu từ `stg_raw_competitions`. Giải mới được thêm vào; giải đã có mà thuộc tính thay đổi thì ghi đè (SCD1). Tên quốc gia còn thiếu được bổ sung từ `stg_raw_countries`; giải quốc tế ghi `International`; tên liên đoàn được chuẩn hóa (EUROPA → UEFA, ASIEN → AFC…).

**Luồng dữ liệu** (component nguồn ──[output]──► component đích):

```
Đọc giải đấu từ Staging                          ────► Làm sạch chuỗi
Làm sạch chuỗi                                   ────► Loại trùng theo competition_id
Loại trùng theo competition_id                   ────► Bổ sung tên quốc gia từ countries
Bổ sung tên quốc gia từ countries                ── [Lookup Match Output]──► Chuẩn hóa tên quốc gia và liên đoàn
Chuẩn hóa tên quốc gia và liên đoàn              ────► Kiểm tra giải đã có trong kho
Kiểm tra giải đã có trong kho                    ── [Lookup No Match Output]──► Thêm giải mới vào Dim_Competition
Kiểm tra giải đã có trong kho                    ── [Lookup Match Output]──► Tìm giải có thuộc tính thay đổi
Tìm giải có thuộc tính thay đổi                  ── [Changed]──► Ghi đè thay đổi SCD1
```

**Chi tiết từng component:**

**3.2.1.1. Đọc giải đấu từ Staging** · *OLE DB Source*

Đọc dữ liệu từ Staging. Câu SQL chỉ `CAST` các cột cần dùng sang `NVARCHAR(n)`: bảng stage lưu `NVARCHAR(MAX)`, SSIS đọc kiểu này thành `DT_NTEXT` và không áp dụng được hàm chuỗi, nên phải đổi sang chuỗi có độ dài.

- **Kết nối:** `localhost.football_dwh_staging`
- **Câu truy vấn:**

```sql
SELECT CAST(competition_id AS NVARCHAR(20)) AS competition_id,
       CAST(name AS NVARCHAR(200)) AS name,
       CAST(type AS NVARCHAR(50)) AS type,
       CAST(sub_type AS NVARCHAR(50)) AS sub_type,
       CAST(country_id AS NVARCHAR(20)) AS country_id,
       CAST(country_name AS NVARCHAR(100)) AS country_name,
       CAST(confederation AS NVARCHAR(20)) AS confederation,
       CAST(batch_id AS NVARCHAR(30)) AS batch_id
FROM dbo.stg_raw_competitions
```

**3.2.1.2. Làm sạch chuỗi** · *Derived Column*

Làm sạch chuỗi: bỏ khoảng trắng đầu/cuối (`TRIM`), thay ký tự khoảng trắng đặc biệt NBSP (`\x00A0`), chuỗi rỗng → `NULL`. Các cột được **thay thế tại chỗ** (Replace).

- **Biểu thức:**
  - thay thế `competition_id`:
    ```
    TRIM(REPLACE(REPLACENULL(competition_id,""),"\x00A0"," ")) == "" ? NULL(DT_WSTR,20) : TRIM(REPLACE(competition_id,"\x00A0"," "))
    ```
  - thay thế `name`:
    ```
    TRIM(REPLACE(REPLACENULL(name,""),"\x00A0"," ")) == "" ? NULL(DT_WSTR,200) : TRIM(REPLACE(name,"\x00A0"," "))
    ```
  - thay thế `type`:
    ```
    TRIM(REPLACE(REPLACENULL(type,""),"\x00A0"," ")) == "" ? NULL(DT_WSTR,50) : TRIM(REPLACE(type,"\x00A0"," "))
    ```
  - thay thế `sub_type`:
    ```
    TRIM(REPLACE(REPLACENULL(sub_type,""),"\x00A0"," ")) == "" ? NULL(DT_WSTR,50) : TRIM(REPLACE(sub_type,"\x00A0"," "))
    ```
  - thay thế `country_id`:
    ```
    TRIM(REPLACENULL(country_id,"")) == "" ? NULL(DT_WSTR,20) : TRIM(country_id)
    ```
  - thay thế `country_name`:
    ```
    TRIM(REPLACE(REPLACENULL(country_name,""),"\x00A0"," ")) == "" ? NULL(DT_WSTR,100) : TRIM(REPLACE(country_name,"\x00A0"," "))
    ```
  - thay thế `confederation`:
    ```
    TRIM(REPLACE(REPLACENULL(confederation,""),"\x00A0"," ")) == "" ? NULL(DT_WSTR,20) : TRIM(REPLACE(confederation,"\x00A0"," "))
    ```

**3.2.1.3. Loại trùng theo competition_id** · *Sort*

Sắp xếp theo khóa tự nhiên và **loại dòng trùng khóa** (Remove rows with duplicate sort values).

- **Khóa sắp xếp:** `competition_id`
- **Loại trùng:** Có (EliminateDuplicates = True)

**3.2.1.4. Bổ sung tên quốc gia từ countries** · *Lookup*

Tra cứu thêm thông tin từ một bảng Staging khác.

- **Kết nối:** `localhost.football_dwh_staging` — **Cache:** Full cache
- **Bảng tham chiếu:**

```sql
SELECT CAST(country_id AS NVARCHAR(20)) AS country_id, CAST(country_name AS NVARCHAR(100)) AS ref_country_name FROM dbo.stg_raw_countries
```
- **Điều kiện nối:** `country_id` = `country_id`
- **Cột lấy về:** `ref_country_name`
- **Không tìm thấy:** Bỏ qua lỗi (Ignore failure): các cột trả về = NULL

**3.2.1.5. Chuẩn hóa tên quốc gia và liên đoàn** · *Derived Column*

Tính toán ở mức từng dòng ngay trong ETL (chuẩn hóa giá trị, nhóm hóa thành band, khóa ngày, cờ 0/1, measure dẫn xuất).

- **Biểu thức:**
  - cột mới `competition_name` (DT_WSTR(200)):
    ```
    (DT_WSTR,200)REPLACENULL(name,"Không xác định")
    ```
  - cột mới `competition_type` (DT_WSTR(50)):
    ```
    (DT_WSTR,50)REPLACENULL(type,"Không xác định")
    ```
  - cột mới `competition_sub_type` (DT_WSTR(50)):
    ```
    (DT_WSTR,50)REPLACENULL(sub_type,"Không xác định")
    ```
  - cột mới `country_name_std` (DT_WSTR(100)):
    ```
    (DT_WSTR,100)((REPLACENULL(country_id,"") == "-1" || ISNULL(country_name)) ? REPLACENULL(TRIM(ref_country_name),"International") : country_name)
    ```
  - cột mới `confederation_std` (DT_WSTR(20)):
    ```
    (DT_WSTR,20)((UPPER(REPLACENULL(confederation,"")) == "EUROPA" || UPPER(REPLACENULL(confederation,"")) == "UEFA") ? "UEFA" : ((UPPER(REPLACENULL(confederation,"")) == "ASIEN" || UPPER(REPLACENULL(confederation,"")) == "AFC") ? "AFC" : ((UPPER(REPLACENULL(confederation,"")) == "AFRIKA" || UPPER(REPLACENULL(confederation,"")) == "CAF") ? "CAF" : ((UPPER(REPLACENULL(confederation,"")) == "AMERIKA" || UPPER(REPLACENULL(confederation,"")) == "AMERICAS" || UPPER(REPLACENULL(confederation,"")) == "CONCACAF" || UPPER(REPLACENULL(confederation,"")) == "CONMEBOL") ? "Americas" : (UPPER(REPLACENULL(confederation,"")) == "OFC" ? "OFC" : (UPPER(REPLACENULL(confederation,"")) == "FIFA" ? "FIFA" : "Không xác định"))))))
    ```

**3.2.1.6. Kiểm tra giải đã có trong kho** · *Lookup*

Tra dimension trong kho theo khóa tự nhiên: **Match** = đã có (đi tiếp để so sánh thay đổi), **No Match** = bản ghi mới (thêm vào dimension).

- **Kết nối:** `localhost.football_dwh_dw` — **Cache:** Full cache
- **Bảng tham chiếu:**

```sql
SELECT competition_id, competition_key, competition_name AS old_name, competition_type AS old_type, competition_sub_type AS old_sub_type, country_name AS old_country, confederation AS old_confederation FROM dbo.dim_competition WHERE competition_key <> -1
```
- **Điều kiện nối:** `competition_id` = `competition_id`
- **Cột lấy về:** `competition_key`, `old_name`, `old_type`, `old_sub_type`, `old_country`, `old_confederation`
- **Không tìm thấy:** Gửi sang **Lookup No Match Output**

**3.2.1.7. Thêm giải mới vào Dim_Competition** · *OLE DB Destination*

Ghi dữ liệu vào bảng đích (Fast load).

- **Kết nối:** `localhost.football_dwh_dw` — **Bảng đích:** `[dbo].[dim_competition]` — **Chế độ:** Table or view – fast load
- **Ánh xạ cột (7):** `competition_id`, `competition_name`, `competition_type`, `competition_sub_type`, `country_name_std`→`country_name`, `confederation_std`→`confederation`, `batch_id`

**3.2.1.8. Tìm giải có thuộc tính thay đổi** · *Conditional Split*

Chia luồng theo điều kiện; điều kiện được xét theo thứ tự, dòng không thỏa điều kiện nào đi vào output mặc định.

- **Các output:**
  - **Changed** (thứ tự 1):
    ```
    competition_name != old_name || competition_type != old_type || competition_sub_type != old_sub_type || country_name_std != old_country || confederation_std != old_confederation
    ```
  - **Unchanged** (mặc định): các dòng còn lại

**3.2.1.9. Ghi đè thay đổi SCD1** · *OLE DB Command*

Chạy câu lệnh SQL cho **từng dòng** (cập nhật dimension theo SCD).

- **Kết nối:** `localhost.football_dwh_dw`
- **Câu lệnh:**

```sql
UPDATE dbo.dim_competition SET competition_name = ?, competition_type = ?, competition_sub_type = ?, country_name = ?, confederation = ?, batch_id = ? WHERE competition_key = ?
```
- **Tham số `?`:** `competition_name`→Param_0, `competition_type`→Param_1, `competition_sub_type`→Param_2, `country_name_std`→Param_3, `confederation_std`→Param_4, `batch_id`→Param_5, `competition_key`→Param_6

#### 3.2.2. Nạp Dim_Club (SCD1 SCD2 SCD3)

| Đích | Cách nạp | Số component |
|---|---|---|
| `Dim_Club` | SCD Type 1 + 2 + 3 | 18 |

Nạp CLB (`stg_raw_clubs`) và đội tuyển quốc gia (`stg_raw_national_teams`) vào cùng một dimension. Ba loại thay đổi được tách riêng: đổi tên/loại/quốc gia/liên đoàn → SCD1 (ghi đè); đổi sân nhà hoặc nhóm sức chứa → SCD2 (thêm phiên bản mới qua stored procedure); đổi giải VĐQG → SCD3 (dời giải hiện tại sang `previous_league_name`).

**Luồng dữ liệu** (component nguồn ──[output]──► component đích):

```
Đọc CLB từ Staging                               ────► Gắn loại Club
Đọc đội tuyển từ Staging                         ────► Gắn loại National Team
Gắn loại Club                                    ────► Gộp CLB và đội tuyển
Gắn loại National Team                           ────► Gộp CLB và đội tuyển
Gộp CLB và đội tuyển                             ────► Làm sạch chuỗi
Làm sạch chuỗi                                   ────► Ép kiểu dữ liệu
Ép kiểu dữ liệu                                  ────► Loại trùng theo club_id
Ép kiểu dữ liệu                                  ── [Data Conversion Error Output]──► Ghi lý do lỗi ép kiểu
Loại trùng theo club_id                          ────► Tra tên giải VĐQG quốc gia và liên đoàn
Ghi lý do lỗi ép kiểu                            ────► Lưu dòng lỗi ép kiểu vào etl_reject
Tra tên giải VĐQG quốc gia và liên đoàn          ── [Lookup Match Output]──► Chuẩn hóa giá trị và nhóm sức chứa sân
Chuẩn hóa giá trị và nhóm sức chứa sân           ────► Kiểm tra CLB đã có trong kho
Kiểm tra CLB đã có trong kho                     ── [Lookup Match Output]──► Phân loại thay đổi theo SCD
Kiểm tra CLB đã có trong kho                     ── [Lookup No Match Output]──► Thêm CLB mới vào Dim_Club
Phân loại thay đổi theo SCD                      ── [SCD1]──► Ghi đè thay đổi SCD1
Phân loại thay đổi theo SCD                      ── [SCD3 League]──► Lưu giải cũ và cập nhật giải mới SCD3
Phân loại thay đổi theo SCD                      ── [SCD2 Stadium]──► Tạo phiên bản mới SCD2
```

**Chi tiết từng component:**

**3.2.2.1. Đọc CLB từ Staging** · *OLE DB Source*

Đọc dữ liệu từ Staging. Câu SQL chỉ `CAST` các cột cần dùng sang `NVARCHAR(n)`: bảng stage lưu `NVARCHAR(MAX)`, SSIS đọc kiểu này thành `DT_NTEXT` và không áp dụng được hàm chuỗi, nên phải đổi sang chuỗi có độ dài.

- **Kết nối:** `localhost.football_dwh_staging`
- **Câu truy vấn:**

```sql
SELECT CAST(club_id AS NVARCHAR(20)) AS club_id, CAST(name AS NVARCHAR(200)) AS club_name,
       CAST(domestic_competition_id AS NVARCHAR(20)) AS league_id, CAST(stadium_name AS NVARCHAR(200)) AS stadium_name,
       CAST(stadium_seats AS NVARCHAR(20)) AS stadium_seats, CAST(NULL AS NVARCHAR(100)) AS country_name,
       CAST(NULL AS NVARCHAR(20)) AS confederation, CAST(batch_id AS NVARCHAR(30)) AS batch_id
FROM dbo.stg_raw_clubs
```

**3.2.2.2. Đọc đội tuyển từ Staging** · *OLE DB Source*

Đọc dữ liệu từ Staging. Câu SQL chỉ `CAST` các cột cần dùng sang `NVARCHAR(n)`: bảng stage lưu `NVARCHAR(MAX)`, SSIS đọc kiểu này thành `DT_NTEXT` và không áp dụng được hàm chuỗi, nên phải đổi sang chuỗi có độ dài.

- **Kết nối:** `localhost.football_dwh_staging`
- **Câu truy vấn:**

```sql
SELECT CAST(national_team_id AS NVARCHAR(20)) AS club_id, CAST(name AS NVARCHAR(200)) AS club_name,
       CAST(NULL AS NVARCHAR(20)) AS league_id, CAST(NULL AS NVARCHAR(200)) AS stadium_name,
       CAST(NULL AS NVARCHAR(20)) AS stadium_seats, CAST(country_name AS NVARCHAR(100)) AS country_name,
       CAST(confederation AS NVARCHAR(20)) AS confederation, CAST(batch_id AS NVARCHAR(30)) AS batch_id
FROM dbo.stg_raw_national_teams
```

**3.2.2.3. Gắn loại Club** · *Derived Column*

Gắn giá trị cố định cho cột `club_type` của nhánh nguồn này.

- **Biểu thức:**
  - cột mới `club_type` (DT_WSTR(20)):
    ```
    (DT_WSTR,20)"Club"
    ```

**3.2.2.4. Gắn loại National Team** · *Derived Column*

Gắn giá trị cố định cho cột `club_type` của nhánh nguồn này.

- **Biểu thức:**
  - cột mới `club_type` (DT_WSTR(20)):
    ```
    (DT_WSTR,20)"National Team"
    ```

**3.2.2.5. Gộp CLB và đội tuyển** · *Union All*

Gộp nhiều luồng nguồn thành một luồng.

- **Số luồng vào:** 3

**3.2.2.6. Làm sạch chuỗi** · *Derived Column*

Làm sạch chuỗi: bỏ khoảng trắng đầu/cuối (`TRIM`), thay ký tự khoảng trắng đặc biệt NBSP (`\x00A0`), chuỗi rỗng → `NULL`. Các cột được **thay thế tại chỗ** (Replace).

- **Biểu thức:**
  - thay thế `club_id`:
    ```
    TRIM(REPLACENULL(club_id,"")) == "" ? NULL(DT_WSTR,20) : TRIM(club_id)
    ```
  - thay thế `club_name`:
    ```
    TRIM(REPLACE(REPLACENULL(club_name,""),"\x00A0"," ")) == "" ? NULL(DT_WSTR,200) : TRIM(REPLACE(club_name,"\x00A0"," "))
    ```
  - thay thế `league_id`:
    ```
    TRIM(REPLACE(REPLACENULL(league_id,""),"\x00A0"," ")) == "" ? NULL(DT_WSTR,20) : TRIM(REPLACE(league_id,"\x00A0"," "))
    ```
  - thay thế `stadium_name`:
    ```
    TRIM(REPLACE(REPLACENULL(stadium_name,""),"\x00A0"," ")) == "" ? NULL(DT_WSTR,200) : TRIM(REPLACE(stadium_name,"\x00A0"," "))
    ```
  - thay thế `stadium_seats`:
    ```
    TRIM(REPLACENULL(stadium_seats,"")) == "" ? NULL(DT_WSTR,20) : TRIM(stadium_seats)
    ```
  - thay thế `country_name`:
    ```
    TRIM(REPLACE(REPLACENULL(country_name,""),"\x00A0"," ")) == "" ? NULL(DT_WSTR,100) : TRIM(REPLACE(country_name,"\x00A0"," "))
    ```
  - thay thế `confederation`:
    ```
    TRIM(REPLACE(REPLACENULL(confederation,""),"\x00A0"," ")) == "" ? NULL(DT_WSTR,20) : TRIM(REPLACE(confederation,"\x00A0"," "))
    ```

**3.2.2.7. Ép kiểu dữ liệu** · *Data Conversion*

Ép kiểu chuỗi sang kiểu số/ngày (cột mới có tiền tố `c_`). Dòng ép kiểu lỗi **không làm dừng package** mà được chuyển (Redirect row) sang **Data Conversion Error Output** → ghi vào `etl_reject`.

- **Cột chuyển đổi:** `club_id` → `c_club_id` DT_I4; `stadium_seats` → `c_stadium_seats` DT_I4
- **Xử lý lỗi:** Redirect row → Data Conversion Error Output

**3.2.2.8. Loại trùng theo club_id** · *Sort*

Sắp xếp theo khóa tự nhiên và **loại dòng trùng khóa** (Remove rows with duplicate sort values).

- **Khóa sắp xếp:** `c_club_id`
- **Loại trùng:** Có (EliminateDuplicates = True)

**3.2.2.9. Ghi lý do lỗi ép kiểu** · *Derived Column*

Tạo 3 cột mô tả dòng bị loại (`source_table`, `natural_key`, `reason`) để ghi vào bảng `etl_reject`.

- **Biểu thức:**
  - cột mới `rj_source_table` (DT_WSTR(100)):
    ```
    (DT_WSTR,100)"stg_raw_clubs"
    ```
  - cột mới `rj_natural_key` (DT_WSTR(200)):
    ```
    (DT_WSTR,200)(REPLACENULL(club_id,""))
    ```
  - cột mới `rj_reason` (DT_WSTR(200)):
    ```
    (DT_WSTR,200)"Lỗi ép kiểu (club_id, stadium_seats)"
    ```

**3.2.2.10. Tra tên giải VĐQG quốc gia và liên đoàn** · *Lookup*

Tra dimension đã nạp để lấy thêm thuộc tính mô tả.

- **Kết nối:** `localhost.football_dwh_dw` — **Cache:** Full cache
- **Bảng tham chiếu:**

```sql
SELECT competition_id, competition_name AS league_name, country_name AS league_country, confederation AS league_confederation FROM dbo.dim_competition WHERE competition_key <> -1
```
- **Điều kiện nối:** `league_id` = `competition_id`
- **Cột lấy về:** `league_name`, `league_country`, `league_confederation`
- **Không tìm thấy:** Bỏ qua lỗi (Ignore failure): các cột trả về = NULL

**3.2.2.11. Lưu dòng lỗi ép kiểu vào etl_reject** · *OLE DB Destination*

Ghi dữ liệu vào bảng đích (Fast load).

- **Kết nối:** `localhost.football_dwh_staging` — **Bảng đích:** `[dbo].[etl_reject]` — **Chế độ:** Table or view – fast load
- **Ánh xạ cột (4):** `batch_id`, `rj_source_table`→`source_table`, `rj_natural_key`→`natural_key`, `rj_reason`→`reason`

**3.2.2.12. Chuẩn hóa giá trị và nhóm sức chứa sân** · *Derived Column*

Tính toán ở mức từng dòng ngay trong ETL (chuẩn hóa giá trị, nhóm hóa thành band, khóa ngày, cờ 0/1, measure dẫn xuất).

- **Biểu thức:**
  - cột mới `club_name_std` (DT_WSTR(200)):
    ```
    (DT_WSTR,200)REPLACENULL(club_name,"CLB " + REPLACENULL(club_id,""))
    ```
  - cột mới `country_std` (DT_WSTR(100)):
    ```
    (DT_WSTR,100)(club_type == "Club" ? REPLACENULL(league_country,"Không xác định") : REPLACENULL(country_name,"Không xác định"))
    ```
  - cột mới `confederation_std` (DT_WSTR(20)):
    ```
    (DT_WSTR,20)(club_type == "Club" ? REPLACENULL(league_confederation,"Không xác định") : (DT_WSTR,20)((UPPER(REPLACENULL(confederation,"")) == "EUROPA" || UPPER(REPLACENULL(confederation,"")) == "UEFA") ? "UEFA" : ((UPPER(REPLACENULL(confederation,"")) == "ASIEN" || UPPER(REPLACENULL(confederation,"")) == "AFC") ? "AFC" : ((UPPER(REPLACENULL(confederation,"")) == "AFRIKA" || UPPER(REPLACENULL(confederation,"")) == "CAF") ? "CAF" : ((UPPER(REPLACENULL(confederation,"")) == "AMERIKA" || UPPER(REPLACENULL(confederation,"")) == "AMERICAS" || UPPER(REPLACENULL(confederation,"")) == "CONCACAF" || UPPER(REPLACENULL(confederation,"")) == "CONMEBOL") ? "Americas" : (UPPER(REPLACENULL(confederation,"")) == "OFC" ? "OFC" : (UPPER(REPLACENULL(confederation,"")) == "FIFA" ? "FIFA" : "Không xác định")))))))
    ```
  - cột mới `league_name_std` (DT_WSTR(200)):
    ```
    (DT_WSTR,200)(club_type == "National Team" ? "Không áp dụng" : REPLACENULL(league_name,"Không xác định"))
    ```
  - cột mới `stadium_std` (DT_WSTR(200)):
    ```
    (DT_WSTR,200)REPLACENULL(stadium_name,"Không xác định")
    ```
  - cột mới `stadium_capacity_band` (DT_WSTR(30)):
    ```
    (DT_WSTR,30)(ISNULL(c_stadium_seats) || c_stadium_seats <= 0 ? "Không xác định" : (c_stadium_seats < 20000 ? "< 20.000" : (c_stadium_seats < 40000 ? "20.000-39.999" : (c_stadium_seats < 60000 ? "40.000-59.999" : ">= 60.000"))))
    ```

**3.2.2.13. Kiểm tra CLB đã có trong kho** · *Lookup*

Tra dimension trong kho theo khóa tự nhiên: **Match** = đã có (đi tiếp để so sánh thay đổi), **No Match** = bản ghi mới (thêm vào dimension).

- **Kết nối:** `localhost.football_dwh_dw` — **Cache:** Full cache
- **Bảng tham chiếu:**

```sql
SELECT club_id, club_key, club_name AS old_name, club_type AS old_type, country_name AS old_country, confederation AS old_confederation, current_league_id AS old_league_id, stadium_name AS old_stadium, stadium_capacity_band AS old_band FROM dbo.dim_club WHERE is_current = 1 AND club_key <> -1
```
- **Điều kiện nối:** `c_club_id` = `club_id`
- **Cột lấy về:** `club_key`, `old_name`, `old_type`, `old_country`, `old_confederation`, `old_league_id`, `old_stadium`, `old_band`
- **Không tìm thấy:** Gửi sang **Lookup No Match Output**

**3.2.2.14. Phân loại thay đổi theo SCD** · *Conditional Split*

Chia luồng theo điều kiện; điều kiện được xét theo thứ tự, dòng không thỏa điều kiện nào đi vào output mặc định.

- **Các output:**
  - **SCD2 Stadium** (thứ tự 1):
    ```
    stadium_std != old_stadium || stadium_capacity_band != old_band
    ```
  - **SCD3 League** (thứ tự 2):
    ```
    REPLACENULL(league_id,"") != REPLACENULL(old_league_id,"")
    ```
  - **SCD1** (thứ tự 3):
    ```
    club_name_std != old_name || club_type != old_type || country_std != old_country || confederation_std != old_confederation
    ```
  - **Unchanged** (mặc định): các dòng còn lại

**3.2.2.15. Thêm CLB mới vào Dim_Club** · *OLE DB Destination*

Ghi dữ liệu vào bảng đích (Fast load).

- **Kết nối:** `localhost.football_dwh_dw` — **Bảng đích:** `[dbo].[dim_club]` — **Chế độ:** Table or view – fast load
- **Ánh xạ cột (10):** `c_club_id`→`club_id`, `club_name_std`→`club_name`, `club_type`, `country_std`→`country_name`, `confederation_std`→`confederation`, `league_id`→`current_league_id`, `league_name_std`→`current_league_name`, `stadium_std`→`stadium_name`, `stadium_capacity_band`, `batch_id`

**3.2.2.16. Ghi đè thay đổi SCD1** · *OLE DB Command*

Chạy câu lệnh SQL cho **từng dòng** (cập nhật dimension theo SCD).

- **Kết nối:** `localhost.football_dwh_dw`
- **Câu lệnh:**

```sql
UPDATE dbo.dim_club SET club_name = ?, club_type = ?, country_name = ?, confederation = ?, batch_id = ? WHERE club_id = ?
```
- **Tham số `?`:** `club_name_std`→Param_0, `club_type`→Param_1, `country_std`→Param_2, `confederation_std`→Param_3, `batch_id`→Param_4, `c_club_id`→Param_5

**3.2.2.17. Lưu giải cũ và cập nhật giải mới SCD3** · *OLE DB Command*

Chạy câu lệnh SQL cho **từng dòng** (cập nhật dimension theo SCD).

- **Kết nối:** `localhost.football_dwh_dw`
- **Câu lệnh:**

```sql
UPDATE dbo.dim_club SET previous_league_name = current_league_name, current_league_id = ?, current_league_name = ?, batch_id = ? WHERE club_key = ?
```
- **Tham số `?`:** `league_id`→Param_0, `league_name_std`→Param_1, `batch_id`→Param_2, `club_key`→Param_3

**3.2.2.18. Tạo phiên bản mới SCD2** · *OLE DB Command*

Chạy câu lệnh SQL cho **từng dòng** (cập nhật dimension theo SCD).

- **Kết nối:** `localhost.football_dwh_dw`
- **Câu lệnh:**

```sql
EXEC dbo.usp_DimClub_NewVersion ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
```
- **Tham số `?`:** `club_key`→@club_key, `club_name_std`→@club_name, `club_type`→@club_type, `country_std`→@country_name, `confederation_std`→@confederation, `league_id`→@current_league_id, `league_name_std`→@current_league_name, `stadium_std`→@stadium_name, `stadium_capacity_band`→@stadium_capacity_band, `batch_id`→@batch_id

#### 3.2.3. Bổ sung CLB chỉ có trong Fact vào Dim_Club

| Đích | Cách nạp | Số component |
|---|---|---|
| `Dim_Club (club_type = Other)` | Chỉ thêm mới | 15 |

Nhiều `club_id` xuất hiện trong trận đấu, chuyển nhượng, định giá nhưng không có trong `clubs.csv` (CLB hạng dưới, CLB nước ngoài). Data Flow này gom các CLB đó từ 5 nguồn, chỉ thêm những CLB chưa có trong Dim_Club với `club_type = Other`, nhờ vậy khi nạp fact không bị rơi về Unknown.

**Luồng dữ liệu** (component nguồn ──[output]──► component đích):

```
Đọc CLB từ player_valuations                     ────► Gộp CLB từ các nguồn fact
Đọc CLB đi từ transfers                          ────► Gộp CLB từ các nguồn fact
Đọc CLB đến từ transfers                         ────► Gộp CLB từ các nguồn fact
Đọc đội khách từ games                           ────► Gộp CLB từ các nguồn fact
Đọc đội nhà từ games                             ────► Gộp CLB từ các nguồn fact
Gộp CLB từ các nguồn fact                        ────► Làm sạch chuỗi
Làm sạch chuỗi                                   ────► Ép kiểu dữ liệu
Ép kiểu dữ liệu                                  ────► Bỏ dòng không có mã CLB
Ép kiểu dữ liệu                                  ── [Data Conversion Error Output]──► Ghi lý do lỗi ép kiểu
Bỏ dòng không có mã CLB                          ── [Has Id]──► Loại trùng theo club_id
Ghi lý do lỗi ép kiểu                            ────► Lưu dòng lỗi ép kiểu vào etl_reject
Loại trùng theo club_id                          ────► Chỉ giữ CLB chưa có trong kho
Chỉ giữ CLB chưa có trong kho                    ── [Lookup No Match Output]──► Gán thuộc tính cho CLB Other
Gán thuộc tính cho CLB Other                     ────► Thêm CLB Other vào Dim_Club
```

**Chi tiết từng component:**

**3.2.3.1. Đọc CLB từ player_valuations** · *OLE DB Source*

Đọc dữ liệu từ Staging. Câu SQL chỉ `CAST` các cột cần dùng sang `NVARCHAR(n)`: bảng stage lưu `NVARCHAR(MAX)`, SSIS đọc kiểu này thành `DT_NTEXT` và không áp dụng được hàm chuỗi, nên phải đổi sang chuỗi có độ dài.

- **Kết nối:** `localhost.football_dwh_staging`
- **Câu truy vấn:**

```sql
SELECT CAST(current_club_id AS NVARCHAR(20)) AS club_id, CAST(current_club_name AS NVARCHAR(200)) AS club_name, CAST(batch_id AS NVARCHAR(30)) AS batch_id
FROM dbo.stg_raw_player_valuations
```

**3.2.3.2. Đọc CLB đi từ transfers** · *OLE DB Source*

Đọc dữ liệu từ Staging. Câu SQL chỉ `CAST` các cột cần dùng sang `NVARCHAR(n)`: bảng stage lưu `NVARCHAR(MAX)`, SSIS đọc kiểu này thành `DT_NTEXT` và không áp dụng được hàm chuỗi, nên phải đổi sang chuỗi có độ dài.

- **Kết nối:** `localhost.football_dwh_staging`
- **Câu truy vấn:**

```sql
SELECT CAST(from_club_id AS NVARCHAR(20)) AS club_id, CAST(from_club_name AS NVARCHAR(200)) AS club_name, CAST(batch_id AS NVARCHAR(30)) AS batch_id
FROM dbo.stg_raw_transfers
```

**3.2.3.3. Đọc CLB đến từ transfers** · *OLE DB Source*

Đọc dữ liệu từ Staging. Câu SQL chỉ `CAST` các cột cần dùng sang `NVARCHAR(n)`: bảng stage lưu `NVARCHAR(MAX)`, SSIS đọc kiểu này thành `DT_NTEXT` và không áp dụng được hàm chuỗi, nên phải đổi sang chuỗi có độ dài.

- **Kết nối:** `localhost.football_dwh_staging`
- **Câu truy vấn:**

```sql
SELECT CAST(to_club_id AS NVARCHAR(20)) AS club_id, CAST(to_club_name AS NVARCHAR(200)) AS club_name, CAST(batch_id AS NVARCHAR(30)) AS batch_id
FROM dbo.stg_raw_transfers
```

**3.2.3.4. Đọc đội khách từ games** · *OLE DB Source*

Đọc dữ liệu từ Staging. Câu SQL chỉ `CAST` các cột cần dùng sang `NVARCHAR(n)`: bảng stage lưu `NVARCHAR(MAX)`, SSIS đọc kiểu này thành `DT_NTEXT` và không áp dụng được hàm chuỗi, nên phải đổi sang chuỗi có độ dài.

- **Kết nối:** `localhost.football_dwh_staging`
- **Câu truy vấn:**

```sql
SELECT CAST(away_club_id AS NVARCHAR(20)) AS club_id, CAST(away_club_name AS NVARCHAR(200)) AS club_name, CAST(batch_id AS NVARCHAR(30)) AS batch_id
FROM dbo.stg_raw_games
```

**3.2.3.5. Đọc đội nhà từ games** · *OLE DB Source*

Đọc dữ liệu từ Staging. Câu SQL chỉ `CAST` các cột cần dùng sang `NVARCHAR(n)`: bảng stage lưu `NVARCHAR(MAX)`, SSIS đọc kiểu này thành `DT_NTEXT` và không áp dụng được hàm chuỗi, nên phải đổi sang chuỗi có độ dài.

- **Kết nối:** `localhost.football_dwh_staging`
- **Câu truy vấn:**

```sql
SELECT CAST(home_club_id AS NVARCHAR(20)) AS club_id, CAST(home_club_name AS NVARCHAR(200)) AS club_name, CAST(batch_id AS NVARCHAR(30)) AS batch_id
FROM dbo.stg_raw_games
```

**3.2.3.6. Gộp CLB từ các nguồn fact** · *Union All*

Gộp nhiều luồng nguồn thành một luồng.

- **Số luồng vào:** 6

**3.2.3.7. Làm sạch chuỗi** · *Derived Column*

Làm sạch chuỗi: bỏ khoảng trắng đầu/cuối (`TRIM`), thay ký tự khoảng trắng đặc biệt NBSP (`\x00A0`), chuỗi rỗng → `NULL`. Các cột được **thay thế tại chỗ** (Replace).

- **Biểu thức:**
  - thay thế `club_id`:
    ```
    TRIM(REPLACENULL(club_id,"")) == "" ? NULL(DT_WSTR,20) : TRIM(club_id)
    ```
  - thay thế `club_name`:
    ```
    TRIM(REPLACE(REPLACENULL(club_name,""),"\x00A0"," ")) == "" ? NULL(DT_WSTR,200) : TRIM(REPLACE(club_name,"\x00A0"," "))
    ```

**3.2.3.8. Ép kiểu dữ liệu** · *Data Conversion*

Ép kiểu chuỗi sang kiểu số/ngày (cột mới có tiền tố `c_`). Dòng ép kiểu lỗi **không làm dừng package** mà được chuyển (Redirect row) sang **Data Conversion Error Output** → ghi vào `etl_reject`.

- **Cột chuyển đổi:** `club_id` → `c_club_id` DT_I4
- **Xử lý lỗi:** Redirect row → Data Conversion Error Output

**3.2.3.9. Bỏ dòng không có mã CLB** · *Conditional Split*

Chia luồng theo điều kiện; điều kiện được xét theo thứ tự, dòng không thỏa điều kiện nào đi vào output mặc định.

- **Các output:**
  - **No Id** (thứ tự 1):
    ```
    ISNULL(c_club_id) || c_club_id == -1
    ```
  - **Has Id** (mặc định): các dòng còn lại

**3.2.3.10. Ghi lý do lỗi ép kiểu** · *Derived Column*

Tạo 3 cột mô tả dòng bị loại (`source_table`, `natural_key`, `reason`) để ghi vào bảng `etl_reject`.

- **Biểu thức:**
  - cột mới `rj_source_table` (DT_WSTR(100)):
    ```
    (DT_WSTR,100)"stg_raw_transfers/games/valuations"
    ```
  - cột mới `rj_natural_key` (DT_WSTR(200)):
    ```
    (DT_WSTR,200)(REPLACENULL(club_id,""))
    ```
  - cột mới `rj_reason` (DT_WSTR(200)):
    ```
    (DT_WSTR,200)"Lỗi ép kiểu club_id"
    ```

**3.2.3.11. Loại trùng theo club_id** · *Sort*

Sắp xếp theo khóa tự nhiên và **loại dòng trùng khóa** (Remove rows with duplicate sort values).

- **Khóa sắp xếp:** `c_club_id`
- **Loại trùng:** Có (EliminateDuplicates = True)

**3.2.3.12. Lưu dòng lỗi ép kiểu vào etl_reject** · *OLE DB Destination*

Ghi dữ liệu vào bảng đích (Fast load).

- **Kết nối:** `localhost.football_dwh_staging` — **Bảng đích:** `[dbo].[etl_reject]` — **Chế độ:** Table or view – fast load
- **Ánh xạ cột (4):** `batch_id`, `rj_source_table`→`source_table`, `rj_natural_key`→`natural_key`, `rj_reason`→`reason`

**3.2.3.13. Chỉ giữ CLB chưa có trong kho** · *Lookup*

Tra dimension trong kho theo khóa tự nhiên: **Match** = đã có (đi tiếp để so sánh thay đổi), **No Match** = bản ghi mới (thêm vào dimension).

- **Kết nối:** `localhost.football_dwh_dw` — **Cache:** Full cache
- **Bảng tham chiếu:**

```sql
SELECT club_id, club_key FROM dbo.dim_club
```
- **Điều kiện nối:** `c_club_id` = `club_id`
- **Cột lấy về:** `club_key`
- **Không tìm thấy:** Gửi sang **Lookup No Match Output**

**3.2.3.14. Gán thuộc tính cho CLB Other** · *Derived Column*

Tính toán ở mức từng dòng ngay trong ETL (chuẩn hóa giá trị, nhóm hóa thành band, khóa ngày, cờ 0/1, measure dẫn xuất).

- **Biểu thức:**
  - cột mới `club_name_std` (DT_WSTR(200)):
    ```
    (DT_WSTR,200)REPLACENULL(club_name,"CLB " + REPLACENULL(club_id,""))
    ```
  - cột mới `club_type` (DT_WSTR(20)):
    ```
    (DT_WSTR,20)"Other"
    ```
  - cột mới `country_std` (DT_WSTR(100)):
    ```
    (DT_WSTR,100)"Không xác định"
    ```
  - cột mới `confederation_std` (DT_WSTR(20)):
    ```
    (DT_WSTR,20)"Không xác định"
    ```
  - cột mới `league_name_std` (DT_WSTR(200)):
    ```
    (DT_WSTR,200)"Không xác định"
    ```
  - cột mới `stadium_std` (DT_WSTR(200)):
    ```
    (DT_WSTR,200)"Không xác định"
    ```
  - cột mới `stadium_capacity_band` (DT_WSTR(30)):
    ```
    (DT_WSTR,30)"Không xác định"
    ```

**3.2.3.15. Thêm CLB Other vào Dim_Club** · *OLE DB Destination*

Ghi dữ liệu vào bảng đích (Fast load).

- **Kết nối:** `localhost.football_dwh_dw` — **Bảng đích:** `[dbo].[dim_club]` — **Chế độ:** Table or view – fast load
- **Ánh xạ cột (9):** `c_club_id`→`club_id`, `club_name_std`→`club_name`, `club_type`, `country_std`→`country_name`, `confederation_std`→`confederation`, `league_name_std`→`current_league_name`, `stadium_std`→`stadium_name`, `stadium_capacity_band`, `batch_id`

#### 3.2.4. Nạp Dim_Player (SCD1 SCD2)

| Đích | Cách nạp | Số component |
|---|---|---|
| `Dim_Player` | SCD Type 1 + 2 | 12 |

Nạp cầu thủ từ `stg_raw_players`. Chiều cao, số trận đội tuyển được nhóm hóa thành band; ngày hết hạn hợp đồng chỉ lấy năm. Đổi vị trí/vị trí chi tiết/người đại diện → SCD2 (thêm phiên bản); đổi các thuộc tính khác → SCD1 (ghi đè).

**Luồng dữ liệu** (component nguồn ──[output]──► component đích):

```
Đọc cầu thủ từ Staging                           ────► Làm sạch chuỗi
Làm sạch chuỗi                                   ────► Ép kiểu dữ liệu
Ép kiểu dữ liệu                                  ────► Loại trùng theo player_id
Ép kiểu dữ liệu                                  ── [Data Conversion Error Output]──► Ghi lý do lỗi ép kiểu
Loại trùng theo player_id                        ────► Chuẩn hóa và tính nhóm chiều cao khoác áo
Ghi lý do lỗi ép kiểu                            ────► Lưu dòng lỗi ép kiểu vào etl_reject
Chuẩn hóa và tính nhóm chiều cao khoác áo        ────► Kiểm tra cầu thủ đã có trong kho
Kiểm tra cầu thủ đã có trong kho                 ── [Lookup Match Output]──► Phân loại thay đổi theo SCD
Kiểm tra cầu thủ đã có trong kho                 ── [Lookup No Match Output]──► Thêm cầu thủ mới vào Dim_Player
Phân loại thay đổi theo SCD                      ── [SCD1]──► Ghi đè thay đổi SCD1
Phân loại thay đổi theo SCD                      ── [SCD2 Position Agent]──► Tạo phiên bản mới SCD2
```

**Chi tiết từng component:**

**3.2.4.1. Đọc cầu thủ từ Staging** · *OLE DB Source*

Đọc dữ liệu từ Staging. Câu SQL chỉ `CAST` các cột cần dùng sang `NVARCHAR(n)`: bảng stage lưu `NVARCHAR(MAX)`, SSIS đọc kiểu này thành `DT_NTEXT` và không áp dụng được hàm chuỗi, nên phải đổi sang chuỗi có độ dài.

- **Kết nối:** `localhost.football_dwh_staging`
- **Câu truy vấn:**

```sql
SELECT CAST(player_id AS NVARCHAR(20)) AS player_id,
       CAST(name AS NVARCHAR(200)) AS name,
       CAST(date_of_birth AS NVARCHAR(30)) AS date_of_birth,
       CAST(country_of_birth AS NVARCHAR(100)) AS country_of_birth,
       CAST(country_of_citizenship AS NVARCHAR(100)) AS country_of_citizenship,
       CAST(position AS NVARCHAR(50)) AS position,
       CAST(sub_position AS NVARCHAR(50)) AS sub_position,
       CAST(foot AS NVARCHAR(20)) AS foot,
       CAST(height_in_cm AS NVARCHAR(10)) AS height_in_cm,
       CAST(agent_name AS NVARCHAR(200)) AS agent_name,
       CAST(contract_expiration_date AS NVARCHAR(30)) AS contract_expiration_date,
       CAST(international_caps AS NVARCHAR(10)) AS international_caps,
       CAST(batch_id AS NVARCHAR(30)) AS batch_id
FROM dbo.stg_raw_players
```

**3.2.4.2. Làm sạch chuỗi** · *Derived Column*

Làm sạch chuỗi: bỏ khoảng trắng đầu/cuối (`TRIM`), thay ký tự khoảng trắng đặc biệt NBSP (`\x00A0`), chuỗi rỗng → `NULL`. Các cột được **thay thế tại chỗ** (Replace).

- **Biểu thức:**
  - thay thế `player_id`:
    ```
    TRIM(REPLACENULL(player_id,"")) == "" ? NULL(DT_WSTR,20) : TRIM(player_id)
    ```
  - thay thế `name`:
    ```
    TRIM(REPLACE(REPLACENULL(name,""),"\x00A0"," ")) == "" ? NULL(DT_WSTR,200) : TRIM(REPLACE(name,"\x00A0"," "))
    ```
  - thay thế `date_of_birth`:
    ```
    TRIM(REPLACENULL(date_of_birth,"")) == "" ? NULL(DT_WSTR,30) : SUBSTRING(TRIM(date_of_birth),1,10)
    ```
  - thay thế `country_of_birth`:
    ```
    TRIM(REPLACE(REPLACENULL(country_of_birth,""),"\x00A0"," ")) == "" ? NULL(DT_WSTR,100) : TRIM(REPLACE(country_of_birth,"\x00A0"," "))
    ```
  - thay thế `country_of_citizenship`:
    ```
    TRIM(REPLACE(REPLACENULL(country_of_citizenship,""),"\x00A0"," ")) == "" ? NULL(DT_WSTR,100) : TRIM(REPLACE(country_of_citizenship,"\x00A0"," "))
    ```
  - thay thế `position`:
    ```
    TRIM(REPLACE(REPLACENULL(position,""),"\x00A0"," ")) == "" ? NULL(DT_WSTR,50) : TRIM(REPLACE(position,"\x00A0"," "))
    ```
  - thay thế `sub_position`:
    ```
    TRIM(REPLACE(REPLACENULL(sub_position,""),"\x00A0"," ")) == "" ? NULL(DT_WSTR,50) : TRIM(REPLACE(sub_position,"\x00A0"," "))
    ```
  - thay thế `foot`:
    ```
    TRIM(REPLACE(REPLACENULL(foot,""),"\x00A0"," ")) == "" ? NULL(DT_WSTR,20) : TRIM(REPLACE(foot,"\x00A0"," "))
    ```
  - thay thế `height_in_cm`:
    ```
    TRIM(REPLACENULL(height_in_cm,"")) == "" ? NULL(DT_WSTR,10) : TRIM(height_in_cm)
    ```
  - thay thế `agent_name`:
    ```
    TRIM(REPLACE(REPLACENULL(agent_name,""),"\x00A0"," ")) == "" ? NULL(DT_WSTR,200) : TRIM(REPLACE(agent_name,"\x00A0"," "))
    ```
  - thay thế `contract_expiration_date`:
    ```
    TRIM(REPLACENULL(contract_expiration_date,"")) == "" ? NULL(DT_WSTR,30) : SUBSTRING(TRIM(contract_expiration_date),1,10)
    ```
  - thay thế `international_caps`:
    ```
    TRIM(REPLACENULL(international_caps,"")) == "" ? NULL(DT_WSTR,10) : TRIM(international_caps)
    ```

**3.2.4.3. Ép kiểu dữ liệu** · *Data Conversion*

Ép kiểu chuỗi sang kiểu số/ngày (cột mới có tiền tố `c_`). Dòng ép kiểu lỗi **không làm dừng package** mà được chuyển (Redirect row) sang **Data Conversion Error Output** → ghi vào `etl_reject`.

- **Cột chuyển đổi:** `player_id` → `c_player_id` DT_I4; `date_of_birth` → `c_date_of_birth` DT_DBDATE; `height_in_cm` → `c_height_in_cm` DT_I2; `contract_expiration_date` → `c_contract_expiration_date` DT_DBDATE; `international_caps` → `c_international_caps` DT_I4
- **Xử lý lỗi:** Redirect row → Data Conversion Error Output

**3.2.4.4. Loại trùng theo player_id** · *Sort*

Sắp xếp theo khóa tự nhiên và **loại dòng trùng khóa** (Remove rows with duplicate sort values).

- **Khóa sắp xếp:** `c_player_id`
- **Loại trùng:** Có (EliminateDuplicates = True)

**3.2.4.5. Ghi lý do lỗi ép kiểu** · *Derived Column*

Tạo 3 cột mô tả dòng bị loại (`source_table`, `natural_key`, `reason`) để ghi vào bảng `etl_reject`.

- **Biểu thức:**
  - cột mới `rj_source_table` (DT_WSTR(100)):
    ```
    (DT_WSTR,100)"stg_raw_players"
    ```
  - cột mới `rj_natural_key` (DT_WSTR(200)):
    ```
    (DT_WSTR,200)(REPLACENULL(player_id,""))
    ```
  - cột mới `rj_reason` (DT_WSTR(200)):
    ```
    (DT_WSTR,200)"Lỗi ép kiểu (ngày sinh, chiều cao, số trận đội tuyển)"
    ```

**3.2.4.6. Chuẩn hóa và tính nhóm chiều cao khoác áo** · *Derived Column*

Tính toán ở mức từng dòng ngay trong ETL (chuẩn hóa giá trị, nhóm hóa thành band, khóa ngày, cờ 0/1, measure dẫn xuất).

- **Biểu thức:**
  - cột mới `full_name_std` (DT_WSTR(200)):
    ```
    (DT_WSTR,200)REPLACENULL(name,"Cầu thủ " + REPLACENULL(player_id,""))
    ```
  - cột mới `country_of_birth_std` (DT_WSTR(100)):
    ```
    (DT_WSTR,100)REPLACENULL(country_of_birth,"Không xác định")
    ```
  - cột mới `country_of_citizenship_std` (DT_WSTR(100)):
    ```
    (DT_WSTR,100)REPLACENULL(country_of_citizenship,"Không xác định")
    ```
  - cột mới `position_std` (DT_WSTR(50)):
    ```
    (DT_WSTR,50)REPLACENULL(position,"Không xác định")
    ```
  - cột mới `sub_position_std` (DT_WSTR(50)):
    ```
    (DT_WSTR,50)REPLACENULL(sub_position,"Không xác định")
    ```
  - cột mới `foot_std` (DT_WSTR(20)):
    ```
    (DT_WSTR,20)REPLACENULL(foot,"Không xác định")
    ```
  - cột mới `agent_name_std` (DT_WSTR(200)):
    ```
    (DT_WSTR,200)REPLACENULL(agent_name,"Không xác định")
    ```
  - cột mới `height_band` (DT_WSTR(30)):
    ```
    (DT_WSTR,30)(ISNULL(c_height_in_cm) || c_height_in_cm < 150 || c_height_in_cm > 220 ? "Không xác định" : (c_height_in_cm < 170 ? "< 170 cm" : (c_height_in_cm < 180 ? "170-179" : (c_height_in_cm < 190 ? "180-189" : ">= 190"))))
    ```
  - cột mới `international_caps_band` (DT_WSTR(30)):
    ```
    (DT_WSTR,30)(ISNULL(c_international_caps) ? "Không xác định" : (c_international_caps == 0 ? "Chưa khoác áo" : (c_international_caps <= 10 ? "1-10" : (c_international_caps <= 50 ? "11-50" : "> 50"))))
    ```
  - cột mới `contract_expiry_year` (DT_I2):
    ```
    ISNULL(c_contract_expiration_date) ? NULL(DT_I2) : (DT_I2)YEAR(c_contract_expiration_date)
    ```

**3.2.4.7. Lưu dòng lỗi ép kiểu vào etl_reject** · *OLE DB Destination*

Ghi dữ liệu vào bảng đích (Fast load).

- **Kết nối:** `localhost.football_dwh_staging` — **Bảng đích:** `[dbo].[etl_reject]` — **Chế độ:** Table or view – fast load
- **Ánh xạ cột (4):** `batch_id`, `rj_source_table`→`source_table`, `rj_natural_key`→`natural_key`, `rj_reason`→`reason`

**3.2.4.8. Kiểm tra cầu thủ đã có trong kho** · *Lookup*

Tra dimension trong kho theo khóa tự nhiên: **Match** = đã có (đi tiếp để so sánh thay đổi), **No Match** = bản ghi mới (thêm vào dimension).

- **Kết nối:** `localhost.football_dwh_dw` — **Cache:** Full cache
- **Bảng tham chiếu:**

```sql
SELECT player_id, player_key, full_name AS old_full_name, date_of_birth AS old_dob, country_of_birth AS old_cob, citizenship AS old_citizenship, position AS old_position, sub_position AS old_sub_position, foot AS old_foot, height_band AS old_height_band, agent_name AS old_agent, contract_expiry_year AS old_cey, international_caps_band AS old_caps_band FROM dbo.dim_player WHERE is_current = 1 AND player_key <> -1
```
- **Điều kiện nối:** `c_player_id` = `player_id`
- **Cột lấy về:** `player_key`, `old_full_name`, `old_dob`, `old_cob`, `old_citizenship`, `old_position`, `old_sub_position`, `old_foot`, `old_height_band`, `old_agent`, `old_cey`, `old_caps_band`
- **Không tìm thấy:** Gửi sang **Lookup No Match Output**

**3.2.4.9. Phân loại thay đổi theo SCD** · *Conditional Split*

Chia luồng theo điều kiện; điều kiện được xét theo thứ tự, dòng không thỏa điều kiện nào đi vào output mặc định.

- **Các output:**
  - **SCD2 Position Agent** (thứ tự 1):
    ```
    position_std != old_position || sub_position_std != old_sub_position || agent_name_std != old_agent
    ```
  - **SCD1** (thứ tự 2):
    ```
    full_name_std != old_full_name || REPLACENULL(c_date_of_birth,(DT_DBDATE)"1900-01-01") != REPLACENULL(old_dob,(DT_DBDATE)"1900-01-01") || country_of_birth_std != old_cob || country_of_citizenship_std != old_citizenship || foot_std != old_foot || height_band != old_height_band || REPLACENULL(contract_expiry_year,(DT_I2)-1) != REPLACENULL(old_cey,(DT_I2)-1) || international_caps_band != old_caps_band
    ```
  - **Unchanged** (mặc định): các dòng còn lại

**3.2.4.10. Thêm cầu thủ mới vào Dim_Player** · *OLE DB Destination*

Ghi dữ liệu vào bảng đích (Fast load).

- **Kết nối:** `localhost.football_dwh_dw` — **Bảng đích:** `[dbo].[dim_player]` — **Chế độ:** Table or view – fast load
- **Ánh xạ cột (13):** `c_player_id`→`player_id`, `full_name_std`→`full_name`, `c_date_of_birth`→`date_of_birth`, `country_of_birth_std`→`country_of_birth`, `country_of_citizenship_std`→`citizenship`, `position_std`→`position`, `sub_position_std`→`sub_position`, `foot_std`→`foot`, `height_band`, `agent_name_std`→`agent_name`, `contract_expiry_year`, `international_caps_band`, `batch_id`

**3.2.4.11. Ghi đè thay đổi SCD1** · *OLE DB Command*

Chạy câu lệnh SQL cho **từng dòng** (cập nhật dimension theo SCD).

- **Kết nối:** `localhost.football_dwh_dw`
- **Câu lệnh:**

```sql
UPDATE dbo.dim_player SET full_name = ?, date_of_birth = ?, country_of_birth = ?, citizenship = ?, foot = ?, height_band = ?, contract_expiry_year = ?, international_caps_band = ?, batch_id = ? WHERE player_id = ?
```
- **Tham số `?`:** `full_name_std`→Param_0, `c_date_of_birth`→Param_1, `country_of_birth_std`→Param_2, `country_of_citizenship_std`→Param_3, `foot_std`→Param_4, `height_band`→Param_5, `contract_expiry_year`→Param_6, `international_caps_band`→Param_7, `batch_id`→Param_8, `c_player_id`→Param_9

**3.2.4.12. Tạo phiên bản mới SCD2** · *OLE DB Command*

Chạy câu lệnh SQL cho **từng dòng** (cập nhật dimension theo SCD).

- **Kết nối:** `localhost.football_dwh_dw`
- **Câu lệnh:**

```sql
EXEC dbo.usp_DimPlayer_NewVersion ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
```
- **Tham số `?`:** `player_key`→@player_key, `full_name_std`→@full_name, `c_date_of_birth`→@date_of_birth, `country_of_birth_std`→@country_of_birth, `country_of_citizenship_std`→@citizenship, `position_std`→@position, `sub_position_std`→@sub_position, `foot_std`→@foot, `height_band`→@height_band, `agent_name_std`→@agent_name, `contract_expiry_year`→@contract_expiry_year, `international_caps_band`→@international_caps_band, `batch_id`→@batch_id

#### 3.2.5. Nạp Dim_Match (SCD1)

| Đích | Cách nạp | Số component |
|---|---|---|
| `Dim_Match` | SCD Type 1 | 11 |

Nạp thông tin mô tả trận đấu từ `stg_raw_games`: vòng đấu, loại vòng (suy ra), sân, trọng tài, sơ đồ chiến thuật, nhóm số khán giả.

**Luồng dữ liệu** (component nguồn ──[output]──► component đích):

```
Đọc trận đấu từ Staging                          ────► Làm sạch chuỗi
Làm sạch chuỗi                                   ────► Ép kiểu dữ liệu
Ép kiểu dữ liệu                                  ────► Loại trùng theo game_id
Ép kiểu dữ liệu                                  ── [Data Conversion Error Output]──► Ghi lý do lỗi ép kiểu
Loại trùng theo game_id                          ────► Chuẩn hóa và tính loại vòng nhóm khán giả
Ghi lý do lỗi ép kiểu                            ────► Lưu dòng lỗi ép kiểu vào etl_reject
Chuẩn hóa và tính loại vòng nhóm khán giả        ────► Kiểm tra trận đã có trong kho
Kiểm tra trận đã có trong kho                    ── [Lookup No Match Output]──► Thêm trận mới vào Dim_Match
Kiểm tra trận đã có trong kho                    ── [Lookup Match Output]──► Tìm trận có thuộc tính thay đổi
Tìm trận có thuộc tính thay đổi                  ── [Changed]──► Ghi đè thay đổi SCD1
```

**Chi tiết từng component:**

**3.2.5.1. Đọc trận đấu từ Staging** · *OLE DB Source*

Đọc dữ liệu từ Staging. Câu SQL chỉ `CAST` các cột cần dùng sang `NVARCHAR(n)`: bảng stage lưu `NVARCHAR(MAX)`, SSIS đọc kiểu này thành `DT_NTEXT` và không áp dụng được hàm chuỗi, nên phải đổi sang chuỗi có độ dài.

- **Kết nối:** `localhost.football_dwh_staging`
- **Câu truy vấn:**

```sql
SELECT CAST(game_id AS NVARCHAR(20)) AS game_id,
       CAST([round] AS NVARCHAR(100)) AS round,
       CAST(stadium AS NVARCHAR(200)) AS stadium,
       CAST(referee AS NVARCHAR(200)) AS referee,
       CAST(home_club_formation AS NVARCHAR(30)) AS home_formation,
       CAST(away_club_formation AS NVARCHAR(30)) AS away_formation,
       CAST(attendance AS NVARCHAR(20)) AS attendance,
       CAST(batch_id AS NVARCHAR(30)) AS batch_id
FROM dbo.stg_raw_games
```

**3.2.5.2. Làm sạch chuỗi** · *Derived Column*

Làm sạch chuỗi: bỏ khoảng trắng đầu/cuối (`TRIM`), thay ký tự khoảng trắng đặc biệt NBSP (`\x00A0`), chuỗi rỗng → `NULL`. Các cột được **thay thế tại chỗ** (Replace).

- **Biểu thức:**
  - thay thế `game_id`:
    ```
    TRIM(REPLACENULL(game_id,"")) == "" ? NULL(DT_WSTR,20) : TRIM(game_id)
    ```
  - thay thế `round`:
    ```
    TRIM(REPLACE(REPLACENULL(round,""),"\x00A0"," ")) == "" ? NULL(DT_WSTR,100) : TRIM(REPLACE(round,"\x00A0"," "))
    ```
  - thay thế `stadium`:
    ```
    TRIM(REPLACE(REPLACENULL(stadium,""),"\x00A0"," ")) == "" ? NULL(DT_WSTR,200) : TRIM(REPLACE(stadium,"\x00A0"," "))
    ```
  - thay thế `referee`:
    ```
    TRIM(REPLACE(REPLACENULL(referee,""),"\x00A0"," ")) == "" ? NULL(DT_WSTR,200) : TRIM(REPLACE(referee,"\x00A0"," "))
    ```
  - thay thế `home_formation`:
    ```
    TRIM(REPLACE(REPLACENULL(home_formation,""),"\x00A0"," ")) == "" ? NULL(DT_WSTR,30) : TRIM(REPLACE(home_formation,"\x00A0"," "))
    ```
  - thay thế `away_formation`:
    ```
    TRIM(REPLACE(REPLACENULL(away_formation,""),"\x00A0"," ")) == "" ? NULL(DT_WSTR,30) : TRIM(REPLACE(away_formation,"\x00A0"," "))
    ```
  - thay thế `attendance`:
    ```
    TRIM(REPLACENULL(attendance,"")) == "" ? NULL(DT_WSTR,20) : TRIM(attendance)
    ```

**3.2.5.3. Ép kiểu dữ liệu** · *Data Conversion*

Ép kiểu chuỗi sang kiểu số/ngày (cột mới có tiền tố `c_`). Dòng ép kiểu lỗi **không làm dừng package** mà được chuyển (Redirect row) sang **Data Conversion Error Output** → ghi vào `etl_reject`.

- **Cột chuyển đổi:** `game_id` → `c_game_id` DT_I4; `attendance` → `c_attendance` DT_I4
- **Xử lý lỗi:** Redirect row → Data Conversion Error Output

**3.2.5.4. Loại trùng theo game_id** · *Sort*

Sắp xếp theo khóa tự nhiên và **loại dòng trùng khóa** (Remove rows with duplicate sort values).

- **Khóa sắp xếp:** `c_game_id`
- **Loại trùng:** Có (EliminateDuplicates = True)

**3.2.5.5. Ghi lý do lỗi ép kiểu** · *Derived Column*

Tạo 3 cột mô tả dòng bị loại (`source_table`, `natural_key`, `reason`) để ghi vào bảng `etl_reject`.

- **Biểu thức:**
  - cột mới `rj_source_table` (DT_WSTR(100)):
    ```
    (DT_WSTR,100)"stg_raw_games"
    ```
  - cột mới `rj_natural_key` (DT_WSTR(200)):
    ```
    (DT_WSTR,200)(REPLACENULL(game_id,""))
    ```
  - cột mới `rj_reason` (DT_WSTR(200)):
    ```
    (DT_WSTR,200)"Lỗi ép kiểu (game_id, attendance)"
    ```

**3.2.5.6. Chuẩn hóa và tính loại vòng nhóm khán giả** · *Derived Column*

Tính toán ở mức từng dòng ngay trong ETL (chuẩn hóa giá trị, nhóm hóa thành band, khóa ngày, cờ 0/1, measure dẫn xuất).

- **Biểu thức:**
  - cột mới `round_std` (DT_WSTR(100)):
    ```
    (DT_WSTR,100)REPLACENULL(round,"Không xác định")
    ```
  - cột mới `round_type` (DT_WSTR(20)):
    ```
    (DT_WSTR,20)(ISNULL(round) ? "Không xác định" : (FINDSTRING(round,"Matchday",1) > 0 ? "Matchday" : (FINDSTRING(round,"Group",1) > 0 ? "Group stage" : (round == "Final" ? "Final" : "Knockout"))))
    ```
  - cột mới `stadium_std` (DT_WSTR(200)):
    ```
    (DT_WSTR,200)REPLACENULL(stadium,"Không xác định")
    ```
  - cột mới `referee_std` (DT_WSTR(200)):
    ```
    (DT_WSTR,200)REPLACENULL(referee,"Không xác định")
    ```
  - cột mới `home_formation_std` (DT_WSTR(30)):
    ```
    (DT_WSTR,30)REPLACENULL(home_formation,"Không xác định")
    ```
  - cột mới `away_formation_std` (DT_WSTR(30)):
    ```
    (DT_WSTR,30)REPLACENULL(away_formation,"Không xác định")
    ```
  - cột mới `attendance_band` (DT_WSTR(30)):
    ```
    (DT_WSTR,30)(ISNULL(c_attendance) ? "Không xác định" : (c_attendance < 10000 ? "< 10.000" : (c_attendance < 30000 ? "10.000-29.999" : (c_attendance < 60000 ? "30.000-59.999" : ">= 60.000"))))
    ```

**3.2.5.7. Lưu dòng lỗi ép kiểu vào etl_reject** · *OLE DB Destination*

Ghi dữ liệu vào bảng đích (Fast load).

- **Kết nối:** `localhost.football_dwh_staging` — **Bảng đích:** `[dbo].[etl_reject]` — **Chế độ:** Table or view – fast load
- **Ánh xạ cột (4):** `batch_id`, `rj_source_table`→`source_table`, `rj_natural_key`→`natural_key`, `rj_reason`→`reason`

**3.2.5.8. Kiểm tra trận đã có trong kho** · *Lookup*

Tra dimension trong kho theo khóa tự nhiên: **Match** = đã có (đi tiếp để so sánh thay đổi), **No Match** = bản ghi mới (thêm vào dimension).

- **Kết nối:** `localhost.football_dwh_dw` — **Cache:** Full cache
- **Bảng tham chiếu:**

```sql
SELECT game_id, match_key, [round] AS old_round, round_type AS old_round_type, stadium AS old_stadium, referee AS old_referee, home_formation AS old_home_formation, away_formation AS old_away_formation, attendance_band AS old_attendance_band FROM dbo.dim_match WHERE match_key <> -1
```
- **Điều kiện nối:** `c_game_id` = `game_id`
- **Cột lấy về:** `match_key`, `old_round`, `old_round_type`, `old_stadium`, `old_referee`, `old_home_formation`, `old_away_formation`, `old_attendance_band`
- **Không tìm thấy:** Gửi sang **Lookup No Match Output**

**3.2.5.9. Thêm trận mới vào Dim_Match** · *OLE DB Destination*

Ghi dữ liệu vào bảng đích (Fast load).

- **Kết nối:** `localhost.football_dwh_dw` — **Bảng đích:** `[dbo].[dim_match]` — **Chế độ:** Table or view – fast load
- **Ánh xạ cột (9):** `c_game_id`→`game_id`, `round_std`→`round`, `round_type`, `stadium_std`→`stadium`, `referee_std`→`referee`, `home_formation_std`→`home_formation`, `away_formation_std`→`away_formation`, `attendance_band`, `batch_id`

**3.2.5.10. Tìm trận có thuộc tính thay đổi** · *Conditional Split*

Chia luồng theo điều kiện; điều kiện được xét theo thứ tự, dòng không thỏa điều kiện nào đi vào output mặc định.

- **Các output:**
  - **Changed** (thứ tự 1):
    ```
    round_std != old_round || round_type != old_round_type || stadium_std != old_stadium || referee_std != old_referee || home_formation_std != old_home_formation || away_formation_std != old_away_formation || attendance_band != old_attendance_band
    ```
  - **Unchanged** (mặc định): các dòng còn lại

**3.2.5.11. Ghi đè thay đổi SCD1** · *OLE DB Command*

Chạy câu lệnh SQL cho **từng dòng** (cập nhật dimension theo SCD).

- **Kết nối:** `localhost.football_dwh_dw`
- **Câu lệnh:**

```sql
UPDATE dbo.dim_match SET [round] = ?, round_type = ?, stadium = ?, referee = ?, home_formation = ?, away_formation = ?, attendance_band = ?, batch_id = ? WHERE match_key = ?
```
- **Tham số `?`:** `round_std`→Param_0, `round_type`→Param_1, `stadium_std`→Param_2, `referee_std`→Param_3, `home_formation_std`→Param_4, `away_formation_std`→Param_5, `attendance_band`→Param_6, `batch_id`→Param_7, `match_key`→Param_8

#### 3.2.6. Nạp Dim_Manager

| Đích | Cách nạp | Số component |
|---|---|---|
| `Dim_Manager` | Chỉ thêm mới | 8 |

Nguồn không có mã HLV nên tên HLV (sau khi chuẩn hóa) là khóa tự nhiên. Tên được gom từ cả hai cột `own_manager_name` và `opponent_manager_name` của `stg_raw_club_games`; chỉ thêm HLV chưa có.

**Luồng dữ liệu** (component nguồn ──[output]──► component đích):

```
Đọc tên HLV đối thủ                              ────► Gộp tên HLV
Đọc tên HLV đội                                  ────► Gộp tên HLV
Gộp tên HLV                                      ────► Làm sạch chuỗi
Làm sạch chuỗi                                   ────► Bỏ tên HLV trống
Bỏ tên HLV trống                                 ── [Has Name]──► Loại trùng theo tên HLV
Loại trùng theo tên HLV                          ────► Chỉ giữ HLV chưa có trong kho
Chỉ giữ HLV chưa có trong kho                    ── [Lookup No Match Output]──► Thêm HLV mới vào Dim_Manager
```

**Chi tiết từng component:**

**3.2.6.1. Đọc tên HLV đối thủ** · *OLE DB Source*

Đọc dữ liệu từ Staging. Câu SQL chỉ `CAST` các cột cần dùng sang `NVARCHAR(n)`: bảng stage lưu `NVARCHAR(MAX)`, SSIS đọc kiểu này thành `DT_NTEXT` và không áp dụng được hàm chuỗi, nên phải đổi sang chuỗi có độ dài.

- **Kết nối:** `localhost.football_dwh_staging`
- **Câu truy vấn:**

```sql
SELECT CAST(opponent_manager_name AS NVARCHAR(200)) AS manager_name, CAST(batch_id AS NVARCHAR(30)) AS batch_id
FROM dbo.stg_raw_club_games
```

**3.2.6.2. Đọc tên HLV đội** · *OLE DB Source*

Đọc dữ liệu từ Staging. Câu SQL chỉ `CAST` các cột cần dùng sang `NVARCHAR(n)`: bảng stage lưu `NVARCHAR(MAX)`, SSIS đọc kiểu này thành `DT_NTEXT` và không áp dụng được hàm chuỗi, nên phải đổi sang chuỗi có độ dài.

- **Kết nối:** `localhost.football_dwh_staging`
- **Câu truy vấn:**

```sql
SELECT CAST(own_manager_name AS NVARCHAR(200)) AS manager_name, CAST(batch_id AS NVARCHAR(30)) AS batch_id
FROM dbo.stg_raw_club_games
```

**3.2.6.3. Gộp tên HLV** · *Union All*

Gộp nhiều luồng nguồn thành một luồng.

- **Số luồng vào:** 3

**3.2.6.4. Làm sạch chuỗi** · *Derived Column*

Làm sạch chuỗi: bỏ khoảng trắng đầu/cuối (`TRIM`), thay ký tự khoảng trắng đặc biệt NBSP (`\x00A0`), chuỗi rỗng → `NULL`. Các cột được **thay thế tại chỗ** (Replace).

- **Biểu thức:**
  - thay thế `manager_name`:
    ```
    REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(TRIM(REPLACE(REPLACENULL(manager_name,""),"\x00A0"," ")) == "" ? NULL(DT_WSTR,200) : TRIM(REPLACE(manager_name,"\x00A0"," ")),"æ","ae"),"Æ","Ae"),"œ","oe"),"Œ","Oe"),"ß","ss")
    ```

**3.2.6.5. Bỏ tên HLV trống** · *Conditional Split*

Chia luồng theo điều kiện; điều kiện được xét theo thứ tự, dòng không thỏa điều kiện nào đi vào output mặc định.

- **Các output:**
  - **No Name** (thứ tự 1):
    ```
    ISNULL(manager_name)
    ```
  - **Has Name** (mặc định): các dòng còn lại

**3.2.6.6. Loại trùng theo tên HLV** · *Sort*

Sắp xếp theo khóa tự nhiên và **loại dòng trùng khóa** (Remove rows with duplicate sort values).

- **Khóa sắp xếp:** `manager_name`
- **Loại trùng:** Có (EliminateDuplicates = True)

**3.2.6.7. Chỉ giữ HLV chưa có trong kho** · *Lookup*

Tra dimension trong kho theo khóa tự nhiên: **Match** = đã có (đi tiếp để so sánh thay đổi), **No Match** = bản ghi mới (thêm vào dimension).

- **Kết nối:** `localhost.football_dwh_dw` — **Cache:** Full cache
- **Bảng tham chiếu:**

```sql
SELECT manager_name, manager_key FROM dbo.dim_manager
```
- **Điều kiện nối:** `manager_name` = `manager_name`
- **Cột lấy về:** `manager_key`
- **Không tìm thấy:** Gửi sang **Lookup No Match Output**

**3.2.6.8. Thêm HLV mới vào Dim_Manager** · *OLE DB Destination*

Ghi dữ liệu vào bảng đích (Fast load).

- **Kết nối:** `localhost.football_dwh_dw` — **Bảng đích:** `[dbo].[dim_manager]` — **Chế độ:** Table or view – fast load
- **Ánh xạ cột (2):** `manager_name`, `batch_id`

---

## 4. 03 - Làm sạch tính toán và nạp Fact

**Mục đích (Transform + Load):** làm sạch, tính các measure mức từng dòng và nạp **4 fact chi tiết** theo cửa sổ thời gian `LoadFrom`–`LoadTo` (chỉ thêm dòng chưa có). Không bảng fact nào bị TRUNCATE, UPDATE hay DELETE.

### 4.1. Control Flow

```
Ghi cửa sổ nạp gia tăng
   ──► Ghi nhật ký bắt đầu lần chạy
   ──► Nạp Fact_Team_Match
   ──► Nạp Fact_Player_Appearance
   ──► Nạp Fact_Player_Valuation
   ──► Nạp Fact_Transfer
   ──► Ghi nhật ký kết thúc lần chạy
```

**Ghi cửa sổ nạp gia tăng** · *Execute SQL Task* — kết nối `localhost.football_dwh_dw`. Thuộc tính `SqlStatementSource` được sinh bằng **Expression** từ hai biến `LoadFrom`, `LoadTo`:

```
"UPDATE dbo.etl_load_window SET window_from = '" + (DT_WSTR,4)YEAR(@[User::LoadFrom]) + "-" + RIGHT("0" + (DT_WSTR,2)MONTH(@[User::LoadFrom]), 2) + "-" + RIGHT("0" + (DT_WSTR,2)DAY(@[User::LoadFrom]), 2) + "', window_to = '" + (DT_WSTR,4)YEAR(@[User::LoadTo]) + "-" + RIGHT("0" + (DT_WSTR,2)MONTH(@[User::LoadTo]), 2) + "-" + RIGHT("0" + (DT_WSTR,2)DAY(@[User::LoadTo]), 2) + "' WHERE id = 1;\nDELETE FROM football_dwh_staging.dbo.etl_reject\nWHERE source_table IN (N'stg_raw_club_games', N'stg_raw_appearances', N'stg_raw_player_valuations', N'stg_raw_transfers');\n"
```

Câu lệnh thực tế khi chạy (với giá trị biến hiện tại):

```sql
UPDATE dbo.etl_load_window SET window_from = '1900-01-01', window_to = '9999-12-31' WHERE id = 1;
DELETE FROM football_dwh_staging.dbo.etl_reject
WHERE source_table IN (N'stg_raw_club_games', N'stg_raw_appearances', N'stg_raw_player_valuations', N'stg_raw_transfers');
```

Ý nghĩa: (1) ghi cửa sổ nạp vào bảng điều khiển `etl_load_window` để truy vết lần nạp; (2) xóa các dòng reject cũ của fact trong Staging. Task này **không cập nhật bảng phân tích nào** trong kho.

**Ghi nhật ký bắt đầu lần chạy** · *Execute SQL Task* — kết nối `localhost.football_dwh_dw`. Thêm 1 dòng vào etl_batch: mã lần chạy, cửa sổ nạp, giờ bắt đầu, tổng số dòng fact trước khi nạp; lần chạy trước còn RUNNING (bị dừng giữa chừng) đánh dấu FAILED. Câu lệnh thực tế khi chạy:

```sql
UPDATE dbo.etl_batch SET status = N'FAILED' WHERE status = N'RUNNING';
INSERT INTO dbo.etl_batch (batch_id, window_from, window_to, started_at, status, fact_rows_before)
VALUES (N'BATCH_20261018_224515', '1900-01-01', '9999-12-31', '2026-10-18 22:45:15', N'RUNNING',
        (SELECT COUNT(*) FROM dbo.fact_team_match) + (SELECT COUNT(*) FROM dbo.fact_player_appearance) + (SELECT COUNT(*) FROM dbo.fact_player_valuation) + (SELECT COUNT(*) FROM dbo.fact_transfer));
```

**Ghi nhật ký kết thúc lần chạy** · *Execute SQL Task* — kết nối `localhost.football_dwh_dw`. Cập nhật dòng etl_batch của lần chạy này: giờ kết thúc, trạng thái SUCCESS, tổng số dòng fact sau khi nạp. Câu lệnh thực tế khi chạy:

```sql
UPDATE dbo.etl_batch SET finished_at = GETDATE(), status = N'SUCCESS',
       fact_rows_after = (SELECT COUNT(*) FROM dbo.fact_team_match) + (SELECT COUNT(*) FROM dbo.fact_player_appearance) + (SELECT COUNT(*) FROM dbo.fact_player_valuation) + (SELECT COUNT(*) FROM dbo.fact_transfer)
WHERE batch_id = N'BATCH_20261018_224515';
```

Ý nghĩa: mỗi lần chạy có đúng 1 dòng trong `etl_batch`. So `fact_rows_before` và `fact_rows_after` để thấy lần nạp đó thêm bao nhiêu dòng (lần chạy lại toàn bộ thì hai số bằng nhau). Nếu một lần chạy dừng giữa chừng, dòng của nó còn `RUNNING`; lần chạy sau sẽ đổi thành `FAILED`. Dòng fact nào cũng truy được về lần chạy đã nạp nó qua `batch_id`.

### 4.2. Khung xử lý chung của 4 Data Flow fact chi tiết

| Bước | Component | Xử lý | Dòng không đạt |
|---|---|---|---|
| 1 | Đọc … từ Staging | Đọc stage, CAST cột cần dùng | |
| 2 | Làm sạch chuỗi | TRIM, bỏ NBSP, rỗng → NULL | |
| 3 | Ép kiểu dữ liệu | Ép kiểu số, ngày | Lỗi ép kiểu → `etl_reject` |
| 4 | Kiểm tra hợp lệ và cửa sổ nạp | Quy tắc nghiệp vụ + cửa sổ nạp | Vi phạm → `etl_reject`; ngoài cửa sổ → bỏ qua |
| 5 | Loại trùng theo … | Loại trùng theo khóa tự nhiên | |
| 6 | Tính … | Tính measure mức từng dòng (cờ, tuổi, phí chênh, khóa ngày) | |
| 7 | Tra khóa … | Tra surrogate key | Không thấy → NULL |
| 8 | Gán khóa Unknown … | NULL → -1 | |
| 9 | Bỏ qua dòng đã có trong Fact | Tra chính bảng fact | Đã có → bỏ qua |
| 10 | Ghi vào Fact_… | Fast load dòng mới | |

Output **Out Of Window** của *Kiểm tra hợp lệ và cửa sổ nạp* **không nối tới đâu**: các sự kiện nằm ngoài cửa sổ được bỏ qua ở lần chạy này và nạp ở lần chạy có cửa sổ phù hợp.

### 4.3. Các Data Flow

#### 4.3.1. Nạp Fact_Team_Match

| Đích | Cách nạp | Số component |
|---|---|---|
| `Fact_Team_Match` | Nạp gia tăng | 21 |

Grain: 1 đội trong 1 trận. Nguồn `stg_raw_club_games`, lấy thêm ngày, mùa, giải của trận từ `stg_raw_games`. Các measure thắng/hòa/thua/sạch lưới được tính lại từ tỉ số. Tra 7 khóa dimension (Club và Manager dùng 2 vai: đội và đối thủ).

**Luồng dữ liệu** (component nguồn ──[output]──► component đích):

```
Đọc kết quả trận theo đội từ Staging             ────► Lấy ngày mùa và giải của trận
Lấy ngày mùa và giải của trận                    ── [Lookup Match Output]──► Làm sạch chuỗi
Làm sạch chuỗi                                   ────► Ép kiểu dữ liệu
Ép kiểu dữ liệu                                  ────► Kiểm tra hợp lệ và cửa sổ nạp
Ép kiểu dữ liệu                                  ── [Data Conversion Error Output]──► Ghi lý do lỗi ép kiểu
Kiểm tra hợp lệ và cửa sổ nạp                    ── [Valid]──► Loại trùng theo trận và CLB
Kiểm tra hợp lệ và cửa sổ nạp                    ── [Reject]──► Ghi lý do vi phạm quy tắc
Ghi lý do lỗi ép kiểu                            ────► Lưu dòng lỗi ép kiểu vào etl_reject
Loại trùng theo trận và CLB                      ────► Tính kết quả trận và khóa ngày
Ghi lý do vi phạm quy tắc                        ────► Lưu dòng vi phạm quy tắc vào etl_reject
Tính kết quả trận và khóa ngày                   ────► Tra khóa mùa giải
Tra khóa mùa giải                                ── [Lookup Match Output]──► Tra khóa giải đấu
Tra khóa giải đấu                                ── [Lookup Match Output]──► Tra khóa trận đấu
Tra khóa trận đấu                                ── [Lookup Match Output]──► Tra khóa CLB
Tra khóa CLB                                     ── [Lookup Match Output]──► Tra khóa CLB đối thủ
Tra khóa CLB đối thủ                             ── [Lookup Match Output]──► Tra khóa HLV
Tra khóa HLV                                     ── [Lookup Match Output]──► Tra khóa HLV đối thủ
Tra khóa HLV đối thủ                             ── [Lookup Match Output]──► Gán khóa Unknown cho khóa không tra được
Gán khóa Unknown cho khóa không tra được         ────► Bỏ qua dòng đã có trong Fact
Bỏ qua dòng đã có trong Fact                     ── [Lookup No Match Output]──► Ghi vào Fact_Team_Match
```

**Chi tiết từng component:**

**4.3.1.1. Đọc kết quả trận theo đội từ Staging** · *OLE DB Source*

Đọc dữ liệu từ Staging. Câu SQL chỉ `CAST` các cột cần dùng sang `NVARCHAR(n)`: bảng stage lưu `NVARCHAR(MAX)`, SSIS đọc kiểu này thành `DT_NTEXT` và không áp dụng được hàm chuỗi, nên phải đổi sang chuỗi có độ dài.

- **Kết nối:** `localhost.football_dwh_staging`
- **Câu truy vấn:**

```sql
SELECT CAST(game_id AS NVARCHAR(20)) AS game_id,
       CAST(club_id AS NVARCHAR(20)) AS club_id,
       CAST(opponent_id AS NVARCHAR(20)) AS opponent_id,
       CAST(own_goals AS NVARCHAR(10)) AS own_goals,
       CAST(opponent_goals AS NVARCHAR(10)) AS opponent_goals,
       CAST(own_position AS NVARCHAR(10)) AS own_position,
       CAST(own_manager_name AS NVARCHAR(200)) AS own_manager_name,
       CAST(opponent_manager_name AS NVARCHAR(200)) AS opponent_manager_name,
       CAST(hosting AS NVARCHAR(10)) AS hosting,
       CAST(batch_id AS NVARCHAR(30)) AS batch_id
FROM dbo.stg_raw_club_games
```

**4.3.1.2. Lấy ngày mùa và giải của trận** · *Lookup*

Tra cứu thêm thông tin từ một bảng Staging khác.

- **Kết nối:** `localhost.football_dwh_staging` — **Cache:** Full cache
- **Bảng tham chiếu:**

```sql
SELECT CAST(game_id AS NVARCHAR(20)) AS game_id, CAST([date] AS NVARCHAR(30)) AS game_date_raw, CAST(season AS NVARCHAR(10)) AS season_raw, CAST(competition_id AS NVARCHAR(20)) AS game_competition_id FROM dbo.stg_raw_games
```
- **Điều kiện nối:** `game_id` = `game_id`
- **Cột lấy về:** `game_date_raw`, `season_raw`, `competition_id`
- **Không tìm thấy:** Bỏ qua lỗi (Ignore failure): các cột trả về = NULL

**4.3.1.3. Làm sạch chuỗi** · *Derived Column*

Làm sạch chuỗi: bỏ khoảng trắng đầu/cuối (`TRIM`), thay ký tự khoảng trắng đặc biệt NBSP (`\x00A0`), chuỗi rỗng → `NULL`. Các cột được **thay thế tại chỗ** (Replace).

- **Biểu thức:**
  - thay thế `game_id`:
    ```
    TRIM(REPLACENULL(game_id,"")) == "" ? NULL(DT_WSTR,20) : TRIM(game_id)
    ```
  - thay thế `club_id`:
    ```
    TRIM(REPLACENULL(club_id,"")) == "" ? NULL(DT_WSTR,20) : TRIM(club_id)
    ```
  - thay thế `opponent_id`:
    ```
    TRIM(REPLACENULL(opponent_id,"")) == "" ? NULL(DT_WSTR,20) : TRIM(opponent_id)
    ```
  - thay thế `own_goals`:
    ```
    TRIM(REPLACENULL(own_goals,"")) == "" ? NULL(DT_WSTR,10) : TRIM(own_goals)
    ```
  - thay thế `opponent_goals`:
    ```
    TRIM(REPLACENULL(opponent_goals,"")) == "" ? NULL(DT_WSTR,10) : TRIM(opponent_goals)
    ```
  - thay thế `own_position`:
    ```
    TRIM(REPLACENULL(own_position,"")) == "" || TRIM(own_position) == "-1" ? NULL(DT_WSTR,10) : TRIM(own_position)
    ```
  - thay thế `own_manager_name`:
    ```
    REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(TRIM(REPLACE(REPLACENULL(own_manager_name,""),"\x00A0"," ")) == "" ? NULL(DT_WSTR,200) : TRIM(REPLACE(own_manager_name,"\x00A0"," ")),"æ","ae"),"Æ","Ae"),"œ","oe"),"Œ","Oe"),"ß","ss")
    ```
  - thay thế `opponent_manager_name`:
    ```
    REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(TRIM(REPLACE(REPLACENULL(opponent_manager_name,""),"\x00A0"," ")) == "" ? NULL(DT_WSTR,200) : TRIM(REPLACE(opponent_manager_name,"\x00A0"," ")),"æ","ae"),"Æ","Ae"),"œ","oe"),"Œ","Oe"),"ß","ss")
    ```
  - thay thế `hosting`:
    ```
    TRIM(REPLACE(REPLACENULL(hosting,""),"\x00A0"," ")) == "" ? NULL(DT_WSTR,10) : TRIM(REPLACE(hosting,"\x00A0"," "))
    ```
  - thay thế `game_date_raw`:
    ```
    TRIM(REPLACENULL(game_date_raw,"")) == "" ? NULL(DT_WSTR,30) : SUBSTRING(TRIM(game_date_raw),1,10)
    ```
  - thay thế `season_raw`:
    ```
    TRIM(REPLACENULL(season_raw,"")) == "" ? NULL(DT_WSTR,10) : TRIM(season_raw)
    ```
  - thay thế `competition_id`:
    ```
    TRIM(REPLACE(REPLACENULL(competition_id,""),"\x00A0"," ")) == "" ? NULL(DT_WSTR,20) : TRIM(REPLACE(competition_id,"\x00A0"," "))
    ```

**4.3.1.4. Ép kiểu dữ liệu** · *Data Conversion*

Ép kiểu chuỗi sang kiểu số/ngày (cột mới có tiền tố `c_`). Dòng ép kiểu lỗi **không làm dừng package** mà được chuyển (Redirect row) sang **Data Conversion Error Output** → ghi vào `etl_reject`.

- **Cột chuyển đổi:** `game_id` → `c_game_id` DT_I4; `club_id` → `c_club_id` DT_I4; `opponent_id` → `c_opponent_id` DT_I4; `own_goals` → `c_own_goals` DT_I2; `opponent_goals` → `c_opponent_goals` DT_I2; `own_position` → `c_own_position` DT_I2; `game_date_raw` → `c_game_date` DT_DBDATE; `season_raw` → `c_season` DT_I2
- **Xử lý lỗi:** Redirect row → Data Conversion Error Output

**4.3.1.5. Kiểm tra hợp lệ và cửa sổ nạp** · *Conditional Split*

Chia luồng theo điều kiện; điều kiện được xét theo thứ tự, dòng không thỏa điều kiện nào đi vào output mặc định.

- **Các output:**
  - **Reject** (thứ tự 1):
    ```
    ISNULL(c_game_id) || ISNULL(c_club_id) || ISNULL(c_own_goals) || ISNULL(c_opponent_goals) || ISNULL(c_game_date)
    ```
  - **Out Of Window** (thứ tự 2):
    ```
    c_game_date < (DT_DBDATE)@[User::LoadFrom] || c_game_date > (DT_DBDATE)@[User::LoadTo]
    ```
  - **Valid** (mặc định): các dòng còn lại

**4.3.1.6. Ghi lý do lỗi ép kiểu** · *Derived Column*

Tạo 3 cột mô tả dòng bị loại (`source_table`, `natural_key`, `reason`) để ghi vào bảng `etl_reject`.

- **Biểu thức:**
  - cột mới `rj_source_table` (DT_WSTR(100)):
    ```
    (DT_WSTR,100)"stg_raw_club_games"
    ```
  - cột mới `rj_natural_key` (DT_WSTR(200)):
    ```
    (DT_WSTR,200)(REPLACENULL(game_id,"") + "|" + REPLACENULL(club_id,""))
    ```
  - cột mới `rj_reason` (DT_WSTR(200)):
    ```
    (DT_WSTR,200)"Lỗi ép kiểu (Data Conversion)"
    ```

**4.3.1.7. Loại trùng theo trận và CLB** · *Sort*

Sắp xếp theo khóa tự nhiên và **loại dòng trùng khóa** (Remove rows with duplicate sort values).

- **Khóa sắp xếp:** `c_game_id`, `c_club_id`
- **Loại trùng:** Có (EliminateDuplicates = True)

**4.3.1.8. Ghi lý do vi phạm quy tắc** · *Derived Column*

Tạo 3 cột mô tả dòng bị loại (`source_table`, `natural_key`, `reason`) để ghi vào bảng `etl_reject`.

- **Biểu thức:**
  - cột mới `rj_source_table` (DT_WSTR(100)):
    ```
    (DT_WSTR,100)"stg_raw_club_games"
    ```
  - cột mới `rj_natural_key` (DT_WSTR(200)):
    ```
    (DT_WSTR,200)(REPLACENULL(game_id,"") + "|" + REPLACENULL(club_id,""))
    ```
  - cột mới `rj_reason` (DT_WSTR(200)):
    ```
    (DT_WSTR,200)"Thiếu khóa, tỉ số hoặc không tìm thấy trận"
    ```

**4.3.1.9. Lưu dòng lỗi ép kiểu vào etl_reject** · *OLE DB Destination*

Ghi dữ liệu vào bảng đích (Fast load).

- **Kết nối:** `localhost.football_dwh_staging` — **Bảng đích:** `[dbo].[etl_reject]` — **Chế độ:** Table or view – fast load
- **Ánh xạ cột (4):** `batch_id`, `rj_source_table`→`source_table`, `rj_natural_key`→`natural_key`, `rj_reason`→`reason`

**4.3.1.10. Tính kết quả trận và khóa ngày** · *Derived Column*

Tính toán ở mức từng dòng ngay trong ETL (chuẩn hóa giá trị, nhóm hóa thành band, khóa ngày, cờ 0/1, measure dẫn xuất).

- **Biểu thức:**
  - cột mới `date_key` (DT_I4):
    ```
    (DT_I4)(YEAR(c_game_date) * 10000 + MONTH(c_game_date) * 100 + DAY(c_game_date))
    ```
  - cột mới `is_home` (DT_UI1):
    ```
    (DT_UI1)(hosting == "Home" ? 1 : 0)
    ```
  - cột mới `is_win` (DT_UI1):
    ```
    (DT_UI1)(c_own_goals > c_opponent_goals ? 1 : 0)
    ```
  - cột mới `is_draw` (DT_UI1):
    ```
    (DT_UI1)(c_own_goals == c_opponent_goals ? 1 : 0)
    ```
  - cột mới `is_loss` (DT_UI1):
    ```
    (DT_UI1)(c_own_goals < c_opponent_goals ? 1 : 0)
    ```
  - cột mới `is_clean_sheet` (DT_UI1):
    ```
    (DT_UI1)(c_opponent_goals == 0 ? 1 : 0)
    ```
  - cột mới `manager_name_std` (DT_WSTR(200)):
    ```
    (DT_WSTR,200)REPLACENULL(own_manager_name,"Không xác định")
    ```
  - cột mới `opponent_manager_name_std` (DT_WSTR(200)):
    ```
    (DT_WSTR,200)REPLACENULL(opponent_manager_name,"Không xác định")
    ```
  - cột mới `points` (DT_UI1):
    ```
    (DT_UI1)(c_own_goals > c_opponent_goals ? 3 : (c_own_goals == c_opponent_goals ? 1 : 0))
    ```
  - cột mới `goal_difference` (DT_I2):
    ```
    (DT_I2)(c_own_goals - c_opponent_goals)
    ```

**4.3.1.11. Lưu dòng vi phạm quy tắc vào etl_reject** · *OLE DB Destination*

Ghi dữ liệu vào bảng đích (Fast load).

- **Kết nối:** `localhost.football_dwh_staging` — **Bảng đích:** `[dbo].[etl_reject]` — **Chế độ:** Table or view – fast load
- **Ánh xạ cột (4):** `batch_id`, `rj_source_table`→`source_table`, `rj_natural_key`→`natural_key`, `rj_reason`→`reason`

**4.3.1.12. Tra khóa mùa giải** · *Lookup*

Tra **surrogate key** của dimension theo khóa tự nhiên. Không tìm thấy thì bỏ qua lỗi (Ignore failure) → khóa = NULL, sau đó đổi thành -1.

- **Kết nối:** `localhost.football_dwh_dw` — **Cache:** Full cache
- **Bảng tham chiếu:**

```sql
SELECT season_start_year, season_key FROM dbo.dim_season WHERE season_key <> -1
```
- **Điều kiện nối:** `c_season` = `season_start_year`
- **Cột lấy về:** `season_key`
- **Không tìm thấy:** Bỏ qua lỗi (Ignore failure): các cột trả về = NULL

**4.3.1.13. Tra khóa giải đấu** · *Lookup*

Tra **surrogate key** của dimension theo khóa tự nhiên. Không tìm thấy thì bỏ qua lỗi (Ignore failure) → khóa = NULL, sau đó đổi thành -1.

- **Kết nối:** `localhost.football_dwh_dw` — **Cache:** Full cache
- **Bảng tham chiếu:**

```sql
SELECT competition_id, competition_key FROM dbo.dim_competition
```
- **Điều kiện nối:** `competition_id` = `competition_id`
- **Cột lấy về:** `competition_key`
- **Không tìm thấy:** Bỏ qua lỗi (Ignore failure): các cột trả về = NULL

**4.3.1.14. Tra khóa trận đấu** · *Lookup*

Tra **surrogate key** của dimension theo khóa tự nhiên. Không tìm thấy thì bỏ qua lỗi (Ignore failure) → khóa = NULL, sau đó đổi thành -1.

- **Kết nối:** `localhost.football_dwh_dw` — **Cache:** Full cache
- **Bảng tham chiếu:**

```sql
SELECT game_id, match_key FROM dbo.dim_match
```
- **Điều kiện nối:** `c_game_id` = `game_id`
- **Cột lấy về:** `match_key`
- **Không tìm thấy:** Bỏ qua lỗi (Ignore failure): các cột trả về = NULL

**4.3.1.15. Tra khóa CLB** · *Lookup*

Tra **surrogate key** của dimension theo khóa tự nhiên. Không tìm thấy thì bỏ qua lỗi (Ignore failure) → khóa = NULL, sau đó đổi thành -1.

- **Kết nối:** `localhost.football_dwh_dw` — **Cache:** Full cache
- **Bảng tham chiếu:**

```sql
SELECT club_id, club_key FROM dbo.dim_club WHERE is_current = 1
```
- **Điều kiện nối:** `c_club_id` = `club_id`
- **Cột lấy về:** `club_key`
- **Không tìm thấy:** Bỏ qua lỗi (Ignore failure): các cột trả về = NULL

**4.3.1.16. Tra khóa CLB đối thủ** · *Lookup*

Tra **surrogate key** của dimension theo khóa tự nhiên. Không tìm thấy thì bỏ qua lỗi (Ignore failure) → khóa = NULL, sau đó đổi thành -1.

- **Kết nối:** `localhost.football_dwh_dw` — **Cache:** Full cache
- **Bảng tham chiếu:**

```sql
SELECT club_id, club_key FROM dbo.dim_club WHERE is_current = 1
```
- **Điều kiện nối:** `c_opponent_id` = `club_id`
- **Cột lấy về:** `opponent_club_key`
- **Không tìm thấy:** Bỏ qua lỗi (Ignore failure): các cột trả về = NULL

**4.3.1.17. Tra khóa HLV** · *Lookup*

Tra **surrogate key** của dimension theo khóa tự nhiên. Không tìm thấy thì bỏ qua lỗi (Ignore failure) → khóa = NULL, sau đó đổi thành -1.

- **Kết nối:** `localhost.football_dwh_dw` — **Cache:** Full cache
- **Bảng tham chiếu:**

```sql
SELECT manager_name, manager_key FROM dbo.dim_manager
```
- **Điều kiện nối:** `manager_name_std` = `manager_name`
- **Cột lấy về:** `manager_key`
- **Không tìm thấy:** Bỏ qua lỗi (Ignore failure): các cột trả về = NULL

**4.3.1.18. Tra khóa HLV đối thủ** · *Lookup*

Tra **surrogate key** của dimension theo khóa tự nhiên. Không tìm thấy thì bỏ qua lỗi (Ignore failure) → khóa = NULL, sau đó đổi thành -1.

- **Kết nối:** `localhost.football_dwh_dw` — **Cache:** Full cache
- **Bảng tham chiếu:**

```sql
SELECT manager_name, manager_key FROM dbo.dim_manager
```
- **Điều kiện nối:** `opponent_manager_name_std` = `manager_name`
- **Cột lấy về:** `opponent_manager_key`
- **Không tìm thấy:** Bỏ qua lỗi (Ignore failure): các cột trả về = NULL

**4.3.1.19. Gán khóa Unknown cho khóa không tra được** · *Derived Column*

Khóa dimension không tra được (NULL) được thay bằng **-1**, trỏ về dòng Unknown của dimension.

- **Biểu thức:**
  - thay thế `season_key`:
    ```
    REPLACENULL(season_key,-1)
    ```
  - thay thế `competition_key`:
    ```
    REPLACENULL(competition_key,-1)
    ```
  - thay thế `match_key`:
    ```
    REPLACENULL(match_key,-1)
    ```
  - thay thế `club_key`:
    ```
    REPLACENULL(club_key,-1)
    ```
  - thay thế `opponent_club_key`:
    ```
    REPLACENULL(opponent_club_key,-1)
    ```
  - thay thế `manager_key`:
    ```
    REPLACENULL(manager_key,-1)
    ```
  - thay thế `opponent_manager_key`:
    ```
    REPLACENULL(opponent_manager_key,-1)
    ```

**4.3.1.20. Bỏ qua dòng đã có trong Fact** · *Lookup*

**Lookup chính bảng fact** theo khóa của grain: dòng đã có trong kho đi vào Match Output và **bị bỏ** (không nối tiếp); chỉ dòng **No Match** (chưa có) mới được nạp → chạy lại nhiều lần không sinh dữ liệu trùng, dữ liệu đã ghi không bị sửa.

- **Kết nối:** `localhost.football_dwh_dw` — **Cache:** Full cache
- **Bảng tham chiếu:**

```sql
SELECT match_key, club_key FROM dbo.fact_team_match
```
- **Điều kiện nối:** `match_key` = `match_key`, `club_key` = `club_key`
- **Cột lấy về:** (không lấy cột nào — chỉ kiểm tra tồn tại)
- **Không tìm thấy:** Gửi sang **Lookup No Match Output**

**4.3.1.21. Ghi vào Fact_Team_Match** · *OLE DB Destination*

Ghi dữ liệu vào bảng đích (Fast load).

- **Kết nối:** `localhost.football_dwh_dw` — **Bảng đích:** `[dbo].[fact_team_match]` — **Chế độ:** Table or view – fast load
- **Ánh xạ cột (19):** `date_key`, `season_key`, `competition_key`, `match_key`, `club_key`, `opponent_club_key`, `manager_key`, `opponent_manager_key`, `is_home`, `c_own_goals`→`goals_for`, `c_opponent_goals`→`goals_against`, `is_win`, `is_draw`, `is_loss`, `is_clean_sheet`, `c_own_position`→`league_position`, `batch_id`, `points`, `goal_difference`

#### 4.3.2. Nạp Fact_Player_Appearance

| Đích | Cách nạp | Số component |
|---|---|---|
| `Fact_Player_Appearance` | Nạp gia tăng | 19 |

Grain: 1 cầu thủ ra sân trong 1 trận. Nguồn `stg_raw_appearances` (~1,9 triệu dòng); mùa giải lấy từ `stg_raw_games` qua `game_id`. `appearance_id` là khóa tự nhiên để chặn nạp trùng.

**Luồng dữ liệu** (component nguồn ──[output]──► component đích):

```
Đọc lượt ra sân từ Staging                       ────► Lấy mùa giải của trận
Lấy mùa giải của trận                            ── [Lookup Match Output]──► Làm sạch chuỗi
Làm sạch chuỗi                                   ────► Ép kiểu dữ liệu
Ép kiểu dữ liệu                                  ────► Kiểm tra hợp lệ và cửa sổ nạp
Ép kiểu dữ liệu                                  ── [Data Conversion Error Output]──► Ghi lý do lỗi ép kiểu
Kiểm tra hợp lệ và cửa sổ nạp                    ── [Valid]──► Loại trùng theo appearance_id
Kiểm tra hợp lệ và cửa sổ nạp                    ── [Reject]──► Ghi lý do vi phạm quy tắc
Ghi lý do lỗi ép kiểu                            ────► Lưu dòng lỗi ép kiểu vào etl_reject
Loại trùng theo appearance_id                    ────► Tính khóa ngày và cột đếm
Ghi lý do vi phạm quy tắc                        ────► Lưu dòng vi phạm quy tắc vào etl_reject
Tính khóa ngày và cột đếm                        ────► Tra khóa mùa giải
Tra khóa mùa giải                                ── [Lookup Match Output]──► Tra khóa giải đấu
Tra khóa giải đấu                                ── [Lookup Match Output]──► Tra khóa trận đấu
Tra khóa trận đấu                                ── [Lookup Match Output]──► Tra khóa cầu thủ
Tra khóa cầu thủ                                 ── [Lookup Match Output]──► Tra khóa CLB
Tra khóa CLB                                     ── [Lookup Match Output]──► Gán khóa Unknown cho khóa không tra được
Gán khóa Unknown cho khóa không tra được         ────► Bỏ qua dòng đã có trong Fact
Bỏ qua dòng đã có trong Fact                     ── [Lookup No Match Output]──► Ghi vào Fact_Player_Appearance
```

**Chi tiết từng component:**

**4.3.2.1. Đọc lượt ra sân từ Staging** · *OLE DB Source*

Đọc dữ liệu từ Staging. Câu SQL chỉ `CAST` các cột cần dùng sang `NVARCHAR(n)`: bảng stage lưu `NVARCHAR(MAX)`, SSIS đọc kiểu này thành `DT_NTEXT` và không áp dụng được hàm chuỗi, nên phải đổi sang chuỗi có độ dài.

- **Kết nối:** `localhost.football_dwh_staging`
- **Câu truy vấn:**

```sql
SELECT CAST(appearance_id AS NVARCHAR(50)) AS appearance_id,
       CAST(game_id AS NVARCHAR(20)) AS game_id,
       CAST(player_id AS NVARCHAR(20)) AS player_id,
       CAST(player_club_id AS NVARCHAR(20)) AS player_club_id,
       CAST([date] AS NVARCHAR(30)) AS game_date_raw,
       CAST(competition_id AS NVARCHAR(20)) AS competition_id,
       CAST(yellow_cards AS NVARCHAR(10)) AS yellow_cards,
       CAST(red_cards AS NVARCHAR(10)) AS red_cards,
       CAST(goals AS NVARCHAR(10)) AS goals,
       CAST(assists AS NVARCHAR(10)) AS assists,
       CAST(minutes_played AS NVARCHAR(10)) AS minutes_played,
       CAST(batch_id AS NVARCHAR(30)) AS batch_id
FROM dbo.stg_raw_appearances
```

**4.3.2.2. Lấy mùa giải của trận** · *Lookup*

Tra cứu thêm thông tin từ một bảng Staging khác.

- **Kết nối:** `localhost.football_dwh_staging` — **Cache:** Full cache
- **Bảng tham chiếu:**

```sql
SELECT CAST(game_id AS NVARCHAR(20)) AS game_id, CAST(season AS NVARCHAR(10)) AS season_raw FROM dbo.stg_raw_games
```
- **Điều kiện nối:** `game_id` = `game_id`
- **Cột lấy về:** `season_raw`
- **Không tìm thấy:** Bỏ qua lỗi (Ignore failure): các cột trả về = NULL

**4.3.2.3. Làm sạch chuỗi** · *Derived Column*

Làm sạch chuỗi: bỏ khoảng trắng đầu/cuối (`TRIM`), thay ký tự khoảng trắng đặc biệt NBSP (`\x00A0`), chuỗi rỗng → `NULL`. Các cột được **thay thế tại chỗ** (Replace).

- **Biểu thức:**
  - thay thế `appearance_id`:
    ```
    TRIM(REPLACE(REPLACENULL(appearance_id,""),"\x00A0"," ")) == "" ? NULL(DT_WSTR,50) : TRIM(REPLACE(appearance_id,"\x00A0"," "))
    ```
  - thay thế `game_id`:
    ```
    TRIM(REPLACENULL(game_id,"")) == "" ? NULL(DT_WSTR,20) : TRIM(game_id)
    ```
  - thay thế `player_id`:
    ```
    TRIM(REPLACENULL(player_id,"")) == "" ? NULL(DT_WSTR,20) : TRIM(player_id)
    ```
  - thay thế `player_club_id`:
    ```
    TRIM(REPLACENULL(player_club_id,"")) == "" ? NULL(DT_WSTR,20) : TRIM(player_club_id)
    ```
  - thay thế `game_date_raw`:
    ```
    TRIM(REPLACENULL(game_date_raw,"")) == "" ? NULL(DT_WSTR,30) : SUBSTRING(TRIM(game_date_raw),1,10)
    ```
  - thay thế `competition_id`:
    ```
    TRIM(REPLACE(REPLACENULL(competition_id,""),"\x00A0"," ")) == "" ? NULL(DT_WSTR,20) : TRIM(REPLACE(competition_id,"\x00A0"," "))
    ```
  - thay thế `yellow_cards`:
    ```
    TRIM(REPLACENULL(yellow_cards,"")) == "" ? NULL(DT_WSTR,10) : TRIM(yellow_cards)
    ```
  - thay thế `red_cards`:
    ```
    TRIM(REPLACENULL(red_cards,"")) == "" ? NULL(DT_WSTR,10) : TRIM(red_cards)
    ```
  - thay thế `goals`:
    ```
    TRIM(REPLACENULL(goals,"")) == "" ? NULL(DT_WSTR,10) : TRIM(goals)
    ```
  - thay thế `assists`:
    ```
    TRIM(REPLACENULL(assists,"")) == "" ? NULL(DT_WSTR,10) : TRIM(assists)
    ```
  - thay thế `minutes_played`:
    ```
    TRIM(REPLACENULL(minutes_played,"")) == "" ? NULL(DT_WSTR,10) : TRIM(minutes_played)
    ```
  - thay thế `season_raw`:
    ```
    TRIM(REPLACENULL(season_raw,"")) == "" ? NULL(DT_WSTR,10) : TRIM(season_raw)
    ```

**4.3.2.4. Ép kiểu dữ liệu** · *Data Conversion*

Ép kiểu chuỗi sang kiểu số/ngày (cột mới có tiền tố `c_`). Dòng ép kiểu lỗi **không làm dừng package** mà được chuyển (Redirect row) sang **Data Conversion Error Output** → ghi vào `etl_reject`.

- **Cột chuyển đổi:** `game_id` → `c_game_id` DT_I4; `player_id` → `c_player_id` DT_I4; `player_club_id` → `c_player_club_id` DT_I4; `game_date_raw` → `c_game_date` DT_DBDATE; `season_raw` → `c_season` DT_I2; `yellow_cards` → `c_yellow_cards` DT_I2; `red_cards` → `c_red_cards` DT_I2; `goals` → `c_goals` DT_I2; `assists` → `c_assists` DT_I2; `minutes_played` → `c_minutes_played` DT_I2
- **Xử lý lỗi:** Redirect row → Data Conversion Error Output

**4.3.2.5. Kiểm tra hợp lệ và cửa sổ nạp** · *Conditional Split*

Chia luồng theo điều kiện; điều kiện được xét theo thứ tự, dòng không thỏa điều kiện nào đi vào output mặc định.

- **Các output:**
  - **Reject** (thứ tự 1):
    ```
    ISNULL(c_game_id) || ISNULL(c_player_id) || ISNULL(c_game_date) || ISNULL(c_minutes_played) || ISNULL(c_goals) || ISNULL(c_assists) || ISNULL(c_yellow_cards) || ISNULL(c_red_cards) || c_minutes_played < 0 || c_minutes_played > 130 || c_goals < 0 || c_assists < 0 || c_yellow_cards < 0 || c_red_cards < 0
    ```
  - **Out Of Window** (thứ tự 2):
    ```
    c_game_date < (DT_DBDATE)@[User::LoadFrom] || c_game_date > (DT_DBDATE)@[User::LoadTo]
    ```
  - **Valid** (mặc định): các dòng còn lại

**4.3.2.6. Ghi lý do lỗi ép kiểu** · *Derived Column*

Tạo 3 cột mô tả dòng bị loại (`source_table`, `natural_key`, `reason`) để ghi vào bảng `etl_reject`.

- **Biểu thức:**
  - cột mới `rj_source_table` (DT_WSTR(100)):
    ```
    (DT_WSTR,100)"stg_raw_appearances"
    ```
  - cột mới `rj_natural_key` (DT_WSTR(200)):
    ```
    (DT_WSTR,200)(appearance_id)
    ```
  - cột mới `rj_reason` (DT_WSTR(200)):
    ```
    (DT_WSTR,200)"Lỗi ép kiểu (Data Conversion)"
    ```

**4.3.2.7. Loại trùng theo appearance_id** · *Sort*

Sắp xếp theo khóa tự nhiên và **loại dòng trùng khóa** (Remove rows with duplicate sort values).

- **Khóa sắp xếp:** `appearance_id`
- **Loại trùng:** Có (EliminateDuplicates = True)

**4.3.2.8. Ghi lý do vi phạm quy tắc** · *Derived Column*

Tạo 3 cột mô tả dòng bị loại (`source_table`, `natural_key`, `reason`) để ghi vào bảng `etl_reject`.

- **Biểu thức:**
  - cột mới `rj_source_table` (DT_WSTR(100)):
    ```
    (DT_WSTR,100)"stg_raw_appearances"
    ```
  - cột mới `rj_natural_key` (DT_WSTR(200)):
    ```
    (DT_WSTR,200)(appearance_id)
    ```
  - cột mới `rj_reason` (DT_WSTR(200)):
    ```
    (DT_WSTR,200)((ISNULL(c_game_id) || ISNULL(c_player_id)) ? "Thiếu game_id/player_id" : ((ISNULL(c_minutes_played) || c_minutes_played < 0 || c_minutes_played > 130) ? "minutes_played ngoài 0-130" : "Số bàn, kiến tạo, thẻ thiếu hoặc âm"))
    ```

**4.3.2.9. Lưu dòng lỗi ép kiểu vào etl_reject** · *OLE DB Destination*

Ghi dữ liệu vào bảng đích (Fast load).

- **Kết nối:** `localhost.football_dwh_staging` — **Bảng đích:** `[dbo].[etl_reject]` — **Chế độ:** Table or view – fast load
- **Ánh xạ cột (4):** `batch_id`, `rj_source_table`→`source_table`, `rj_natural_key`→`natural_key`, `rj_reason`→`reason`

**4.3.2.10. Tính khóa ngày và cột đếm** · *Derived Column*

Tính toán ở mức từng dòng ngay trong ETL (chuẩn hóa giá trị, nhóm hóa thành band, khóa ngày, cờ 0/1, measure dẫn xuất).

- **Biểu thức:**
  - cột mới `date_key` (DT_I4):
    ```
    (DT_I4)(YEAR(c_game_date) * 10000 + MONTH(c_game_date) * 100 + DAY(c_game_date))
    ```
  - cột mới `appearance_count` (DT_UI1):
    ```
    (DT_UI1)1
    ```

**4.3.2.11. Lưu dòng vi phạm quy tắc vào etl_reject** · *OLE DB Destination*

Ghi dữ liệu vào bảng đích (Fast load).

- **Kết nối:** `localhost.football_dwh_staging` — **Bảng đích:** `[dbo].[etl_reject]` — **Chế độ:** Table or view – fast load
- **Ánh xạ cột (4):** `batch_id`, `rj_source_table`→`source_table`, `rj_natural_key`→`natural_key`, `rj_reason`→`reason`

**4.3.2.12. Tra khóa mùa giải** · *Lookup*

Tra **surrogate key** của dimension theo khóa tự nhiên. Không tìm thấy thì bỏ qua lỗi (Ignore failure) → khóa = NULL, sau đó đổi thành -1.

- **Kết nối:** `localhost.football_dwh_dw` — **Cache:** Full cache
- **Bảng tham chiếu:**

```sql
SELECT season_start_year, season_key FROM dbo.dim_season WHERE season_key <> -1
```
- **Điều kiện nối:** `c_season` = `season_start_year`
- **Cột lấy về:** `season_key`
- **Không tìm thấy:** Bỏ qua lỗi (Ignore failure): các cột trả về = NULL

**4.3.2.13. Tra khóa giải đấu** · *Lookup*

Tra **surrogate key** của dimension theo khóa tự nhiên. Không tìm thấy thì bỏ qua lỗi (Ignore failure) → khóa = NULL, sau đó đổi thành -1.

- **Kết nối:** `localhost.football_dwh_dw` — **Cache:** Full cache
- **Bảng tham chiếu:**

```sql
SELECT competition_id, competition_key FROM dbo.dim_competition
```
- **Điều kiện nối:** `competition_id` = `competition_id`
- **Cột lấy về:** `competition_key`
- **Không tìm thấy:** Bỏ qua lỗi (Ignore failure): các cột trả về = NULL

**4.3.2.14. Tra khóa trận đấu** · *Lookup*

Tra **surrogate key** của dimension theo khóa tự nhiên. Không tìm thấy thì bỏ qua lỗi (Ignore failure) → khóa = NULL, sau đó đổi thành -1.

- **Kết nối:** `localhost.football_dwh_dw` — **Cache:** Full cache
- **Bảng tham chiếu:**

```sql
SELECT game_id, match_key FROM dbo.dim_match
```
- **Điều kiện nối:** `c_game_id` = `game_id`
- **Cột lấy về:** `match_key`
- **Không tìm thấy:** Bỏ qua lỗi (Ignore failure): các cột trả về = NULL

**4.3.2.15. Tra khóa cầu thủ** · *Lookup*

Tra **surrogate key** của dimension theo khóa tự nhiên. Không tìm thấy thì bỏ qua lỗi (Ignore failure) → khóa = NULL, sau đó đổi thành -1.

- **Kết nối:** `localhost.football_dwh_dw` — **Cache:** Full cache
- **Bảng tham chiếu:**

```sql
SELECT player_id, player_key, date_of_birth FROM dbo.dim_player WHERE is_current = 1
```
- **Điều kiện nối:** `c_player_id` = `player_id`
- **Cột lấy về:** `player_key`
- **Không tìm thấy:** Bỏ qua lỗi (Ignore failure): các cột trả về = NULL

**4.3.2.16. Tra khóa CLB** · *Lookup*

Tra **surrogate key** của dimension theo khóa tự nhiên. Không tìm thấy thì bỏ qua lỗi (Ignore failure) → khóa = NULL, sau đó đổi thành -1.

- **Kết nối:** `localhost.football_dwh_dw` — **Cache:** Full cache
- **Bảng tham chiếu:**

```sql
SELECT club_id, club_key FROM dbo.dim_club WHERE is_current = 1
```
- **Điều kiện nối:** `c_player_club_id` = `club_id`
- **Cột lấy về:** `club_key`
- **Không tìm thấy:** Bỏ qua lỗi (Ignore failure): các cột trả về = NULL

**4.3.2.17. Gán khóa Unknown cho khóa không tra được** · *Derived Column*

Khóa dimension không tra được (NULL) được thay bằng **-1**, trỏ về dòng Unknown của dimension.

- **Biểu thức:**
  - thay thế `season_key`:
    ```
    REPLACENULL(season_key,-1)
    ```
  - thay thế `competition_key`:
    ```
    REPLACENULL(competition_key,-1)
    ```
  - thay thế `match_key`:
    ```
    REPLACENULL(match_key,-1)
    ```
  - thay thế `player_key`:
    ```
    REPLACENULL(player_key,-1)
    ```
  - thay thế `club_key`:
    ```
    REPLACENULL(club_key,-1)
    ```

**4.3.2.18. Bỏ qua dòng đã có trong Fact** · *Lookup*

**Lookup chính bảng fact** theo khóa của grain: dòng đã có trong kho đi vào Match Output và **bị bỏ** (không nối tiếp); chỉ dòng **No Match** (chưa có) mới được nạp → chạy lại nhiều lần không sinh dữ liệu trùng, dữ liệu đã ghi không bị sửa.

- **Kết nối:** `localhost.football_dwh_dw` — **Cache:** Full cache
- **Bảng tham chiếu:**

```sql
SELECT appearance_id FROM dbo.fact_player_appearance
```
- **Điều kiện nối:** `appearance_id` = `appearance_id`
- **Cột lấy về:** (không lấy cột nào — chỉ kiểm tra tồn tại)
- **Không tìm thấy:** Gửi sang **Lookup No Match Output**

**4.3.2.19. Ghi vào Fact_Player_Appearance** · *OLE DB Destination*

Ghi dữ liệu vào bảng đích (Fast load).

- **Kết nối:** `localhost.football_dwh_dw` — **Bảng đích:** `[dbo].[fact_player_appearance]` — **Chế độ:** Table or view – fast load
- **Ánh xạ cột (14):** `date_key`, `season_key`, `competition_key`, `match_key`, `player_key`, `club_key`, `appearance_id`, `c_minutes_played`→`minutes_played`, `c_goals`→`goals`, `c_assists`→`assists`, `c_yellow_cards`→`yellow_cards`, `c_red_cards`→`red_cards`, `appearance_count`, `batch_id`

#### 4.3.3. Nạp Fact_Player_Valuation

| Đích | Cách nạp | Số component |
|---|---|---|
| `Fact_Player_Valuation` | Nạp gia tăng | 16 |

Grain: 1 lần định giá của 1 cầu thủ tại 1 ngày (periodic snapshot). `value_change_eur` tính bằng hàm LAG ngay trong câu nguồn (SSIS không có phép tính theo dòng trước); tuổi tại ngày định giá tính bằng Derived Column.

**Luồng dữ liệu** (component nguồn ──[output]──► component đích):

```
Đọc định giá và tính biến động giá trị           ────► Làm sạch chuỗi
Làm sạch chuỗi                                   ────► Ép kiểu dữ liệu
Ép kiểu dữ liệu                                  ────► Kiểm tra hợp lệ và cửa sổ nạp
Ép kiểu dữ liệu                                  ── [Data Conversion Error Output]──► Ghi lý do lỗi ép kiểu
Kiểm tra hợp lệ và cửa sổ nạp                    ── [Valid]──► Loại trùng theo cầu thủ và ngày
Kiểm tra hợp lệ và cửa sổ nạp                    ── [Reject]──► Ghi lý do vi phạm quy tắc
Ghi lý do lỗi ép kiểu                            ────► Lưu dòng lỗi ép kiểu vào etl_reject
Loại trùng theo cầu thủ và ngày                  ────► Tính khóa ngày và cột đếm
Ghi lý do vi phạm quy tắc                        ────► Lưu dòng vi phạm quy tắc vào etl_reject
Tính khóa ngày và cột đếm                        ────► Tra khóa cầu thủ và ngày sinh
Tra khóa cầu thủ và ngày sinh                    ── [Lookup Match Output]──► Tra khóa CLB
Tra khóa CLB                                     ── [Lookup Match Output]──► Tra khóa giải đấu
Tra khóa giải đấu                                ── [Lookup Match Output]──► Tính tuổi và gán khóa Unknown
Tính tuổi và gán khóa Unknown                    ────► Bỏ qua dòng đã có trong Fact
Bỏ qua dòng đã có trong Fact                     ── [Lookup No Match Output]──► Ghi vào Fact_Player_Valuation
```

**Chi tiết từng component:**

**4.3.3.1. Đọc định giá và tính biến động giá trị** · *OLE DB Source*

Đọc dữ liệu từ Staging. Câu SQL chỉ `CAST` các cột cần dùng sang `NVARCHAR(n)`: bảng stage lưu `NVARCHAR(MAX)`, SSIS đọc kiểu này thành `DT_NTEXT` và không áp dụng được hàm chuỗi, nên phải đổi sang chuỗi có độ dài.

- **Kết nối:** `localhost.football_dwh_staging`
- **Câu truy vấn:**

```sql
WITH v AS (
    SELECT CAST(player_id AS NVARCHAR(20))                            AS player_id,
           CAST([date] AS NVARCHAR(30))                               AS valuation_date_raw,
           CAST(market_value_in_eur AS NVARCHAR(30))                  AS market_value,
           CAST(current_club_id AS NVARCHAR(20))                      AS current_club_id,
           CAST(player_club_domestic_competition_id AS NVARCHAR(20))  AS competition_id,
           CAST(batch_id AS NVARCHAR(30))                             AS batch_id,
           TRY_CAST(LEFT(CAST([date] AS NVARCHAR(30)), 10) AS DATE)   AS d,
           TRY_CAST(CAST(market_value_in_eur AS NVARCHAR(30)) AS BIGINT) AS mv
    FROM dbo.stg_raw_player_valuations
)
SELECT player_id, valuation_date_raw, market_value, current_club_id, competition_id, batch_id,
       CAST(mv - LAG(mv) OVER (PARTITION BY player_id ORDER BY d) AS BIGINT) AS value_change_eur
FROM v;
```

**4.3.3.2. Làm sạch chuỗi** · *Derived Column*

Làm sạch chuỗi: bỏ khoảng trắng đầu/cuối (`TRIM`), thay ký tự khoảng trắng đặc biệt NBSP (`\x00A0`), chuỗi rỗng → `NULL`. Các cột được **thay thế tại chỗ** (Replace).

- **Biểu thức:**
  - thay thế `player_id`:
    ```
    TRIM(REPLACENULL(player_id,"")) == "" ? NULL(DT_WSTR,20) : TRIM(player_id)
    ```
  - thay thế `valuation_date_raw`:
    ```
    TRIM(REPLACENULL(valuation_date_raw,"")) == "" ? NULL(DT_WSTR,30) : SUBSTRING(TRIM(valuation_date_raw),1,10)
    ```
  - thay thế `market_value`:
    ```
    TRIM(REPLACENULL(market_value,"")) == "" ? NULL(DT_WSTR,30) : TRIM(market_value)
    ```
  - thay thế `current_club_id`:
    ```
    TRIM(REPLACENULL(current_club_id,"")) == "" ? NULL(DT_WSTR,20) : TRIM(current_club_id)
    ```
  - thay thế `competition_id`:
    ```
    TRIM(REPLACE(REPLACENULL(competition_id,""),"\x00A0"," ")) == "" ? NULL(DT_WSTR,20) : TRIM(REPLACE(competition_id,"\x00A0"," "))
    ```

**4.3.3.3. Ép kiểu dữ liệu** · *Data Conversion*

Ép kiểu chuỗi sang kiểu số/ngày (cột mới có tiền tố `c_`). Dòng ép kiểu lỗi **không làm dừng package** mà được chuyển (Redirect row) sang **Data Conversion Error Output** → ghi vào `etl_reject`.

- **Cột chuyển đổi:** `player_id` → `c_player_id` DT_I4; `valuation_date_raw` → `c_valuation_date` DT_DBDATE; `market_value` → `c_market_value` DT_I8; `current_club_id` → `c_current_club_id` DT_I4
- **Xử lý lỗi:** Redirect row → Data Conversion Error Output

**4.3.3.4. Kiểm tra hợp lệ và cửa sổ nạp** · *Conditional Split*

Chia luồng theo điều kiện; điều kiện được xét theo thứ tự, dòng không thỏa điều kiện nào đi vào output mặc định.

- **Các output:**
  - **Reject** (thứ tự 1):
    ```
    ISNULL(c_player_id) || ISNULL(c_valuation_date) || (!ISNULL(c_market_value) && c_market_value < 0)
    ```
  - **Out Of Window** (thứ tự 2):
    ```
    c_valuation_date < (DT_DBDATE)@[User::LoadFrom] || c_valuation_date > (DT_DBDATE)@[User::LoadTo]
    ```
  - **Valid** (mặc định): các dòng còn lại

**4.3.3.5. Ghi lý do lỗi ép kiểu** · *Derived Column*

Tạo 3 cột mô tả dòng bị loại (`source_table`, `natural_key`, `reason`) để ghi vào bảng `etl_reject`.

- **Biểu thức:**
  - cột mới `rj_source_table` (DT_WSTR(100)):
    ```
    (DT_WSTR,100)"stg_raw_player_valuations"
    ```
  - cột mới `rj_natural_key` (DT_WSTR(200)):
    ```
    (DT_WSTR,200)(REPLACENULL(player_id,"") + "|" + REPLACENULL(valuation_date_raw,""))
    ```
  - cột mới `rj_reason` (DT_WSTR(200)):
    ```
    (DT_WSTR,200)"Lỗi ép kiểu (Data Conversion)"
    ```

**4.3.3.6. Loại trùng theo cầu thủ và ngày** · *Sort*

Sắp xếp theo khóa tự nhiên và **loại dòng trùng khóa** (Remove rows with duplicate sort values).

- **Khóa sắp xếp:** `c_player_id`, `c_valuation_date`
- **Loại trùng:** Có (EliminateDuplicates = True)

**4.3.3.7. Ghi lý do vi phạm quy tắc** · *Derived Column*

Tạo 3 cột mô tả dòng bị loại (`source_table`, `natural_key`, `reason`) để ghi vào bảng `etl_reject`.

- **Biểu thức:**
  - cột mới `rj_source_table` (DT_WSTR(100)):
    ```
    (DT_WSTR,100)"stg_raw_player_valuations"
    ```
  - cột mới `rj_natural_key` (DT_WSTR(200)):
    ```
    (DT_WSTR,200)(REPLACENULL(player_id,"") + "|" + REPLACENULL(valuation_date_raw,""))
    ```
  - cột mới `rj_reason` (DT_WSTR(200)):
    ```
    (DT_WSTR,200)"Thiếu khóa hoặc giá trị âm"
    ```

**4.3.3.8. Lưu dòng lỗi ép kiểu vào etl_reject** · *OLE DB Destination*

Ghi dữ liệu vào bảng đích (Fast load).

- **Kết nối:** `localhost.football_dwh_staging` — **Bảng đích:** `[dbo].[etl_reject]` — **Chế độ:** Table or view – fast load
- **Ánh xạ cột (4):** `batch_id`, `rj_source_table`→`source_table`, `rj_natural_key`→`natural_key`, `rj_reason`→`reason`

**4.3.3.9. Tính khóa ngày và cột đếm** · *Derived Column*

Tính toán ở mức từng dòng ngay trong ETL (chuẩn hóa giá trị, nhóm hóa thành band, khóa ngày, cờ 0/1, measure dẫn xuất).

- **Biểu thức:**
  - cột mới `date_key` (DT_I4):
    ```
    (DT_I4)(YEAR(c_valuation_date) * 10000 + MONTH(c_valuation_date) * 100 + DAY(c_valuation_date))
    ```
  - cột mới `valuation_count` (DT_UI1):
    ```
    (DT_UI1)1
    ```

**4.3.3.10. Lưu dòng vi phạm quy tắc vào etl_reject** · *OLE DB Destination*

Ghi dữ liệu vào bảng đích (Fast load).

- **Kết nối:** `localhost.football_dwh_staging` — **Bảng đích:** `[dbo].[etl_reject]` — **Chế độ:** Table or view – fast load
- **Ánh xạ cột (4):** `batch_id`, `rj_source_table`→`source_table`, `rj_natural_key`→`natural_key`, `rj_reason`→`reason`

**4.3.3.11. Tra khóa cầu thủ và ngày sinh** · *Lookup*

Tra **surrogate key** của dimension theo khóa tự nhiên. Không tìm thấy thì bỏ qua lỗi (Ignore failure) → khóa = NULL, sau đó đổi thành -1.

- **Kết nối:** `localhost.football_dwh_dw` — **Cache:** Full cache
- **Bảng tham chiếu:**

```sql
SELECT player_id, player_key, date_of_birth FROM dbo.dim_player WHERE is_current = 1
```
- **Điều kiện nối:** `c_player_id` = `player_id`
- **Cột lấy về:** `player_key`, `date_of_birth`
- **Không tìm thấy:** Bỏ qua lỗi (Ignore failure): các cột trả về = NULL

**4.3.3.12. Tra khóa CLB** · *Lookup*

Tra **surrogate key** của dimension theo khóa tự nhiên. Không tìm thấy thì bỏ qua lỗi (Ignore failure) → khóa = NULL, sau đó đổi thành -1.

- **Kết nối:** `localhost.football_dwh_dw` — **Cache:** Full cache
- **Bảng tham chiếu:**

```sql
SELECT club_id, club_key FROM dbo.dim_club WHERE is_current = 1
```
- **Điều kiện nối:** `c_current_club_id` = `club_id`
- **Cột lấy về:** `club_key`
- **Không tìm thấy:** Bỏ qua lỗi (Ignore failure): các cột trả về = NULL

**4.3.3.13. Tra khóa giải đấu** · *Lookup*

Tra **surrogate key** của dimension theo khóa tự nhiên. Không tìm thấy thì bỏ qua lỗi (Ignore failure) → khóa = NULL, sau đó đổi thành -1.

- **Kết nối:** `localhost.football_dwh_dw` — **Cache:** Full cache
- **Bảng tham chiếu:**

```sql
SELECT competition_id, competition_key FROM dbo.dim_competition
```
- **Điều kiện nối:** `competition_id` = `competition_id`
- **Cột lấy về:** `competition_key`
- **Không tìm thấy:** Bỏ qua lỗi (Ignore failure): các cột trả về = NULL

**4.3.3.14. Tính tuổi và gán khóa Unknown** · *Derived Column*

Tính toán ở mức từng dòng ngay trong ETL (chuẩn hóa giá trị, nhóm hóa thành band, khóa ngày, cờ 0/1, measure dẫn xuất).

- **Biểu thức:**
  - thay thế `player_key`:
    ```
    REPLACENULL(player_key,-1)
    ```
  - thay thế `club_key`:
    ```
    REPLACENULL(club_key,-1)
    ```
  - thay thế `competition_key`:
    ```
    REPLACENULL(competition_key,-1)
    ```
  - cột mới `age_at_valuation` (DT_UI1):
    ```
    ISNULL(date_of_birth) || ISNULL(c_valuation_date) ? NULL(DT_UI1) : ((DATEDIFF("yyyy",date_of_birth,c_valuation_date) - ((MONTH(c_valuation_date) * 100 + DAY(c_valuation_date)) < (MONTH(date_of_birth) * 100 + DAY(date_of_birth)) ? 1 : 0)) < 14 || (DATEDIFF("yyyy",date_of_birth,c_valuation_date) - ((MONTH(c_valuation_date) * 100 + DAY(c_valuation_date)) < (MONTH(date_of_birth) * 100 + DAY(date_of_birth)) ? 1 : 0)) > 100 ? NULL(DT_UI1) : (DT_UI1)(DATEDIFF("yyyy",date_of_birth,c_valuation_date) - ((MONTH(c_valuation_date) * 100 + DAY(c_valuation_date)) < (MONTH(date_of_birth) * 100 + DAY(date_of_birth)) ? 1 : 0)))
    ```

**4.3.3.15. Bỏ qua dòng đã có trong Fact** · *Lookup*

**Lookup chính bảng fact** theo khóa của grain: dòng đã có trong kho đi vào Match Output và **bị bỏ** (không nối tiếp); chỉ dòng **No Match** (chưa có) mới được nạp → chạy lại nhiều lần không sinh dữ liệu trùng, dữ liệu đã ghi không bị sửa.

- **Kết nối:** `localhost.football_dwh_dw` — **Cache:** Full cache
- **Bảng tham chiếu:**

```sql
SELECT player_key, date_key FROM dbo.fact_player_valuation
```
- **Điều kiện nối:** `player_key` = `player_key`, `date_key` = `date_key`
- **Cột lấy về:** (không lấy cột nào — chỉ kiểm tra tồn tại)
- **Không tìm thấy:** Gửi sang **Lookup No Match Output**

**4.3.3.16. Ghi vào Fact_Player_Valuation** · *OLE DB Destination*

Ghi dữ liệu vào bảng đích (Fast load).

- **Kết nối:** `localhost.football_dwh_dw` — **Bảng đích:** `[dbo].[fact_player_valuation]` — **Chế độ:** Table or view – fast load
- **Ánh xạ cột (9):** `date_key`, `player_key`, `club_key`, `competition_key`, `c_market_value`→`market_value_eur`, `value_change_eur`, `age_at_valuation`, `valuation_count`, `batch_id`

#### 4.3.4. Nạp Fact_Transfer

| Đích | Cách nạp | Số component |
|---|---|---|
| `Fact_Transfer` | Nạp gia tăng | 18 |

Grain: 1 lần chuyển nhượng. Phí trống (không công bố) giữ NULL, khác phí 0 (miễn phí/cho mượn); hai trường hợp được phân biệt qua Dim_Transfer_Type. Tính thêm `fee_premium_eur` (phí − giá trị thị trường) và tuổi tại ngày chuyển nhượng.

**Luồng dữ liệu** (component nguồn ──[output]──► component đích):

```
Đọc chuyển nhượng từ Staging                     ────► Làm sạch chuỗi
Làm sạch chuỗi                                   ────► Ép kiểu dữ liệu
Ép kiểu dữ liệu                                  ────► Kiểm tra hợp lệ và cửa sổ nạp
Ép kiểu dữ liệu                                  ── [Data Conversion Error Output]──► Ghi lý do lỗi ép kiểu
Kiểm tra hợp lệ và cửa sổ nạp                    ── [Valid]──► Loại trùng theo thương vụ
Kiểm tra hợp lệ và cửa sổ nạp                    ── [Reject]──► Ghi lý do vi phạm quy tắc
Ghi lý do lỗi ép kiểu                            ────► Lưu dòng lỗi ép kiểu vào etl_reject
Loại trùng theo thương vụ                        ────► Tính loại phí phí chênh và khóa ngày
Ghi lý do vi phạm quy tắc                        ────► Lưu dòng vi phạm quy tắc vào etl_reject
Tính loại phí phí chênh và khóa ngày             ────► Tra khóa mùa giải
Tra khóa mùa giải                                ── [Lookup Match Output]──► Tra khóa cầu thủ và ngày sinh
Tra khóa cầu thủ và ngày sinh                    ── [Lookup Match Output]──► Tra khóa CLB đi
Tra khóa CLB đi                                  ── [Lookup Match Output]──► Tra khóa CLB đến
Tra khóa CLB đến                                 ── [Lookup Match Output]──► Tra khóa loại chuyển nhượng
Tra khóa loại chuyển nhượng                      ── [Lookup Match Output]──► Tính tuổi và gán khóa Unknown
Tính tuổi và gán khóa Unknown                    ────► Bỏ qua dòng đã có trong Fact
Bỏ qua dòng đã có trong Fact                     ── [Lookup No Match Output]──► Ghi vào Fact_Transfer
```

**Chi tiết từng component:**

**4.3.4.1. Đọc chuyển nhượng từ Staging** · *OLE DB Source*

Đọc dữ liệu từ Staging. Câu SQL chỉ `CAST` các cột cần dùng sang `NVARCHAR(n)`: bảng stage lưu `NVARCHAR(MAX)`, SSIS đọc kiểu này thành `DT_NTEXT` và không áp dụng được hàm chuỗi, nên phải đổi sang chuỗi có độ dài.

- **Kết nối:** `localhost.football_dwh_staging`
- **Câu truy vấn:**

```sql
SELECT CAST(player_id AS NVARCHAR(20)) AS player_id,
       CAST(transfer_date AS NVARCHAR(30)) AS transfer_date_raw,
       CAST(transfer_season AS NVARCHAR(10)) AS transfer_season,
       CAST(from_club_id AS NVARCHAR(20)) AS from_club_id,
       CAST(to_club_id AS NVARCHAR(20)) AS to_club_id,
       CAST(transfer_fee AS NVARCHAR(30)) AS transfer_fee,
       CAST(market_value_in_eur AS NVARCHAR(30)) AS market_value,
       CAST(batch_id AS NVARCHAR(30)) AS batch_id
FROM dbo.stg_raw_transfers
```

**4.3.4.2. Làm sạch chuỗi** · *Derived Column*

Làm sạch chuỗi: bỏ khoảng trắng đầu/cuối (`TRIM`), thay ký tự khoảng trắng đặc biệt NBSP (`\x00A0`), chuỗi rỗng → `NULL`. Các cột được **thay thế tại chỗ** (Replace).

- **Biểu thức:**
  - thay thế `player_id`:
    ```
    TRIM(REPLACENULL(player_id,"")) == "" ? NULL(DT_WSTR,20) : TRIM(player_id)
    ```
  - thay thế `transfer_date_raw`:
    ```
    TRIM(REPLACENULL(transfer_date_raw,"")) == "" ? NULL(DT_WSTR,30) : SUBSTRING(TRIM(transfer_date_raw),1,10)
    ```
  - thay thế `transfer_season`:
    ```
    TRIM(REPLACE(REPLACENULL(transfer_season,""),"\x00A0"," ")) == "" ? NULL(DT_WSTR,10) : TRIM(REPLACE(transfer_season,"\x00A0"," "))
    ```
  - thay thế `from_club_id`:
    ```
    TRIM(REPLACENULL(from_club_id,"")) == "" ? NULL(DT_WSTR,20) : TRIM(from_club_id)
    ```
  - thay thế `to_club_id`:
    ```
    TRIM(REPLACENULL(to_club_id,"")) == "" ? NULL(DT_WSTR,20) : TRIM(to_club_id)
    ```
  - thay thế `transfer_fee`:
    ```
    TRIM(REPLACENULL(transfer_fee,"")) == "" ? NULL(DT_WSTR,30) : TRIM(transfer_fee)
    ```
  - thay thế `market_value`:
    ```
    TRIM(REPLACENULL(market_value,"")) == "" ? NULL(DT_WSTR,30) : TRIM(market_value)
    ```

**4.3.4.3. Ép kiểu dữ liệu** · *Data Conversion*

Ép kiểu chuỗi sang kiểu số/ngày (cột mới có tiền tố `c_`). Dòng ép kiểu lỗi **không làm dừng package** mà được chuyển (Redirect row) sang **Data Conversion Error Output** → ghi vào `etl_reject`.

- **Cột chuyển đổi:** `player_id` → `c_player_id` DT_I4; `transfer_date_raw` → `c_transfer_date` DT_DBDATE; `from_club_id` → `c_from_club_id` DT_I4; `to_club_id` → `c_to_club_id` DT_I4; `transfer_fee` → `c_transfer_fee` DT_NUMERIC(19,3); `market_value` → `c_market_value` DT_NUMERIC(19,3)
- **Xử lý lỗi:** Redirect row → Data Conversion Error Output

**4.3.4.4. Kiểm tra hợp lệ và cửa sổ nạp** · *Conditional Split*

Chia luồng theo điều kiện; điều kiện được xét theo thứ tự, dòng không thỏa điều kiện nào đi vào output mặc định.

- **Các output:**
  - **Reject** (thứ tự 1):
    ```
    ISNULL(c_player_id) || ISNULL(c_transfer_date) || (!ISNULL(c_transfer_fee) && c_transfer_fee < 0) || (!ISNULL(c_market_value) && c_market_value < 0)
    ```
  - **Out Of Window** (thứ tự 2):
    ```
    c_transfer_date < (DT_DBDATE)@[User::LoadFrom] || c_transfer_date > (DT_DBDATE)@[User::LoadTo]
    ```
  - **Valid** (mặc định): các dòng còn lại

**4.3.4.5. Ghi lý do lỗi ép kiểu** · *Derived Column*

Tạo 3 cột mô tả dòng bị loại (`source_table`, `natural_key`, `reason`) để ghi vào bảng `etl_reject`.

- **Biểu thức:**
  - cột mới `rj_source_table` (DT_WSTR(100)):
    ```
    (DT_WSTR,100)"stg_raw_transfers"
    ```
  - cột mới `rj_natural_key` (DT_WSTR(200)):
    ```
    (DT_WSTR,200)(REPLACENULL(player_id,"") + "|" + REPLACENULL(transfer_date_raw,""))
    ```
  - cột mới `rj_reason` (DT_WSTR(200)):
    ```
    (DT_WSTR,200)"Lỗi ép kiểu (Data Conversion)"
    ```

**4.3.4.6. Loại trùng theo thương vụ** · *Sort*

Sắp xếp theo khóa tự nhiên và **loại dòng trùng khóa** (Remove rows with duplicate sort values).

- **Khóa sắp xếp:** `c_player_id`, `c_transfer_date`, `c_from_club_id`, `c_to_club_id`
- **Loại trùng:** Có (EliminateDuplicates = True)

**4.3.4.7. Ghi lý do vi phạm quy tắc** · *Derived Column*

Tạo 3 cột mô tả dòng bị loại (`source_table`, `natural_key`, `reason`) để ghi vào bảng `etl_reject`.

- **Biểu thức:**
  - cột mới `rj_source_table` (DT_WSTR(100)):
    ```
    (DT_WSTR,100)"stg_raw_transfers"
    ```
  - cột mới `rj_natural_key` (DT_WSTR(200)):
    ```
    (DT_WSTR,200)(REPLACENULL(player_id,"") + "|" + REPLACENULL(transfer_date_raw,""))
    ```
  - cột mới `rj_reason` (DT_WSTR(200)):
    ```
    (DT_WSTR,200)"Thiếu khóa hoặc số tiền âm"
    ```

**4.3.4.8. Lưu dòng lỗi ép kiểu vào etl_reject** · *OLE DB Destination*

Ghi dữ liệu vào bảng đích (Fast load).

- **Kết nối:** `localhost.football_dwh_staging` — **Bảng đích:** `[dbo].[etl_reject]` — **Chế độ:** Table or view – fast load
- **Ánh xạ cột (4):** `batch_id`, `rj_source_table`→`source_table`, `rj_natural_key`→`natural_key`, `rj_reason`→`reason`

**4.3.4.9. Tính loại phí phí chênh và khóa ngày** · *Derived Column*

Tính toán ở mức từng dòng ngay trong ETL (chuẩn hóa giá trị, nhóm hóa thành band, khóa ngày, cờ 0/1, measure dẫn xuất).

- **Biểu thức:**
  - cột mới `date_key` (DT_I4):
    ```
    (DT_I4)(YEAR(c_transfer_date) * 10000 + MONTH(c_transfer_date) * 100 + DAY(c_transfer_date))
    ```
  - cột mới `transfer_fee_eur` (DT_I8):
    ```
    ISNULL(c_transfer_fee) ? NULL(DT_I8) : (DT_I8)c_transfer_fee
    ```
  - cột mới `market_value_eur` (DT_I8):
    ```
    ISNULL(c_market_value) ? NULL(DT_I8) : (DT_I8)c_market_value
    ```
  - cột mới `fee_status` (DT_WSTR(40)):
    ```
    (DT_WSTR,40)(ISNULL(c_transfer_fee) ? "Không công bố" : (c_transfer_fee == 0 ? "Miễn phí hoặc cho mượn" : "Có phí"))
    ```
  - cột mới `fee_band` (DT_WSTR(30)):
    ```
    (DT_WSTR,30)(ISNULL(c_transfer_fee) || c_transfer_fee == 0 ? "Không áp dụng" : (c_transfer_fee < 1000000 ? "< 1 triệu" : (c_transfer_fee <= 10000000 ? "1-10 triệu" : (c_transfer_fee <= 50000000 ? "10-50 triệu" : "> 50 triệu"))))
    ```
  - cột mới `fee_premium_eur` (DT_I8):
    ```
    ISNULL(c_transfer_fee) || ISNULL(c_market_value) ? NULL(DT_I8) : (DT_I8)(c_transfer_fee - c_market_value)
    ```
  - cột mới `transfer_count` (DT_UI1):
    ```
    (DT_UI1)1
    ```

**4.3.4.10. Lưu dòng vi phạm quy tắc vào etl_reject** · *OLE DB Destination*

Ghi dữ liệu vào bảng đích (Fast load).

- **Kết nối:** `localhost.football_dwh_staging` — **Bảng đích:** `[dbo].[etl_reject]` — **Chế độ:** Table or view – fast load
- **Ánh xạ cột (4):** `batch_id`, `rj_source_table`→`source_table`, `rj_natural_key`→`natural_key`, `rj_reason`→`reason`

**4.3.4.11. Tra khóa mùa giải** · *Lookup*

Tra **surrogate key** của dimension theo khóa tự nhiên. Không tìm thấy thì bỏ qua lỗi (Ignore failure) → khóa = NULL, sau đó đổi thành -1.

- **Kết nối:** `localhost.football_dwh_dw` — **Cache:** Full cache
- **Bảng tham chiếu:**

```sql
SELECT season_short, season_key FROM dbo.dim_season WHERE season_key <> -1
```
- **Điều kiện nối:** `transfer_season` = `season_short`
- **Cột lấy về:** `season_key`
- **Không tìm thấy:** Bỏ qua lỗi (Ignore failure): các cột trả về = NULL

**4.3.4.12. Tra khóa cầu thủ và ngày sinh** · *Lookup*

Tra **surrogate key** của dimension theo khóa tự nhiên. Không tìm thấy thì bỏ qua lỗi (Ignore failure) → khóa = NULL, sau đó đổi thành -1.

- **Kết nối:** `localhost.football_dwh_dw` — **Cache:** Full cache
- **Bảng tham chiếu:**

```sql
SELECT player_id, player_key, date_of_birth FROM dbo.dim_player WHERE is_current = 1
```
- **Điều kiện nối:** `c_player_id` = `player_id`
- **Cột lấy về:** `player_key`, `date_of_birth`
- **Không tìm thấy:** Bỏ qua lỗi (Ignore failure): các cột trả về = NULL

**4.3.4.13. Tra khóa CLB đi** · *Lookup*

Tra **surrogate key** của dimension theo khóa tự nhiên. Không tìm thấy thì bỏ qua lỗi (Ignore failure) → khóa = NULL, sau đó đổi thành -1.

- **Kết nối:** `localhost.football_dwh_dw` — **Cache:** Full cache
- **Bảng tham chiếu:**

```sql
SELECT club_id, club_key FROM dbo.dim_club WHERE is_current = 1
```
- **Điều kiện nối:** `c_from_club_id` = `club_id`
- **Cột lấy về:** `from_club_key`
- **Không tìm thấy:** Bỏ qua lỗi (Ignore failure): các cột trả về = NULL

**4.3.4.14. Tra khóa CLB đến** · *Lookup*

Tra **surrogate key** của dimension theo khóa tự nhiên. Không tìm thấy thì bỏ qua lỗi (Ignore failure) → khóa = NULL, sau đó đổi thành -1.

- **Kết nối:** `localhost.football_dwh_dw` — **Cache:** Full cache
- **Bảng tham chiếu:**

```sql
SELECT club_id, club_key FROM dbo.dim_club WHERE is_current = 1
```
- **Điều kiện nối:** `c_to_club_id` = `club_id`
- **Cột lấy về:** `to_club_key`
- **Không tìm thấy:** Bỏ qua lỗi (Ignore failure): các cột trả về = NULL

**4.3.4.15. Tra khóa loại chuyển nhượng** · *Lookup*

Tra **surrogate key** của dimension theo khóa tự nhiên. Không tìm thấy thì bỏ qua lỗi (Ignore failure) → khóa = NULL, sau đó đổi thành -1.

- **Kết nối:** `localhost.football_dwh_dw` — **Cache:** Full cache
- **Bảng tham chiếu:**

```sql
SELECT fee_status, fee_band, transfer_type_key FROM dbo.dim_transfer_type
```
- **Điều kiện nối:** `fee_status` = `fee_status`, `fee_band` = `fee_band`
- **Cột lấy về:** `transfer_type_key`
- **Không tìm thấy:** Bỏ qua lỗi (Ignore failure): các cột trả về = NULL

**4.3.4.16. Tính tuổi và gán khóa Unknown** · *Derived Column*

Tính toán ở mức từng dòng ngay trong ETL (chuẩn hóa giá trị, nhóm hóa thành band, khóa ngày, cờ 0/1, measure dẫn xuất).

- **Biểu thức:**
  - thay thế `season_key`:
    ```
    REPLACENULL(season_key,-1)
    ```
  - thay thế `player_key`:
    ```
    REPLACENULL(player_key,-1)
    ```
  - thay thế `from_club_key`:
    ```
    REPLACENULL(from_club_key,-1)
    ```
  - thay thế `to_club_key`:
    ```
    REPLACENULL(to_club_key,-1)
    ```
  - thay thế `transfer_type_key`:
    ```
    REPLACENULL(transfer_type_key,-1)
    ```
  - cột mới `age_at_transfer` (DT_UI1):
    ```
    ISNULL(date_of_birth) || ISNULL(c_transfer_date) ? NULL(DT_UI1) : ((DATEDIFF("yyyy",date_of_birth,c_transfer_date) - ((MONTH(c_transfer_date) * 100 + DAY(c_transfer_date)) < (MONTH(date_of_birth) * 100 + DAY(date_of_birth)) ? 1 : 0)) < 0 || (DATEDIFF("yyyy",date_of_birth,c_transfer_date) - ((MONTH(c_transfer_date) * 100 + DAY(c_transfer_date)) < (MONTH(date_of_birth) * 100 + DAY(date_of_birth)) ? 1 : 0)) > 100 ? NULL(DT_UI1) : (DT_UI1)(DATEDIFF("yyyy",date_of_birth,c_transfer_date) - ((MONTH(c_transfer_date) * 100 + DAY(c_transfer_date)) < (MONTH(date_of_birth) * 100 + DAY(date_of_birth)) ? 1 : 0)))
    ```
  - cột mới `is_youth_transfer` (DT_UI1):
    ```
    ISNULL(date_of_birth) || ISNULL(c_transfer_date) ? NULL(DT_UI1) : (DT_UI1)((DATEDIFF("yyyy",date_of_birth,c_transfer_date) - ((MONTH(c_transfer_date) * 100 + DAY(c_transfer_date)) < (MONTH(date_of_birth) * 100 + DAY(date_of_birth)) ? 1 : 0)) < 18 ? 1 : 0)
    ```

**4.3.4.17. Bỏ qua dòng đã có trong Fact** · *Lookup*

**Lookup chính bảng fact** theo khóa của grain: dòng đã có trong kho đi vào Match Output và **bị bỏ** (không nối tiếp); chỉ dòng **No Match** (chưa có) mới được nạp → chạy lại nhiều lần không sinh dữ liệu trùng, dữ liệu đã ghi không bị sửa.

- **Kết nối:** `localhost.football_dwh_dw` — **Cache:** Full cache
- **Bảng tham chiếu:**

```sql
SELECT player_key, date_key, from_club_key, to_club_key FROM dbo.fact_transfer
```
- **Điều kiện nối:** `player_key` = `player_key`, `date_key` = `date_key`, `from_club_key` = `from_club_key`, `to_club_key` = `to_club_key`
- **Cột lấy về:** (không lấy cột nào — chỉ kiểm tra tồn tại)
- **Không tìm thấy:** Gửi sang **Lookup No Match Output**

**4.3.4.18. Ghi vào Fact_Transfer** · *OLE DB Destination*

Ghi dữ liệu vào bảng đích (Fast load).

- **Kết nối:** `localhost.football_dwh_dw` — **Bảng đích:** `[dbo].[fact_transfer]` — **Chế độ:** Table or view – fast load
- **Ánh xạ cột (13):** `date_key`, `season_key`, `player_key`, `from_club_key`, `to_club_key`, `transfer_type_key`, `transfer_fee_eur`, `market_value_eur`, `fee_premium_eur`, `age_at_transfer`, `transfer_count`, `batch_id`, `is_youth_transfer`

---

## 5. Tính toán ở đâu: ETL, kho hay tầng phân tích

| Tầng | Làm gì | Ví dụ |
|---|---|---|
| **ETL (SSIS)** | Tính measure mức từng dòng, trước khi ghi kho | `is_win`, `points`, `goal_difference`, `is_clean_sheet` (Fact_Team_Match); `appearance_count`; `value_change_eur` (LAG), `age_at_valuation`; `fee_status`, `fee_band`, `fee_premium_eur`, `age_at_transfer`; các band của dimension |
| **Kho dữ liệu** | Chỉ lưu fact chi tiết và dimension; fact chỉ thêm dòng mới | Không có bảng tổng hợp, không chạy SQL tính toán sau khi nạp |
| **SSAS / Power BI** | Tổng hợp theo chiều người dùng chọn | Điểm = SUM(points); Tỉ lệ thắng = SUM(is_win)/số trận; Bàn mỗi 90 phút = SUM(goals)·90/SUM(minutes_played); Chi tiêu ròng = phí mua − phí bán |

Phiên bản trước có container *Aggregate* chạy `DELETE` rồi `INSERT … GROUP BY` trên chính kho sau khi nạp. Cách đó sai vì kho bị tính toán và sửa sau khi đã lưu; nay đã bỏ. Danh mục đầy đủ từng phép tính (component, toán tử, ý nghĩa, câu hỏi, mục đích) xem `docs/Tinh_toan_trong_ETL_va_Measure.md`.

---

## 6. Các quy ước xử lý dùng chung

| Quy ước | Cách làm trong SSIS | Ở đâu |
|---|---|---|
| Đặt tên | Container, Data Flow, component đặt tên **theo chức năng** (Đọc…, Làm sạch…, Ép kiểu…, Tính…, Tra khóa…, Ghi vào…) | Toàn package |
| Làm sạch chuỗi | `TRIM`, thay NBSP, rỗng → `NULL(DT_WSTR,n)` | Làm sạch chuỗi |
| Ép kiểu an toàn | Data Conversion, lỗi → Redirect row → `etl_reject` | Ép kiểu dữ liệu |
| Giá trị thiếu ở dimension | `REPLACENULL(x, "Không xác định")` | Chuẩn hóa… |
| Khóa không tra được | Lookup *Ignore failure* → NULL → `REPLACENULL(key,-1)` (dòng Unknown) | Tra khóa…, Gán khóa Unknown… |
| SCD1 | OLE DB Command `UPDATE … WHERE` khóa | Ghi đè thay đổi SCD1 |
| SCD2 | OLE DB Command gọi `usp_DimClub_NewVersion` / `usp_DimPlayer_NewVersion` | Tạo phiên bản mới SCD2 |
| SCD3 | OLE DB Command dời `current_league_name` sang `previous_league_name` | Lưu giải cũ và cập nhật giải mới SCD3 |
| Tính toán mức từng dòng | Derived Column (cờ 0/1, tuổi, phí chênh, band, khóa ngày); LAG trong câu nguồn định giá | Tính … |
| Tính toán tổng hợp | Không làm trong ETL hay kho; SSAS / Power BI tổng hợp từ fact chi tiết | Tầng phân tích |
| Nạp gia tăng | Cửa sổ `LoadFrom`–`LoadTo` + Lookup chính bảng fact, chỉ nạp No Match; không UPDATE/DELETE fact | Kiểm tra hợp lệ và cửa sổ nạp, Bỏ qua dòng đã có trong Fact |
| Truy vết, kiểm toán | Cột `batch_id`; bảng `etl_reject` (source_table, natural_key, reason) | Mọi Data Flow |

