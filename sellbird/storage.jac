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
    async def connect(name: str, *, timeout: float) -> any {}

    async def check_schema(name: str) {}

    def exists(name: str) -> bool | None {}
}

def register_backend(prefix: str, backend: any) {
    if not prefix or not prefix.isidentifier() {
        raise ValueError("a storage prefix is a short name like 'pg'");
    }
    if not isinstance(backend, StorageBackend) {
        raise TypeError("a storage backend needs connect, check_schema and exists");
    }
    _BACKENDS[prefix] = backend;
}

def unregister_backend(prefix: str) {
    _BACKENDS.pop(prefix, None);
}

def split(locator: any) -> tuple[any, str] {
    text = str(locator);
    (prefix, sep, rest) = text.partition(":");
    if not sep or text == ":memory:" or not prefix.isidentifier() or len(prefix) == 1 {
        return (None, text);
    }
    if not _ENTRY_POINTS_LOADED {
        _ENTRY_POINTS_LOADED = True;
        for ep in entry_points(group=ENTRY_POINT_GROUP) {
            if ep.name not in _BACKENDS {
                register_backend(ep.name, ep.load()());
            }
        }
    }
    backend = _BACKENDS.get(prefix);
    if backend is None {
        raise LookupError(f"no storage backend is registered for '{prefix}:'");
    }
    return (backend, rest);
}

def manages_schema(locator: any) -> bool {
    return split(locator)[0] is not None;
}

@asynccontextmanager
async def connect(locator: any, *, timeout: float = BUSY_TIMEOUT_SECONDS) -> AsyncIterator[any] {
    (backend, name) = split(locator);
    db = await (
        aiosqlite.connect(name, timeout=timeout)
            if backend is None
            else backend.connect(name, timeout=timeout)
    );
    try {
        yield db;
    } finally {
        await db.close();
    }
}

async def check_schema(locator: any) {
    (backend, name) = split(locator);
    if backend is not None {
        await backend.check_schema(name);
    }
}

def exists(locator: any) -> bool {
    (backend, name) = split(locator);
    return Path(name).exists() if backend is None else backend.exists(name);
}
