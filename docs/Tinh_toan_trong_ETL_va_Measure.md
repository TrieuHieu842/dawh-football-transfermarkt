# Tính toán trong ETL và measure ở tầng phân tích

Tài liệu chỉ rõ **phép tính nào được làm trong ETL (SSIS), bằng component và toán tử nào**, tạo ra cột/measure nào, measure đó **có ý nghĩa gì, trả lời câu hỏi nghiệp vụ nào và dùng để làm gì**; đồng thời liệt kê các measure **tổng hợp** để tầng phân tích (SSAS / Power BI) tính.

## Nguyên tắc phân vai

| Tầng | Làm gì | Không làm gì |
|---|---|---|
| **ETL (SSIS)** | Làm sạch, ép kiểu, kiểm tra, tra surrogate key và **tính các measure trên từng dòng** (cờ thắng/hòa/thua, điểm, hiệu số, tuổi, phí chênh, biến động giá trị, nhóm/band) | Không gom nhóm theo mùa, không tính tỉ lệ |
| **Kho dữ liệu** (`football_dwh_dw`) | **Chỉ lưu** fact ở grain chi tiết nhất cùng các measure đã tính, và các dimension | Không chạy SQL tính toán hay sửa dữ liệu phân tích sau khi nạp (fact chỉ thêm dòng mới) |
| **Tầng phân tích** (SSAS / Power BI) | **Tổng hợp** theo chiều người dùng chọn: SUM, đếm, trung bình, tỉ lệ, chi tiêu ròng, bảng xếp hạng | Không làm sạch hay sửa dữ liệu |

Lý do: measure ở mức từng dòng không đổi khi người dùng đổi bộ lọc nên tính một lần trong ETL; còn tổng hợp và tỉ lệ thay đổi theo mùa, giải, CLB, HLV đang chọn nên để tầng phân tích tính, kho không cần bảng tổng hợp vật lý.

---

## A. Các biến đổi dùng chung trong ETL

| Biến đổi | Component (toán tử SSIS) | Toán tử / quy tắc | Áp dụng cho | Mục đích |
|---|---|---|---|---|
| Đọc đúng cột cần dùng | Đọc … từ Staging (OLE DB Source) | SELECT CAST(cột AS NVARCHAR(n)) | Mọi data flow dim/fact | Chỉ lấy cột đã chọn lọc; đổi NVARCHAR(MAX) sang chuỗi có độ dài để dùng được hàm chuỗi |
| Làm sạch chuỗi | Làm sạch chuỗi (Derived Column) | TRIM, REPLACE(NBSP→' '), REPLACENULL, chuỗi rỗng → NULL; SUBSTRING(ngày,1,10) | Mọi cột chuỗi | Bỏ khoảng trắng thừa, ký tự đặc biệt; cắt phần giờ 00:00:00 của ngày |
| Chuẩn hóa ký tự ghép trong tên HLV | Làm sạch chuỗi (Derived Column) của Nạp Dim_Manager và Nạp Fact_Team_Match | REPLACE: æ→ae, Æ→Ae, œ→oe, Œ→Oe, ß→ss | manager_name, own_manager_name, opponent_manager_name | Một HLV viết 2 kiểu (Solskjær / Solskjaer) chỉ thành 1 thành viên; Lookup của SSIS (so từng byte) khớp với ràng buộc UNIQUE của SQL Server (coi æ = ae) |
| Ép kiểu | Ép kiểu dữ liệu (Data Conversion) | Chuỗi → DT_I2, DT_I4, DT_I8, DT_NUMERIC, DT_DBDATE; lỗi → Redirect row | Mã, số bàn, phút, tiền, ngày | Đưa về đúng kiểu số/ngày; dòng không ép được ghi etl_reject |
| Kiểm tra quy tắc | Kiểm tra hợp lệ và cửa sổ nạp (Conditional Split) | ISNULL(), so sánh <, >; minutes_played trong 0–130; số không âm | 4 fact | Loại dòng thiếu khóa hoặc sai miền giá trị, ghi etl_reject kèm lý do |
| Lọc cửa sổ nạp | Kiểm tra hợp lệ và cửa sổ nạp (Conditional Split) | ngày < @[User::LoadFrom] \|\| ngày > @[User::LoadTo] | 4 fact | Nạp gia tăng theo khoảng thời gian |
| Khử trùng lặp | Loại trùng theo … (Sort) | Sort theo khóa tự nhiên, Remove rows with duplicate sort values | Mọi data flow | Mỗi khóa tự nhiên chỉ còn một dòng |
| Gộp nguồn | Gộp … (Union All) | Union All nhiều luồng | Dim_Club, Dim_Manager, CLB Other | Gom CLB + đội tuyển; HLV đội + HLV đối thủ; CLB xuất hiện trong fact |
| Tra surrogate key | Tra khóa … (Lookup, full cache) | JOIN theo khóa tự nhiên với dim | 4 fact | Thay mã gốc bằng surrogate key của dimension |
| Gán thành viên Unknown | Gán khóa Unknown … (Derived Column) | REPLACENULL(key, -1) | 4 fact | Khóa không tra được trỏ về dòng Unknown thay vì bị loại |
| Chống nạp trùng | Bỏ qua dòng đã có trong Fact (Lookup) | Lookup chính bảng fact theo khóa grain, chỉ nạp No Match | 4 fact | Chạy lại không sinh dòng trùng, không sửa dòng đã có |
| Phát hiện thay đổi SCD | Phân loại thay đổi theo SCD / Tìm … có thay đổi (Conditional Split) | So sánh giá trị mới != giá trị đang lưu | Dim_Club, Dim_Player, Dim_Competition, Dim_Match | Chọn nhánh SCD1 (ghi đè), SCD2 (phiên bản mới), SCD3 (lưu giá trị cũ) |

