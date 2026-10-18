# Context giai đoạn SSAS & Power BI – Phần 4

> Nội dung: **Toàn bộ Power BI (không làm SSAS)**. File này tự đủ thông tin; ai nhận phần này có thể dán nguyên vào trợ lý AI để làm tiếp.

## A. Bối cảnh dự án

- Đồ án môn Kho dữ liệu: **Football Transfermarkt DWH**, mô hình Kimball, **Galaxy Schema** (4 fact dùng chung dimension).
- Nguồn: bộ Kaggle / GitHub *transfermarkt-datasets* (10 file CSV).
- ETL bằng **SSIS** đã xong (`etl-ssis-transfermarkt/.../Main_ETL_Master.dtsx`). Kho `football_dwh_dw` trên SQL Server 2022 đã nạp đủ và qua kiểm tra (`sql/99_kiem_tra_ket_qua.sql`).
- Nguyên tắc thầy đã duyệt:
  - **ETL** tính các giá trị trên từng dòng (cờ, điểm, hiệu số, tuổi, phí chênh…).
  - **Kho chỉ lưu** fact chi tiết, chỉ thêm dòng mới, không có bảng tổng hợp.
  - **Tổng hợp làm ở SSAS / Power BI.** Đó là việc của giai đoạn này.
- Tài liệu nên đọc trong repo:
  - `docs/Tinh_toan_trong_ETL_va_Measure.md`, **mục C**: danh sách measure, công thức gợi ý, câu hỏi nghiệp vụ.
  - `docs/Dien_giai_chi_tiet_SSIS.md`: các cột được tính thế nào.
  - `docs/hinh/Hinh_2_1_Galaxy_Schema.png`: sơ đồ kho.
  - `sql/01_create_dw.sql`: định nghĩa bảng.

## B. Kho dữ liệu `football_dwh_dw`

### Fact (grain chi tiết nhất)

| Fact | Grain | Khóa dimension | Measure |
|---|---|---|---|
| `fact_team_match` (177.916 dòng) | 1 trận × 1 đội (mỗi trận 2 dòng) | date_key, season_key, competition_key, match_key, club_key, **opponent_club_key**, manager_key, **opponent_manager_key** | is_home, goals_for, goals_against, is_win, is_draw, is_loss, is_clean_sheet, points, goal_difference, league_position |
| `fact_player_appearance` (1.894.347) | 1 cầu thủ × 1 trận | date_key, season_key, competition_key, match_key, player_key, club_key | minutes_played, goals, assists, yellow_cards, red_cards, appearance_count (=1); appearance_id (degenerate) |
| `fact_player_valuation` (656.301) | 1 cầu thủ × 1 lần định giá | date_key, player_key, club_key, competition_key (**không có season_key**) | market_value_eur, value_change_eur, age_at_valuation, valuation_count (=1) |
| `fact_transfer` (175.165) | 1 thương vụ | date_key, season_key, player_key, **from_club_key**, **to_club_key**, transfer_type_key | transfer_fee_eur (NULL = không công bố), market_value_eur, fee_premium_eur, age_at_transfer, is_youth_transfer, transfer_count (=1) |

### Dimension (mỗi dim có dòng Unknown key = -1, tên "Không xác định")

| Dim | Cột chính | Hierarchy gợi ý |
|---|---|---|
| `dim_date` | date_key (yyyymmdd), full_date, year, quarter, month, month_name, day_of_week, day_name, is_weekend | Năm → Quý → Tháng → Ngày |
| `dim_season` | season_key, season_start_year, season_label (2024/25), season_short | |
| `dim_competition` | competition_key, competition_id (GB1, ES1, L1, IT1, FR1…), competition_name, competition_type, competition_sub_type, country_name, confederation | Liên đoàn → Quốc gia → Giải |
| `dim_club` (SCD1/2/3) | club_key, club_id, club_name, club_type (Club / National Team / Other), country_name, confederation, current_league_name, previous_league_name (SCD3), stadium_name, stadium_capacity_band (SCD2), is_current | Liên đoàn → Quốc gia → CLB |
| `dim_player` (SCD1/2) | player_key, player_id, full_name, date_of_birth, citizenship, position (Attack / Midfield / Defender / Goalkeeper), sub_position, foot, height_band, agent_name, international_caps_band, is_current | Vị trí → Vị trí chi tiết → Cầu thủ |
| `dim_match` | match_key, game_id, round, round_type, stadium, referee, home_formation, away_formation, attendance_band | |
| `dim_manager` | manager_key, manager_name | |
| `dim_transfer_type` | transfer_type_key, fee_status (Có phí / Miễn phí hoặc cho mượn / Không công bố), fee_band (< 1 triệu, 1-10 triệu, 10-50 triệu, > 50 triệu, Không áp dụng) | Trạng thái phí → Khoảng phí |

