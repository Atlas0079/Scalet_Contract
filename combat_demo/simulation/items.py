"""Item capabilities shared by menus, plans, previews and world execution."""
from __future__ import annotations

from dataclasses import dataclass, field
from .weapon import ItemDefinition, RIFLE


@dataclass(frozen=True)
class UseDefinition:
    id: str
    label: str
    target: str
    duration: float
    cost: int = 0
    range: float = 0.0
    radius: float = 0.0
    breach: bool = False
    effect: str = ""


@dataclass(frozen=True)
class SupplyDefinition:
    item: ItemDefinition
    order: int
    uses: tuple[UseDefinition, ...]

    @property
    def id(self): return self.item.id

    @property
    def name(self): return self.item.name


ITEMS = {
    "rifle": SupplyDefinition(RIFLE.item, 10, (UseDefinition("reload", "换弹", "self", 2.5),)),
    "flashbang": SupplyDefinition(ItemDefinition("flashbang", "闪光弹", "consumable"), 20, (
        UseDefinition("throw", "投掷…", "ground", .6, 1, 6.0, 4.0, True, "flash"),)),
    "bandage": SupplyDefinition(ItemDefinition("bandage", "包扎用品", "consumable"), 30, (
        UseDefinition("bandage", "自行包扎", "self", 3.0, 1, effect="heal"),)),
}


@dataclass
class Inventory:
    quantities: dict[str, int] = field(default_factory=lambda: {"flashbang": 1, "bandage": 1})
    reservations: dict[str, tuple[str, int]] = field(default_factory=dict)

    def reserved(self, item: str) -> int:
        return sum(q for i, q in self.reservations.values() if i == item)

    def available(self, item: str, releasing: set[str] | None = None) -> int:
        held = sum(q for token, (i, q) in self.reservations.items()
                   if i == item and token not in (releasing or set()))
        return self.quantities.get(item, 0) - held

    def reserve(self, token: str, item: str, count: int = 1) -> None:
        if token in self.reservations or self.available(item) < count:
            raise ValueError("物品不足或重复预约")
        self.reservations[token] = item, count

    def release(self, token: str) -> None:
        self.reservations.pop(token, None)

    def consume(self, token: str) -> bool:
        entry = self.reservations.get(token)
        if entry is None:
            return False
        item, count = entry
        if self.quantities.get(item, 0) < count:
            return False
        self.quantities[item] -= count
        del self.reservations[token]
        return True

    def definitions(self) -> list[SupplyDefinition]:
        return sorted((v for k, v in ITEMS.items() if k == "rifle" or k in self.quantities),
                      key=lambda v: (v.order, v.id))


def use_for(item: str, action: str | None = None) -> UseDefinition:
    definition = ITEMS[item]
    return next(u for u in definition.uses if action is None or u.id == action)
