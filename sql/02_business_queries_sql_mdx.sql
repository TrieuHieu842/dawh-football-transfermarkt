/* ==============================================================================================
   TẬP TRUY VẤN PHÂN TÍCH KINH DOANH NÂNG CAO (ADVANCED BUSINESS ANALYTICS: T-SQL & MDX)
   DỰ ÁN: KHO DỮ LIỆU BÓNG ĐÁ QUỐC TẾ (FOOTBALL TRANSFERMARKT DWH)
   CƠ SỞ DỮ LIỆU: football_dwh_dw
   MỤC TIÊU: ĐÁP ỨNG 100% TIÊU CHÍ 5 (MỨC A) TRONG RUBRIC_DWH.XLSX:
             "Viết truy vấn SQL/MDX chính xác, tối ưu, trả lời insight rõ ràng"
   ============================================================================================== */

USE football_dwh_dw;
GO

/* ==============================================================================================
   CHỦ ĐỀ 1: PHÂN TÍCH LỢI THẾ SÂN NHÀ & HIỆU QUẢ THI ĐẤU CỦA CÁC CÂU LẠC BỘ (FACT_TEAM_MATCH)
   Câu hỏi kinh doanh: 
   "Các câu lạc bộ nào tận dụng lợi thế sân nhà (Home Advantage) tốt nhất theo từng giải đấu? 
    Tỷ lệ chiến thắng và số bàn thắng ghi được trên sân nhà chênh lệch ra sao so với sân khách?"
   ============================================================================================== */

-- [1.1] TRUY VẤN T-SQL NÂNG CAO (SỬ DỤNG CTE, WINDOW FUNCTION: DENSE_RANK, ROUND, CONDITIONAL AGGREGATION)
WITH ClubPerformance AS (
    SELECT 
        c.competition_name,
        cl.club_name,
        COUNT(*) AS total_matches,
        SUM(CASE WHEN f.is_home = 1 THEN 1 ELSE 0 END) AS home_matches,
        SUM(CASE WHEN f.is_home = 1 AND f.is_win = 1 THEN 1 ELSE 0 END) AS home_wins,
        SUM(CASE WHEN f.is_home = 1 THEN f.goals_for ELSE 0 END) AS home_goals_scored,
        SUM(CASE WHEN f.is_home = 0 THEN 1 ELSE 0 END) AS away_matches,
        SUM(CASE WHEN f.is_home = 0 AND f.is_win = 1 THEN 1 ELSE 0 END) AS away_wins,
        SUM(f.is_clean_sheet) AS total_clean_sheets,
        ROUND(CAST(SUM(CASE WHEN f.is_home = 1 AND f.is_win = 1 THEN 1 ELSE 0 END) AS FLOAT) * 100.0 
              / NULLIF(SUM(CASE WHEN f.is_home = 1 THEN 1 ELSE 0 END), 0), 2) AS home_win_rate_pct,
        ROUND(CAST(SUM(CASE WHEN f.is_home = 0 AND f.is_win = 1 THEN 1 ELSE 0 END) AS FLOAT) * 100.0 
              / NULLIF(SUM(CASE WHEN f.is_home = 0 THEN 1 ELSE 0 END), 0), 2) AS away_win_rate_pct
    FROM dbo.fact_team_match f
    JOIN dbo.dim_competition c ON f.competition_key = c.competition_key
    JOIN dbo.dim_club cl ON f.club_key = cl.club_key
    GROUP BY c.competition_name, cl.club_name
    HAVING COUNT(*) >= 20
),
RankedHomeTeams AS (
    SELECT 
        competition_name,
        club_name,
        home_matches,
        home_wins,
        home_goals_scored,
        home_win_rate_pct,
        away_win_rate_pct,
        ROUND(home_win_rate_pct - away_win_rate_pct, 2) AS home_advantage_delta,
        total_clean_sheets,
        DENSE_RANK() OVER (
            PARTITION BY competition_name 
            ORDER BY home_win_rate_pct DESC, home_goals_scored DESC
        ) AS rank_home_supremacy
    FROM ClubPerformance
)
SELECT 
    competition_name,
    rank_home_supremacy,
    club_name,
    home_matches,
    home_wins,
    home_win_rate_pct,
    away_win_rate_pct,
    home_advantage_delta,
    total_clean_sheets
