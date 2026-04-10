from functools import lru_cache
from pathlib import Path

from pydantic import AliasChoices, Field
from pydantic_settings import BaseSettings, SettingsConfigDict


def _find_repo_root(start: Path) -> Path | None:
    for candidate in (start, *start.parents):
        if (candidate / "docker-compose.yml").exists() or (candidate / ".git").exists():
            return candidate
    return None


CHATSERVER_DIR = Path(__file__).resolve().parent.parent
REPO_ROOT = _find_repo_root(CHATSERVER_DIR)
ENV_FILES = [str(CHATSERVER_DIR / ".env")]
if REPO_ROOT is not None and REPO_ROOT != CHATSERVER_DIR:
    ENV_FILES.insert(0, str(REPO_ROOT / ".env"))


class Settings(BaseSettings):
    host: str = "0.0.0.0"
    port: int = 8001
    reload: bool = False
    app_debug: bool = False
    log_level: str = "info"

    socketio_path: str = "socket.io"
    public_namespaces: str = "warehouse"
    allow_origins: str = "*"

    database_path: str = "./data/chatserver.db"

    clickhouse_host: str = "localhost"
    clickhouse_port: int = 8123
    clickhouse_username: str = "password"
    clickhouse_password: str = "admin"
    clickhouse_database: str = "inventory_mart"
    clickhouse_secure: bool = False
    clickhouse_connect_timeout: int = 10
    clickhouse_send_receive_timeout: int = 30
    clickhouse_raw_database: str = "inventory_raw"
    clickhouse_mart_database: str = "inventory_mart"

    azure_openai_endpoint: str = Field(
        default="",
        validation_alias=AliasChoices(
            "CHATSERVER_AZURE_OPENAI_ENDPOINT",
            "AZURE_OPENAI_ENDPOINT",
        ),
    )
    azure_openai_api_key: str = Field(
        default="",
        validation_alias=AliasChoices(
            "CHATSERVER_AZURE_OPENAI_API_KEY",
            "AZURE_OPENAI_API_KEY",
        ),
    )
    azure_openai_api_version: str = Field(
        default="2024-10-21",
        validation_alias=AliasChoices(
            "CHATSERVER_AZURE_OPENAI_API_VERSION",
            "AZURE_OPENAI_API_VERSION",
        ),
    )
    azure_openai_deployment: str = Field(
        default="gpt-5.2",
        validation_alias=AliasChoices(
            "CHATSERVER_AZURE_OPENAI_DEPLOYMENT",
            "CHATSERVER_AZURE_OPENAI_DEPLOYMENT_NAME",
            "AZURE_OPENAI_DEPLOYMENT",
            "AZURE_OPENAI_DEPLOYMENT_NAME",
        ),
    )
    azure_openai_max_retries: int = Field(
        default=2,
        validation_alias=AliasChoices(
            "CHATSERVER_AZURE_OPENAI_MAX_RETRIES",
            "AZURE_OPENAI_MAX_RETRIES",
        ),
    )
    openai_api_key: str = Field(
        default="",
        validation_alias=AliasChoices(
            "CHATSERVER_OPENAI_API_KEY",
            "OPENAI_API_KEY",
            "OPENAI_PROXY_API_KEY",
        ),
    )
    openai_base_url: str = Field(
        default="",
        validation_alias=AliasChoices(
            "CHATSERVER_OPENAI_BASE_URL",
            "OPENAI_BASE_URL",
        ),
    )
    openai_model: str = Field(
        default="gpt-5.2",
        validation_alias=AliasChoices(
            "CHATSERVER_OPENAI_MODEL",
            "OPENAI_MODEL",
        ),
    )
    openai_timeout_seconds: float = Field(
        default=60.0,
        validation_alias=AliasChoices(
            "CHATSERVER_OPENAI_TIMEOUT_SECONDS",
            "OPENAI_TIMEOUT_SECONDS",
        ),
    )

    model_config = SettingsConfigDict(
        env_file=tuple(ENV_FILES),
        env_prefix="CHATSERVER_",
        extra="allow",
    )

    def get_socketio_allowed_origins(self) -> str | list[str]:
        raw = (self.allow_origins or "").strip()
        if raw in {"", "*"}:
            return "*"
        return [origin.strip() for origin in raw.split(",") if origin.strip()]

    def llm_enabled(self) -> bool:
        has_openai_compatible = bool(
            self.openai_base_url.strip() and self.openai_api_key.strip()
        )
        has_azure = bool(
            self.azure_openai_endpoint.strip() and self.azure_openai_api_key.strip()
        )
        return has_openai_compatible or has_azure


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
