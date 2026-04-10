from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel


class MessageLink(BaseModel):
    title: str
    link: str | None = None
    format: str | None = None


class ChatMessageChunk(BaseModel):
    text: str


class ChatMessage(BaseModel):
    msg_id: str | None = None
    sender: str
    message: str
    links: list[MessageLink] | None = None
    created_at: str | None = None


class Conversation(BaseModel):
    conversation_id: str
    namespace: str | None = None
    state: dict[str, Any] | None = None
    started_at: str | None = None
    updated_at: str | None = None


class ChatRequest(BaseModel):
    conversation_id: str | None = None
    message: str
    history: list[ChatMessage] | None = None
    state: dict[str, Any] | None = None
    context: Any | None = None


class PongResponse(BaseModel):
    event: Literal["pong"]


class ChunkData(BaseModel):
    conversation_id: str
    msg_id: str
    chunk: str


class StreamingChunkResponse(BaseModel):
    event: Literal["chunk"]
    data: ChunkData


class CompleteMessageData(BaseModel):
    msg_id: str
    sender: str
    message: str
    links: list[MessageLink] | None = None


class CompleteMessageResponse(BaseModel):
    event: Literal["message"]
    data: CompleteMessageData


class ChatResponseData(BaseModel):
    conversation_id: str
    context: Any | None = None
    state: dict[str, Any] | None = None
    last_message_id: str | None = None
    updated_at: str | None = None


class ChatResponse(BaseModel):
    event: Literal["response"]
    data: ChatResponseData


class InterruptedResponse(BaseModel):
    event: Literal["interrupted"]


class ErrorResponse(BaseModel):
    error: str
    message: str


class ConversationItem(BaseModel):
    conversations: str
    started_at: str
    first_message: str
    snippet: str


class ConversationListResponse(BaseModel):
    items: list[ConversationItem]


class ConversationDetailResponse(BaseModel):
    conversation_id: str
    state: dict[str, Any] | None = None
    updated_at: str | None = None
    last_message_id: str | None = None
    has_more: bool = False
    next_offset: int | None = None
    history: list[ChatMessage]


ServerMessage = (
    PongResponse
    | StreamingChunkResponse
    | CompleteMessageResponse
    | ChatResponse
    | InterruptedResponse
    | ErrorResponse
)