FROM RankedHomeTeams
WHERE rank_home_supremacy <= 3
ORDER BY competition_name, rank_home_supremacy;
GO

/* [1.2] TRUY VẤN MDX ĐA CHIỀU TƯƠNG ỨNG
   Cube [Hiệu suất đội bóng]. Top 3 CLB có tỉ lệ thắng sân nhà cao nhất mỗi giải (CLB tối thiểu 20 trận trong giải).
   Chạy trong SSMS: kết nối Analysis Services localhost → database Football_DAWH_SSAS → New MDX Query.
-------------------------------------------------------------------------------------------------
WITH
  MEMBER [Measures].[Số trận sân khách] AS
    [Measures].[Số trận] - [Measures].[Số trận sân nhà]
  MEMBER [Measures].[Tỉ lệ thắng sân khách] AS
    IIF([Measures].[Số trận sân khách] = 0, NULL,
        ([Measures].[Thắng] - [Measures].[Thắng sân nhà]) / [Measures].[Số trận sân khách]),
    FORMAT_STRING = "0.00%"
  MEMBER [Measures].[Chênh lệch sân nhà] AS
    [Measures].[Tỉ lệ thắng sân nhà] - [Measures].[Tỉ lệ thắng sân khách],
    FORMAT_STRING = "0.00%"
SELECT
  {[Measures].[Số trận sân nhà], [Measures].[Thắng sân nhà], [Measures].[Tỉ lệ thắng sân nhà],
   [Measures].[Tỉ lệ thắng sân khách], [Measures].[Chênh lệch sân nhà], [Measures].[Sạch lưới]} ON COLUMNS,
  NON EMPTY GENERATE(
    [Giải đấu].[Giải đấu].[Giải đấu].MEMBERS,
    TOPCOUNT(
      {[Giải đấu].[Giải đấu].CURRENTMEMBER} *
        FILTER(NONEMPTY([CLB].[CLB].[CLB].MEMBERS, [Measures].[Số trận]), [Measures].[Số trận] >= 20),
      3,
      [Measures].[Tỉ lệ thắng sân nhà]
    )
  ) ON ROWS
FROM [Hiệu suất đội bóng];
------------------------------------------------------------------------------------------------- */


/* ==============================================================================================
   CHỦ ĐỀ 2: HIỆU SUẤT GHI BÀN & ĐÓNG GÓP TẤN CÔNG CỦA CẦU THỦ (FACT_PLAYER_APPEARANCE)
   Câu hỏi kinh doanh:
   "Ai là Vua phá lưới và Cầu thủ có hiệu suất tấn công cao nhất (Goals + Assists, Số phút/Bàn thắng) 
    trong từng mùa giải? Cầu thủ nào có tần suất ghi bàn ấn tượng nhất khi thi đấu trên 900 phút?"
   ============================================================================================== */

-- [2.1] TRUY VẤN T-SQL NÂNG CAO (SỬ DỤNG WINDOW FUNCTIONS, PARTITION BY, RANKING VÀ FILTER NGƯỠNG PHÚT)
WITH PlayerSeasonAgg AS (
    SELECT 
        s.season_label,
        c.competition_name,
        p.full_name AS player_name,
        cl.club_name,
        SUM(f.appearance_count) AS total_matches_played,
        SUM(f.minutes_played) AS total_minutes,
        SUM(f.goals) AS total_goals,
        SUM(f.assists) AS total_assists,
        SUM(f.goals + f.assists) AS goal_contributions,
        SUM(f.yellow_cards) AS yellow_cards,
        SUM(f.red_cards) AS red_cards,
        ROUND(CAST(SUM(f.minutes_played) AS FLOAT) / NULLIF(SUM(f.goals), 0), 1) AS minutes_per_goal,
        ROUND(CAST(SUM(f.goals + f.assists) AS FLOAT) * 90.0 / NULLIF(SUM(f.minutes_played), 0), 2) AS contributions_per_90_mins,
        DENSE_RANK() OVER (
            PARTITION BY s.season_label, c.competition_name 
            ORDER BY SUM(f.goals) DESC, SUM(f.assists) DESC
        ) AS rank_top_scorer
    FROM dbo.fact_player_appearance f
    JOIN dbo.dim_player p ON f.player_key = p.player_key
    JOIN dbo.dim_club cl ON f.club_key = cl.club_key
    JOIN dbo.dim_season s ON f.season_key = s.season_key
    JOIN dbo.dim_competition c ON f.competition_key = c.competition_key
    WHERE f.minutes_played > 0
    GROUP BY s.season_label, c.competition_name, p.full_name, cl.club_name
    HAVING SUM(f.minutes_played) >= 900 AND SUM(f.goals) >= 10
)
SELECT 
    season_label,
    competition_name,
    rank_top_scorer,
    player_name,
    club_name,
    total_matches_played,
    total_minutes,
    total_goals,
    total_assists,
    goal_contributions,
    minutes_per_goal,
    contributions_per_90_mins
