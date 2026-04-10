from __future__ import annotations

from contextlib import AsyncExitStack, asynccontextmanager

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from .clickhouse import get_clickhouse_service
from .config import get_settings
from .db import ConversationStore
from .models import ConversationDetailResponse, ConversationItem, ConversationListResponse
from .realtime import build_socketio_asgi_app
from .warehouse_mcp import mcp


def create_fastapi_app(store: ConversationStore, mcp_app) -> FastAPI:
    settings = get_settings()
    clickhouse = get_clickhouse_service()

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        await store.initialize()
        app.state.store = store
        app.state.mcp_app = mcp_app

        async with AsyncExitStack() as stack:
            await stack.enter_async_context(mcp_app.lifespan(app))
            yield

    app = FastAPI(
        title="Warehouse Chat Server",
        version="0.1.0",
        lifespan=lifespan,
        debug=settings.app_debug,
    )
    cors_origins = settings.get_socketio_allowed_origins()
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"] if cors_origins == "*" else cors_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    app.mount("/clickhouse", mcp_app)

    @app.get("/")
    async def root():
        return {
            "name": "warehouse-chatserver",
            "socketio_path": f"/{settings.socketio_path.lstrip('/')}",
            "mcp_path": "/clickhouse/mcp",
        }

    @app.get("/health")
    async def health():
        return {
            "status": "ok",
            "clickhouse": clickhouse.health(),
        }

    @app.get("/api/v1/warehouse/dashboard")
    async def warehouse_dashboard():
        return clickhouse.get_dashboard_summary()

    @app.get("/api/v1/chat/{namespace}/history", response_model=ConversationListResponse)
    async def get_conversations(
        namespace: str,
        page: int = 1,
        page_size: int = 20,
    ):
        offset = max(page - 1, 0) * page_size
        items = await app.state.store.list_conversations(
            namespace=namespace,
            limit=page_size,
            offset=offset,
        )
        return ConversationListResponse(
            items=[
                ConversationItem(
                    conversations=item["conversation_id"],
                    started_at=item["started_at"],
                    first_message=item["first_message"],
                    snippet=item["first_message"].strip(),
                )
                for item in items
            ]
        )

    @app.get(
        "/api/v1/chat/{namespace}/history/{conversation_id}",
        response_model=ConversationDetailResponse,
    )
    async def get_conversation(
        namespace: str,
        conversation_id: str,
        page: int = 1,
        page_size: int = 100,
    ):
        _ = namespace
        offset = max(page - 1, 0) * page_size
        conversation, history = await app.state.store.get_conversation_history(
            conversation_id=conversation_id,
            limit=page_size + 1,
            offset=offset,
        )
        if conversation is None:
            raise HTTPException(status_code=404, detail="Conversation not found")

        has_more = len(history) > page_size
        visible_history = history[:page_size]
        last_message_id = visible_history[-1].msg_id if visible_history else None
        return ConversationDetailResponse(
            conversation_id=conversation_id,
            state=conversation.state or {},
            updated_at=conversation.updated_at,
            last_message_id=last_message_id,
            has_more=has_more,
            next_offset=offset + len(visible_history) if has_more else None,
            history=visible_history,
        )

    @app.delete("/api/v1/chat/{namespace}/history/{conversation_id}")
    async def delete_conversation(namespace: str, conversation_id: str):
        _ = namespace
        deleted = await app.state.store.delete_conversation(conversation_id)
        if not deleted:
            raise HTTPException(status_code=404, detail="Conversation not found")
        return {"message": f"Conversation {conversation_id} deleted successfully"}

    return app


def create_app():
    settings = get_settings()
    store = ConversationStore(settings.database_path)
    mcp_app = mcp.http_app(path="/mcp")
    fastapi_app = create_fastapi_app(store=store, mcp_app=mcp_app)
    return build_socketio_asgi_app(
        fastapi_app=fastapi_app,
        store=store,
        socketio_path=settings.socketio_path,
        allowed_origins=settings.get_socketio_allowed_origins(),
    )
