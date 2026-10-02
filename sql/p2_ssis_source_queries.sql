/* =====================================================================
   p2_ssis_source_queries.sql  (Nguoi 2)
   Cac cau SQL dan vao SSIS package P2_Clean_Competitions_Games.dtsx.
   Moi khoi ghi ro dan vao component nao.
   ===================================================================== */
USE football_dwh_staging;
GO

/* ---------------------------------------------------------------------
   [1] Execute SQL Task: SQL_Truncate_Competitions
   --------------------------------------------------------------------- */
TRUNCATE TABLE stg_clean.competitions;
DELETE FROM dbo.etl_reject WHERE source_table IN (N'stg_raw_competitions', N'stg_raw_countries');
GO


/* ---------------------------------------------------------------------
   [2] DFT_Clean_Competitions -> OLE DB Source (SQL command)
   LEFT JOIN countries de lay country_name.
   Chuan hoa confederation: tieng Duc -> tieng Anh. Khu trung theo competition_id.
   country_id = -1 hoac country_name rong -> 'International'.
   --------------------------------------------------------------------- */
/* Khu trung: giu 1 dong moi khoa (competition_id), uu tien dong nap sau cung */
SELECT [competition_id], [competition_name], [competition_type], [competition_sub_type], [country_name], [confederation], [batch_id], [loaded_at]
FROM (
    SELECT q.*, ROW_NUMBER() OVER (PARTITION BY q.competition_id ORDER BY q.loaded_at DESC) AS rn
    FROM (
SELECT 
    competition_id, competition_name, competition_type, competition_sub_type, 
    country_name, confederation, batch_id, loaded_at 
FROM ( 
    SELECT 
        CAST(NULLIF(LTRIM(RTRIM(CAST(c.competition_id AS NVARCHAR(20)))), N'') AS NVARCHAR(20)) AS competition_id, 
        CAST(NULLIF(LTRIM(RTRIM(CAST(c.name AS NVARCHAR(200)))),N'') AS NVARCHAR(200)) AS competition_name, 
        CAST(NULLIF(LTRIM(RTRIM(CAST(c.type AS NVARCHAR(50)))), N'') AS NVARCHAR(50)) AS competition_type, 
        CAST(NULLIF(LTRIM(RTRIM(CAST(c.sub_type AS NVARCHAR(50)))), N'') AS NVARCHAR(50)) AS competition_sub_type, 
        CASE 
            WHEN TRY_CAST(CAST(c.country_id AS NVARCHAR(20)) AS INT) = -1 
              OR NULLIF(LTRIM(RTRIM(CAST(c.country_name AS NVARCHAR(100)))), N'') IS NULL 
            THEN COALESCE(
                NULLIF(LTRIM(RTRIM(CAST(co.country_name AS NVARCHAR(100)))), N''), 
                N'International'
            ) 
            ELSE LTRIM(RTRIM(CAST(c.country_name AS NVARCHAR(100)))) 
        END AS country_name, 
        CASE UPPER(LTRIM(RTRIM(CAST(c.confederation AS NVARCHAR(20))))) 
            WHEN N'EUROPA'   THEN N'UEFA' 
            WHEN N'UEFA'     THEN N'UEFA' 
            WHEN N'ASIEN'    THEN N'AFC' 
            WHEN N'AFC'      THEN N'AFC' 
            WHEN N'AFRIKA'   THEN N'CAF' 
            WHEN N'CAF'      THEN N'CAF' 
            WHEN N'AMERIKA'  THEN N'Americas' 
            WHEN N'AMERICAS' THEN N'Americas' 
            WHEN N'FIFA'     THEN N'FIFA' 
            ELSE N'Không xác định' 
        END AS confederation, 
        CAST(c.batch_id AS NVARCHAR(30)) AS batch_id, 
        c.loaded_at 
    FROM dbo.stg_raw_competitions c 
    LEFT JOIN dbo.stg_raw_countries co 
        ON CAST(c.country_id AS NVARCHAR(20)) = CAST(co.country_id AS NVARCHAR(20)) 
) x
    ) q
) d
WHERE d.rn = 1 OR d.competition_id IS NULL;

GO

/* ---------------------------------------------------------------------
   [3] Execute SQL Task: SQL_Truncate_Games
   --------------------------------------------------------------------- */
TRUNCATE TABLE stg_clean.games;
DELETE FROM dbo.etl_reject WHERE source_table = N'stg_raw_games';
GO


/* ---------------------------------------------------------------------
   [4] DFT_Clean_Games -> OLE DB Source (SQL command)
   Tinh season_start_year, season_label (2009/10), season_short (09/10).
   Tinh round_type (4 nhom: Matchday/Group stage/Final/Knockout).
   Tinh attendance_band (muc 5.4).
   date -> game_date (DATE). Giu home/away club id & goals de doi chieu DQ.
   Bo ten CLB, aggregate, url.
   --------------------------------------------------------------------- */
