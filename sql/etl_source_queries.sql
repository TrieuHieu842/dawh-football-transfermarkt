/* =====================================================================
   etl_source_queries.sql
   Cac cau SQL dung trong Main_ETL_Master.dtsx:
     Container 01 - Load Source to Stage : CSV -> stg_raw (chep tho)
     Container 02 - Load Dimensions      : moi dim 1 data flow  SRC -> (DC) -> LKP Dim -> DST / CMD
     Container 03 - Load Facts           : moi fact 1 data flow SRC -> CSPL -> DC -> LKP cac Dim -> LKP Fact -> DST
     Container 04 - Aggregate            : tinh lai bang tong hop theo mua
   Cau nguon (OLE DB Source) lam sach, ep kieu, khu trung, JOIN ngay trong SQL;
   Derived Column tinh nhom / co / measure / DateKey; Lookup lay surrogate key.
   Fact chi lay su kien trong cua so nap (football_dwh_dw.dbo.etl_load_window,
   duoc dat tu bien LoadFrom/LoadTo cua package) -> nap gia tang.
   ===================================================================== */
USE football_dwh_staging;
GO

/* ---------------------------------------------------------------------
   [D_COMP] DF - Load DimCompetition -> SRC - stg Competitions
   --------------------------------------------------------------------- */
SELECT competition_id, competition_name, competition_type, competition_sub_type,
       country_name, confederation, batch_id
FROM (
    SELECT CAST(NULLIF(LTRIM(RTRIM(CAST(c.competition_id AS NVARCHAR(20)))), N'') AS NVARCHAR(20)) AS competition_id,
           CAST(COALESCE(NULLIF(LTRIM(RTRIM(REPLACE(CAST(c.name AS NVARCHAR(200)), NCHAR(160), N' '))), N''), N'Không xác định') AS NVARCHAR(200)) AS competition_name,
           CAST(COALESCE(NULLIF(LTRIM(RTRIM(CAST(c.type AS NVARCHAR(50)))), N''), N'Không xác định') AS NVARCHAR(50))      AS competition_type,
           CAST(COALESCE(NULLIF(LTRIM(RTRIM(CAST(c.sub_type AS NVARCHAR(50)))), N''), N'Không xác định') AS NVARCHAR(50))  AS competition_sub_type,
           CAST(CASE WHEN TRY_CAST(CAST(c.country_id AS NVARCHAR(20)) AS INT) = -1
                       OR NULLIF(LTRIM(RTRIM(CAST(c.country_name AS NVARCHAR(100)))), N'') IS NULL
                     THEN COALESCE(co.country_name, N'International')
                     ELSE LTRIM(RTRIM(CAST(c.country_name AS NVARCHAR(100)))) END AS NVARCHAR(100))               AS country_name,
           CAST(CASE UPPER(LTRIM(RTRIM(CAST(c.confederation AS NVARCHAR(20)))))
                    WHEN N'EUROPA' THEN N'UEFA' WHEN N'UEFA' THEN N'UEFA'
                    WHEN N'ASIEN' THEN N'AFC'   WHEN N'AFC' THEN N'AFC'
                    WHEN N'AFRIKA' THEN N'CAF'  WHEN N'CAF' THEN N'CAF'
                    WHEN N'AMERIKA' THEN N'Americas' WHEN N'AMERICAS' THEN N'Americas'
                    WHEN N'FIFA' THEN N'FIFA'
                    ELSE N'Không xác định' END AS NVARCHAR(20))                                                    AS confederation,
           CAST(c.batch_id AS NVARCHAR(30))                                                                       AS batch_id,
           ROW_NUMBER() OVER (PARTITION BY CAST(c.competition_id AS NVARCHAR(20)) ORDER BY c.loaded_at DESC)      AS rn
    FROM dbo.stg_raw_competitions c
    LEFT JOIN (SELECT CAST(country_id AS NVARCHAR(20)) AS country_id,
                      MAX(NULLIF(LTRIM(RTRIM(CAST(country_name AS NVARCHAR(100)))), N'')) AS country_name
               FROM dbo.stg_raw_countries GROUP BY CAST(country_id AS NVARCHAR(20))) co
      ON co.country_id = CAST(c.country_id AS NVARCHAR(20))
) x
WHERE rn = 1 AND competition_id IS NOT NULL;
GO