---

## B. Các cột được tính trong ETL


### Fact_Team_Match

| Cột | Loại | Data Flow → component | Toán tử / biểu thức | Ý nghĩa | Câu hỏi nghiệp vụ | Để làm gì |
|---|---|---|---|---|---|---|
| `date_key` | Khóa | Nạp Fact_Team_Match → *Tính kết quả trận và khóa ngày (Derived Column)* | `YEAR(ngày)*10000 + MONTH(ngày)*100 + DAY(ngày)` | Khóa ngày dạng YYYYMMDD nối với Dim_Date | Kết quả của đội theo tháng, theo cuối tuần? | Phân tích thành tích theo thời gian |
| `is_home` | Degenerate | Nạp Fact_Team_Match → *Tính kết quả trận và khóa ngày (Derived Column)* | `hosting == "Home" ? 1 : 0` | 1 = đá sân nhà | Lợi thế sân nhà của từng giải lớn cỡ nào? | Đặt mục tiêu điểm sân nhà / sân khách |
| `is_win, is_draw, is_loss` | Measure (additive) | Nạp Fact_Team_Match → *Tính kết quả trận và khóa ngày (Derived Column)* | `so sánh own_goals > / == / < opponent_goals ? 1 : 0` | Kết quả trận dạng cờ 0/1; SUM ra số trận thắng/hòa/thua | HLV nào thắng nhiều trận nhất? Tỉ lệ thắng sân nhà theo giải? | Đánh giá HLV, theo dõi phong độ |
| `is_clean_sheet` | Measure (additive) | Nạp Fact_Team_Match → *Tính kết quả trận và khóa ngày (Derived Column)* | `opponent_goals == 0 ? 1 : 0` | Trận không thủng lưới | Đội/HLV nào giữ sạch lưới nhiều nhất mùa? | Đánh giá thủ môn, hàng thủ khi gia hạn hoặc mua người |
| `points` | Measure (additive) | Nạp Fact_Team_Match → *Tính kết quả trận và khóa ngày (Derived Column)* | `own > opp ? 3 : (own == opp ? 1 : 0)` | Điểm của đội trong trận (3 thắng, 1 hòa, 0 thua) | Bảng xếp hạng của giải qua từng mùa? | Theo dõi tiến độ so với mục tiêu vô địch, trụ hạng; đánh giá HLV |
| `goal_difference` | Measure (additive) | Nạp Fact_Team_Match → *Tính kết quả trận và khóa ngày (Derived Column)* | `own_goals − opponent_goals` | Hiệu số bàn thắng của trận | Hiệu số của CLB trong mùa? Đội nào thắng đậm nhất? | Tiêu chí phụ khi xếp hạng; đánh giá cân bằng công – thủ |
| `goals_for, goals_against` | Measure (additive) | Nạp Fact_Team_Match → *Ép kiểu dữ liệu (Data Conversion)* | `chuỗi → DT_I2` | Bàn thắng, bàn thua của đội trong trận | Đội có hàng công / hàng thủ tốt nhất mùa? | Quyết định tăng cường tiền đạo hoặc hậu vệ |
| `league_position` | Measure (non-additive) | Nạp Fact_Team_Match → *Làm sạch chuỗi + Ép kiểu dữ liệu* | `own_position = '-1' → NULL; chuỗi → DT_I2` | Thứ hạng của đội trên BXH tại thời điểm trận | Thứ hạng cao nhất của CLB trong mùa? | Theo dõi vị trí so với mục tiêu giữa mùa |
| `season, competition của trận` | Bổ sung | Nạp Fact_Team_Match → *Lấy ngày mùa và giải của trận (Lookup trên Staging)* | `JOIN stg_raw_games theo game_id` | club_games không có ngày, mùa, giải nên lấy từ games | — | Có đủ ngữ cảnh thời gian và giải đấu cho từng trận |