/* Khu trung: giu 1 dong moi khoa (game_id), uu tien dong nap sau cung */
SELECT [game_id], [competition_id], [season_start_year], [season_label], [season_short], [game_date], [round], [round_type], [stadium], [referee], [home_formation], [away_formation], [attendance_band], [home_club_id], [away_club_id], [home_club_goals], [away_club_goals], [batch_id], [loaded_at]
FROM (
    SELECT q.*, ROW_NUMBER() OVER (PARTITION BY q.game_id ORDER BY q.loaded_at DESC) AS rn
    FROM (
SELECT 
    game_id, competition_id, 
    season_start_year, season_label, season_short, 
    game_date, round, round_type, 
    stadium, referee, home_formation, away_formation, 
    attendance_band, 
    home_club_id, away_club_id, home_club_goals, away_club_goals, 
    batch_id, loaded_at 
FROM ( 
    SELECT 
        TRY_CAST(CAST(game_id AS NVARCHAR(20)) AS INT) AS game_id, 
        CAST(NULLIF(LTRIM(RTRIM(CAST(competition_id AS NVARCHAR(20)))), N'') AS NVARCHAR(20)) AS competition_id, 

        TRY_CAST(CAST(season AS NVARCHAR(10)) AS SMALLINT) AS season_start_year, 

        CASE 
            WHEN TRY_CAST(CAST(season AS NVARCHAR(10)) AS INT) IS NOT NULL 
            THEN CAST(TRY_CAST(CAST(season AS NVARCHAR(10)) AS INT) AS NVARCHAR(4)) 
                 + N'/' 
                 + RIGHT(
                     N'00' + CAST(
                         (TRY_CAST(CAST(season AS NVARCHAR(10)) AS INT) + 1) % 100 
                         AS NVARCHAR(2)
                     ), 
                     2
                 ) 
            ELSE NULL 
        END AS season_label, 

        CASE 
            WHEN TRY_CAST(CAST(season AS NVARCHAR(10)) AS INT) IS NOT NULL 
            THEN RIGHT(
                     N'00' + CAST(
                         TRY_CAST(CAST(season AS NVARCHAR(10)) AS INT) % 100 
                         AS NVARCHAR(2)
                 ), 
                 2
             )
             + N'/'
             + RIGHT(
                 N'00' + CAST(
                     (TRY_CAST(CAST(season AS NVARCHAR(10)) AS INT) + 1) % 100 
                     AS NVARCHAR(2)
                 ), 
                 2
             ) 
            ELSE NULL 
        END AS season_short, 

        TRY_CAST(LEFT(CAST(date AS NVARCHAR(30)), 10) AS DATE) AS game_date, 

        CAST(NULLIF(
            LTRIM(RTRIM(CAST(round AS NVARCHAR(100)))), 
            N''
        ) AS NVARCHAR(100)) AS round, 

        CASE 
            WHEN CHARINDEX(N'Matchday', CAST(round AS NVARCHAR(100))) > 0 
                THEN N'Matchday'
            WHEN CHARINDEX(N'Group', CAST(round AS NVARCHAR(100))) > 0 
                THEN N'Group stage'
            WHEN LTRIM(RTRIM(CAST(round AS NVARCHAR(100)))) = N'Final' 
                THEN N'Final'
            ELSE N'Knockout'
        END AS round_type, 

        CAST(NULLIF(LTRIM(RTRIM(
            CAST(stadium AS NVARCHAR(200))
        )), N'') AS NVARCHAR(200)) AS stadium, 

        CAST(NULLIF(LTRIM(RTRIM(
            CAST(referee AS NVARCHAR(200))
        )), N'') AS NVARCHAR(200)) AS referee, 

        CAST(NULLIF(LTRIM(RTRIM(
            CAST(home_club_formation AS NVARCHAR(30))
        )), N'') AS NVARCHAR(30)) AS home_formation, 

        CAST(NULLIF(LTRIM(RTRIM(
            CAST(away_club_formation AS NVARCHAR(30))
        )), N'') AS NVARCHAR(30)) AS away_formation, 

        CASE 
            WHEN TRY_CAST(
                NULLIF(LTRIM(RTRIM(
                    CAST(attendance AS NVARCHAR(20))
                )), N'') AS BIGINT
            ) IS NULL 
                THEN N'Không xác định'

            WHEN TRY_CAST(
                NULLIF(LTRIM(RTRIM(
                    CAST(attendance AS NVARCHAR(20))
                )), N'') AS BIGINT
            ) < 10000 
                THEN N'< 10.000'

            WHEN TRY_CAST(
                NULLIF(LTRIM(RTRIM(
                    CAST(attendance AS NVARCHAR(20))
                )), N'') AS BIGINT
            ) < 30000 
                THEN N'10.000-29.999'

            WHEN TRY_CAST(
                NULLIF(LTRIM(RTRIM(
                    CAST(attendance AS NVARCHAR(20))
                )), N'') AS BIGINT
            ) < 60000 
                THEN N'30.000-59.999'

            ELSE N'>= 60.000'
        END AS attendance_band, 

        TRY_CAST(CAST(home_club_id AS NVARCHAR(20)) AS INT) AS home_club_id, 
        TRY_CAST(CAST(away_club_id AS NVARCHAR(20)) AS INT) AS away_club_id, 

        TRY_CAST(
            CAST(home_club_goals AS NVARCHAR(10)) AS SMALLINT
        ) AS home_club_goals, 

        TRY_CAST(
            CAST(away_club_goals AS NVARCHAR(10)) AS SMALLINT
        ) AS away_club_goals, 

        CAST(batch_id AS NVARCHAR(30)) AS batch_id, 
        loaded_at 

    FROM dbo.stg_raw_games 
) x
    ) q
) d
WHERE d.rn = 1 OR d.game_id IS NULL;

GO