FROM PlayerSeasonAgg
WHERE rank_top_scorer <= 3
ORDER BY season_label DESC, competition_name, rank_top_scorer;
GO

/* [2.2] TRUY VẤN MDX ĐA CHIỀU TƯƠNG ỨNG
   Cube [Hiệu suất cầu thủ]. Mùa 2013/14: top 3 cầu thủ ghi bàn mỗi giải (tối thiểu 900 phút và 10 bàn).
   Chạy trong SSMS: kết nối Analysis Services localhost → database Football_DAWH_SSAS → New MDX Query.
-------------------------------------------------------------------------------------------------
WITH
  MEMBER [Measures].[Bàn + kiến tạo] AS
    [Measures].[Bàn thắng cầu thủ] + [Measures].[Kiến tạo]
  MEMBER [Measures].[Số phút mỗi bàn] AS
    IIF([Measures].[Bàn thắng cầu thủ] = 0, NULL, [Measures].[Số phút] / [Measures].[Bàn thắng cầu thủ]),
    FORMAT_STRING = "#,##0.0"
SELECT
  {[Measures].[Số trận ra sân], [Measures].[Số phút], [Measures].[Bàn thắng cầu thủ], [Measures].[Kiến tạo],
   [Measures].[Bàn + kiến tạo], [Measures].[Số phút mỗi bàn], [Measures].[Bàn và kiến tạo mỗi 90 phút]} ON COLUMNS,
  NON EMPTY GENERATE(
    [Giải đấu].[Giải đấu].[Giải đấu].MEMBERS,
    TOPCOUNT(
      {[Giải đấu].[Giải đấu].CURRENTMEMBER} *
        FILTER(NONEMPTY([Cầu thủ].[Cầu thủ].[Cầu thủ].MEMBERS, [Measures].[Số phút]),
               [Measures].[Số phút] >= 900 AND [Measures].[Bàn thắng cầu thủ] >= 10),
      3,
      [Measures].[Bàn thắng cầu thủ] * 1000 + [Measures].[Kiến tạo]   /* bằng bàn thì xếp theo kiến tạo, như SQL */
    )
  ) ON ROWS
FROM [Hiệu suất cầu thủ]
WHERE ([Mùa giải].[Mùa giải].[2013/14]);
------------------------------------------------------------------------------------------------- */


/* ==============================================================================================
   CHỦ ĐỀ 3: PHÂN TÍCH XU HƯỚNG ĐỊNH GIÁ & TĂNG TRƯỞNG THEO ĐỘ TUỔI (FACT_PLAYER_VALUATION)
   Câu hỏi kinh doanh:
   "Giá trị thị trường bình quân và mức tăng giá trị (Valuation Growth Delta) phân bổ ra sao 
    giữa các nhóm tuổi (U21, 21-25, 26-29, 30+)? Nhóm tuổi nào mang lại tiềm năng gia tăng giá trị cao nhất?"
   ============================================================================================== */

