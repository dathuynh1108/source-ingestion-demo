from __future__ import annotations

import json
from datetime import UTC, datetime
from pathlib import Path

import aiosqlite
from ulid import ULID

from .models import ChatMessage, Conversation


def utc_now_iso() -> str:
    return datetime.now(UTC).isoformat().replace("+00:00", "Z")


def _loads_json(raw: str | None, default):
    if not raw:
        return default
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return default


class ConversationStore:
    def __init__(self, database_path: str):
        self.database_path = Path(database_path)
        self.database_path.parent.mkdir(parents=True, exist_ok=True)

    async def initialize(self) -> None:
        async with aiosqlite.connect(self.database_path) as db:
            await db.execute("PRAGMA journal_mode=WAL;")
            await db.execute("PRAGMA foreign_keys=ON;")
            await db.execute(
                """
                CREATE TABLE IF NOT EXISTS conversations (
                    conversation_id TEXT PRIMARY KEY,
                    namespace TEXT NOT NULL,
                    started_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    state_json TEXT NOT NULL DEFAULT '{}'
                )
                """
            )
            await db.execute(
                """
                CREATE TABLE IF NOT EXISTS messages (
                    msg_id TEXT PRIMARY KEY,
                    conversation_id TEXT NOT NULL,
                    sender TEXT NOT NULL,
                    message TEXT NOT NULL,
                    links_json TEXT,
                    created_at TEXT NOT NULL,
                    FOREIGN KEY (conversation_id)
                        REFERENCES conversations (conversation_id)
                        ON DELETE CASCADE
                )
                """
            )
            await db.execute(
                """
                CREATE INDEX IF NOT EXISTS idx_conversations_namespace_updated_at
                ON conversations (namespace, updated_at DESC)
                """
            )
            await db.execute(
                """
                CREATE INDEX IF NOT EXISTS idx_messages_conversation_created_at
                ON messages (conversation_id, created_at ASC)
                """
            )
            await db.commit()

    async def list_conversations(
        self,
        namespace: str,
        limit: int = 20,
        offset: int = 0,
    ) -> list[dict[str, str]]:
        async with aiosqlite.connect(self.database_path) as db:
            db.row_factory = aiosqlite.Row
            cursor = await db.execute(
                """
                SELECT
                    c.conversation_id,
                    c.started_at,
                    (
                        SELECT m.message
                        FROM messages m
                        WHERE m.conversation_id = c.conversation_id
                        ORDER BY m.created_at ASC
                        LIMIT 1
                    ) AS first_message
                FROM conversations c
                WHERE c.namespace = ?
                ORDER BY c.updated_at DESC
                LIMIT ? OFFSET ?
                """,
                (namespace, limit, offset),
            )
            rows = await cursor.fetchall()

        return [
            {
                "conversation_id": row["conversation_id"],
                "started_at": row["started_at"],
                "first_message": row["first_message"] or "",
            }
            for row in rows
        ]

    async def get_conversation_history(
        self,
        conversation_id: str,
        limit: int = 100,
        offset: int = 0,
    ) -> tuple[Conversation | None, list[ChatMessage]]:
        async with aiosqlite.connect(self.database_path) as db:
            db.row_factory = aiosqlite.Row
            convo_cursor = await db.execute(
                """
                SELECT conversation_id, namespace, started_at, updated_at, state_json
                FROM conversations
                WHERE conversation_id = ?
                """,
                (conversation_id,),
            )
            convo_row = await convo_cursor.fetchone()
            if convo_row is None:
                return None, []

            msg_cursor = await db.execute(
                """
                SELECT msg_id, sender, message, links_json, created_at
                FROM messages
                WHERE conversation_id = ?
                ORDER BY created_at ASC
                LIMIT ? OFFSET ?
                """,
                (conversation_id, limit, offset),
            )
            message_rows = await msg_cursor.fetchall()

        conversation = Conversation(
            conversation_id=convo_row["conversation_id"],
            namespace=convo_row["namespace"],
            started_at=convo_row["started_at"],
            updated_at=convo_row["updated_at"],
            state=_loads_json(convo_row["state_json"], {}),
        )
        messages = [
            ChatMessage(
                msg_id=row["msg_id"],
                sender=row["sender"],
                message=row["message"],
                links=_loads_json(row["links_json"], None),
                created_at=row["created_at"],
            )
            for row in message_rows
        ]
        return conversation, messages

    async def store_message(
        self,
        namespace: str,
        conversation_id: str,
        sender: str,
        message: str,
        links: list[dict] | None = None,
        state: dict | None = None,
        msg_id: str | None = None,
    ) -> tuple[Conversation, ChatMessage]:
        now = utc_now_iso()
        resolved_msg_id = msg_id or str(ULID())

        async with aiosqlite.connect(self.database_path) as db:
            await db.execute("PRAGMA foreign_keys=ON;")
            await db.execute(
                """
                INSERT OR IGNORE INTO conversations (
                    conversation_id,
                    namespace,
                    started_at,
                    updated_at,
                    state_json
                ) VALUES (?, ?, ?, ?, ?)
                """,
                (conversation_id, namespace, now, now, json.dumps(state or {})),
            )
            if state is None:
                await db.execute(
                    """
                    UPDATE conversations
                    SET updated_at = ?
                    WHERE conversation_id = ?
                    """,
                    (now, conversation_id),
                )
            else:
                await db.execute(
                    """
                    UPDATE conversations
                    SET updated_at = ?, state_json = ?
                    WHERE conversation_id = ?
                    """,
                    (now, json.dumps(state), conversation_id),
                )

            await db.execute(
                """
                INSERT INTO messages (
                    msg_id,
                    conversation_id,
                    sender,
                    message,
                    links_json,
                    created_at
                ) VALUES (?, ?, ?, ?, ?, ?)
                """,
                (
                    resolved_msg_id,
                    conversation_id,
                    sender,
                    message,
                    json.dumps(links) if links else None,
                    now,
                ),
            )

            convo_cursor = await db.execute(
                """
                SELECT conversation_id, namespace, started_at, updated_at, state_json
                FROM conversations
                WHERE conversation_id = ?
                """,
                (conversation_id,),
            )
            convo_row = await convo_cursor.fetchone()
            await db.commit()

        conversation = Conversation(
            conversation_id=convo_row[0],
            namespace=convo_row[1],
            started_at=convo_row[2],
            updated_at=convo_row[3],
            state=_loads_json(convo_row[4], {}),
        )
        chat_message = ChatMessage(
            msg_id=resolved_msg_id,
            sender=sender,
            message=message,
            links=links,
            created_at=now,
        )
        return conversation, chat_message

    async def delete_conversation(self, conversation_id: str) -> bool:
        async with aiosqlite.connect(self.database_path) as db:
            cursor = await db.execute(
                "DELETE FROM conversations WHERE conversation_id = ?",
                (conversation_id,),
            )
            await db.commit()
            return (cursor.rowcount or 0) > 0
