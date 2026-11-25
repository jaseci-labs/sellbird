import builtins;
import os;
import re;
import keyring;
import keyring.errors;

glob SERVICE = "sellbird",
     _REF = re.compile("^[a-z0-9:_-]{1,128}$"),
     _KEYRING_ERRORS = (keyring.errors.KeyringError,);

class SecretStoreUnavailable(Exception) {
    def init(hosted: bool = False);
}

class SecretStoreLocked(SecretStoreUnavailable) {
    def init;
}

def _check_ref(ref: str);

class MemorySecretBackend {
    has _data: dict[tuple[str, str], str] = {};

    def get_password(service: str, ref: str) -> str | None;

    def set_password(service: str, ref: str, value: str);

    def delete_password(service: str, ref: str);

    def __repr__ -> str;

    def __str__ -> str;
}

class SecretStore {
    has _explicit_backend: any = None,
        _explicit_env: any = None;

    def init(backend: any = None, env: any = None);

    @builtins.property
    def _backend -> any;

    @builtins.property
    def _env -> any;

    def get(ref: str, env_var: str | None = None) -> str | None;

    def `set(ref: str, value: str);

    def available -> bool;

    def __repr__ -> str;

    def __str__ -> str;
}
