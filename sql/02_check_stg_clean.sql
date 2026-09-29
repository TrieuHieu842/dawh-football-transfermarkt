/* =====================================================================
   02_check_stg_clean.sql  (Người 3 - kiểm tra chất lượng Staging Clean)
   Chạy sau khi Container 02 nạp xong. Mỗi kiểm tra trả về PASS / FAIL / SKIP.
   Quy ước: dbo.etl_reject.source_table = tên bảng stg_raw nguồn (vd: stg_raw_players).
   ===================================================================== */
USE football_dwh_staging;
GO
SET NOCOUNT ON;

/* ---------- 1. Đối soát số dòng: clean + reject = raw ---------- */
;WITH m AS (
    SELECT 'players' AS clean_tbl, 'stg_raw_players' AS raw_tbl,
           (SELECT COUNT(*) FROM dbo.stg_raw_players) AS raw_cnt,
           (SELECT COUNT(*) FROM stg_clean.players)   AS clean_cnt
    UNION ALL
    SELECT 'clubs', 'stg_raw_clubs + stg_raw_national_teams',
           (SELECT COUNT(*) FROM dbo.stg_raw_clubs) + (SELECT COUNT(*) FROM dbo.stg_raw_national_teams),
           (SELECT COUNT(*) FROM stg_clean.clubs)
    UNION ALL
    SELECT 'competitions', 'stg_raw_competitions',
           (SELECT COUNT(*) FROM dbo.stg_raw_competitions), (SELECT COUNT(*) FROM stg_clean.competitions)
    UNION ALL
    SELECT 'games', 'stg_raw_games',
           (SELECT COUNT(*) FROM dbo.stg_raw_games), (SELECT COUNT(*) FROM stg_clean.games)
    UNION ALL
    SELECT 'club_games', 'stg_raw_club_games',
           (SELECT COUNT(*) FROM dbo.stg_raw_club_games), (SELECT COUNT(*) FROM stg_clean.club_games)
    UNION ALL
    SELECT 'appearances', 'stg_raw_appearances',
           (SELECT COUNT(*) FROM dbo.stg_raw_appearances), (SELECT COUNT(*) FROM stg_clean.appearances)
    UNION ALL
    SELECT 'player_valuations', 'stg_raw_player_valuations',
           (SELECT COUNT(*) FROM dbo.stg_raw_player_valuations), (SELECT COUNT(*) FROM stg_clean.player_valuations)
    UNION ALL
    SELECT 'transfers', 'stg_raw_transfers',
           (SELECT COUNT(*) FROM dbo.stg_raw_transfers), (SELECT COUNT(*) FROM stg_clean.transfers)
)
SELECT '1. So dong' AS kiem_tra,
       m.clean_tbl, m.raw_cnt, m.clean_cnt, r.reject_cnt,
       m.raw_cnt - m.clean_cnt - r.reject_cnt AS chenh_lech,
       CASE WHEN m.clean_cnt = 0 AND r.reject_cnt = 0 THEN 'SKIP (chua nap)'
            WHEN m.raw_cnt = m.clean_cnt + r.reject_cnt THEN 'PASS'
            ELSE 'FAIL' END AS ket_qua
FROM m
CROSS APPLY (SELECT COUNT(*) AS reject_cnt
             FROM dbo.etl_reject e
             WHERE e.source_table IN (SELECT LTRIM(value) FROM STRING_SPLIT(REPLACE(m.raw_tbl, '+', ','), ','))) r
ORDER BY m.clean_tbl;

/* ---------- 2..6. Kiểm tra nghiệp vụ ---------- */
DECLARE @cg INT = (SELECT COUNT(*) FROM stg_clean.club_games);
DECLARE @g  INT = (SELECT COUNT(*) FROM stg_clean.games);
DECLARE @ap INT = (SELECT COUNT(*) FROM stg_clean.appearances);
DECLARE @pv INT = (SELECT COUNT(*) FROM stg_clean.player_valuations);

DECLARE @r TABLE (kiem_tra NVARCHAR(100), so_dong_loi BIGINT, ket_qua NVARCHAR(20));

-- 2. Mỗi game_id trong club_games có đúng 2 dòng
INSERT @r
SELECT '2. club_games: moi game_id dung 2 dong', COUNT(*),
       CASE WHEN @cg = 0 THEN 'SKIP' WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT game_id FROM stg_clean.club_games GROUP BY game_id HAVING COUNT(*) <> 2) x;

-- 3. is_win + is_draw + is_loss = 1
INSERT @r
SELECT '3. club_games: is_win + is_draw + is_loss = 1', COUNT(*),
       CASE WHEN @cg = 0 THEN 'SKIP' WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM stg_clean.club_games
WHERE ISNULL(CAST(is_win AS INT), 0) + ISNULL(CAST(is_draw AS INT), 0) + ISNULL(CAST(is_loss AS INT), 0) <> 1;

-- 4. Tổng own_goals 2 dòng của 1 trận = home_club_goals + away_club_goals
INSERT @r
SELECT '4. club_games vs games: tong ban thang khop', COUNT(*),
       CASE WHEN @cg = 0 OR @g = 0 THEN 'SKIP' WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT game_id, SUM(own_goals) AS goals FROM stg_clean.club_games GROUP BY game_id) c
JOIN stg_clean.games g ON g.game_id = c.game_id
WHERE c.goals <> ISNULL(g.home_club_goals, 0) + ISNULL(g.away_club_goals, 0);

-- 5a. appearance_id duy nhất
INSERT @r
SELECT '5a. appearances: appearance_id duy nhat', COUNT(*),
       CASE WHEN @ap = 0 THEN 'SKIP' WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT appearance_id FROM stg_clean.appearances GROUP BY appearance_id HAVING COUNT(*) > 1) x;

-- 5b. (player_id, valuation_date) duy nhất
INSERT @r
SELECT '5b. player_valuations: (player_id, valuation_date) duy nhat', COUNT(*),
       CASE WHEN @pv = 0 THEN 'SKIP' WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT player_id, valuation_date FROM stg_clean.player_valuations
      GROUP BY player_id, valuation_date HAVING COUNT(*) > 1) x;

-- 6. (thêm) appearances: minutes_played trong 0-130, không có số âm
INSERT @r
SELECT '6. appearances: minutes 0-130, khong so am', COUNT(*),
       CASE WHEN @ap = 0 THEN 'SKIP' WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM stg_clean.appearances
WHERE minutes_played NOT BETWEEN 0 AND 130
   OR goals < 0 OR assists < 0 OR yellow_cards < 0 OR red_cards < 0;

-- 7. (thêm) club_games: mỗi trận có đúng 1 đội Home
INSERT @r
SELECT '7. club_games: moi tran 1 Home + 1 Away', COUNT(*),
       CASE WHEN @cg = 0 THEN 'SKIP' WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT game_id FROM stg_clean.club_games GROUP BY game_id HAVING SUM(CAST(is_home AS INT)) <> 1) x;

SELECT * FROM @r;

/* ---------- 8. Tóm tắt etl_reject ---------- */
SELECT '8. etl_reject' AS kiem_tra, source_table, reason, COUNT(*) AS so_dong
FROM dbo.etl_reject
GROUP BY source_table, reason
ORDER BY source_table, so_dong DESC;
GO
