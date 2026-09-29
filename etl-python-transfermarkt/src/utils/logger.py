import logging
import sys
from config.settings import LOG_DIR, CURRENT_BATCH_ID

def setup_logger():
    logger = logging.getLogger("ETL_Pipeline")
    logger.setLevel(logging.INFO)

    log_format = logging.Formatter(
        "[%(asctime)s] [%(levelname)s] [%(filename)s:%(lineno)d] - %(message)s"
    )

    # Console Handler
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setFormatter(log_format)
    logger.addHandler(console_handler)

    # File Handler
    file_handler = logging.FileHandler(LOG_DIR / f"{CURRENT_BATCH_ID}.log", encoding="utf-8")
    file_handler.setFormatter(log_format)
    logger.addHandler(file_handler)

    return logger

logger = setup_logger()