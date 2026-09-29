import os
from datetime import datetime
from pathlib import Path

# Đường dẫn gốc của dự án
BASE_DIR = Path(__file__).resolve().parent.parent

SERVER_NAME = "MSI\\TRIEUHIEU" # Thay bằng tên Server Name trong SQL Server Management Studio
DATABASE_NAME = "football_dwh"
DB_URL = os.getenv(
    "DATABASE_URL", 
    f"mssql+pyodbc://@{SERVER_NAME}/{DATABASE_NAME}?driver=ODBC+Driver+17+for+SQL+Server&Trusted_Connection=yes"
)

# Đường dẫn thư mục dữ liệu và logs
DATA_RAW_DIR = BASE_DIR / "data" / "raw"
LOG_DIR = BASE_DIR / "logs"
LOG_DIR.mkdir(parents=True, exist_ok=True)

# Tên Schema dùng cho tầng Staging Raw
SCHEMA_STG_RAW = "dbo"

# Sinh BATCH_ID tự động theo thời gian chạy (Ví dụ: BATCH_20260928_120000)
CURRENT_BATCH_ID = f"BATCH_{datetime.now().strftime('%Y%m%d_%H%M%S')}"