import pandas as pd
from sqlalchemy import text
from config.settings import CURRENT_BATCH_ID, SCHEMA_STG_RAW
from src.db.connection import get_db_engine
from src.transform.clean_transformers import (
    transform_stg_clean_players,
    transform_stg_clean_club_games,
    transform_stg_clean_player_valuations,
    transform_stg_clean_transfers
)
from src.utils.logger import logger

SCHEMA_STG_CLEAN = "stg_clean"

def load_stg_raw_table(table_name: str, engine) -> pd.DataFrame:
    """Đọc dữ liệu thô từ bảng stg_raw."""
    query = f"SELECT * FROM {table_name}"
    return pd.read_sql_query(query, con=engine)

def save_to_stg_clean(df: pd.DataFrame, table_name: str, engine):
    """Ghi dữ liệu đã làm sạch vào tầng stg_clean."""
    df.to_sql(
        name=table_name,
        con=engine,
        schema=SCHEMA_STG_CLEAN if "postgresql" in engine.dialect.name else None,
        if_exists="replace",
        index=False,
        method="multi" if "sqlite" in engine.dialect.name else None
    )
    logger.info(f"---> [Thành công] Đã nạp {len(df):,} dòng sạch vào [{table_name}].")

def run_pipeline_stage_02():
    logger.info("==================================================================")
    logger.info(f"BẮT ĐẦU PIPELINE STAGE 2: TRANSFORM TO STAGING CLEAN - BATCH: {CURRENT_BATCH_ID}")
    logger.info("==================================================================")

    engine = get_db_engine()

    try:
        # 1. Biến đổi Cầu thủ (Players)
        raw_players = load_stg_raw_table("stg_raw_players", engine)
        clean_players = transform_stg_clean_players(raw_players)
        save_to_stg_clean(clean_players, "stg_clean_players", engine)

        # 2. Biến đổi Trận đấu CLB (Club Games)
        raw_club_games = load_stg_raw_table("stg_raw_club_games", engine)
        clean_club_games = transform_stg_clean_club_games(raw_club_games)
        save_to_stg_clean(clean_club_games, "stg_clean_club_games", engine)

        # 3. Biến đổi Định giá (Player Valuations) - Cần clean_players để tính tuổi
        raw_valuations = load_stg_raw_table("stg_raw_player_valuations", engine)
        clean_valuations = transform_stg_clean_player_valuations(raw_valuations, clean_players)
        save_to_stg_clean(clean_valuations, "stg_clean_player_valuations", engine)

        # 4. Biến đổi Chuyển nhượng (Transfers)
        raw_transfers = load_stg_raw_table("stg_raw_transfers", engine)
        clean_transfers = transform_stg_clean_transfers(raw_transfers, clean_players)
        save_to_stg_clean(clean_transfers, "stg_clean_transfers", engine)

        logger.info("\n=== Hoàn thành xuất sắc Pipeline Stage 2 (stg_clean)! ===")

    except Exception as e:
        logger.error(f"Lỗi trong quá trình chạy Pipeline Stage 2: {e}")
        raise e

if __name__ == "__main__":
    run_pipeline_stage_02()