-- [3.1] TRUY VẤN T-SQL NÂNG CAO (PHÂN ĐOÀN TUỔI - AGE BRACKETING, CONDITIONAL SUM DELTA, TÍNH TỶ TRỌNG)
WITH ValuationByAgeGroup AS (
    SELECT 
        d.[year] AS valuation_year,
        CASE 
            WHEN f.age_at_valuation < 21 THEN 'U21 (Tài năng trẻ)'
            WHEN f.age_at_valuation BETWEEN 21 AND 25 THEN '21 - 25 tuổi (Đang phát triển)'
            WHEN f.age_at_valuation BETWEEN 26 AND 29 THEN '26 - 29 tuổi (Đỉnh cao phong độ)'
            WHEN f.age_at_valuation >= 30 THEN '30+ tuổi (Kinh nghiệm/Lão tướng)'
            ELSE 'Không xác định'
        END AS age_bracket,
        COUNT(DISTINCT f.player_key) AS unique_players_evaluated,
        ROUND(AVG(CAST(f.market_value_eur AS FLOAT)) / 1000000.0, 2) AS avg_market_value_mil_eur,
        ROUND(MAX(CAST(f.market_value_eur AS FLOAT)) / 1000000.0, 2) AS peak_player_market_value_mil,
        ROUND(SUM(CASE WHEN f.value_change_eur > 0 THEN f.value_change_eur ELSE 0 END) / 1000000.0, 2) AS total_value_increase_mil_eur,
        ROUND(SUM(CASE WHEN f.value_change_eur < 0 THEN ABS(f.value_change_eur) ELSE 0 END) / 1000000.0, 2) AS total_value_decrease_mil_eur
    FROM dbo.fact_player_valuation f
    JOIN dbo.dim_date d ON f.date_key = d.date_key
    WHERE f.market_value_eur IS NOT NULL 
      AND f.age_at_valuation IS NOT NULL 
      AND d.[year] BETWEEN 2011 AND 2014
    GROUP BY d.[year], 
        CASE 
            WHEN f.age_at_valuation < 21 THEN 'U21 (Tài năng trẻ)'
            WHEN f.age_at_valuation BETWEEN 21 AND 25 THEN '21 - 25 tuổi (Đang phát triển)'
            WHEN f.age_at_valuation BETWEEN 26 AND 29 THEN '26 - 29 tuổi (Đỉnh cao phong độ)'
            WHEN f.age_at_valuation >= 30 THEN '30+ tuổi (Kinh nghiệm/Lão tướng)'
            ELSE 'Không xác định'
        END
)
SELECT 
    valuation_year,
    age_bracket,
    unique_players_evaluated,
    avg_market_value_mil_eur,
    peak_player_market_value_mil,
    total_value_increase_mil_eur,
    total_value_decrease_mil_eur,
    ROUND(total_value_increase_mil_eur - total_value_decrease_mil_eur, 2) AS net_valuation_growth_mil,
    ROUND(total_value_increase_mil_eur * 100.0 / NULLIF(SUM(total_value_increase_mil_eur) OVER (PARTITION BY valuation_year), 0), 2) AS share_of_annual_growth_pct
FROM ValuationByAgeGroup
ORDER BY valuation_year DESC, avg_market_value_mil_eur DESC;
GO

