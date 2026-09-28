from sqlalchemy import create_engine
from config.settings import DB_URL
from src.utils.logger import logger

def get_db_engine():
    try:
        # Bật fast_executemany cho SQL Server
        engine = create_engine(DB_URL, fast_executemany=True, pool_pre_ping=True)
        logger.info("Kết nối Database thành công")
        return engine
    except Exception as e:
        logger.error(f"Lỗi kết nối Database: {e}")
        raise e