### Fact_Player_Appearance

| Cột | Loại | Data Flow → component | Toán tử / biểu thức | Ý nghĩa | Câu hỏi nghiệp vụ | Để làm gì |
|---|---|---|---|---|---|---|
| `date_key` | Khóa | Nạp Fact_Player_Appearance → *Tính khóa ngày và cột đếm (Derived Column)* | `YEAR*10000 + MONTH*100 + DAY` | Khóa ngày thi đấu | Phong độ cầu thủ theo tháng? | Phát hiện cầu thủ sa sút hoặc quá tải |
| `appearance_count` | Measure (additive) | Nạp Fact_Player_Appearance → *Tính khóa ngày và cột đếm (Derived Column)* | `(DT_UI1)1` | Luôn bằng 1; SUM = số trận ra sân | Cầu thủ ra sân nhiều nhất mùa? | Mẫu số tính bàn/trận; điều khoản thưởng theo số trận |
| `minutes_played, goals, assists, yellow_cards, red_cards` | Measure (additive) | Nạp Fact_Player_Appearance → *Ép kiểu dữ liệu + Kiểm tra hợp lệ* | `chuỗi → DT_I2; minutes_played 0–130; không âm` | Số phút, bàn, kiến tạo, thẻ của cầu thủ trong trận (đã kiểm tra hợp lệ) | Vua phá lưới, vua kiến tạo; trọng tài rút nhiều thẻ nhất? | Tuyển trạch, định giá, trao giải; quản lý kỷ luật |
| `season của trận` | Bổ sung | Nạp Fact_Player_Appearance → *Lấy mùa giải của trận (Lookup trên Staging)* | `JOIN stg_raw_games theo game_id` | appearances không có mùa nên lấy từ games | — | Thống kê được theo mùa |

### Fact_Player_Valuation