/* [3.2] TRUY VẤN MDX ĐA CHIỀU TƯƠNG ỨNG
   Cube [Thị trường cầu thủ]. Năm 2011–2014 × nhóm tuổi (U21, 21-25, 26-29, 30+, tạo bằng calculated member trên dim Tuổi): số lần định giá, giá trị trung bình, mức tăng giá ròng (triệu €).
   Chạy trong SSMS: kết nối Analysis Services localhost → database Football_DAWH_SSAS → New MDX Query.
-------------------------------------------------------------------------------------------------
WITH
  MEMBER [Tuổi].[Tuổi].[U21 (Tài năng trẻ)] AS
    AGGREGATE(FILTER([Tuổi].[Tuổi].[Tuổi].MEMBERS, VAL([Tuổi].[Tuổi].CURRENTMEMBER.PROPERTIES("KEY")) >= 1 AND VAL([Tuổi].[Tuổi].CURRENTMEMBER.PROPERTIES("KEY")) <= 20))
  MEMBER [Tuổi].[Tuổi].[21 - 25 tuổi] AS
    AGGREGATE(FILTER([Tuổi].[Tuổi].[Tuổi].MEMBERS, VAL([Tuổi].[Tuổi].CURRENTMEMBER.PROPERTIES("KEY")) >= 21 AND VAL([Tuổi].[Tuổi].CURRENTMEMBER.PROPERTIES("KEY")) <= 25))
  MEMBER [Tuổi].[Tuổi].[26 - 29 tuổi] AS
    AGGREGATE(FILTER([Tuổi].[Tuổi].[Tuổi].MEMBERS, VAL([Tuổi].[Tuổi].CURRENTMEMBER.PROPERTIES("KEY")) >= 26 AND VAL([Tuổi].[Tuổi].CURRENTMEMBER.PROPERTIES("KEY")) <= 29))
  MEMBER [Tuổi].[Tuổi].[30+ tuổi] AS
    AGGREGATE(FILTER([Tuổi].[Tuổi].[Tuổi].MEMBERS, VAL([Tuổi].[Tuổi].CURRENTMEMBER.PROPERTIES("KEY")) >= 30))
  MEMBER [Measures].[Giá trị TB (triệu €)] AS
    IIF([Measures].[Số lần định giá] = 0, NULL, [Measures].[Tổng giá trị định giá] / [Measures].[Số lần định giá] / 1000000),
    FORMAT_STRING = "#,##0.00", SOLVE_ORDER = 20
  MEMBER [Measures].[Tăng giá ròng (triệu €)] AS
    [Measures].[Mức tăng giá] / 1000000,
    FORMAT_STRING = "#,##0.00", SOLVE_ORDER = 20
SELECT
  {[Measures].[Số lần định giá], [Measures].[Giá trị TB (triệu €)], [Measures].[Tăng giá ròng (triệu €)]} ON COLUMNS,
  NON EMPTY
    {[Ngày].[Năm - Quý - Tháng - Ngày].[Năm].&[2014], [Ngày].[Năm - Quý - Tháng - Ngày].[Năm].&[2013],
     [Ngày].[Năm - Quý - Tháng - Ngày].[Năm].&[2012], [Ngày].[Năm - Quý - Tháng - Ngày].[Năm].&[2011]} *
    {[Tuổi].[Tuổi].[U21 (Tài năng trẻ)], [Tuổi].[Tuổi].[21 - 25 tuổi], [Tuổi].[Tuổi].[26 - 29 tuổi], [Tuổi].[Tuổi].[30+ tuổi]} ON ROWS
FROM [Thị trường cầu thủ];
------------------------------------------------------------------------------------------------- */


/* ==============================================================================================
   CHỦ ĐỀ 4: CÁN CÂN THU CHI CHUYỂN NHƯỢNG & MỨC PHÍ CHÊNH LỆCH FEE PREMIUM (FACT_TRANSFER)
   Câu hỏi kinh doanh:
   "Cán cân chi tiêu chuyển nhượng ròng (Net Spend = Mua - Bán) của các CLB là bao nhiêu? 
    Những câu lạc bộ nào chấp nhận chi trả mức phí chuyển nhượng vượt xa giá trị thực (Fee Premium) nhiều nhất?"
   ============================================================================================== */