### Role-playing (một dim, nhiều vai trò)

- **Dim_Club** có 4 vai trò: CLB, CLB đối thủ (Fact_Team_Match); CLB đi, CLB đến (Fact_Transfer).
- **Dim_Manager** có 2 vai trò: HLV, HLV đối thủ.
- **Dim_Date** dùng chung cho cả 4 fact.

## C. Công cụ, cấu trúc project và quy tắc làm chung

- **SSAS Multidimensional** (cube). Mở bằng Visual Studio (2022 hoặc 2026) có extension *Microsoft Analysis Services Projects*. Server SSAS `localhost` (instance mặc định, chế độ Multidimensional). Lý do: môn học yêu cầu cube và các thao tác OLAP roll-up, drill-down, slice, dice, pivot. Ngoài ra `market_value_eur` cần `LastNonEmpty`.
- **Power BI** do **Phần 4** làm toàn bộ, kết nối *Live connection* vào cube. **Phần 4 không làm SSAS.** Phần 1–3 làm SSAS, rồi gửi câu hỏi nghiệp vụ và visual đề xuất cho Phần 4.

### Cấu trúc project (giống SSIS: khung đã tạo sẵn, mỗi phần vào điền phần của mình)

```
ssas-transfermarkt/Football_DAWH_SSAS/
├── Football_DAWH_SSAS.slnx
└── Football_DAWH_SSAS/
    ├── Football DWH.ds              Data Source           – khung (có sẵn)
    ├── Football DWH.dsv             Data Source View      – khung (có sẵn)
    ├── Ngay.dim, Mua giai.dim       Dimension thời gian    – khung (có sẵn, đã điền)
    ├── Giai dau.dim, Tran dau.dim, HLV.dim, CLB.dim        – Phần 1
    ├── Loai chuyen nhuong.dim, Cau thu.dim                 – Phần 3
    ├── Football DWH.cube            Cube tổng (khung, measure gốc) – có sẵn, giữ nguyên
    ├── Hieu suat doi bong.cube      Cube riêng của Phần 1 – tự tạo
    ├── Hieu suat cau thu.cube       Cube riêng của Phần 2 – tự tạo
    └── Thi truong cau thu.cube      Cube riêng của Phần 3 – đã tạo (mẫu)
```

- Mỗi file `.dim` là một file riêng, nên ai sửa dim của người nấy thì không bị xung đột.
- **Mỗi phần có một file `.cube` riêng**, nên ai sửa cube của người nấy, không lo xung đột.
- **Chỉ `.dsv` là file dùng chung.** Ai cần sửa DSV phải **giữ lượt**: nhắn nhóm "đang giữ DSV", `git pull`, sửa, deploy, commit + push, rồi nhắn "trả DSV". Không để 2 người sửa cùng lúc, vì XML này không merge được.
- Cube `Football DWH` giữ nguyên làm cube tổng. **Không viết calculated member / KPI vào cube này.** Các khối *Phần 1–3* trong tab Calculations của nó để trống.
- Cần thêm cột tính trong DSV (Named Calculation) thì nhờ người tạo khung thêm.
- Không commit tên server riêng. Máy dùng instance khác `localhost` thì sửa `Football DWH.ds` trên máy mình và chạy `git update-index --skip-worktree` cho file đó.
- Tên measure tiếng Việt, đúng như trong `Tinh_toan_trong_ETL_va_Measure.md` (Điểm, Tỉ lệ thắng, Bàn mỗi 90 phút…).