| Cột | Loại | Data Flow → component | Toán tử / biểu thức | Ý nghĩa | Câu hỏi nghiệp vụ | Để làm gì |
|---|---|---|---|---|---|---|
| `value_change_eur` | Measure (additive) | Nạp Fact_Player_Valuation → *Đọc định giá và tính biến động giá trị (OLE DB Source)* | `LAG(market_value) OVER (PARTITION BY player_id ORDER BY ngày)` | Giá trị lần này − lần định giá trước | Cầu thủ nào tăng giá mạnh nhất năm 2024? | Mua sớm cầu thủ đang lên giá, bán đúng đỉnh; đánh giá hiệu quả đào tạo |
| `age_at_valuation` | Measure (non-additive) | Nạp Fact_Player_Valuation → *Tính tuổi và gán khóa Unknown (Derived Column)* | `DATEDIFF("yyyy", ngày sinh, ngày định giá) − 1 nếu chưa tới sinh nhật; ngày sinh lấy từ Tra khóa cầu thủ; tuổi < 14 hoặc > 100 → NULL` | Tuổi tròn tại ngày định giá (tuổi < 14 coi là ngày sinh nguồn sai, đặt NULL) | Giá trị cầu thủ đạt đỉnh ở độ tuổi nào? | Lên kế hoạch mua trẻ, bán đúng thời điểm |
| `valuation_count` | Measure (additive) | Nạp Fact_Player_Valuation → *Tính khóa ngày và cột đếm (Derived Column)* | `(DT_UI1)1` | Luôn bằng 1; SUM = số lần định giá | Cầu thủ nào được định giá lại thường xuyên nhất? | Mẫu số tính giá trị trung bình; đánh giá độ tin cậy dữ liệu |
| `market_value_eur` | Measure (semi-additive) | Nạp Fact_Player_Valuation → *Ép kiểu dữ liệu (Data Conversion)* | `chuỗi → DT_I8; giá trị âm → reject` | Giá trị thị trường tại ngày định giá | Tổng giá trị đội hình CLB tại 30/06? | Định giá tài sản, đàm phán mua bán |

### Fact_Transfer

| Cột | Loại | Data Flow → component | Toán tử / biểu thức | Ý nghĩa | Câu hỏi nghiệp vụ | Để làm gì |
|---|---|---|---|---|---|---|
| `transfer_fee_eur` | Measure (additive) | Nạp Fact_Transfer → *Ép kiểu dữ liệu + Tính loại phí phí chênh và khóa ngày* | `'700000.000' → DT_NUMERIC(19,3) → DT_I8; trống giữ NULL` | Phí chuyển nhượng (NULL = không công bố, 0 = miễn phí/cho mượn) | CLB nào chi tiêu nhiều nhất mùa? | Kiểm soát ngân sách, tuân thủ FFP |
| `fee_status` | Thuộc tính → khóa | Nạp Fact_Transfer → *Tính loại phí phí chênh và khóa ngày (Derived Column)* | `ISNULL(phí) ? 'Không công bố' : (phí == 0 ? 'Miễn phí hoặc cho mượn' : 'Có phí')` | Trạng thái phí của thương vụ | Tỉ lệ thương vụ miễn phí, cho mượn theo mùa? | Đánh giá chiến lược giảm chi phí; loại thương vụ không công bố khỏi thống kê phí |
| `fee_band` | Thuộc tính → khóa | Nạp Fact_Transfer → *Tính loại phí phí chênh và khóa ngày (Derived Column)* | `?: lồng nhau theo ngưỡng 1, 10, 50 triệu EUR` | Nhóm mức phí | Phân bố thương vụ theo mức phí? | Biết phân khúc giá chủ yếu của thị trường |
| `transfer_type_key` | Khóa | Nạp Fact_Transfer → *Tra khóa loại chuyển nhượng (Lookup)* | `JOIN Dim_Transfer_Type theo (fee_status, fee_band)` | Khóa junk dimension loại thương vụ | — | Lọc, nhóm theo loại phí |
| `fee_premium_eur` | Measure (additive) | Nạp Fact_Transfer → *Tính loại phí phí chênh và khóa ngày (Derived Column)* | `transfer_fee − market_value (NULL nếu thiếu một trong hai)` | Phí chênh so với giá trị thị trường (dương = mua đắt) | Thương vụ nào bị mua đắt nhất? | Đánh giá hiệu quả đàm phán, tránh mua hớ |
| `age_at_transfer` | Measure (non-additive) | Nạp Fact_Transfer → *Tính tuổi và gán khóa Unknown (Derived Column)* | `DATEDIFF("yyyy", ngày sinh, ngày chuyển nhượng) − 1 nếu chưa tới sinh nhật` | Tuổi tròn tại ngày chuyển nhượng | Tuổi trung bình cầu thủ mỗi CLB mua về? | Xác định chiến lược mua trẻ hay mua kinh nghiệm |
| `is_youth_transfer` | Degenerate (cờ lọc) | Nạp Fact_Transfer → *Tính tuổi và gán khóa Unknown (Derived Column)* | `ISNULL(ngày sinh) \|\| ISNULL(ngày) ? NULL : (tuổi < 18 ? 1 : 0)` | 1 = cầu thủ dưới 18 tuổi (chuyển nhượng ở cấp đội trẻ, thường phí 0) | Tuổi trung bình cầu thủ chuyên nghiệp được mua? Tỉ lệ thương vụ đội trẻ? | Tách thị trường đội trẻ khỏi thị trường chuyên nghiệp để tuổi trung bình, phí trung bình không bị kéo lệch |
| `transfer_count` | Measure (additive) | Nạp Fact_Transfer → *Tính loại phí phí chênh và khóa ngày (Derived Column)* | `(DT_UI1)1` | Luôn bằng 1; SUM = số thương vụ | CLB nào giao dịch nhiều nhất? | Đo mức độ xáo trộn đội hình |

