import json;
import logging;
import from datetime { datetime }
import from pathlib { Path }

glob logger = logging.getLogger("sellbird.analyst");

class Analyst {
    has state: any = None;

    def init(state: StateManager);
    async def run;
    def _generate_insights(summary: dict[str, any]) -> list[str];
}