/* ---------------------------------------------------------------------
   [D_CLUB] DF - Load DimClub -> SRC - stg Clubs
   CLB (clubs) + doi tuyen (national_teams) + CLB chi xuat hien trong fact
   (transfers, games, club_games, appearances, player_valuations) -> club_type = Other.
   --------------------------------------------------------------------- */
WITH comp AS (
    SELECT CAST(competition_id AS NVARCHAR(20)) AS competition_id,
           MAX(CAST(name AS NVARCHAR(200))) AS league_name,
           MAX(NULLIF(LTRIM(RTRIM(CAST(country_name AS NVARCHAR(100)))), N'')) AS country_name,
           MAX(CASE UPPER(LTRIM(RTRIM(CAST(confederation AS NVARCHAR(20)))))
                    WHEN N'EUROPA' THEN N'UEFA' WHEN N'ASIEN' THEN N'AFC' WHEN N'AFRIKA' THEN N'CAF'
                    WHEN N'AMERIKA' THEN N'Americas' WHEN N'FIFA' THEN N'FIFA' END) AS confederation
    FROM dbo.stg_raw_competitions GROUP BY CAST(competition_id AS NVARCHAR(20))
), cl AS (
    SELECT TRY_CAST(CAST(club_id AS NVARCHAR(20)) AS INT) AS club_id,
           NULLIF(LTRIM(RTRIM(REPLACE(CAST(name AS NVARCHAR(200)), NCHAR(160), N' '))), N'') AS club_name,
           NULLIF(LTRIM(RTRIM(CAST(domestic_competition_id AS NVARCHAR(20)))), N'') AS league_id,
           NULLIF(LTRIM(RTRIM(REPLACE(CAST(stadium_name AS NVARCHAR(200)), NCHAR(160), N' '))), N'') AS stadium_name,
           TRY_CAST(NULLIF(LTRIM(RTRIM(CAST(stadium_seats AS NVARCHAR(20)))), N'') AS INT) AS stadium_seats,
           CAST(batch_id AS NVARCHAR(30)) AS batch_id,
           ROW_NUMBER() OVER (PARTITION BY CAST(club_id AS NVARCHAR(20)) ORDER BY loaded_at DESC) AS rn
    FROM dbo.stg_raw_clubs
), nt AS (
    SELECT TRY_CAST(CAST(national_team_id AS NVARCHAR(20)) AS INT) AS club_id,
           NULLIF(LTRIM(RTRIM(REPLACE(CAST(name AS NVARCHAR(200)), NCHAR(160), N' '))), N'') AS club_name,
           NULLIF(LTRIM(RTRIM(CAST(country_name AS NVARCHAR(100)))), N'') AS country_name,
           CASE UPPER(LTRIM(RTRIM(CAST(confederation AS NVARCHAR(20)))))
                WHEN N'UEFA' THEN N'UEFA' WHEN N'AFC' THEN N'AFC' WHEN N'CAF' THEN N'CAF'
                WHEN N'CONCACAF' THEN N'Americas' WHEN N'CONMEBOL' THEN N'Americas'
                WHEN N'OFC' THEN N'OFC' WHEN N'FIFA' THEN N'FIFA' END AS confederation,
           CAST(batch_id AS NVARCHAR(30)) AS batch_id,
           ROW_NUMBER() OVER (PARTITION BY CAST(national_team_id AS NVARCHAR(20)) ORDER BY loaded_at DESC) AS rn
    FROM dbo.stg_raw_national_teams
), other_src AS (
    SELECT TRY_CAST(NULLIF(LTRIM(RTRIM(CAST(from_club_id AS NVARCHAR(20)))), N'') AS INT) AS club_id,
           NULLIF(LTRIM(RTRIM(REPLACE(CAST(from_club_name AS NVARCHAR(200)), NCHAR(160), N' '))), N'') AS club_name FROM dbo.stg_raw_transfers
    UNION ALL SELECT TRY_CAST(NULLIF(LTRIM(RTRIM(CAST(to_club_id AS NVARCHAR(20)))), N'') AS INT),
           NULLIF(LTRIM(RTRIM(REPLACE(CAST(to_club_name AS NVARCHAR(200)), NCHAR(160), N' '))), N'') FROM dbo.stg_raw_transfers
    UNION ALL SELECT TRY_CAST(CAST(home_club_id AS NVARCHAR(20)) AS INT), NULLIF(LTRIM(RTRIM(CAST(home_club_name AS NVARCHAR(200)))), N'') FROM dbo.stg_raw_games
    UNION ALL SELECT TRY_CAST(CAST(away_club_id AS NVARCHAR(20)) AS INT), NULLIF(LTRIM(RTRIM(CAST(away_club_name AS NVARCHAR(200)))), N'') FROM dbo.stg_raw_games
    UNION ALL SELECT TRY_CAST(NULLIF(LTRIM(RTRIM(CAST(current_club_id AS NVARCHAR(20)))), N'') AS INT),
           NULLIF(LTRIM(RTRIM(CAST(current_club_name AS NVARCHAR(200)))), N'') FROM dbo.stg_raw_player_valuations
    UNION ALL SELECT TRY_CAST(CAST(club_id AS NVARCHAR(20)) AS INT), NULL FROM dbo.stg_raw_club_games
    UNION ALL SELECT TRY_CAST(CAST(opponent_id AS NVARCHAR(20)) AS INT), NULL FROM dbo.stg_raw_club_games
    UNION ALL SELECT TRY_CAST(CAST(player_club_id AS NVARCHAR(20)) AS INT), NULL FROM dbo.stg_raw_appearances
), other AS (
    SELECT club_id, MAX(club_name) AS club_name
    FROM other_src
    WHERE club_id IS NOT NULL AND club_id <> -1
      AND club_id NOT IN (SELECT club_id FROM cl WHERE club_id IS NOT NULL)
      AND club_id NOT IN (SELECT club_id FROM nt WHERE club_id IS NOT NULL)
    GROUP BY club_id
)
SELECT CAST(club_id AS INT) AS club_id,
       CAST(club_name AS NVARCHAR(200)) AS club_name,
       CAST(club_type AS NVARCHAR(20)) AS club_type,
       CAST(country_name AS NVARCHAR(100)) AS country_name,
       CAST(confederation AS NVARCHAR(20)) AS confederation,
       CAST(current_league_id AS NVARCHAR(20)) AS current_league_id,
       CAST(current_league_name AS NVARCHAR(200)) AS current_league_name,
       CAST(stadium_name AS NVARCHAR(200)) AS stadium_name,
       CAST(stadium_seats AS INT) AS stadium_seats,
       CAST(batch_id AS NVARCHAR(30)) AS batch_id