### Dim_Club

| Cột | Loại | Data Flow → component | Toán tử / biểu thức | Ý nghĩa | Câu hỏi nghiệp vụ | Để làm gì |
|---|---|---|---|---|---|---|
| `stadium_capacity_band` | Thuộc tính (SCD2) | Nạp Dim_Club (SCD1 SCD2 SCD3) → *Chuẩn hóa giá trị và nhóm sức chứa sân (Derived Column)* | `?: theo ngưỡng 20.000 / 40.000 / 60.000 chỗ` | Nhóm quy mô sân | Sân lớn có giúp đội nhà thắng nhiều hơn? | Tham khảo khi nâng cấp sân |
| `country_name, confederation` | Thuộc tính (SCD1) | Nạp Dim_Club (SCD1 SCD2 SCD3) → *Tra tên giải VĐQG… (Lookup) + Chuẩn hóa… (Derived Column)* | `lấy theo giải VĐQG; UPPER + so sánh: EUROPA→UEFA, ASIEN→AFC…` | Quốc gia, liên đoàn của CLB | Dòng tiền chuyển nhượng giữa các quốc gia, châu lục? | Phân tích thị trường mua bán |
| `club_type` | Thuộc tính (SCD1) | Nạp Dim_Club / Bổ sung CLB… → *Gắn loại … (Derived Column)* | `hằng 'Club' / 'National Team' / 'Other'` | Phân loại CLB, đội tuyển, CLB ngoài phạm vi | — | Tách thống kê CLB và đội tuyển |

### Dim_Player

| Cột | Loại | Data Flow → component | Toán tử / biểu thức | Ý nghĩa | Câu hỏi nghiệp vụ | Để làm gì |
|---|---|---|---|---|---|---|
| `height_band` | Thuộc tính (SCD1) | Nạp Dim_Player (SCD1 SCD2) → *Chuẩn hóa và tính nhóm chiều cao khoác áo (Derived Column)* | `ngoài 150–220 cm → Không xác định; ?: theo 170/180/190 cm` | Nhóm chiều cao | Chiều cao có liên quan tới vị trí, bàn thắng? | Tuyển trạch theo thể hình phù hợp lối chơi |
| `international_caps_band` | Thuộc tính (SCD1) | Nạp Dim_Player (SCD1 SCD2) → *Chuẩn hóa và tính nhóm chiều cao khoác áo (Derived Column)* | `?: 0 / 1–10 / 11–50 / > 50` | Nhóm số trận khoác áo đội tuyển | Cầu thủ quốc tế có giá trị cao hơn? | Đánh giá kinh nghiệm khi định giá |
| `contract_expiry_year` | Thuộc tính (SCD1) | Nạp Dim_Player (SCD1 SCD2) → *Chuẩn hóa và tính nhóm chiều cao khoác áo (Derived Column)* | `YEAR(contract_expiration_date)` | Năm hết hạn hợp đồng | Cầu thủ sắp hết hợp đồng có bị bán rẻ? | Gia hạn hoặc bán sớm để không mất trắng |

