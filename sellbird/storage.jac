import sqlite3;
import aiosqlite;
import from contextlib { asynccontextmanager }
import from importlib.metadata { entry_points }
import from pathlib { Path }
import from typing { Protocol, runtime_checkable }

glob BUSY_TIMEOUT_SECONDS = 30.0,
     ENTRY_POINT_GROUP = "sellbird.storage",
     _BACKENDS: dict[str, any] = {},
     _ENTRY_POINTS_LOADED = False;

class IntegrityError(sqlite3.IntegrityError) {}

@runtime_checkable
class StorageBackend(Protocol) {
    async def connect(name: str, *, timeout: float) -> any;
    async def check_schema(name: str);
    def exists(name: str) -> bool | None;
}

def register_backend(prefix: str, backend: any);

def unregister_backend(prefix: str);

def split(locator: any) -> tuple[any, str];

def manages_schema(locator: any) -> bool;

@asynccontextmanager
async def connect(locator: any, *, timeout: float = BUSY_TIMEOUT_SECONDS) -> AsyncIterator[any];

async def check_schema(locator: any);

def exists(locator: any) -> bool;