FROM (
    SELECT cl.club_id, COALESCE(cl.club_name, N'CLB ' + CAST(cl.club_id AS NVARCHAR(20))) AS club_name, N'Club' AS club_type,
           COALESCE(comp.country_name, N'Không xác định') AS country_name, COALESCE(comp.confederation, N'Không xác định') AS confederation,
           cl.league_id AS current_league_id, COALESCE(comp.league_name, N'Không xác định') AS current_league_name,
           COALESCE(cl.stadium_name, N'Không xác định') AS stadium_name, cl.stadium_seats, cl.batch_id
    FROM cl LEFT JOIN comp ON comp.competition_id = cl.league_id
    WHERE cl.rn = 1 AND cl.club_id IS NOT NULL
    UNION ALL
    SELECT nt.club_id, COALESCE(nt.club_name, N'Đội tuyển ' + CAST(nt.club_id AS NVARCHAR(20))), N'National Team',
           COALESCE(nt.country_name, N'Không xác định'), COALESCE(nt.confederation, N'Không xác định'),
           NULL, N'Không áp dụng', N'Không xác định', NULL, nt.batch_id
    FROM nt WHERE nt.rn = 1 AND nt.club_id IS NOT NULL
    UNION ALL
    SELECT o.club_id, COALESCE(o.club_name, N'CLB ' + CAST(o.club_id AS NVARCHAR(20))), N'Other',
           N'Không xác định', N'Không xác định', NULL, N'Không xác định', N'Không xác định', NULL, NULL
    FROM other o
) u;
GO

/* ---------------------------------------------------------------------
   [D_PLAYER] DF - Load DimPlayer -> SRC - stg Players
   Cau thu trong players + cau thu chi xuat hien trong fact (appearances, transfers, valuations).
   --------------------------------------------------------------------- */