### Dim_Match

| Cột | Loại | Data Flow → component | Toán tử / biểu thức | Ý nghĩa | Câu hỏi nghiệp vụ | Để làm gì |
|---|---|---|---|---|---|---|
| `round_type` | Thuộc tính | Nạp Dim_Match (SCD1) → *Chuẩn hóa và tính loại vòng nhóm khán giả (Derived Column)* | `FINDSTRING(round,'Matchday') / 'Group' / 'Final' → Knockout` | Loại vòng đấu | Vòng loại trực tiếp có ít bàn hơn vòng bảng? | Chuẩn bị cho giai đoạn quyết định |
| `attendance_band` | Thuộc tính | Nạp Dim_Match (SCD1) → *Chuẩn hóa và tính loại vòng nhóm khán giả (Derived Column)* | `?: theo ngưỡng 10.000 / 30.000 / 60.000 khán giả` | Nhóm số khán giả | Đông khán giả có giúp đội nhà thắng nhiều hơn? | Chính sách bán vé |

### Dim_Competition

| Cột | Loại | Data Flow → component | Toán tử / biểu thức | Ý nghĩa | Câu hỏi nghiệp vụ | Để làm gì |
|---|---|---|---|---|---|---|
| `country_name, confederation` | Thuộc tính (SCD1) | Nạp Dim_Competition (SCD1) → *Bổ sung tên quốc gia từ countries (Lookup) + Chuẩn hóa… (Derived Column)* | `country_id = -1 → 'International'; chuẩn hóa liên đoàn` | Quốc gia, liên đoàn của giải | So sánh chỉ số giữa các quốc gia, châu lục? | Chọn thị trường tuyển trạch, tài trợ |

---

## C. Measure tổng hợp ở tầng phân tích (SSAS / Power BI)

Các measure dưới đây **không lưu trong kho**; tầng phân tích tính khi người dùng chọn chiều phân tích, dựa trên các cột đã tính ở mục B.

