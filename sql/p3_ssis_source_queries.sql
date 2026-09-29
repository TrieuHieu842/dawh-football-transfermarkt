/* =====================================================================
   p3_ssis_source_queries.sql  (Người 3)
   Các câu SQL dán vào SSIS package P3_Clean_ClubGames_Appearances.dtsx.
   Mỗi khối ghi rõ dán vào component nào.
   ===================================================================== */
USE football_dwh_staging;
GO

/* ---------------------------------------------------------------------
   [1] Execute SQL Task: SQL_Truncate_ClubGames
   --------------------------------------------------------------------- */
TRUNCATE TABLE stg_clean.club_games;
DELETE FROM dbo.etl_reject WHERE source_table = N'stg_raw_club_games';
GO

/* ---------------------------------------------------------------------
   [2] DFT_Clean_ClubGames -> OLE DB Source (SQL command)
   Giữ dạng chuỗi ngắn; ép kiểu số làm ở Data Conversion (lỗi -> etl_reject).
   hosting chỉ dùng để tính is_home, không ghi vào bảng đích.
   Khử trùng (game_id, club_id) bằng ROW_NUMBER, không dùng Sort.
   --------------------------------------------------------------------- */
SELECT game_id, club_id, own_goals, own_position, own_manager_name,
       opponent_id, opponent_goals, opponent_manager_name,
       hosting, batch_id, loaded_at
FROM (
    SELECT CAST(game_id               AS NVARCHAR(20))  AS game_id,
           CAST(club_id               AS NVARCHAR(20))  AS club_id,
           CAST(own_goals             AS NVARCHAR(10))  AS own_goals,
           CAST(own_position          AS NVARCHAR(10))  AS own_position,
           CAST(own_manager_name      AS NVARCHAR(200)) AS own_manager_name,
           CAST(opponent_id           AS NVARCHAR(20))  AS opponent_id,
           CAST(opponent_goals        AS NVARCHAR(10))  AS opponent_goals,
           CAST(opponent_manager_name AS NVARCHAR(200)) AS opponent_manager_name,
           CAST(hosting               AS NVARCHAR(10))  AS hosting,
           CAST(batch_id              AS NVARCHAR(30))  AS batch_id,
           loaded_at,
           ROW_NUMBER() OVER (PARTITION BY CAST(game_id AS NVARCHAR(20)), CAST(club_id AS NVARCHAR(20))
                              ORDER BY loaded_at DESC) AS rn
    FROM dbo.stg_raw_club_games
) x
WHERE rn = 1;
GO

/* ---------------------------------------------------------------------
   [3] Execute SQL Task: SQL_Truncate_Appearances
   --------------------------------------------------------------------- */
TRUNCATE TABLE stg_clean.appearances;
DELETE FROM dbo.etl_reject WHERE source_table = N'stg_raw_appearances';
GO

/* ---------------------------------------------------------------------
   [4] DFT_Clean_Appearances -> OLE DB Source (SQL command)
   1,9 triệu dòng: ép kiểu bằng TRY_CAST (SMALLINT khớp bảng đích) ngay trong SQL (nhanh hơn Data Conversion),
   giá trị không ép được -> NULL -> Conditional Split đẩy vào etl_reject.
   Khử trùng appearance_id bằng ROW_NUMBER, không dùng Sort.
   Bỏ player_name, player_current_club_id. date -> game_date.
   --------------------------------------------------------------------- */
SELECT appearance_id, game_id, player_id, player_club_id, game_date, competition_id,
       yellow_cards, red_cards, goals, assists, minutes_played, batch_id, loaded_at
FROM (
    SELECT CAST(appearance_id AS NVARCHAR(50))                               AS appearance_id,
           TRY_CAST(CAST(game_id        AS NVARCHAR(20)) AS INT)             AS game_id,
           TRY_CAST(CAST(player_id      AS NVARCHAR(20)) AS INT)             AS player_id,
           TRY_CAST(CAST(player_club_id AS NVARCHAR(20)) AS INT)             AS player_club_id,
           TRY_CAST(LEFT(CAST(date AS NVARCHAR(30)), 10) AS DATE)            AS game_date,
           CAST(NULLIF(LTRIM(RTRIM(CAST(competition_id AS NVARCHAR(20)))), N'') AS NVARCHAR(20)) AS competition_id,
           TRY_CAST(CAST(yellow_cards   AS NVARCHAR(10)) AS SMALLINT)        AS yellow_cards,
           TRY_CAST(CAST(red_cards      AS NVARCHAR(10)) AS SMALLINT)        AS red_cards,
           TRY_CAST(CAST(goals          AS NVARCHAR(10)) AS SMALLINT)        AS goals,
           TRY_CAST(CAST(assists        AS NVARCHAR(10)) AS SMALLINT)        AS assists,
           TRY_CAST(CAST(minutes_played AS NVARCHAR(10)) AS SMALLINT)        AS minutes_played,
           CAST(batch_id AS NVARCHAR(30))                                    AS batch_id,
           loaded_at,
           ROW_NUMBER() OVER (PARTITION BY CAST(appearance_id AS NVARCHAR(50))
                              ORDER BY loaded_at DESC)                       AS rn
    FROM dbo.stg_raw_appearances
) x
WHERE rn = 1;
GO