WITH p AS (
    SELECT TRY_CAST(CAST(player_id AS NVARCHAR(20)) AS INT) AS player_id,
           NULLIF(LTRIM(RTRIM(REPLACE(CAST(name AS NVARCHAR(200)), NCHAR(160), N' '))), N'') AS full_name,
           TRY_CAST(NULLIF(LEFT(LTRIM(CAST(date_of_birth AS NVARCHAR(30))), 10), N'') AS DATE) AS date_of_birth,
           NULLIF(LTRIM(RTRIM(REPLACE(CAST(country_of_birth AS NVARCHAR(100)), NCHAR(160), N' '))), N'') AS country_of_birth,
           NULLIF(LTRIM(RTRIM(REPLACE(CAST(country_of_citizenship AS NVARCHAR(100)), NCHAR(160), N' '))), N'') AS citizenship,
           NULLIF(LTRIM(RTRIM(CAST(position AS NVARCHAR(50)))), N'') AS position,
           NULLIF(LTRIM(RTRIM(CAST(sub_position AS NVARCHAR(50)))), N'') AS sub_position,
           NULLIF(LTRIM(RTRIM(CAST(foot AS NVARCHAR(20)))), N'') AS foot,
           TRY_CAST(NULLIF(LTRIM(RTRIM(CAST(height_in_cm AS NVARCHAR(10)))), N'') AS SMALLINT) AS height_in_cm,
           NULLIF(LTRIM(RTRIM(REPLACE(CAST(agent_name AS NVARCHAR(200)), NCHAR(160), N' '))), N'') AS agent_name,
           TRY_CAST(NULLIF(LEFT(LTRIM(CAST(contract_expiration_date AS NVARCHAR(30))), 10), N'') AS DATE) AS contract_expiration_date,
           TRY_CAST(NULLIF(LTRIM(RTRIM(CAST(international_caps AS NVARCHAR(10)))), N'') AS INT) AS international_caps,
           CAST(batch_id AS NVARCHAR(30)) AS batch_id,
           ROW_NUMBER() OVER (PARTITION BY CAST(player_id AS NVARCHAR(20)) ORDER BY loaded_at DESC) AS rn
    FROM dbo.stg_raw_players
), other_src AS (
    SELECT TRY_CAST(CAST(player_id AS NVARCHAR(20)) AS INT) AS player_id, NULLIF(LTRIM(RTRIM(CAST(player_name AS NVARCHAR(200)))), N'') AS full_name FROM dbo.stg_raw_appearances
    UNION ALL SELECT TRY_CAST(CAST(player_id AS NVARCHAR(20)) AS INT), NULLIF(LTRIM(RTRIM(CAST(player_name AS NVARCHAR(200)))), N'') FROM dbo.stg_raw_transfers
    UNION ALL SELECT TRY_CAST(CAST(player_id AS NVARCHAR(20)) AS INT), NULL FROM dbo.stg_raw_player_valuations
), other AS (
    SELECT player_id, MAX(full_name) AS full_name FROM other_src
    WHERE player_id IS NOT NULL AND player_id NOT IN (SELECT player_id FROM p WHERE player_id IS NOT NULL)
    GROUP BY player_id
)
SELECT CAST(player_id AS INT) AS player_id,
       CAST(COALESCE(full_name, N'Cầu thủ ' + CAST(player_id AS NVARCHAR(20))) AS NVARCHAR(200)) AS full_name,
       date_of_birth,
       CAST(COALESCE(country_of_birth, N'Không xác định') AS NVARCHAR(100)) AS country_of_birth,
       CAST(COALESCE(citizenship, N'Không xác định') AS NVARCHAR(100))      AS citizenship,
       CAST(COALESCE(position, N'Không xác định') AS NVARCHAR(50))          AS position,
       CAST(COALESCE(sub_position, N'Không xác định') AS NVARCHAR(50))      AS sub_position,
       CAST(COALESCE(foot, N'Không xác định') AS NVARCHAR(20))              AS foot,
       CAST(height_in_cm AS SMALLINT)                                      AS height_in_cm,
       CAST(COALESCE(agent_name, N'Không xác định') AS NVARCHAR(200))       AS agent_name,
       CAST(YEAR(contract_expiration_date) AS SMALLINT)                    AS contract_expiry_year,
       CAST(international_caps AS INT)                                     AS international_caps,
       CAST(batch_id AS NVARCHAR(30))                                      AS batch_id