| Measure | Công thức (DAX / MDX tương đương) | Dựa trên cột | Tính chất | Câu hỏi nghiệp vụ | Để làm gì |
|---|---|---|---|---|---|
| **Số trận** | `COUNTROWS(Fact_Team_Match)` | Fact_Team_Match | Additive | Mỗi CLB đá bao nhiêu trận trong mùa? | Mẫu số cho các tỉ lệ |
| **Thắng / Hòa / Thua** | `SUM(is_win) / SUM(is_draw) / SUM(is_loss)` | is_win, is_draw, is_loss | Additive | CLB nào thắng nhiều nhất mùa? | Đánh giá thành tích, đánh giá HLV |
| **Điểm** | `SUM(points)` | points | Additive | Bảng xếp hạng cuối mùa? | Xác định vô địch, suất dự cúp, xuống hạng |
| **Hiệu số** | `SUM(goal_difference)` | goal_difference | Additive | Hiệu số bàn thắng của từng CLB? | Tiêu chí phụ khi bằng điểm |
| **Tỉ lệ thắng** | `DIVIDE(SUM(is_win), COUNTROWS(Fact_Team_Match))` | is_win | Non-additive (tính lại theo bộ lọc) | HLV nào có tỉ lệ thắng cao nhất (tối thiểu 50 trận)? | Chọn, gia hạn hoặc sa thải HLV |
| **Tỉ lệ thắng sân nhà** | `CALCULATE([Tỉ lệ thắng], is_home = 1)` | is_win, is_home | Non-additive | Giải nào có lợi thế sân nhà lớn nhất? | Đặt mục tiêu điểm sân nhà |
| **Bàn thắng mỗi trận** | `DIVIDE(SUM(goals_for), [Số trận])` | goals_for | Non-additive | Giải nào ghi nhiều bàn mỗi trận nhất? | So sánh độ hấp dẫn giữa các giải |
| **Số trận sạch lưới** | `SUM(is_clean_sheet)` | is_clean_sheet | Additive | Thủ môn / hàng thủ nào tốt nhất mùa? | Gia hạn hoặc mua thủ môn |
| **Bàn thắng, kiến tạo, phút** | `SUM(goals), SUM(assists), SUM(minutes_played)` | Fact_Player_Appearance | Additive | Vua phá lưới, vua kiến tạo từng giải, từng mùa? | Tuyển trạch, trao giải |
| **Bàn mỗi 90 phút** | `DIVIDE(SUM(goals) * 90, SUM(minutes_played))` | goals, minutes_played | Non-additive | Tiền đạo nào ghi bàn hiệu quả nhất mỗi 90 phút? | So sánh công bằng giữa cầu thủ đá chính và dự bị |
| **Số trận ra sân** | `SUM(appearance_count)` | appearance_count | Additive | Cầu thủ nào ra sân nhiều nhất? | Đánh giá độ ổn định, điều khoản hợp đồng |
| **Thẻ phạt mỗi trận** | `DIVIDE(SUM(yellow_cards) + SUM(red_cards), DISTINCTCOUNT(match_key))` | yellow_cards, red_cards | Non-additive | Trọng tài nào khắt khe nhất? | Chuẩn bị cho cầu thủ trước trận |
| **Giá trị đội hình tại một ngày** | `Giá trị lần định giá gần nhất của từng cầu thủ, rồi SUM theo CLB (LastNonEmpty)` | market_value_eur | Semi-additive | Tổng giá trị đội hình CLB ngày 30/06/2025? | Báo cáo tài sản, đàm phán tài trợ |
| **Mức tăng giá** | `SUM(value_change_eur)` | value_change_eur | Additive | Cầu thủ, CLB nào tăng giá mạnh nhất năm? | Đánh giá hiệu quả đào tạo, thời điểm bán |
| **Tuổi trung bình** | `AVERAGE(age_at_valuation); CALCULATE(AVERAGE(age_at_transfer), is_youth_transfer = 0)` | age_at_valuation, age_at_transfer, is_youth_transfer | Non-additive | Độ tuổi đỉnh giá trị? Tuổi trung bình cầu thủ chuyên nghiệp được mua? | Chiến lược mua trẻ hay mua kinh nghiệm (không bị thương vụ đội trẻ kéo lệch) |
| **Tỉ lệ thương vụ đội trẻ** | `DIVIDE(SUM(is_youth_transfer), COUNT(is_youth_transfer))` | is_youth_transfer | Non-additive | CLB nào mua nhiều cầu thủ trẻ nhất? | Đánh giá chiến lược đào tạo trẻ |
| **Chi mua / Thu bán** | `SUM(transfer_fee_eur) theo vai to_club_key / from_club_key (USERELATIONSHIP)` | transfer_fee_eur | Additive | CLB chi bao nhiêu, thu bao nhiêu mỗi mùa? | Kiểm soát ngân sách chuyển nhượng |
| **Chi tiêu ròng** | `[Chi mua] − [Thu bán]` | transfer_fee_eur | Additive | CLB nào chi tiêu ròng nhiều nhất mùa? | Tuân thủ FFP, so sánh với đối thủ |
| **Phí chênh trung bình** | `AVERAGE(fee_premium_eur)` | fee_premium_eur | Non-additive | CLB / người đại diện nào hay mua đắt? | Cải thiện đàm phán |
| **Số thương vụ, tỉ lệ miễn phí** | `SUM(transfer_count); DIVIDE(số thương vụ fee_status = 'Miễn phí…', SUM(transfer_count))` | transfer_count, transfer_type_key | Additive / Non-additive | Tỉ lệ thương vụ miễn phí, cho mượn theo mùa? | Đánh giá chiến lược tiết kiệm chi phí |

---

## D. Những gì không còn làm

- Không còn container *Aggregate* chạy `DELETE` + `INSERT … GROUP BY` trên kho sau khi nạp.
- Không còn bảng tổng hợp / snapshot theo mùa trong kho: tổng hợp theo mùa do SSAS / Power BI tính từ fact chi tiết.
- Không còn `UPDATE dim_date SET is_future_date` mỗi lần chạy: cột này được tính một lần khi sinh Dim_Date.