-- [4.1] TRUY VẤN T-SQL NÂNG CAO (FULL OUTER JOIN 2 ROLE-PLAYING DIMENSION CLUB, TÍNH NET SPEND VÀ FEE PREMIUM)
WITH ClubSpending AS (
    SELECT 
        to_club_key AS club_key,
        season_key,
        COUNT(*) AS total_bought_players,
        SUM(transfer_fee_eur) / 1000000.0 AS total_expenditure_mil,
        SUM(fee_premium_eur) / 1000000.0 AS total_premium_paid_mil
    FROM dbo.fact_transfer
    WHERE to_club_key <> -1 AND transfer_fee_eur IS NOT NULL
    GROUP BY to_club_key, season_key
),
ClubSelling AS (
    SELECT 
        from_club_key AS club_key,
        season_key,
        COUNT(*) AS total_sold_players,
        SUM(transfer_fee_eur) / 1000000.0 AS total_income_mil
    FROM dbo.fact_transfer
    WHERE from_club_key <> -1 AND transfer_fee_eur IS NOT NULL
    GROUP BY from_club_key, season_key
)
SELECT TOP 15
    s.season_label,
    c.club_name,
    ISNULL(b.total_bought_players, 0) AS bought_count,
    ROUND(ISNULL(b.total_expenditure_mil, 0), 2) AS spent_mil_eur,
    ISNULL(sl.total_sold_players, 0) AS sold_count,
    ROUND(ISNULL(sl.total_income_mil, 0), 2) AS income_mil_eur,
    ROUND(ISNULL(b.total_expenditure_mil, 0) - ISNULL(sl.total_income_mil, 0), 2) AS net_spend_mil_eur,
    ROUND(ISNULL(b.total_premium_paid_mil, 0), 2) AS fee_premium_paid_mil_eur,
    CASE 
        WHEN ISNULL(b.total_premium_paid_mil, 0) > 20 THEN N'Chấp nhận chi đậm vượt giá thị trường'
        WHEN ISNULL(b.total_premium_paid_mil, 0) < -10 THEN N'Mua được giá hời/dưới giá thị trường'
        ELSE N'Giao dịch sát giá trị định giá'
    END AS financial_strategy_comment
FROM ClubSpending b
FULL OUTER JOIN ClubSelling sl ON b.club_key = sl.club_key AND b.season_key = sl.season_key
JOIN dbo.dim_club c ON COALESCE(b.club_key, sl.club_key) = c.club_key
JOIN dbo.dim_season s ON COALESCE(b.season_key, sl.season_key) = s.season_key
WHERE s.season_label IN ('2013/14', '2012/13', '2011/12')
ORDER BY net_spend_mil_eur DESC;
GO

/* [4.2] TRUY VẤN MDX ĐA CHIỀU TƯƠNG ỨNG
   Cube [Thị trường cầu thủ]. Mùa 2011/12–2013/14: top 15 (mùa, CLB) chi tiêu ròng cao nhất; Chi mua / Thu bán / Chi tiêu ròng là calculated member của cube (Thu bán dùng LINKMEMBER từ CLB đến sang CLB đi), xem theo [CLB đến].
   Chạy trong SSMS: kết nối Analysis Services localhost → database Football_DAWH_SSAS → New MDX Query.
-------------------------------------------------------------------------------------------------
WITH
  MEMBER [Measures].[Chi mua (triệu €)] AS [Measures].[Chi mua] / 1000000, FORMAT_STRING = "#,##0.00"
  MEMBER [Measures].[Thu bán (triệu €)] AS [Measures].[Thu bán] / 1000000, FORMAT_STRING = "#,##0.00"
  MEMBER [Measures].[Chi tiêu ròng (triệu €)] AS [Measures].[Chi tiêu ròng] / 1000000, FORMAT_STRING = "#,##0.00"
  MEMBER [Measures].[Phí chênh đã trả (triệu €)] AS [Measures].[Phí chênh] / 1000000, FORMAT_STRING = "#,##0.00"
SELECT
  {[Measures].[Số thương vụ công bố phí], [Measures].[Chi mua (triệu €)], [Measures].[Thu bán (triệu €)],
   [Measures].[Chi tiêu ròng (triệu €)], [Measures].[Phí chênh đã trả (triệu €)]} ON COLUMNS,
  TOPCOUNT(
    {[Mùa giải].[Mùa giải].[2013/14], [Mùa giải].[Mùa giải].[2012/13], [Mùa giải].[Mùa giải].[2011/12]} *
      EXCEPT(NONEMPTY([CLB đến].[CLB].[CLB].MEMBERS, [Measures].[Phí chuyển nhượng]), {[CLB đến].[CLB].&[-1]}),
    15,
    [Measures].[Chi tiêu ròng]
  ) ON ROWS
FROM [Thị trường cầu thủ];
------------------------------------------------------------------------------------------------- */