FROM (
    SELECT player_id, full_name, date_of_birth, country_of_birth, citizenship, position, sub_position, foot,
           height_in_cm, agent_name, contract_expiration_date, international_caps, batch_id
    FROM p WHERE rn = 1 AND player_id IS NOT NULL
    UNION ALL
    SELECT player_id, full_name, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL FROM other
) u;
GO

/* ---------------------------------------------------------------------
   [D_MATCH] DF - Load DimMatch -> SRC - stg Games
   --------------------------------------------------------------------- */
SELECT game_id, [round], stadium, referee, home_formation, away_formation, attendance, batch_id
FROM (
    SELECT TRY_CAST(CAST(game_id AS NVARCHAR(20)) AS INT) AS game_id,
           CAST(COALESCE(NULLIF(LTRIM(RTRIM(CAST([round] AS NVARCHAR(100)))), N''), N'Không xác định') AS NVARCHAR(100)) AS [round],
           CAST(COALESCE(NULLIF(LTRIM(RTRIM(REPLACE(CAST(stadium AS NVARCHAR(200)), NCHAR(160), N' '))), N''), N'Không xác định') AS NVARCHAR(200)) AS stadium,
           CAST(COALESCE(NULLIF(LTRIM(RTRIM(REPLACE(CAST(referee AS NVARCHAR(200)), NCHAR(160), N' '))), N''), N'Không xác định') AS NVARCHAR(200)) AS referee,
           CAST(COALESCE(NULLIF(LTRIM(RTRIM(CAST(home_club_formation AS NVARCHAR(30)))), N''), N'Không xác định') AS NVARCHAR(30)) AS home_formation,
           CAST(COALESCE(NULLIF(LTRIM(RTRIM(CAST(away_club_formation AS NVARCHAR(30)))), N''), N'Không xác định') AS NVARCHAR(30)) AS away_formation,
           TRY_CAST(NULLIF(LTRIM(RTRIM(CAST(attendance AS NVARCHAR(20)))), N'') AS INT) AS attendance,
           CAST(batch_id AS NVARCHAR(30)) AS batch_id,
           ROW_NUMBER() OVER (PARTITION BY CAST(game_id AS NVARCHAR(20)) ORDER BY loaded_at DESC) AS rn
    FROM dbo.stg_raw_games
) x
WHERE rn = 1 AND game_id IS NOT NULL;
GO

/* ---------------------------------------------------------------------
   [D_MANAGER] DF - Load DimManager -> SRC - stg Managers (ten HLV hai doi trong club_games)
   --------------------------------------------------------------------- */
SELECT CAST(manager_name AS NVARCHAR(200)) AS manager_name, MAX(batch_id) AS batch_id
FROM (
    SELECT NULLIF(LTRIM(RTRIM(REPLACE(CAST(own_manager_name AS NVARCHAR(200)), NCHAR(160), N' '))), N'') AS manager_name,
           CAST(batch_id AS NVARCHAR(30)) AS batch_id
    FROM dbo.stg_raw_club_games
    UNION ALL
    SELECT NULLIF(LTRIM(RTRIM(REPLACE(CAST(opponent_manager_name AS NVARCHAR(200)), NCHAR(160), N' '))), N''),
           CAST(batch_id AS NVARCHAR(30))
    FROM dbo.stg_raw_club_games
) m
WHERE manager_name IS NOT NULL
GROUP BY manager_name;
GO

/* ---------------------------------------------------------------------
   [F_TEAM] DF - Load FactTeamMatch -> SRC - stg Club Games
   club_games JOIN games (ngay, mua, giai), trong cua so nap.
   reject_reason khac NULL -> CSPL dua sang etl_reject.
   --------------------------------------------------------------------- */
