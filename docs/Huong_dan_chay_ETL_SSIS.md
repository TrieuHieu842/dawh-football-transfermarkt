# Hướng dẫn chạy ETL SSIS – Football Transfermarkt DWH

Tài liệu mô tả cách chạy thực tế toàn bộ quy trình ETL và cấu trúc package `Main_ETL_Master.dtsx`. Cấu hình chi tiết từng component (câu SQL, biểu thức, Lookup, Aggregate…) xem ở `docs/Dien_giai_chi_tiet_SSIS.md`.

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
10 file CSV ──01──► stg_raw (football_dwh_staging) ──02──► Dimension ──03──► Fact chi tiết ──► SSAS / Power BI
             Extract                                  Transform + Load        Transform + Load      (tổng hợp)
```

| Lớp | Nội dung | Nguyên tắc |
|---|---|---|
| **Stage** (`stg_raw_*`) | Bản sao nguyên trạng 10 file CSV, mọi cột kiểu chuỗi | Không biến đổi; TRUNCATE rồi nạp lại mỗi lần chạy |
| **DW – Dimension** (`dim_*`) | 8 dimension theo thiết kế Kimball | Chỉ chứa thuộc tính đã chọn lọc; SCD1/2/3 |
| **DW – Fact chi tiết** | `fact_team_match`, `fact_player_appearance`, `fact_player_valuation`, `fact_transfer` | Nạp gia tăng, chỉ thêm dòng chưa có |
| **Tầng phân tích** | SSAS / Power BI | Tổng hợp theo mùa, CLB, HLV…; tính tỉ lệ (không lưu trong kho) |

Nguyên tắc của phần ETL:

- **Measure mức từng dòng tính trong ETL, trước khi ghi vào kho** (Extract → Transform → Load). Kho chỉ lưu, không chạy SQL tính toán sau khi nạp, không UPDATE/DELETE fact. **Tổng hợp** do SSAS / Power BI làm. Danh mục phép tính: `docs/Tinh_toan_trong_ETL_va_Measure.md`.
- **Mỗi dim, mỗi fact là một Data Flow**, đi thẳng từ stage tới đích, không qua bảng trung gian.
- **Tên container, Data Flow, component đặt theo chức năng** (Đọc…, Làm sạch…, Ép kiểu…, Tính…, Tra khóa…, Ghi vào…).
- **Nguồn (OLE DB Source) chỉ `SELECT CAST(cột AS NVARCHAR(n))`** đúng các cột đã chọn, vì SSIS đọc `NVARCHAR(MAX)` thành `DT_NTEXT` và không dùng được hàm chuỗi.
- **Tính toán mức từng dòng** bằng Derived Column (cờ thắng/hòa/thua, điểm, hiệu số, tuổi, phí chênh, band, khóa ngày); ngoại lệ duy nhất dùng SQL là `value_change_eur` tính bằng `LAG` trong câu nguồn.
- **Không có bảng tổng hợp trong kho**, không còn container Aggregate chạy SQL sau khi nạp.
- **Nạp gia tăng:** fact chi tiết lấy sự kiện trong cửa sổ `LoadFrom`–`LoadTo`; bước *Bỏ qua dòng đã có trong Fact* chặn dòng đã nạp.

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

- Tạo 8 dim, 4 fact chi tiết, `etl_load_window` (cửa sổ nạp), `etl_batch`.
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
4. Bố cục Control Flow và các Data Flow đã được sắp sẵn trong file. **Không** bấm *Format → Auto Layout* ở tab Control Flow (sẽ kéo Container 01 thành một hàng dài).

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
| **Toàn bộ** (01 → 02 → 03) | Nhấn **F5** (Start Debugging) khi đang mở `Main_ETL_Master.dtsx` |
| Một container | Chuột phải container → **Execute Container** |
| Một Data Flow hoặc task | Chuột phải khối → **Execute Task** |

Trong lúc chạy:

- Khối **vàng** là đang chạy, **✅ xanh** là xong, **❌ đỏ** là lỗi.
- Double-click một Data Flow để xem **số dòng trên từng mũi tên**. Nên chụp màn hình phần này cho báo cáo.
- Nhật ký nằm ở tab **Progress**; tên tab đổi thành *Execution Results* sau khi dừng.
- Chạy xong, nhấn **Shift+F5** để thoát chế độ debug.

Container 01 và Container 03 chạy lâu nhất, vì có bảng appearances 1,9 triệu dòng (dùng trong *Nạp Fact_Player_Appearance*).

### Bước 6. Demo nạp gia tăng

| Lần chạy | `LoadTo` | Kết quả mong đợi |
|---|---|---|
| 1 | 12/31/2018 | Dim nạp đầy đủ; fact chi tiết chỉ có sự kiện đến hết 2018 |
| 2 | 12/31/2021 | Fact **chỉ thêm** dữ liệu 2019–2021; dòng cũ không bị sửa |
| 3 | 12/31/9999 | Nạp phần còn lại |
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
01 - Trích xuất file CSV vào Staging
        │
        ▼
02 - Làm sạch và nạp Dimension ──► 03 - Làm sạch tính toán và nạp Fact
```

