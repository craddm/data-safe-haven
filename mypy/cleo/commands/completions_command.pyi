from _typeshed import Incomplete

from .._compat import encode as encode
from ..helpers import argument as argument
from ..helpers import option as option
from .command import Command as Command

class CompletionsCommand(Command):
    name: str
    description: str
    arguments: Incomplete
    options: Incomplete
    SUPPORTED_SHELLS: Incomplete
    hidden: bool
    help: str
    def handle(self) -> int: ...
    def render(self, shell: str) -> str: ...
    def render_bash(self) -> str: ...
    def render_zsh(self): ...
    def render_fish(self): ...
    def get_shell_type(self): ...