### Mỗi phần tạo một cube riêng

Không dồn mọi thứ vào cube `Football DWH`. Mỗi phần tạo **một cube riêng** cho quy trình nghiệp vụ của mình. Cube đó chỉ chứa fact và dimension cần thiết, và phải nói rõ **giá trị mang lại** (trả lời câu hỏi gì, hỗ trợ quyết định gì).

| Cube | File | Phần | Fact (measure group) | Cube dimension | Giá trị mang lại |
|---|---|---|---|---|---|
| Football DWH | `Football DWH.cube` | khung (có sẵn, giữ nguyên) | cả 4 fact, chỉ measure gốc | tất cả | Cube tổng để kiểm tra số liệu và làm trang *Tổng quan* |
| **Hiệu suất đội bóng** | `Hieu suat doi bong.cube` | 1 | Trận đấu đội (fact_team_match) | Ngày, Mùa giải, Giải đấu, Trận đấu, CLB, CLB đối thủ, HLV, HLV đối thủ | Bảng xếp hạng, phong độ theo mùa, HLV hiệu quả, lợi thế sân nhà → đánh giá thành tích, giữ hay thay HLV, đặt mục tiêu điểm |
| **Hiệu suất cầu thủ** | `Hieu suat cau thu.cube` | 2 | Lượt ra sân + Trận có ra sân (Distinct Count match_key) | Ngày, Mùa giải, Giải đấu, Trận đấu, CLB, Cầu thủ | Vua phá lưới, bàn mỗi 90 phút, cầu thủ ra sân nhiều, trọng tài khắt khe → tuyển trạch, đánh giá và gia hạn cầu thủ |
| **Thị trường cầu thủ** | `Thi truong cau thu.cube` | 3 | Định giá + Chuyển nhượng | Ngày, Mùa giải, Giải đấu, Cầu thủ, Tuổi, CLB, CLB đi, CLB đến, Loại chuyển nhượng | Giá trị đội hình, độ tuổi đỉnh giá trị, chi tiêu ròng, mua đắt hay rẻ, tỉ lệ thương vụ miễn phí / đội trẻ → quản lý tài sản cầu thủ và ngân sách chuyển nhượng (**đã làm xong**, dùng làm mẫu) |

Cách tạo cube riêng trong Visual Studio:
1. Chuột phải **Cubes → New Cube** → *Use existing tables*.
2. **Measure group tables:** chỉ chọn fact của phần mình.
3. **Measures:** chọn các cột measure và các Named Calculation đã có trong DSV (ví dụ `home_win`). Bỏ cột khóa và `batch_id`. Đổi tên sang tiếng Việt.
   - Measure Sum trên cột tinyint/smallint: đặt **DataType** của measure là Integer (hoặc BigInt nếu là tiền), để cộng dồn không bị tràn số.
4. **Dimensions:** chỉ chọn các dim có sẵn mà phần mình dùng. **Không tạo dim mới bằng wizard.**
5. **Đặt tên cube** theo bảng trên.
6. Ở khung Dimensions của cube, đổi tên các bản role-playing (CLB đối thủ, CLB đi, CLB đến, HLV đối thủ).
7. Kiểm tra tab **Dimension Usage**.
8. Chọn cube → Properties → **Description**: ghi giá trị mang lại. Ghi lại nội dung này ở đầu tab Calculations dưới dạng chú thích `/* … */`.
9. Viết calculated member và KPI vào tab **Calculations / KPIs** của **cube mình**.
10. Deploy, kiểm tra số liệu với SQL.

Cube `Thi truong cau thu.cube` là mẫu đầy đủ: có Description, MDX, KPI và đã khớp SQL.

### Điểm dễ sai

