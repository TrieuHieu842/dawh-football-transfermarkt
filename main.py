from config.settings import DATA_RAW_DIR, CURRENT_BATCH_ID
from config.source_files import SOURCE_FILES_CONFIG
from src.db.connection import get_db_engine
from src.extract.csv_extractor import inspect_csv_file
from src.load.raw_loader import load_csv_to_stg_raw
from src.utils.logger import logger

def run_pipeline_stage_01():
    logger.info("==================================================================")
    logger.info(f"BẮT ĐẦU PIPELINE STAGE 1: LOAD STAGING RAW - BATCH: {CURRENT_BATCH_ID}")
    logger.info("==================================================================")

    engine = get_db_engine()
    summary_report = []

    for file_name, table_name in SOURCE_FILES_CONFIG.items():
        file_path = DATA_RAW_DIR / file_name
        try:
            # 1. Kiểm tra file nguồn
            source_rows, checksum = inspect_csv_file(file_path)

            # 2. Thực hiện nạp vào stg_raw
            inserted_rows = load_csv_to_stg_raw(
                file_path=file_path,
                table_name=table_name,
                engine=engine,
                chunksize=100_000
            )

            # 3. Đối chiếu số dòng
            is_match = (source_rows == inserted_rows)
            summary_report.append({
                "file": file_name,
                "table": table_name,
                "source_rows": source_rows,
                "inserted_rows": inserted_rows,
                "status": "PASS" if is_match else "MISMATCH"
            })

        except Exception as e:
            logger.error(f"Thất bại khi xử lý file [{file_name}]: {e}")
            summary_report.append({
                "file": file_name,
                "table": table_name,
                "source_rows": -1,
                "inserted_rows": 0,
                "status": f"FAILED: {str(e)}"
            })

    # Báo cáo tổng kết đợt nạp
    logger.info("\n================ TỔNG KẾT BÁO CÁO TẦNG STG_RAW ================")
    for item in summary_report:
        logger.info(
            f"File: {item['file']:<22} | Bảng: {item['table']:<25} | "
            f"Nguồn: {item['source_rows']:>10,} | Nạp: {item['inserted_rows']:>10,} | "
            f"Trạng thái: {item['status']}"
        )
    logger.info("==================================================================")

if __name__ == "__main__":
    run_pipeline_stage_01()
