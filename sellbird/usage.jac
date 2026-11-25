import os;

import from pathlib { Path }

def claude_config_dir -> Path {
    pinned = os.environ.get("CLAUDE_CONFIG_DIR", "").strip();
    return Path(pinned).expanduser() if pinned else Path.home() / ".claude";
}