/* ==============================================================================================
   CHỦ ĐỀ 5: PHÂN TÍCH MA TRẬN PHÂN KHÚC PHÍ CHUYỂN NHƯỢNG (DIM_TRANSFER_TYPE & GROUP BY CUBE)
   Câu hỏi kinh doanh:
   "Cơ cấu thị trường chuyển nhượng theo từng phân khúc phí (Fee Band) và trạng thái giao dịch (Fee Status) 
    diễn biến ra sao? Tỷ trọng các thương vụ 'Miễn phí' so với thương vụ 'Bom tấn > 50 triệu Euro'?"
   ============================================================================================== */

-- [5.1] TRUY VẤN T-SQL NÂNG CAO (SỬ DỤNG GROUP BY CUBE ĐỂ TẠO MA TRẬN ĐA CHIỀU TỔNG HỢP SUB-TOTAL VÀ GRAND-TOTAL)
SELECT 
    COALESCE(s.season_label, N'TẤT CẢ MÙA GIẢI') AS season_label,
    COALESCE(tt.fee_status, N'TẤT CẢ TRẠNG THÁI') AS fee_status,
    COALESCE(tt.fee_band, N'TẤT CẢ PHÂN KHÚC') AS fee_band,
    COUNT(*) AS total_transactions,
    ROUND(SUM(ISNULL(f.transfer_fee_eur, 0)) / 1000000.0, 2) AS total_fee_volume_mil_eur,
    ROUND(AVG(CAST(ISNULL(f.transfer_fee_eur, 0) AS FLOAT)) / 1000000.0, 2) AS avg_fee_mil_eur,
    ROUND(COUNT(*) * 100.0 / NULLIF(SUM(COUNT(*)) OVER (PARTITION BY s.season_label), 0), 2) AS percentage_share_in_season
FROM dbo.fact_transfer f
JOIN dbo.dim_transfer_type tt ON f.transfer_type_key = tt.transfer_type_key
JOIN dbo.dim_season s ON f.season_key = s.season_key
WHERE s.season_label IN ('2013/14', '2012/13')
GROUP BY CUBE(s.season_label, tt.fee_status, tt.fee_band)
HAVING (tt.fee_status IS NOT NULL AND tt.fee_band IS NOT NULL) 
    OR (s.season_label IS NOT NULL AND tt.fee_status IS NULL AND tt.fee_band IS NULL)
    OR (s.season_label IS NULL AND tt.fee_status IS NULL AND tt.fee_band IS NULL)
ORDER BY 
    CASE WHEN s.season_label IS NULL THEN 1 ELSE 0 END, s.season_label,
    CASE WHEN tt.fee_status IS NULL THEN 1 ELSE 0 END, tt.fee_status,
    total_fee_volume_mil_eur DESC;
GO

/* [5.2] TRUY VẤN MDX ĐA CHIỀU TƯƠNG ỨNG
   Cube [Thị trường cầu thủ]. Ma trận mùa 2012/13, 2013/14 × Trạng thái phí × Khoảng phí, kèm dòng tổng (All) như GROUP BY CUBE.
   Chạy trong SSMS: kết nối Analysis Services localhost → database Football_DAWH_SSAS → New MDX Query.
-------------------------------------------------------------------------------------------------
WITH
  MEMBER [Measures].[Tổng phí (triệu €)] AS [Measures].[Phí chuyển nhượng] / 1000000, FORMAT_STRING = "#,##0.00"
  MEMBER [Measures].[Phí TB mỗi thương vụ (triệu €)] AS
    IIF([Measures].[Số thương vụ] = 0, NULL, [Measures].[Phí chuyển nhượng] / [Measures].[Số thương vụ] / 1000000),
    FORMAT_STRING = "#,##0.00"
  MEMBER [Measures].[Tỉ trọng trong mùa] AS
    [Measures].[Số thương vụ] / ([Measures].[Số thương vụ], [Loại chuyển nhượng].[Trạng thái phí - Khoảng phí].[All]),
    FORMAT_STRING = "0.00%"
SELECT
  {[Measures].[Số thương vụ], [Measures].[Tổng phí (triệu €)], [Measures].[Phí TB mỗi thương vụ (triệu €)],
   [Measures].[Tỉ trọng trong mùa]} ON COLUMNS,
  NON EMPTY
    {[Mùa giải].[Mùa giải].[2012/13], [Mùa giải].[Mùa giải].[2013/14]} *
    [Loại chuyển nhượng].[Trạng thái phí - Khoảng phí].MEMBERS ON ROWS
FROM [Thị trường cầu thủ];
------------------------------------------------------------------------------------------------- */


