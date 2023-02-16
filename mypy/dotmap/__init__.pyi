from typing import Any, Dict, Optional, OrderedDict

from _typeshed import Incomplete

class DotMap(OrderedDict[Any, Any]):
    def __init__(self, *args: Any, **kwargs: Any) -> None: ...
    def toDict(self, seen: Optional[Dict[str, Any]] = ...) -> Dict[str, Any]: ...
