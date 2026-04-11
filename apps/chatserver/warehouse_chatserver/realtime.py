from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any

import socketio
from ulid import ULID

from .db import ConversationStore
from .message_handler import MessageHandler
from .models import ChatRequest, ChatResponse, ErrorResponse, ServerMessage, StreamingChunkResponse


@dataclass
class ConnectionContext:
    sid: str
    namespace: str
    client_session_id: str
    room: str
    message_handler: MessageHandler
    last_conversation_id: str | None = None
    last_message_id: str | None = None
    conversation_updated_at: str | None = None


class SessionStore:
    def __init__(self):
        self._sessions: dict[tuple[str, str], dict[str, Any]] = {}

    async def get(self, namespace: str, client_session_id: str) -> dict[str, Any] | None:
        return self._sessions.get((namespace, client_session_id))

    async def save(
        self,
        namespace: str,
        client_session_id: str,
        payload: dict[str, Any],
    ) -> None:
        self._sessions[(namespace, client_session_id)] = payload


class SocketIOChatManager:
    def __init__(self, store: ConversationStore, allowed_origins: str | list[str]):
        self.store = store
        self.session_store = SessionStore()
        self.active_connections: dict[str, ConnectionContext] = {}
        self.sio = socketio.AsyncServer(
            async_mode="asgi",
            cors_allowed_origins=allowed_origins,
            logger=False,
            engineio_logger=False,
        )
        self._register_handlers()

    def _register_handlers(self) -> None:
        @self.sio.event
        async def connect(sid, environ, auth):
            return await self._on_connect(sid, auth)

        @self.sio.event
        async def disconnect(sid):
            await self._on_disconnect(sid)

        @self.sio.on("client_message")
        async def client_message(sid, data):
            await self._on_client_message(sid, data)

    async def _on_connect(self, sid: str, auth: dict | None):
        auth_payload = auth if isinstance(auth, dict) else {}
        namespace = (auth_payload.get("namespace") or "warehouse").strip() or "warehouse"
        client_session_id = (
            auth_payload.get("client_session_id") or str(ULID())
        ).strip()
        room = f"session:{namespace}:{client_session_id}"
        restored = await self.session_store.get(namespace, client_session_id) or {}

        stale_sids = [
            other_sid
            for other_sid, other_ctx in self.active_connections.items()
            if other_sid != sid
            and other_ctx.namespace == namespace
            and other_ctx.client_session_id == client_session_id
        ]
        for other_sid in stale_sids:
            stale_ctx = self.active_connections.get(other_sid)
            if stale_ctx is None:
                continue
            restored["last_conversation_id"] = (
                stale_ctx.last_conversation_id or restored.get("last_conversation_id")
            )
            restored["last_message_id"] = (
                stale_ctx.last_message_id or restored.get("last_message_id")
            )
            restored["conversation_updated_at"] = (
                stale_ctx.conversation_updated_at
                or restored.get("conversation_updated_at")
            )
            await self._cleanup_connection(other_sid, stop_handler=True)
            try:
                await self.sio.disconnect(other_sid)
            except Exception:
                pass

        ctx = ConnectionContext(
            sid=sid,
            namespace=namespace,
            client_session_id=client_session_id,
            room=room,
            message_handler=MessageHandler(self.store, namespace),
            last_conversation_id=restored.get("last_conversation_id"),
            last_message_id=restored.get("last_message_id"),
            conversation_updated_at=restored.get("conversation_updated_at"),
        )
        self.active_connections[sid] = ctx
        await self.sio.enter_room(sid, room)
        await self.sio.emit(
            "session",
            {
                "namespace": namespace,
                "client_session_id": client_session_id,
                "conversation_id": ctx.last_conversation_id,
                "last_message_id": ctx.last_message_id,
                "updated_at": ctx.conversation_updated_at,
                "resume_available": bool(ctx.last_conversation_id),
            },
            to=sid,
        )
        return True

    async def _on_disconnect(self, sid: str) -> None:
        await self._cleanup_connection(sid, stop_handler=True)

    async def _cleanup_connection(self, sid: str, stop_handler: bool) -> None:
        ctx = self.active_connections.pop(sid, None)
        if ctx is None:
            return
        if stop_handler:
            try:
                await ctx.message_handler.handle_stop()
            except Exception:
                pass
        await self.session_store.save(
            ctx.namespace,
            ctx.client_session_id,
            {
                "last_conversation_id": ctx.last_conversation_id,
                "last_message_id": ctx.last_message_id,
                "conversation_updated_at": ctx.conversation_updated_at,
            },
        )

    async def _on_client_message(self, sid: str, data: Any) -> None:
        ctx = self.active_connections.get(sid)
        if ctx is None:
            await self._emit_server_message(
                sid,
                ErrorResponse(
                    error="unauthorized",
                    message="Connection context not found. Please reconnect.",
                ),
            )
            return

        if isinstance(data, str):
            data = json.loads(data)

        if not isinstance(data, dict):
            await self._emit_server_message(
                sid,
                ErrorResponse(
                    error="invalid_message",
                    message="Message payload must be a JSON object.",
                ),
            )
            return

        try:
            if data.get("type") == "ping":
                await self._emit_server_message(sid, await ctx.message_handler.handle_ping())
                return

            if data.get("type") == "stop":
                interrupted = await ctx.message_handler.handle_stop()
                if interrupted is not None:
                    await self._emit_server_message(sid, interrupted)
                return

            request = ChatRequest(**data)
            if not request.conversation_id and ctx.last_conversation_id:
                request.conversation_id = ctx.last_conversation_id

            active_conversation_id = request.conversation_id
            async for response in ctx.message_handler.handle_chat_request(request):
                await self._emit_server_message(sid, response)
                if isinstance(response, StreamingChunkResponse):
                    active_conversation_id = response.data.conversation_id
                if isinstance(response, ChatResponse):
                    ctx.last_message_id = response.data.last_message_id
                    ctx.conversation_updated_at = response.data.updated_at
                    active_conversation_id = response.data.conversation_id

            ctx.last_conversation_id = active_conversation_id
            await self.session_store.save(
                ctx.namespace,
                ctx.client_session_id,
                {
                    "last_conversation_id": ctx.last_conversation_id,
                    "last_message_id": ctx.last_message_id,
                    "conversation_updated_at": ctx.conversation_updated_at,
                },
            )
        except Exception as exc:
            await self._emit_server_message(
                sid,
                ErrorResponse(error="server_error", message=str(exc)),
            )

    async def _emit_server_message(self, sid: str, message: ServerMessage) -> None:
        ctx = self.active_connections.get(sid)
        target = ctx.room if ctx is not None else sid
        await self.sio.emit(
            "server_message",
            message.model_dump(mode="json"),
            to=target,
        )


def build_socketio_asgi_app(
    fastapi_app,
    store: ConversationStore,
    socketio_path: str,
    allowed_origins: str | list[str],
):
    manager = SocketIOChatManager(store=store, allowed_origins=allowed_origins)
    fastapi_app.state.socketio_manager = manager
    return socketio.ASGIApp(
        manager.sio,
        other_asgi_app=fastapi_app,
        socketio_path=socketio_path.lstrip("/"),
    )