SELECT cg.game_id, cg.club_id, cg.opponent_id, g.game_date, g.season_start_year, g.competition_id,
       cg.own_manager_name, cg.opponent_manager_name, cg.hosting,
       cg.own_goals, cg.opponent_goals, cg.own_position, cg.batch_id,
       CAST(N'stg_raw_club_games' AS NVARCHAR(100)) AS source_table,
       CAST(CAST(cg.game_id AS NVARCHAR(20)) + N'|' + CAST(cg.club_id AS NVARCHAR(20)) AS NVARCHAR(200)) AS natural_key,
       CAST(CASE WHEN cg.game_id IS NULL OR cg.club_id IS NULL THEN N'Thiếu game_id/club_id'
                 WHEN cg.own_goals IS NULL OR cg.opponent_goals IS NULL THEN N'Thiếu tỉ số' END AS NVARCHAR(200)) AS reject_reason
FROM (
    SELECT TRY_CAST(CAST(game_id AS NVARCHAR(20)) AS INT) AS game_id,
           TRY_CAST(CAST(club_id AS NVARCHAR(20)) AS INT) AS club_id,
           TRY_CAST(CAST(opponent_id AS NVARCHAR(20)) AS INT) AS opponent_id,
           CAST(COALESCE(NULLIF(LTRIM(RTRIM(REPLACE(CAST(own_manager_name AS NVARCHAR(200)), NCHAR(160), N' '))), N''), N'Không xác định') AS NVARCHAR(200)) AS own_manager_name,
           CAST(COALESCE(NULLIF(LTRIM(RTRIM(REPLACE(CAST(opponent_manager_name AS NVARCHAR(200)), NCHAR(160), N' '))), N''), N'Không xác định') AS NVARCHAR(200)) AS opponent_manager_name,
           CAST(LTRIM(RTRIM(CAST(hosting AS NVARCHAR(10)))) AS NVARCHAR(10)) AS hosting,
           TRY_CAST(NULLIF(LTRIM(RTRIM(CAST(own_goals AS NVARCHAR(10)))), N'') AS SMALLINT) AS own_goals,
           TRY_CAST(NULLIF(LTRIM(RTRIM(CAST(opponent_goals AS NVARCHAR(10)))), N'') AS SMALLINT) AS opponent_goals,
           CAST(NULLIF(TRY_CAST(NULLIF(LTRIM(RTRIM(CAST(own_position AS NVARCHAR(10)))), N'') AS SMALLINT), -1) AS SMALLINT) AS own_position,
           CAST(batch_id AS NVARCHAR(30)) AS batch_id,
           ROW_NUMBER() OVER (PARTITION BY CAST(game_id AS NVARCHAR(20)), CAST(club_id AS NVARCHAR(20)) ORDER BY loaded_at DESC) AS rn
    FROM dbo.stg_raw_club_games
) cg
JOIN (
    SELECT TRY_CAST(CAST(game_id AS NVARCHAR(20)) AS INT) AS game_id,
           TRY_CAST(LEFT(CAST([date] AS NVARCHAR(30)), 10) AS DATE) AS game_date,
           TRY_CAST(CAST(season AS NVARCHAR(10)) AS SMALLINT) AS season_start_year,
           CAST(NULLIF(LTRIM(RTRIM(CAST(competition_id AS NVARCHAR(20)))), N'') AS NVARCHAR(20)) AS competition_id,
           ROW_NUMBER() OVER (PARTITION BY CAST(game_id AS NVARCHAR(20)) ORDER BY loaded_at DESC) AS rn
    FROM dbo.stg_raw_games
) g ON g.game_id = cg.game_id AND g.rn = 1
CROSS JOIN football_dwh_dw.dbo.etl_load_window w
WHERE cg.rn = 1 AND g.game_date BETWEEN w.window_from AND w.window_to;
GO

/* ---------------------------------------------------------------------
   [F_APP] DF - Load FactPlayerAppearance -> SRC - stg Appearances
   Khu trung appearance_id; mua lay tu games; trong cua so nap.
   --------------------------------------------------------------------- */
