from __future__ import annotations

import asyncio
from typing import AsyncGenerator

from ulid import ULID

from .db import ConversationStore
from .models import (
    ChatMessage,
    ChatMessageChunk,
    ChatRequest,
    ChatResponse,
    ChatResponseData,
    ChunkData,
    CompleteMessageData,
    CompleteMessageResponse,
    ErrorResponse,
    InterruptedResponse,
    PongResponse,
    ServerMessage,
    StreamingChunkResponse,
)
from .warehouse_agent import WarehouseAgent


class MessageHandler:
    def __init__(self, store: ConversationStore, namespace: str):
        self.store = store
        self.namespace = namespace
        self.agent = WarehouseAgent(namespace)
        self.is_processing = False
        self._cancel_event = asyncio.Event()
        self._current_task: asyncio.Task | None = None
        self._queue: asyncio.Queue | None = None

    async def handle_ping(self) -> PongResponse:
        return PongResponse(event="pong")

    async def handle_stop(self) -> InterruptedResponse | None:
        if not self.is_processing:
            return None
        self._cancel_event.set()
        self.agent.stop_processing()
        if self._current_task and not self._current_task.done():
            self._current_task.cancel()
        return InterruptedResponse(event="interrupted")

    async def handle_chat_request(
        self,
        request: ChatRequest,
    ) -> AsyncGenerator[ServerMessage, None]:
        if self.is_processing:
            self._cancel_event.set()
            self.agent.stop_processing()
            if self._current_task and not self._current_task.done():
                self._current_task.cancel()

        self.is_processing = True
        self._cancel_event.clear()

        try:
            conversation_id = request.conversation_id or str(ULID())
            user_text = (request.message or "").strip()
            conversation, user_message = await self.store.store_message(
                namespace=self.namespace,
                conversation_id=conversation_id,
                sender="user",
                message=user_text,
            )
            user_message.sender = "user"

            _, history = await self.store.get_conversation_history(
                conversation_id=conversation_id,
                limit=200,
            )

            stream_msg_id = str(ULID())
            queue: asyncio.Queue = asyncio.Queue()
            self._queue = queue

            async def producer():
                try:
                    async for item in self.agent.process_message(
                        user_message=user_message,
                        conversation=conversation,
                        history=history,
                    ):
                        await queue.put(item)
                except asyncio.CancelledError:
                    pass
                except Exception as exc:
                    await queue.put(exc)
                finally:
                    await queue.put(None)

            self._current_task = asyncio.create_task(producer())
            assistant_message_id: str | None = None
            updated_at: str | None = None

            while True:
                if self._cancel_event.is_set():
                    self.agent.stop_processing()
                    if self._current_task and not self._current_task.done():
                        self._current_task.cancel()
                    break

                item = await queue.get()
                if item is None:
                    break
                if isinstance(item, Exception):
                    raise item

                if isinstance(item, ChatMessageChunk):
                    yield StreamingChunkResponse(
                        event="chunk",
                        data=ChunkData(
                            conversation_id=conversation_id,
                            msg_id=stream_msg_id,
                            chunk=item.text,
                        ),
                    )
                    continue

                if isinstance(item, ChatMessage):
                    stored_conversation, stored_message = await self.store.store_message(
                        namespace=self.namespace,
                        conversation_id=conversation_id,
                        sender=item.sender,
                        message=item.message,
                        msg_id=stream_msg_id,
                        links=[
                            link.model_dump(exclude_none=True) for link in (item.links or [])
                        ]
                        or None,
                        state=conversation.state,
                    )
                    assistant_message_id = stored_message.msg_id
                    updated_at = stored_conversation.updated_at
                    yield CompleteMessageResponse(
                        event="message",
                        data=CompleteMessageData(
                            msg_id=stored_message.msg_id or stream_msg_id,
                            sender=stored_message.sender,
                            message=stored_message.message,
                            links=stored_message.links,
                        ),
                    )

            if not self._cancel_event.is_set():
                yield ChatResponse(
                    event="response",
                    data=ChatResponseData(
                        conversation_id=conversation_id,
                        context=request.context,
                        state=conversation.state or {},
                        last_message_id=assistant_message_id,
                        updated_at=updated_at,
                    ),
                )
        finally:
            self.is_processing = False
            self._cancel_event.clear()
            self._current_task = None
            self._queue = None

    def create_error_response(self, error_type: str, message: str) -> ErrorResponse:
        return ErrorResponse(error=error_type, message=message)
