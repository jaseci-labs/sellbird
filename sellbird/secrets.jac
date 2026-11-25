import builtins;
import os;
import re;
import keyring;
import keyring.errors;

glob SERVICE = "sellbird",
     _REF = re.compile("^[a-z0-9:_-]{1,128}$"),
     _KEYRING_ERRORS = (keyring.errors.KeyringError,);

class SecretStoreUnavailable(Exception) {
    def init(hosted: bool = False) {
        super.init(
            "This workspace has no secret storage configured."
                if hosted
                else "No system keychain is available here (headless or Docker), so this sign-in can't be stored safely.",
        );
    }
}

class SecretStoreLocked(SecretStoreUnavailable) {
    def init {
        (Exception as any).__init__(
            self, "Your system keychain is locked or refused the request. Unlock it and try again."
        );
    }
}

def _check_ref(ref: str) {
    if not isinstance(ref, str) or not _REF.match(ref) {
        raise ValueError("secret ref must match ^[a-z0-9:_-]{1,128}$");
    }
}

class MemorySecretBackend {
    has _data: dict[tuple[str, str], str] = {};

    def get_password(service: str, ref: str) -> str | None {
        return self._data.get((service, ref));
    }

    def set_password(service: str, ref: str, value: str) {
        self._data[(service, ref)] = value;
    }

    def delete_password(service: str, ref: str) {
        self._data.pop((service, ref), None);
    }

    def __repr__ -> str {
        return "MemorySecretBackend()";
    }

    def __str__ -> str {
        return self.__repr__();
    }
}

class SecretStore {
    has _explicit_backend: any = None,
        _explicit_env: any = None;

    def init(backend: any = None, env: any = None) {
        self._explicit_backend = backend;
        self._explicit_env = env;
    }

    @builtins.property
    def _backend -> any {
        if self._explicit_backend is not None {
            return self._explicit_backend;
        }
        home = current_home();
        if home.secret_backend is not None {
            return home.secret_backend;
        }
        if home.hosted {
            raise SecretStoreUnavailable(hosted=True);
        }
        return keyring;
    }

    @builtins.property
    def _env -> any {
        if self._explicit_env is not None {
            return self._explicit_env;
        }
        return {} if current_home().hosted else os.environ;
    }

    def get(ref: str, env_var: str | None = None) -> str | None {
        _check_ref(ref);
        try {
            value = self._backend.get_password(SERVICE, ref);
        } except (SecretStoreUnavailable, keyring.errors.KeyringError) {
            value = None;
        }
        return value or ((self._env.get(env_var) or None) if env_var else None);
    }

    def `set(ref: str, value: str) {
        _check_ref(ref);
        backend = self._backend;
        try {
            backend.set_password(SERVICE, ref, value);
        } except (keyring.errors.NoKeyringError, keyring.errors.InitError) {
            raise SecretStoreUnavailable(hosted=current_home().hosted) from None;
        } except keyring.errors.KeyringError {
            raise SecretStoreLocked() from None;
        }
    }

    def available -> bool {
        try {
            self._backend.get_password(SERVICE, "probe");
        } except (SecretStoreUnavailable, keyring.errors.KeyringError) {
            return False;
        }
        return True;
    }

    def __repr__ -> str {
        return f"SecretStore(service={SERVICE!r})";
    }

    def __str__ -> str {
        return self.__repr__();
    }
}
