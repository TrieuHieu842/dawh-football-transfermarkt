/* =====================================================================
   etl_source_queries.sql
   Main_ETL_Master.dtsx xu ly ETL chu yeu bang component SSIS:
     OLE DB Source chi SELECT CAST(cot AS NVARCHAR(n)) cac cot da chon tu stg_raw
     (bat buoc vi NVARCHAR(MAX) duoc SSIS doc thanh DT_NTEXT, khong dung duoc ham chuoi);
     lam sach, ep kieu, khu trung, chuan hoa, kiem tra, cua so nap, Lookup ... deu la component SSIS.
   File nay chi giu cac cau SQL con lai:
     [S_VAL]   nguon FactPlayerValuation: value_change_eur can LAG (SSIS khong co LAG)
     [PREPARE] Execute SQL dau Container 03
     [AGG]     Execute SQL Container 04
   ===================================================================== */
USE football_dwh_staging;
GO

/* ---------------------------------------------------------------------
   [S_VAL] DF - Load FactPlayerValuation -> SRC - stg Player Valuations
   Ngoai le duy nhat dung SQL: tinh value_change_eur bang LAG theo player_id, sap theo ngay.
   Cac cot khac van tra ve dang chuoi de SSIS lam sach / ep kieu.
   --------------------------------------------------------------------- */
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
GO

USE football_dwh_dw;
GO

/* ---------------------------------------------------------------------
   [PREPARE] Container 03 -> SQL - Set Load Window (phan sau lenh UPDATE etl_load_window
   duoc package sinh tu bien LoadFrom/LoadTo): xoa reject cu cua fact, cap nhat is_future_date.
   --------------------------------------------------------------------- */
DELETE FROM football_dwh_staging.dbo.etl_reject
WHERE source_table IN (N'stg_raw_club_games', N'stg_raw_appearances', N'stg_raw_player_valuations', N'stg_raw_transfers');
UPDATE dbo.dim_date SET is_future_date = CASE WHEN full_date > CAST(GETDATE() AS DATE) THEN 1 ELSE 0 END WHERE date_key <> -1;
GO

/* ---------------------------------------------------------------------
   [AGG] Container 04 -> SQL - Rebuild Season Summary:
   xoa va tinh lai bang tong hop cho cac mua co su kien trong cua so nap
   --------------------------------------------------------------------- */
DECLARE @seasons TABLE (season_key INT PRIMARY KEY);
INSERT @seasons
SELECT DISTINCT f.season_key
FROM dbo.fact_team_match f
JOIN dbo.dim_date d ON d.date_key = f.date_key
CROSS JOIN dbo.etl_load_window w
WHERE d.full_date BETWEEN w.window_from AND w.window_to;

DELETE s FROM dbo.fact_club_season_summary s WHERE s.season_key IN (SELECT season_key FROM @seasons);
INSERT dbo.fact_club_season_summary (club_key, competition_key, season_key, matches_played, wins, draws, losses,
                                     goals_for, goals_against, clean_sheets, points, batch_id)
SELECT f.club_key, f.competition_key, f.season_key, COUNT(*), SUM(f.is_win), SUM(f.is_draw), SUM(f.is_loss),
       SUM(f.goals_for), SUM(f.goals_against), SUM(f.is_clean_sheet), 3 * SUM(f.is_win) + SUM(f.is_draw), MAX(f.batch_id)
FROM dbo.fact_team_match f
WHERE f.season_key IN (SELECT season_key FROM @seasons)
GROUP BY f.club_key, f.competition_key, f.season_key;

DELETE s FROM dbo.fact_player_season_summary s WHERE s.season_key IN (SELECT season_key FROM @seasons);
INSERT dbo.fact_player_season_summary (player_key, club_key, competition_key, season_key, matches_played, minutes_played,
                                       goals, assists, yellow_cards, red_cards, batch_id)
SELECT f.player_key, f.club_key, f.competition_key, f.season_key, SUM(f.appearance_count), SUM(f.minutes_played),
       SUM(f.goals), SUM(f.assists), SUM(f.yellow_cards), SUM(f.red_cards), MAX(f.batch_id)
FROM dbo.fact_player_appearance f
WHERE f.season_key IN (SELECT season_key FROM @seasons)
GROUP BY f.player_key, f.club_key, f.competition_key, f.season_key;
GO