| Điểm | Cách đúng |
|---|---|
| Tỉ lệ (tỉ lệ thắng, bàn / 90 phút…) | Calculated member = measure gốc / measure gốc. Không tạo measure SUM của tỉ lệ |
| Tuổi, `league_position` | Không cộng; chỉ AVG / MIN / MAX (calculated member = Sum / Count) |
| `market_value_eur` | Semi-additive: **LastNonEmpty** theo thời gian, cộng theo cầu thủ / CLB |
| `transfer_fee_eur` NULL | Giữ NULL; đếm riêng "không công bố". Đổi NULL thành 0 sẽ làm phí trung bình sai |
| Dòng Unknown (-1) | Giữ; khi xếp hạng thì lọc bỏ "Không xác định" |
| `ASSOCIATED_MEASURE_GROUP` trong `CREATE MEMBER` | Ghi **tên hiển thị** của measure group (ví dụ 'Định giá'), không ghi ID ('Fact Player Valuation'). Ghi ID sẽ báo lỗi *measure group was not found* |
| Thuộc tính SCD2 | Fact tra theo phiên bản hiện tại, nên vị trí / sân / người đại diện là giá trị hiện tại |

### Kết quả chuẩn để kiểm tra cube (đã đúng trên SQL)

- Premier League 2024/25: Liverpool 38 trận, **84 điểm**, +45; Arsenal 74; Man City 71; Chelsea 69; Newcastle 66.
- Vua phá lưới Premier League 2024/25: **Salah 29 bàn** (0,77 / 90 phút), Isak 23, Haaland 22.
- Thương vụ đội trẻ (`is_youth_transfer = 1`): 36.443 thương vụ, tuổi trung bình 15,4. Chuyên nghiệp: 138.695 thương vụ, tuổi trung bình 22,6.

## D. Các phần việc và thứ tự

### Khung SSAS (đã tạo sẵn)

Project `Football_DAWH_SSAS` đã có sẵn: Data Source, DSV (12 bảng + Named Calculation), 8 dimension (Ngày, Mùa giải đã điền đủ; 6 dim còn lại chỉ có khóa và tên), cube tổng `Football DWH` với 5 measure group, role-playing dimension, Dimension Usage. Cứ `git pull` là có. Mỗi phần tự tạo **cube riêng** của mình theo mục C (*Mỗi phần tạo một cube riêng*). Cube `Thị trường cầu thủ` của Phần 3 đã có sẵn để làm mẫu.

### 4 phần việc (nhóm tự nhận)

| Phần | Nội dung | Dimension phải điền | File context |
|---|---|---|---|
| **1** | Hiệu suất đội bóng và HLV (Fact_Team_Match) | Giải đấu, Trận đấu, HLV, CLB | `Phan_1_Hieu_suat_doi_bong.md` |
| **2** | Hiệu suất cầu thủ (Fact_Player_Appearance) + tổng hợp bảng đối chiếu cube = SQL | – | `Phan_2_Hieu_suat_cau_thu.md` |
| **3** | Giá trị cầu thủ và chuyển nhượng (Fact_Player_Valuation, Fact_Transfer) | Loại chuyển nhượng, Cầu thủ | `Phan_3_Gia_tri_va_chuyen_nhuong.md` |
| **4** | Toàn bộ Power BI (không làm SSAS) | – | `Phan_4_PowerBI.md` |

### Thứ tự

| Giai đoạn | Phần 1, 2, 3 | Phần 4 |
|---|---|---|
| 1 | Điền dim của phần mình; viết câu hỏi, SQL đối chiếu, nháp MDX | Theme, layout, phác thảo các trang (có thể Import thẳng từ kho để làm nháp) |
| 2 | Tạo cube riêng, viết MDX / KPI vào cube của mình, kiểm tra cube = SQL, minh họa OLAP | Dựng các trang Power BI khi cube có measure |
| 3 | Ảnh minh chứng, phần báo cáo; Phần 2 tổng hợp bảng đối chiếu | Hoàn thiện Power BI, ảnh từng trang |

## E. Phần việc: toàn bộ Power BI (không làm SSAS)

Phần này **không sửa project SSAS**. Chỉ dùng cube đã deploy làm nguồn dữ liệu. Trong lúc nhóm dựng cube (giai đoạn 1), chuẩn bị theme, layout, phác thảo từng trang theo câu hỏi nghiệp vụ của Phần 1, C, D (mục E1 và E4 trong file context của họ). Có thể dựng nháp bằng *Import* trực tiếp từ `football_dwh_dw`, rồi đổi sang Live connection khi cube xong.

