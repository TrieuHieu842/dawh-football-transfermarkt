import pandas as pd
from config.settings import CURRENT_BATCH_ID
from src.db.connection import get_db_engine
from src.load.dim_loader import generate_dim_date, load_dim_scd1, load_dim_player_scd2
from src.utils.logger import logger

SCHEMA_STG_CLEAN = "stg_clean"
SCHEMA_DW = "dw"

def run_pipeline_stage_03():
    logger.info("==================================================================")
    logger.info(f"BẮT ĐẦU PIPELINE STAGE 3: LOAD DIMENSION TABLES (DW) - BATCH: {CURRENT_BATCH_ID}")
    logger.info("==================================================================")

    engine = get_db_engine()

    try:
        # 1. Sinh & Nạp Dim_Date
        dim_date_df = generate_dim_date(start_year=1990, end_year=2030)
        dim_date_df.to_sql(
            name="dim_date",
            con=engine,
            schema=SCHEMA_DW if "postgresql" in engine.dialect.name else None,
            if_exists="replace",
            index=False
        )
        logger.info(f"---> [Thành công] Đã nạp {len(dim_date_df):,} ngày vào [dim_date].")

        # 2. Nạp Dim_Competition (SCD Type 1)
        stg_competitions = pd.read_sql_table("stg_raw_competitions", con=engine)
        load_dim_scd1(
            df_clean=stg_competitions,
            target_table="dim_competition",
            natural_key="competition_id",
            sk_name="competition_key",
            engine=engine
        )

        # 3. Nạp Dim_Player (SCD Type 2)
        stg_players_clean = pd.read_sql_table("stg_clean_players", con=engine)
        load_dim_player_scd2(stg_players_clean, engine)

        logger.info("\n=== Hoàn thành xuất sắc Pipeline Stage 3 (Load Dimensions)! ===")

    except Exception as e:
        logger.error(f"Lỗi trong quá trình chạy Pipeline Stage 3: {e}")
        raise e

if __name__ == "__main__":
    run_pipeline_stage_03()