Dim phải nạp xong trước, vì fact cần Lookup sang dim để lấy surrogate key. Không có container *Aggregate*: phép tổng hợp do SSAS / Power BI thực hiện trên fact chi tiết.

| Container | Task bên trong (theo thứ tự chạy) | Giai đoạn |
|---|---|---|
| **01 - Trích xuất file CSV vào Staging** | *Xóa dữ liệu cũ trong Staging* → 10 Data Flow *Chép file … vào Staging* (song song) | Extract |
| **02 - Làm sạch và nạp Dimension** | *Nạp Dim_Competition (SCD1)* → *Nạp Dim_Club (SCD1 SCD2 SCD3)* → *Bổ sung CLB chỉ có trong Fact vào Dim_Club* → *Nạp Dim_Player (SCD1 SCD2)* → *Nạp Dim_Match (SCD1)* → *Nạp Dim_Manager* | Transform + Load |
| **03 - Làm sạch tính toán và nạp Fact** | *Ghi cửa sổ nạp gia tăng* → *Nạp Fact_Team_Match* → *Nạp Fact_Player_Appearance* → *Nạp Fact_Player_Valuation* → *Nạp Fact_Transfer* | Transform + Load |

### Các Execute SQL Task

| Task | Việc làm |
|---|---|
| *Xóa dữ liệu cũ trong Staging* | TRUNCATE 10 bảng `stg_raw_*`, để nạp lại không bị nhân đôi |
| *Ghi cửa sổ nạp gia tăng* | Ghi `LoadFrom`/`LoadTo` vào bảng điều khiển `etl_load_window`; xóa reject cũ của các bảng fact (không cập nhật bảng phân tích nào) |

---

## 4. Data Flow và component

Mỗi Data Flow là một chuỗi component đặt tên theo việc nó làm. Chi tiết cấu hình từng component xem `docs/Dien_giai_chi_tiet_SSIS.md`.

| Data Flow | Luồng chính |
|---|---|
| *Chép file … vào Staging* (10) | Đọc file CSV → Thêm cột truy vết → Ghi vào bảng Staging |
| *Nạp Dim_…* | Đọc … từ Staging → Làm sạch chuỗi → Ép kiểu dữ liệu → Loại trùng → Chuẩn hóa/tính band → Kiểm tra … đã có trong kho → (mới) Thêm … / (đã có) Phân loại thay đổi → Ghi đè SCD1 / Tạo phiên bản mới SCD2 / Lưu giải cũ SCD3 |
| *Nạp Fact_…* (4) | Đọc … từ Staging → Làm sạch chuỗi → Ép kiểu dữ liệu → Kiểm tra hợp lệ và cửa sổ nạp → Loại trùng → Tính … (cờ, điểm, hiệu số, tuổi, phí chênh, khóa ngày) → Tra khóa … → Gán khóa Unknown → Bỏ qua dòng đã có trong Fact → Ghi vào Fact_… |

Dòng lỗi ép kiểu và dòng vi phạm quy tắc được ghi vào `football_dwh_staging.dbo.etl_reject` qua các nhánh *Ghi lý do … → Lưu dòng … vào etl_reject*.

---

## 5. Kiểm tra kết quả

Bộ kiểm tra đầy đủ nằm trong **`sql/99_kiem_tra_ket_qua.sql`**: số dòng, cửa sổ nạp, reject, trùng khóa, công thức các cột tính trong ETL, miền tuổi, và BXH / vua phá lưới Premier League 2024/25 để đối chiếu nghiệp vụ. Bản rút gọn như sau. Chạy trong SSMS sau mỗi lần chạy package:

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
UNION ALL SELECT 'fact_transfer', COUNT(*) FROM dbo.fact_transfer;

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
| *Package Validation Error* … `OfflineMode property is TRUE` | VS đang ở chế độ **Work Offline** (thường tự bật khi mở package lúc SQL Server chưa chạy) | Menu **Extensions/SSIS → bỏ tick Work Offline**, chuột phải từng connection manager → bỏ tick **Work Offline**, rồi chạy lại |
| Task của Container 01 lỗi đọc CSV | Đường dẫn `FFCM ...` sai hoặc file bị đổi ký tự xuống dòng (CRLF) | Sửa File name trong Connection Manager; dùng file CSV gốc tải từ Kaggle |
| Số dòng stage gấp đôi | Chạy Container 01 không qua *Xóa dữ liệu cũ trong Staging* | Chạy cả container, không chạy lẻ từng *Chép file … vào Staging* |
| Lookup báo không tìm thấy bảng | Chưa chạy `sql/01_create_dw.sql` | Chạy script tạo DW (Bước 2) |
| Fact không tăng dòng khi chạy lại | **Đúng thiết kế**: bước *Bỏ qua … đã có trong Fact* chặn dòng đã có | Muốn nạp lại từ đầu thì chạy lại `sql/01_create_dw.sql` |
| *Nạp Fact_Player_Appearance* chạy lâu, tốn RAM | Sort trên 1,9 triệu dòng | Nạp theo đợt nhỏ (đặt `LoadTo`) hoặc tăng RAM cho máy |
| Khối báo ❌ | Lỗi lúc thực thi | Mở tab **Progress**, đọc dòng lỗi màu đỏ đầu tiên |