### E1. Power BI (một người làm, file `powerbi-transfermarkt/Football_DWH.pbix`)
1. *Get Data → SQL Server Analysis Services*: Server `localhost`, chọn **Connect live**, chọn cube.
   - Live connection chỉ nối **1 cube cho mỗi file**. Vì vậy mỗi trang chủ đề là một file `.pbix` nối với cube tương ứng:
     - Tổng quan → `Football DWH`;
     - Đội bóng & HLV → `Hiệu suất đội bóng`;
     - Cầu thủ → `Hiệu suất cầu thủ`;
     - Thị trường chuyển nhượng → `Thị trường cầu thủ`.
   - Muốn gộp tất cả vào 1 file thì dùng chế độ *Import* (mất tính live).
   - Cube `Thị trường cầu thủ` đã xong, có thể làm trang đó trước.
2. Theme chung + thanh điều hướng giữa các trang.
3. Có 5 trang. Câu hỏi và measure lấy từ phần của Phần 1, C, D (đề xuất visual của họ nằm ở mục E4 trong file context của từng người):

| Trang | Nội dung | Measure chính |
|---|---|---|
| Tổng quan | Thẻ: số trận, số lượt ra sân, số thương vụ, tổng phí công bố; số trận theo mùa; bàn thắng theo giải | Số trận, Số trận ra sân, Số thương vụ, Bàn thắng |
| Đội bóng & HLV (Phần 1) | Bảng xếp hạng (slicer mùa, giải); xu hướng điểm, bàn mỗi trận; top HLV theo tỉ lệ thắng; lợi thế sân nhà theo giải | Điểm, Hiệu số, Tỉ lệ thắng, Tỉ lệ thắng sân nhà |
| Cầu thủ (Phần 2) | Top vua phá lưới / kiến tạo; phân tán số phút × bàn mỗi 90 phút; ma trận vị trí × giải; trọng tài theo thẻ phạt | Bàn thắng, Kiến tạo, Bàn mỗi 90 phút, Thẻ phạt mỗi trận |
| Thị trường chuyển nhượng (Phần 3) | Top CLB theo chi tiêu ròng; giá trị đội hình theo thời gian; giá trị theo tuổi và vị trí; tỉ lệ loại thương vụ theo mùa | Chi tiêu ròng, Giá trị thị trường, Tỉ lệ miễn phí, Tỉ lệ đội trẻ |
| KPI | Các KPI của Phần 1, C, D (tỉ lệ thắng HLV, bàn / 90 phút tiền đạo, chi tiêu ròng) | KPI trong cube |

4. Mỗi visual ghi rõ trả lời câu hỏi nào (Q mấy, của ai). Chụp ảnh từng trang vào `docs/hinh/powerbi/`.
5. Live connection không cho thêm measure vào model. Chỉ tạo được *report measure* đơn giản. Measure chính phải nằm trong cube (calculated member của Phần 1–3). Thiếu measure nào thì nhắn người phụ trách thêm vào cube.

### E2. Kiểm tra số liệu
- Trang *Đội bóng & HLV*, lọc Premier League 2024/25: Liverpool phải ra **84 điểm**.
- Trang *Cầu thủ*: Salah phải ra **29 bàn**.

## Kết quả cần nộp (Definition of done)

1. Mọi measure trong phần việc có giá trị trên cube **khớp với SQL đối chiếu** (ghi bảng: câu hỏi, bộ lọc, kết quả cube, kết quả SQL).
2. Ảnh minh chứng: Phần 1–3 chụp cấu hình trong Visual Studio, kết quả browse cube và 5 thao tác OLAP; Phần 4 chụp từng trang Power BI.
3. Đoạn viết cho báo cáo: câu hỏi nghiệp vụ → measure dùng → kết quả → ý nghĩa / quyết định hỗ trợ.

## Cách dùng file này với trợ lý AI

Dán toàn bộ file này vào đầu cuộc trò chuyện, rồi hỏi từng bước, ví dụ:
- "Viết MDX cho measure … theo context trên."
- "Viết SQL đối chiếu cho câu hỏi Q2."
- "Hướng dẫn tạo KPI … trong SSAS Multidimensional."
