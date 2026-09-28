from config.settings import CURRENT_BATCH_ID
from src.db.connection import get_db_engine
from src.load.fact_loader import (
    load_fact_team_match,
    load_fact_player_valuation,
    load_fact_transfer
)
from src.utils.logger import logger

def run_pipeline_stage_04():
    logger.info("==================================================================")
    logger.info(f"BẮT ĐẦU PIPELINE STAGE 4: LOAD FACT TABLES (DW) - BATCH: {CURRENT_BATCH_ID}")
    logger.info("==================================================================")

    engine = get_db_engine()

    try:
        # 1. Nạp Fact Trận đấu CLB
        load_fact_team_match(engine)

        # 2. Nạp Fact Định giá Cầu thủ
        load_fact_player_valuation(engine)

        # 3. Nạp Fact Chuyển nhượng Cầu thủ
        load_fact_transfer(engine)

        logger.info("\n==================================================================")
        logger.info("🎉 CHÚC MỪNG! BẠN ĐÃ HOÀN THÀNH TOÀN BỘ PIPELINE ETL KHO DỮ LIỆU! 🎉")
        logger.info("==================================================================")

    except Exception as e:
        logger.error(f"Lỗi trong quá trình chạy Pipeline Stage 4: {e}")
        raise e

if __name__ == "__main__":
    run_pipeline_stage_04()