SELECT a.appearance_id, a.game_id, a.player_id, a.player_club_id, a.game_date, g.season_start_year, a.competition_id,
       a.minutes_played, a.goals, a.assists, a.yellow_cards, a.red_cards, a.batch_id,
       CAST(N'stg_raw_appearances' AS NVARCHAR(100)) AS source_table,
       CAST(a.appearance_id AS NVARCHAR(200)) AS natural_key,
       CAST(CASE WHEN a.game_id IS NULL OR a.player_id IS NULL THEN N'Thiếu game_id/player_id'
                 WHEN a.minutes_played IS NULL OR a.minutes_played NOT BETWEEN 0 AND 130 THEN N'minutes_played ngoài 0-130'
                 WHEN a.goals IS NULL OR a.assists IS NULL OR a.yellow_cards IS NULL OR a.red_cards IS NULL
                   OR a.goals < 0 OR a.assists < 0 OR a.yellow_cards < 0 OR a.red_cards < 0 THEN N'Số bàn, kiến tạo, thẻ thiếu hoặc âm' END AS NVARCHAR(200)) AS reject_reason
FROM (
    SELECT CAST(appearance_id AS NVARCHAR(50)) AS appearance_id,
           TRY_CAST(CAST(game_id AS NVARCHAR(20)) AS INT) AS game_id,
           TRY_CAST(CAST(player_id AS NVARCHAR(20)) AS INT) AS player_id,
           TRY_CAST(CAST(player_club_id AS NVARCHAR(20)) AS INT) AS player_club_id,
           TRY_CAST(LEFT(CAST([date] AS NVARCHAR(30)), 10) AS DATE) AS game_date,
           CAST(NULLIF(LTRIM(RTRIM(CAST(competition_id AS NVARCHAR(20)))), N'') AS NVARCHAR(20)) AS competition_id,
           TRY_CAST(CAST(minutes_played AS NVARCHAR(10)) AS SMALLINT) AS minutes_played,
           TRY_CAST(CAST(goals AS NVARCHAR(10)) AS SMALLINT) AS goals,
           TRY_CAST(CAST(assists AS NVARCHAR(10)) AS SMALLINT) AS assists,
           TRY_CAST(CAST(yellow_cards AS NVARCHAR(10)) AS SMALLINT) AS yellow_cards,
           TRY_CAST(CAST(red_cards AS NVARCHAR(10)) AS SMALLINT) AS red_cards,
           CAST(batch_id AS NVARCHAR(30)) AS batch_id,
           ROW_NUMBER() OVER (PARTITION BY CAST(appearance_id AS NVARCHAR(50)) ORDER BY loaded_at DESC) AS rn
    FROM dbo.stg_raw_appearances
) a
LEFT JOIN (
    SELECT CAST(game_id AS NVARCHAR(20)) AS game_id_s, MAX(TRY_CAST(CAST(season AS NVARCHAR(10)) AS SMALLINT)) AS season_start_year
    FROM dbo.stg_raw_games GROUP BY CAST(game_id AS NVARCHAR(20))
) g ON g.game_id_s = CAST(a.game_id AS NVARCHAR(20))
CROSS JOIN football_dwh_dw.dbo.etl_load_window w
WHERE a.rn = 1 AND a.game_date BETWEEN w.window_from AND w.window_to;
GO

/* ---------------------------------------------------------------------
   [F_VAL] DF - Load FactPlayerValuation -> SRC - stg Player Valuations
   Khu trung, tinh LAG tren toan bo lich su roi moi loc cua so nap.
   --------------------------------------------------------------------- */
WITH src AS (
    SELECT TRY_CAST(CAST(player_id AS NVARCHAR(20)) AS INT) AS player_id,
           TRY_CAST(LEFT(CAST([date] AS NVARCHAR(30)), 10) AS DATE) AS valuation_date,
           TRY_CAST(TRY_CAST(NULLIF(LTRIM(RTRIM(CAST(market_value_in_eur AS NVARCHAR(50)))), N'') AS DECIMAL(19,3)) AS BIGINT) AS market_value_eur,
           TRY_CAST(NULLIF(LTRIM(RTRIM(CAST(current_club_id AS NVARCHAR(20)))), N'') AS INT) AS current_club_id,
           CAST(NULLIF(LTRIM(RTRIM(CAST(player_club_domestic_competition_id AS NVARCHAR(20)))), N'') AS NVARCHAR(20)) AS competition_id,
           CAST(batch_id AS NVARCHAR(30)) AS batch_id,
           loaded_at
    FROM dbo.stg_raw_player_valuations
), dedup AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY player_id, valuation_date ORDER BY loaded_at DESC) AS rn FROM src
), calc AS (
    SELECT player_id, valuation_date, market_value_eur, current_club_id, competition_id, batch_id,
           market_value_eur - LAG(market_value_eur) OVER (PARTITION BY player_id ORDER BY valuation_date) AS value_change_eur
    FROM dedup WHERE rn = 1
)
SELECT c.player_id, c.valuation_date, c.market_value_eur, c.value_change_eur, c.current_club_id, c.competition_id, c.batch_id,
       CAST(N'stg_raw_player_valuations' AS NVARCHAR(100)) AS source_table,
       CAST(CAST(c.player_id AS NVARCHAR(20)) + N'|' + CONVERT(NVARCHAR(10), c.valuation_date, 23) AS NVARCHAR(200)) AS natural_key,
       CAST(CASE WHEN c.player_id IS NULL THEN N'Thiếu player_id'
                 WHEN c.market_value_eur < 0 THEN N'Giá trị thị trường âm' END AS NVARCHAR(200)) AS reject_reason