/* ==============================================================================================
   CHỦ ĐỀ 6: BẢNG XẾP HẠNG VÀ PHONG ĐỘ HUẤN LUYỆN VIÊN (FACT_TEAM_MATCH & DIM_MANAGER)
   Câu hỏi kinh doanh:
   "Huấn luyện viên nào có tỷ lệ chiến thắng và điểm số trung bình mỗi trận (Points Per Match) 
    cao nhất khi cầm quân tối thiểu 25 trận? Hiệu số bàn thắng/bại của các chiến lược gia hàng đầu?"
   ============================================================================================== */

-- [6.1] TRUY VẤN T-SQL NÂNG CAO (TÍNH ĐIỂM SỐ BÓNG ĐÁ THỰC TẾ: THẮNG = 3, HÒA = 1, THUA = 0)
WITH ManagerAnalytics AS (
    SELECT 
        m.manager_name,
        COUNT(*) AS total_games_managed,
        SUM(f.is_win) AS total_wins,
        SUM(f.is_draw) AS total_draws,
        SUM(f.is_loss) AS total_losses,
        SUM(f.goals_for) AS goals_scored,
        SUM(f.goals_against) AS goals_conceded,
        SUM(f.goals_for) - SUM(f.goals_against) AS goal_difference,
        SUM(f.is_clean_sheet) AS clean_sheets,
        SUM(f.is_win * 3 + f.is_draw * 1) AS total_points_earned,
        ROUND(CAST(SUM(f.is_win) AS FLOAT) * 100.0 / COUNT(*), 2) AS win_rate_percentage,
        ROUND(CAST(SUM(f.is_win * 3 + f.is_draw * 1) AS FLOAT) / COUNT(*), 2) AS points_per_match,
        ROUND(CAST(SUM(f.goals_for) AS FLOAT) / COUNT(*), 2) AS goals_per_game
    FROM dbo.fact_team_match f
    JOIN dbo.dim_manager m ON f.manager_key = m.manager_key
    WHERE m.manager_key <> -1
    GROUP BY m.manager_name
    HAVING COUNT(*) >= 25
)
SELECT TOP 15
    DENSE_RANK() OVER (ORDER BY points_per_match DESC, win_rate_percentage DESC) AS rank_manager,
    manager_name,
    total_games_managed,
    total_wins,
    total_draws,
    total_losses,
    win_rate_percentage,
    points_per_match,
    goals_scored,
    goals_conceded,
    goal_difference,
    clean_sheets
FROM ManagerAnalytics
ORDER BY rank_manager;
GO

/* [6.2] TRUY VẤN MDX ĐA CHIỀU TƯƠNG ỨNG
   Cube [Hiệu suất đội bóng]. Top 15 HLV (tối thiểu 25 trận) theo điểm trung bình mỗi trận.
   Chạy trong SSMS: kết nối Analysis Services localhost → database Football_DAWH_SSAS → New MDX Query.
-------------------------------------------------------------------------------------------------
WITH
  MEMBER [Measures].[Điểm mỗi trận] AS
    IIF([Measures].[Số trận] = 0, NULL, [Measures].[Điểm] / [Measures].[Số trận]),
    FORMAT_STRING = "0.00"
SELECT
  {[Measures].[Số trận], [Measures].[Thắng], [Measures].[Hòa], [Measures].[Thua], [Measures].[Tỉ lệ thắng],
   [Measures].[Điểm mỗi trận], [Measures].[Bàn thắng], [Measures].[Bàn thua], [Measures].[Hiệu số],
   [Measures].[Sạch lưới]} ON COLUMNS,
  TOPCOUNT(
    FILTER(EXCEPT([HLV].[HLV].[HLV].MEMBERS, {[HLV].[HLV].&[-1]}), [Measures].[Số trận] >= 25),
    15,
    [Measures].[Điểm mỗi trận]
  ) ON ROWS
FROM [Hiệu suất đội bóng];
------------------------------------------------------------------------------------------------- */