FROM calc c CROSS JOIN football_dwh_dw.dbo.etl_load_window w
WHERE c.valuation_date BETWEEN w.window_from AND w.window_to;
GO

/* ---------------------------------------------------------------------
   [F_TRANSFER] DF - Load FactTransfer -> SRC - stg Transfers
   Tien dang '700000.000' -> ep qua DECIMAL roi BIGINT. Phi trong -> NULL (khong cong bo).
   --------------------------------------------------------------------- */
SELECT t.player_id, t.transfer_date, t.season_short, t.from_club_id, t.to_club_id, t.transfer_fee_eur, t.market_value_eur, t.batch_id,
       CAST(N'stg_raw_transfers' AS NVARCHAR(100)) AS source_table,
       CAST(CAST(t.player_id AS NVARCHAR(20)) + N'|' + CONVERT(NVARCHAR(10), t.transfer_date, 23) AS NVARCHAR(200)) AS natural_key,
       CAST(CASE WHEN t.player_id IS NULL THEN N'Thiếu player_id'
                 WHEN t.transfer_fee_eur < 0 OR t.market_value_eur < 0 THEN N'Số tiền âm' END AS NVARCHAR(200)) AS reject_reason
FROM (
    SELECT TRY_CAST(CAST(player_id AS NVARCHAR(20)) AS INT) AS player_id,
           TRY_CAST(LEFT(CAST(transfer_date AS NVARCHAR(30)), 10) AS DATE) AS transfer_date,
           CAST(NULLIF(LTRIM(RTRIM(CAST(transfer_season AS NVARCHAR(10)))), N'') AS NVARCHAR(10)) AS season_short,
           TRY_CAST(NULLIF(LTRIM(RTRIM(CAST(from_club_id AS NVARCHAR(20)))), N'') AS INT) AS from_club_id,
           TRY_CAST(NULLIF(LTRIM(RTRIM(CAST(to_club_id AS NVARCHAR(20)))), N'') AS INT) AS to_club_id,
           TRY_CAST(TRY_CAST(NULLIF(LTRIM(RTRIM(CAST(transfer_fee AS NVARCHAR(50)))), N'') AS DECIMAL(19,3)) AS BIGINT) AS transfer_fee_eur,
           TRY_CAST(TRY_CAST(NULLIF(LTRIM(RTRIM(CAST(market_value_in_eur AS NVARCHAR(50)))), N'') AS DECIMAL(19,3)) AS BIGINT) AS market_value_eur,
           CAST(batch_id AS NVARCHAR(30)) AS batch_id,
           ROW_NUMBER() OVER (PARTITION BY CAST(player_id AS NVARCHAR(20)), CAST(transfer_date AS NVARCHAR(30)),
                                           CAST(from_club_id AS NVARCHAR(20)), CAST(to_club_id AS NVARCHAR(20))
                              ORDER BY loaded_at DESC) AS rn
    FROM dbo.stg_raw_transfers
) t
CROSS JOIN football_dwh_dw.dbo.etl_load_window w
WHERE t.rn = 1 AND t.transfer_date BETWEEN w.window_from AND w.window_to;
GO

/* =====================================================================
   Execute SQL Task (ket noi DW)
   ===================================================================== */
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
